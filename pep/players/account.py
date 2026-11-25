"""
Settings › Your data and Help: download everything Tracka holds about you,
and report a problem.

DATA PORTABILITY (handbook chapter 12): a player, or their guardian, can ask
"what do you have on me?". `export()` answers in one JSON file, built from the
same tables the app uses. It walks every table that points at the player (the
same foreign-key walk that deleting an account uses), so a new feature's data
is included the day it's added, and nothing secret leaves: password hashes,
login sessions and one-time codes are left out.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel
from sqlalchemy import Column, DateTime, ForeignKey, String, Table, Text, insert, select

from .. import db
from ..log import get_logger
from . import auth, store

log = get_logger(__name__)

feedback = Table(
    "feedback",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("kind", String(16), nullable=False),  # problem | idea | safety
    Column("text", Text, nullable=False),
    Column("app_version", String(20)),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

# Never exported: secrets and things that only make sense to the server.
SKIP_TABLES = {"sessions", "guardian_sessions", "upload_keys", "devices"}
SKIP_COLUMNS = {"password_hash", "otp_hash", "otp_expires_at", "otp_tries", "token", "token_hash", "user_id"}


def _clean(v: Any) -> Any:
    if isinstance(v, datetime | date):
        return v.isoformat()
    return v


def export(uid: str) -> dict:
    out: dict[str, Any] = {
        "exportedAt": datetime.now(UTC).isoformat(),
        "about": "Everything Tracka holds about you.",
    }
    with db.engine().connect() as c:
        user = c.execute(select(store.users).where(store.users.c.id == uid)).first()
        if user is not None:
            out["account"] = {k: _clean(v) for k, v in user._mapping.items() if k not in SKIP_COLUMNS}
        for table in db.metadata.sorted_tables:
            if table is store.users or table.name in SKIP_TABLES:
                continue
            for col in table.c:
                if any(fk.column is store.users.c.id for fk in col.foreign_keys):
                    rows = c.execute(select(table).where(col == uid)).all()
                    if rows:
                        key = table.name if col.name == "user_id" else f"{table.name} ({col.name})"
                        out[key] = [
                            {k: _clean(v) for k, v in r._mapping.items() if k not in SKIP_COLUMNS}
                            for r in rows
                        ]
        # Pep's results live with the analysis jobs, linked from the player's clips.
        job_ids = [v["job_id"] for v in out.get("videos", []) if v.get("job_id")]
        if job_ids:
            jobs = c.execute(
                select(db.jobs.c.id, db.jobs.c.status, db.jobs.c.result).where(db.jobs.c.id.in_(job_ids))
            ).all()
            out["analyses"] = [{"id": j.id, "status": j.status, "result": j.result} for j in jobs]
    return out


router = APIRouter(tags=["player app: account"])


@router.get("/me/export")
def export_me(user: dict = Depends(auth.current_user)) -> dict:
    log.info("player.export", user_id=user["id"])
    return export(user["id"])


class FeedbackIn(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")
    kind: Literal["problem", "idea", "safety"] = "problem"
    text: str = Field(min_length=3, max_length=2000)
    app_version: str | None = Field(None, max_length=20)


@router.post("/feedback", status_code=201)
def send_feedback(body: FeedbackIn, user: dict = Depends(auth.current_user)) -> dict:
    """Help › Report a problem. Safety reports are logged as warnings so they stand out."""
    with db.engine().begin() as c:
        c.execute(
            insert(feedback).values(
                id=str(uuid.uuid4()),
                user_id=user["id"],
                kind=body.kind,
                text=body.text.strip(),
                app_version=body.app_version,
                created_at=datetime.now(UTC),
            )
        )
    (log.warning if body.kind == "safety" else log.info)(
        "player.feedback", user_id=user["id"], kind=body.kind
    )
    return {"ok": True}
