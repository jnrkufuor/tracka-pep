"""
The database: tables and the job queue.

Two tables:
  jobs     one row per clip to analyse: the request, its status, the result
  ratings  scouts' ratings of analysed clips (the training data for the learned scorer)

SQLAlchemy "Core" (not the ORM) is used: you write queries that look like
SQL, in Python, and the same code runs on SQLite (local, tests) and
Postgres (production). Tables are created on start-up with `create_all`;
when the schema starts changing in production, switch to Alembic migrations
(docs/handbook/09-improving.md explains why and how).

THE QUEUE
=========
Why a queue at all? Analysing a clip takes 10 s to several minutes. An HTTP
request must answer in seconds, so the API only *records* the job and
answers 202 Accepted; separate worker processes do the heavy work. That
split (fast web tier, slow worker tier) is the most common shape of real
backend systems.

Why in Postgres and not Redis/RabbitMQ/SQS? One less moving part. Postgres
has a feature made for this:

    SELECT ... FOR UPDATE SKIP LOCKED

Many workers can ask for "the next job" at the same moment; each one locks
the row it gets and *skips* rows other workers have locked, so no job is
handed out twice and nobody waits. It comfortably handles thousands of jobs
an hour, which is far beyond what Pep needs for a long time.

LEASES. A claimed job gets `lease_until = now + 5 min`. A working worker
keeps extending it (a heartbeat). If a worker crashes or its machine
disappears, the lease runs out and another worker reclaims the job. That's
how you get "at least once" processing without anyone watching. (At least
once, not exactly once: so finishing a job must be safe to repeat; it is.)
"""

from __future__ import annotations

import random
import uuid
from datetime import UTC, datetime, timedelta
from functools import cache
from typing import Any

from sqlalchemy import (
    JSON,
    Column,
    DateTime,
    Engine,
    Integer,
    MetaData,
    String,
    Table,
    Text,
    and_,
    create_engine,
    func,
    insert,
    or_,
    select,
    text,
    update,
)

from .config import settings

metadata = MetaData()

jobs = Table(
    "jobs",
    metadata,
    Column("id", String(36), primary_key=True),
    Column("analysis_id", String(64), nullable=False, index=True),
    Column("source", String(16), nullable=False),  # "tracka" or "lab"
    Column("request", JSON, nullable=False),
    Column("video_key", String(255)),  # clips uploaded through the Lab live in our storage
    Column("status", String(16), nullable=False, index=True),  # QUEUED RUNNING READY FAILED
    Column("attempts", Integer, nullable=False, default=0),
    Column("run_after", DateTime(timezone=True), nullable=False),
    Column("lease_until", DateTime(timezone=True)),
    Column("worker", String(64)),
    Column("created_at", DateTime(timezone=True), nullable=False),
    Column("started_at", DateTime(timezone=True)),
    Column("finished_at", DateTime(timezone=True)),
    Column("result", JSON),
    Column("timings", JSON),
    Column("error", Text),
    Column("overlay_key", String(255)),
    Column("thumb_key", String(255)),
    # Delivering the result back to Tracka is its own little state machine.
    Column("callback_status", String(16), nullable=False, default="NONE"),  # NONE PENDING SENT GAVE_UP
    Column("callback_attempts", Integer, nullable=False, default=0),
    Column("callback_next_at", DateTime(timezone=True)),
    Column("callback_error", Text),
)

ratings = Table(
    "ratings",
    metadata,
    Column("id", String(36), primary_key=True),
    Column("job_id", String(36), nullable=False, index=True),
    Column("rater", String(80), nullable=False),
    Column("role", String(40)),
    Column("overall", Integer, nullable=False),
    Column("skills", JSON),
    Column("notes", Text),
    Column("created_at", DateTime(timezone=True), nullable=False),
)


def now() -> datetime:
    return datetime.now(UTC)


@cache
def engine() -> Engine:
    s = settings()
    kwargs: dict[str, Any] = {"pool_pre_ping": True}  # drop dead connections instead of failing a request
    if s.is_sqlite:
        # SQLite: allow use from the API's threads, and wait (not fail) when another writer holds the lock.
        kwargs["connect_args"] = {"check_same_thread": False, "timeout": 30}
    eng = create_engine(s.database_url, **kwargs)
    metadata.create_all(eng)
    if s.is_sqlite:
        with eng.begin() as c:
            c.execute(text("PRAGMA journal_mode=WAL"))  # readers don't block the writer
    return eng


