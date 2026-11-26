"""
Crash reports from the app: POST /v1/app-errors, and Pep Lab › App errors.

WHY NOT PUT SENTRY IN THE APP? The app is used by children. Every analytics or
crash SDK inside it has to be declared in the store privacy forms, and each one
sends data straight from the phone to another company. Instead the app sends a
small report to *our* API (`lib/state/crash_report.dart`), and the server
decides what to keep and what to forward (pep/errors.py, with the same
scrubbing). One place to check, one privacy story.

WHAT A REPORT HOLDS: the error message and stack trace (emails and phone
numbers replaced), which screen, the app version and platform. Not the
player's name, clips or anything they typed. It points at `users` so it is
included in "Download my data" and deleted with the account.

KEEPING IT CHEAP (handbook chapter 10, "rate limits"): a crash inside a build
method can fire 60 times a second. The app sends each different error once per
session; the server also keeps at most `PER_DAY` reports per player per day
and `ANON_PER_DAY` from logged-out phones, and ignores the rest.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel
from sqlalchemy import Column, DateTime, ForeignKey, String, Table, Text, func, insert, select

from .. import db
from ..errors import capture_message, scrub_text
from ..log import get_logger
from . import auth
from .moderation import _lab

log = get_logger(__name__)

PER_DAY = 20
ANON_PER_DAY = 500

app_errors = Table(
    "app_errors",
    db.metadata,
    Column("id", String(36), primary_key=True),
    # Nullable: the app can crash before anyone logs in.
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True),
    Column("fingerprint", String(16), nullable=False, index=True),  # same error = same fingerprint
    Column("message", Text, nullable=False),
    Column("stack", Text),
    Column("screen", String(60)),
    Column("app_version", String(20)),
    Column("platform", String(20)),
    Column("created_at", DateTime(timezone=True), nullable=False, index=True),
)


def fingerprint(message: str, stack: str | None) -> str:
    """Group the same crash together: the message's first line plus the top of the stack."""
    top = "\n".join((stack or "").strip().splitlines()[:3])
    return hashlib.sha256(f"{message.splitlines()[0] if message else ''}\n{top}".encode()).hexdigest()[:16]


def optional_user(authorization: str | None = Header(None)) -> dict | None:
    """The logged-in player if the token is good, otherwise None (crashes before login still count)."""
    if not authorization:
        return None
    try:
        return auth.current_user(authorization)
    except Exception:
        return None


class AppErrorIn(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="ignore")
    message: str = Field(min_length=1, max_length=2000)
    stack: str | None = Field(None, max_length=8000)
    screen: str | None = Field(None, max_length=60)
    app_version: str | None = Field(None, max_length=20)
    platform: str | None = Field(None, max_length=20)


router = APIRouter(tags=["player app: crash reports"])


@router.post("/app-errors", status_code=202)
def report(body: AppErrorIn, user: dict | None = Depends(optional_user)) -> dict:
    uid = user["id"] if user else None
    since = datetime.now(UTC) - timedelta(days=1)
    with db.engine().begin() as c:
        q = select(func.count()).select_from(app_errors).where(app_errors.c.created_at >= since)
        q = q.where(app_errors.c.user_id == uid) if uid else q.where(app_errors.c.user_id.is_(None))
        if c.execute(q).scalar_one() >= (PER_DAY if uid else ANON_PER_DAY):
            return {"kept": False}
        message = scrub_text(body.message)[:2000]
        stack = scrub_text(body.stack)[:8000] if body.stack else None
        fp = fingerprint(message, stack)
        c.execute(
            insert(app_errors).values(
                id=str(uuid.uuid4()),
                user_id=uid,
                fingerprint=fp,
                message=message,
                stack=stack,
                screen=body.screen,
                app_version=body.app_version,
                platform=body.platform,
                created_at=datetime.now(UTC),
            )
        )
    log.warning("app.error", fingerprint=fp, screen=body.screen, version=body.app_version)
    capture_message(
        message, source="app", screen=body.screen, version=body.app_version, platform=body.platform
    )
    return {"kept": True}


lab_router = APIRouter(prefix="/lab/app-errors", tags=["lab"], dependencies=[Depends(_lab)])


@lab_router.get("")
def recent(days: int = 7) -> list[dict]:
    """The last week's crashes, one row per kind, most frequent first."""
    since = datetime.now(UTC) - timedelta(days=max(1, min(days, 90)))
    t = app_errors.c
    with db.engine().connect() as c:
        rows = c.execute(
            select(
                t.fingerprint,
                func.count().label("count"),
                func.count(func.distinct(t.user_id)).label("players"),
                func.max(t.created_at).label("last"),
                func.max(t.message).label("message"),
                func.max(t.screen).label("screen"),
                func.max(t.app_version).label("version"),
            )
            .where(t.created_at >= since)
            .group_by(t.fingerprint)
            .order_by(func.count().desc())
            .limit(100)
        ).all()
    return [
        {
            "fingerprint": r.fingerprint,
            "count": r.count,
            "players": r.players,
            "last": r.last.isoformat() if r.last else None,
            "message": r.message,
            "screen": r.screen,
            "version": r.version,
        }
        for r in rows
    ]


@lab_router.get("/{fp}")
def one(fp: str) -> dict:
    """The newest report of one kind, with its stack trace."""
    with db.engine().connect() as c:
        r = c.execute(
            select(app_errors).where(app_errors.c.fingerprint == fp).order_by(app_errors.c.created_at.desc())
        ).first()
    if r is None:
        return {}
    m = dict(r._mapping)
    m.pop("user_id", None)
    m["created_at"] = m["created_at"].isoformat()
    return m
