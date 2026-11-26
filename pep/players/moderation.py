"""
Moderation: the staff side of Pitchside safety (Pep Lab › Safety).

Players report clips (pitchside.py); three reports from different players
hide a clip for everyone until a person looks at it. Players can also send
"Someone is unsafe" from Help (account.py). Staff see all of it here and act:

    keep         the clip was fine: show it again and clear its reports
    take down    remove the post (the clip stays private in the player's library)
    pause        stop this player posting for 7 or 30 days, or until lifted
    done         mark a safety or problem report as handled

Every action is written to `moderation_log` with who did it and why, so
decisions can be checked later (an AUDIT TRAIL, handbook chapter 10). Staff
see shirt names, never full names, unless a safety report needs a human to
contact the guardian; that's a TODO with the safeguarding policy.

These routes sit under /lab and use the Lab password (pep/api/app.py).
"""

from __future__ import annotations

import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, ForeignKey, String, Table, Text, delete, func, insert, select, update

from .. import db
from ..config import settings
from ..log import get_logger
from ..storage import storage
from . import account, pitchside, store

log = get_logger(__name__)

posting_holds = Table(
    "posting_holds",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("reason", String(200), nullable=False),
    Column("until", DateTime(timezone=True)),  # None = until a person lifts it
    Column("created_at", DateTime(timezone=True), nullable=False),
)