def _aware(d: datetime | None) -> datetime | None:
    """SQLite hands datetimes back without a timezone; treat them as UTC."""
    if d is not None and d.tzinfo is None:
        return d.replace(tzinfo=UTC)
    return d


def row_dict(row) -> dict:
    d = dict(row._mapping)
    for k in ("run_after", "lease_until", "created_at", "started_at", "finished_at", "callback_next_at"):
        d[k] = _aware(d.get(k))
    return d


# ---------------------------------------------------------------- jobs


def enqueue(request: dict, source: str, video_key: str | None = None) -> dict:
    """
    Adds a job, or returns the existing one for the same analysisId.

    IDEMPOTENCY: Tracka may send the same analysis twice (a retry after a
    timeout, a double click). The same request must not create two jobs.
    If the earlier job failed for good, sending it again means "retry".
    """
    with engine().begin() as c:
        existing = c.execute(
            select(jobs).where(jobs.c.analysis_id == request["analysisId"], jobs.c.source == source)
        ).first()
        if existing is not None:
            job = row_dict(existing)
            if job["status"] != "FAILED":
                return job
            c.execute(
                update(jobs)
                .where(jobs.c.id == job["id"])
                .values(
                    status="QUEUED",
                    attempts=0,
                    run_after=now(),
                    error=None,
                    request=request,
                    callback_status="NONE",
                    callback_attempts=0,
                )
            )
            return job | {"status": "QUEUED"}
        job_id = str(uuid.uuid4())
        values = {
            "id": job_id,
            "analysis_id": request["analysisId"],
            "source": source,
            "request": request,
            "video_key": video_key,
            "status": "QUEUED",
            "attempts": 0,
            "run_after": now(),
            "created_at": now(),
            "callback_status": "NONE",
            "callback_attempts": 0,
        }
        c.execute(insert(jobs).values(**values))
        return values


def claim(worker: str, lease_seconds: int) -> dict | None:
    """Hands the next job to this worker (or None). Safe with many workers at once."""
    s = settings()
    t = now()
    due = or_(
        and_(jobs.c.status == "QUEUED", jobs.c.run_after <= t),
        and_(jobs.c.status == "RUNNING", jobs.c.lease_until < t),  # its worker died: take it over
    )
    pick = select(jobs.c.id).where(due).order_by(jobs.c.created_at).limit(1)
    if not s.is_sqlite:
        pick = pick.with_for_update(skip_locked=True)  # Postgres: FOR UPDATE SKIP LOCKED
    with engine().begin() as c:
        job_id = c.execute(pick).scalar()
        if job_id is None:
            return None
        c.execute(
            update(jobs)
            .where(jobs.c.id == job_id)
            .values(
                status="RUNNING",
                attempts=jobs.c.attempts + 1,
                worker=worker,
                started_at=t,
                lease_until=t + timedelta(seconds=lease_seconds),
            )
        )
        return row_dict(c.execute(select(jobs).where(jobs.c.id == job_id)).one())


def heartbeat(job_id: str, worker: str, lease_seconds: int) -> bool:
    """Extends the lease. False means another worker took the job over: stop working on it."""
    with engine().begin() as c:
        res = c.execute(
            update(jobs)
            .where(jobs.c.id == job_id, jobs.c.worker == worker, jobs.c.status == "RUNNING")
            .values(lease_until=now() + timedelta(seconds=lease_seconds))
        )
        return res.rowcount == 1


def finish(
    job_id: str,
    worker: str,
    result: dict,
    timings: dict,
    overlay_key: str | None,
    callback: bool,
    thumb_key: str | None = None,
) -> None:
    with engine().begin() as c:
        c.execute(
            update(jobs)
            .where(jobs.c.id == job_id, jobs.c.worker == worker)
            .values(
                status=result["status"],
                result=result,
                timings=timings,
                finished_at=now(),
                lease_until=None,
                error=result.get("error"),
                overlay_key=overlay_key,
                thumb_key=thumb_key,
                callback_status="PENDING" if callback else "NONE",
                callback_next_at=now(),
            )
        )


def retry_later(job_id: str, worker: str, error: str, attempts: int) -> bool:
    """
    Puts a job back with EXPONENTIAL BACKOFF plus JITTER: wait 30 s, then 60, then 120...
    plus a random bit, so many failed jobs don't all retry in the same second
    (the "thundering herd"). Returns False when out of attempts.
    """
    if attempts >= settings().job_max_attempts:
        return False
    delay = 30 * 2 ** (attempts - 1) + random.uniform(0, 10)
    with engine().begin() as c:
        c.execute(
            update(jobs)
            .where(jobs.c.id == job_id, jobs.c.worker == worker)
            .values(
                status="QUEUED",
                run_after=now() + timedelta(seconds=delay),
                error=error[:500],
                lease_until=None,
            )
        )
    return True


def get_job(job_id: str) -> dict | None:
    with engine().connect() as c:
        row = c.execute(select(jobs).where(jobs.c.id == job_id)).first()
        return row_dict(row) if row else None


def get_by_analysis(analysis_id: str, source: str = "tracka") -> dict | None:
    with engine().connect() as c:
        row = c.execute(
            select(jobs).where(jobs.c.analysis_id == analysis_id, jobs.c.source == source)
        ).first()
        return row_dict(row) if row else None


def list_jobs(limit: int = 50, source: str | None = None) -> list[dict]:
    q = select(jobs).order_by(jobs.c.created_at.desc()).limit(limit)
    if source:
        q = q.where(jobs.c.source == source)
    with engine().connect() as c:
        return [row_dict(r) for r in c.execute(q)]


# ---------------------------------------------------------------- callbacks


def callbacks_due(limit: int = 20) -> list[dict]:
    with engine().connect() as c:
        rows = c.execute(
            select(jobs)
            .where(jobs.c.callback_status == "PENDING", jobs.c.callback_next_at <= now())
            .order_by(jobs.c.callback_next_at)
            .limit(limit)
        )
        return [row_dict(r) for r in rows]


def callback_result(job_id: str, ok: bool, error: str | None, attempts: int) -> None:
    max_attempts = settings().callback_max_attempts
    if ok:
        values: dict[str, Any] = {"callback_status": "SENT", "callback_error": None}
    elif attempts >= max_attempts:
        values = {"callback_status": "GAVE_UP", "callback_error": (error or "")[:500]}
    else:
        delay = 15 * 2 ** (attempts - 1) + random.uniform(0, 5)  # 15 s, 30 s, 1 min, 2 min...
        values = {"callback_next_at": now() + timedelta(seconds=delay), "callback_error": (error or "")[:500]}
    with engine().begin() as c:
        c.execute(update(jobs).where(jobs.c.id == job_id).values(callback_attempts=attempts, **values))


# ---------------------------------------------------------------- ratings & stats


def add_rating(
    job_id: str, rater: str, overall: int, role: str | None, skills: dict | None, notes: str | None
) -> str:
    rid = str(uuid.uuid4())
    with engine().begin() as c:
        c.execute(
            insert(ratings).values(
                id=rid,
                job_id=job_id,
                rater=rater,
                role=role,
                overall=overall,
                skills=skills or {},
                notes=notes,
                created_at=now(),
            )
        )
    return rid


def list_ratings(job_id: str | None = None) -> list[dict]:
    q = select(ratings).order_by(ratings.c.created_at.desc())
    if job_id:
        q = q.where(ratings.c.job_id == job_id)
    with engine().connect() as c:
        return [dict(r._mapping) for r in c.execute(q)]


def status_counts() -> dict[str, int]:
    with engine().connect() as c:
        return {s: n for s, n in c.execute(select(jobs.c.status, func.count()).group_by(jobs.c.status))}


def oldest_queued_seconds() -> float:
    with engine().connect() as c:
        oldest = c.execute(select(func.min(jobs.c.created_at)).where(jobs.c.status == "QUEUED")).scalar()
    oldest = _aware(oldest)
    return (now() - oldest).total_seconds() if oldest else 0.0


def recent_finished(hours: int = 24) -> list[dict]:
    since = now() - timedelta(hours=hours)
    with engine().connect() as c:
        rows = c.execute(
            select(
                jobs.c.status,
                jobs.c.created_at,
                jobs.c.started_at,
                jobs.c.finished_at,
                jobs.c.timings,
                jobs.c.callback_status,
            ).where(jobs.c.finished_at >= since)
        )
        return [row_dict(r) for r in rows]


def ping() -> bool:
    with engine().connect() as c:
        c.execute(text("SELECT 1"))
    return True