moderation_log = Table(
    "moderation_log",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("action", String(16), nullable=False),  # keep | take_down | pause | lift | done
    Column("post_id", String(36)),
    Column("user_id", String(36)),
    Column("feedback_id", String(36)),
    Column("by", String(60), nullable=False),
    Column("note", Text, nullable=False, default=""),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

feedback_done = Table(
    "feedback_done",
    db.metadata,
    Column("feedback_id", String(36), ForeignKey("feedback.id", ondelete="CASCADE"), primary_key=True),
    Column("done_at", DateTime(timezone=True), nullable=False),
)


def now() -> datetime:
    return datetime.now(UTC)


def _aware(d: datetime | None) -> datetime | None:
    return d.replace(tzinfo=UTC) if d is not None and d.tzinfo is None else d


def on_hold(uid: str) -> bool:
    with db.engine().connect() as c:
        row = c.execute(select(posting_holds).where(posting_holds.c.user_id == uid)).first()
    if row is None:
        return False
    until = _aware(row.until)
    return until is None or until > now()


def _log(c, action: str, by: str, note: str = "", **ids) -> None:
    c.execute(
        insert(moderation_log).values(
            id=str(uuid.uuid4()), action=action, by=by, note=note, created_at=now(), **ids
        )
    )


def queue() -> dict:
    """Everything waiting for a person: reported posts (hidden ones first) and open reports."""
    with db.engine().connect() as c:
        counts = c.execute(
            select(
                pitchside.reports.c.post_id,
                func.count(func.distinct(pitchside.reports.c.user_id)).label("n"),
                func.max(pitchside.reports.c.created_at).label("last"),
            ).group_by(pitchside.reports.c.post_id)
        ).all()
        reasons = c.execute(select(pitchside.reports.c.post_id, pitchside.reports.c.reason)).all()
        post_rows = {
            r.id: r
            for r in c.execute(
                select(pitchside.posts).where(pitchside.posts.c.id.in_([x.post_id for x in counts]))
            )
        }
        keys = {
            v.id: v.video_key
            for v in c.execute(
                select(store.videos.c.id, store.videos.c.video_key).where(
                    store.videos.c.id.in_([p.video_id for p in post_rows.values()])
                )
            )
        }
        done = {r.feedback_id for r in c.execute(select(feedback_done.c.feedback_id))}
        fb = c.execute(
            select(account.feedback).order_by(account.feedback.c.created_at.desc()).limit(200)
        ).all()
        holds = c.execute(select(posting_holds)).all()
    posts = []
    for x in counts:
        p = post_rows.get(x.post_id)
        if p is None:
            continue
        why: dict[str, int] = {}
        for r in reasons:
            if r.post_id == x.post_id:
                why[r.reason] = why.get(r.reason, 0) + 1
        a = pitchside.author(p.user_id)
        posts.append(
            {
                "postId": p.id,
                "videoId": p.video_id,
                "videoUrl": storage().url(keys[p.video_id]) if p.video_id in keys else None,
                "caption": p.caption,
                "hidden": p.hidden,
                "reports": x.n,
                "reasons": why,
                "lastReport": _aware(x.last).isoformat(),  # type: ignore[union-attr]
                "author": {
                    "id": p.user_id,
                    "shirtName": a["shirtName"],
                    "ageGroup": a["ageGroup"],
                    "under18": a["under18"],
                },
                "onHold": on_hold(p.user_id),
            }
        )
    posts.sort(key=lambda p: (not p["hidden"], p["lastReport"]), reverse=False)
    reports = [
        {
            "id": f.id,
            "kind": f.kind,
            "text": f.text,
            "userId": f.user_id,
            "shirtName": pitchside.author(f.user_id)["shirtName"],
            "createdAt": _aware(f.created_at).isoformat(),  # type: ignore[union-attr]
        }
        for f in fb
        if f.id not in done
    ]
    reports.sort(key=lambda r: r["kind"] != "safety")  # safety first
    return {
        "posts": posts,
        "reports": reports,
        "holds": [
            {
                "userId": h.user_id,
                "reason": h.reason,
                "until": _aware(h.until).isoformat() if h.until else None,
            }
            for h in holds
        ],
    }


_basic = HTTPBasic(auto_error=False)


def _lab(creds: HTTPBasicCredentials | None = Depends(_basic)) -> str:
    """The Lab password (same rule as pep/api/app.py); returns who acted, for the log."""
    password = settings().lab_password
    if password and (creds is None or not secrets.compare_digest(creds.password, password)):
        raise HTTPException(
            401, "Pep Lab password needed", headers={"WWW-Authenticate": 'Basic realm="Pep Lab"'}
        )
    return (creds.username if creds and creds.username else "staff")[:60]


router = APIRouter(prefix="/lab/moderation", tags=["lab: moderation"])


@router.get("")
def get_queue(by: str = Depends(_lab)) -> dict:
    return queue()


class PostAction(BaseModel):
    action: Literal["keep", "take_down"]
    note: str = Field("", max_length=500)


@router.post("/posts/{post_id}")
def act_on_post(post_id: str, body: PostAction, by: str = Depends(_lab)) -> dict:
    with db.engine().begin() as c:
        p = c.execute(select(pitchside.posts).where(pitchside.posts.c.id == post_id)).first()
        if p is None:
            raise HTTPException(404, "Post not found.")
        if body.action == "keep":
            c.execute(update(pitchside.posts).where(pitchside.posts.c.id == post_id).values(hidden=False))
            c.execute(delete(pitchside.reports).where(pitchside.reports.c.post_id == post_id))
        else:
            for t in (pitchside.respect, pitchside.saves, pitchside.reports):
                c.execute(delete(t).where(t.c.post_id == post_id))
            c.execute(delete(pitchside.posts).where(pitchside.posts.c.id == post_id))
        _log(c, body.action, by, body.note, post_id=post_id, user_id=p.user_id)
    log.info("moderation.post", action=body.action, post_id=post_id, by=by)
    return queue()


class HoldIn(BaseModel):
    days: int | None = Field(7, ge=1, le=365)  # None = until lifted
    reason: str = Field(min_length=3, max_length=200)


@router.put("/holds/{user_id}")
def pause_posting(user_id: str, body: HoldIn, by: str = Depends(_lab)) -> dict:
    until = now() + timedelta(days=body.days) if body.days else None
    with db.engine().begin() as c:
        c.execute(delete(posting_holds).where(posting_holds.c.user_id == user_id))
        c.execute(
            insert(posting_holds).values(user_id=user_id, reason=body.reason, until=until, created_at=now())
        )
        _log(c, "pause", by, body.reason, user_id=user_id)
    return queue()


@router.delete("/holds/{user_id}")
def lift_pause(user_id: str, by: str = Depends(_lab)) -> dict:
    with db.engine().begin() as c:
        c.execute(delete(posting_holds).where(posting_holds.c.user_id == user_id))
        _log(c, "lift", by, user_id=user_id)
    return queue()


@router.post("/reports/{feedback_id}/done")
def report_done(feedback_id: str, note: str = "", by: str = Depends(_lab)) -> dict:
    with db.engine().begin() as c:
        c.execute(delete(feedback_done).where(feedback_done.c.feedback_id == feedback_id))
        c.execute(insert(feedback_done).values(feedback_id=feedback_id, done_at=now()))
        _log(c, "done", by, note[:500], feedback_id=feedback_id)
    return queue()


@router.get("/log")
def audit_log(by: str = Depends(_lab)) -> list[dict]:
    with db.engine().connect() as c:
        rows = c.execute(select(moderation_log).order_by(moderation_log.c.created_at.desc()).limit(200)).all()
    return [
        {
            "action": r.action,
            "postId": r.post_id,
            "userId": r.user_id,
            "feedbackId": r.feedback_id,
            "by": r.by,
            "note": r.note,
            "at": _aware(r.created_at).isoformat(),  # type: ignore[union-attr]
        }
        for r in rows
    ]
