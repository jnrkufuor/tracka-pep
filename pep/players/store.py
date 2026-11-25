"""
Player data: accounts, profiles, videos and login sessions.

These tables share the database (and SQLAlchemy `metadata`) with the job
queue in pep/db.py. A player's video points at the job that analysed it
(`videos.job_id`), so the analysis result lives in exactly one place.

Built to grow: scouts, clubs and opportunities will be new tables that
reference `users.id`, not changes to these. See docs/handbook/02-designing-a-system.md.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    Column,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Table,
    Text,
    delete,
    insert,
    select,
    update,
)

from .. import db
from . import details, training  # noqa: F401  (their tables must exist before delete_user walks them)

users = Table(
    "users",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("email", String(254), nullable=False, unique=True, index=True),
    Column("password_hash", String(255), nullable=False),
    Column("role", String(16), nullable=False, default="player"),  # later: "scout", "coach", "admin"
    Column("created_at", DateTime(timezone=True), nullable=False),
)

profiles = Table(
    "profiles",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("display_name", String(80), nullable=False, default=""),
    Column("birth_date", Date),
    Column("sex", String(8)),  # "male" | "female": which norms to compare with
    Column("height_m", Float),
    Column("positions", JSON, nullable=False, default=list),
    Column("foot", String(8)),  # "left" | "right" | "both"
    Column("region", String(40)),
    Column("club", String(80)),
    Column("bio", Text),
    Column("guardian_email", String(254)),
    Column("guardian_consent", Boolean, nullable=False, default=False),
    Column("settings", JSON, nullable=False, default=dict),
    Column("updated_at", DateTime(timezone=True), nullable=False),
)

videos = Table(
    "videos",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("title", String(120), nullable=False, default=""),
    Column("video_key", String(255), nullable=False),
    Column("clip_type", String(16), nullable=False, default="match"),
    Column("drill", String(40)),
    Column("size_bytes", Integer),
    Column("job_id", String(36), index=True),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

# One row per refresh token handed out. Lets us log a device out (revoke) and
# detect a stolen token being reused (rotation): see auth.py.
sessions = Table(
    "sessions",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("expires_at", DateTime(timezone=True), nullable=False),
    Column("revoked", Boolean, nullable=False, default=False),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

DEFAULT_SETTINGS: dict[str, Any] = {
    "units": "kmh",  # "kmh" | "mph"
    "coachNotes": True,  # AI-written notes on each clip
    "notifyWhenReady": True,
    "shareWithScouts": False,  # for the future scouting app; off until the player opts in
    "mainColour": "volt",  # Settings › Main colour: the "you" colour (Pep purple and warning gold never change)
    "reduceMotion": False,  # Settings › Accessibility: less movement, on top of the phone's own setting
    "uploadOnWifiOnly": True,  # Settings › Your data: mobile data is expensive, so clips wait for Wi-Fi by default
    "sessionsPerWeek": 3,  # Pep sessions fitted around the player's own football each week
    "kit": ["ball"],  # what the player has: ball, wall, space, cones, gym (Pep picks drills they can do)
    "pepVoice": "coach",  # "street" (local football talk) or "coach" (plain coaching words)
}


def new_id() -> str:
    return str(uuid.uuid4())


# ---------------------------------------------------------------- users


def create_user(email: str, password_hash: str) -> dict:
    uid = new_id()
    now = db.now()
    with db.engine().begin() as c:
        c.execute(
            insert(users).values(
                id=uid, email=email, password_hash=password_hash, role="player", created_at=now
            )
        )
        c.execute(
            insert(profiles).values(
                user_id=uid,
                display_name="",
                positions=[],
                settings=DEFAULT_SETTINGS,
                guardian_consent=False,
                updated_at=now,
            )
        )
    return {"id": uid, "email": email, "role": "player"}


def user_by_email(email: str) -> dict | None:
    with db.engine().connect() as c:
        row = c.execute(select(users).where(users.c.email == email)).first()
        return dict(row._mapping) if row else None


def user_by_id(uid: str) -> dict | None:
    with db.engine().connect() as c:
        row = c.execute(select(users).where(users.c.id == uid)).first()
        return dict(row._mapping) if row else None


def delete_user(uid: str) -> list[str]:
    """Deletes the account and everything in it. Returns storage keys to delete."""
    keys: list[str] = []
    with db.engine().begin() as c:
        for v in c.execute(select(videos).where(videos.c.user_id == uid)):
            keys.append(v.video_key)
            if v.job_id:
                job = c.execute(select(db.jobs).where(db.jobs.c.id == v.job_id)).first()
                if job is not None:
                    keys += [k for k in (job.overlay_key, job.thumb_key) if k]
                c.execute(delete(db.jobs).where(db.jobs.c.id == v.job_id))
                c.execute(delete(db.ratings).where(db.ratings.c.job_id == v.job_id))
        # Every row in every table that points at this user, children first
        # (SQLite doesn't enforce ON DELETE CASCADE unless asked to). Found from the
        # foreign keys themselves, so a new feature's table is covered the day it's
        # added: nothing to remember here. (Words to know: *metadata reflection*.)
        for table in reversed(db.metadata.sorted_tables):
            for col in table.c:
                if table is not users and any(fk.column is users.c.id for fk in col.foreign_keys):
                    c.execute(delete(table).where(col == uid))
        c.execute(delete(users).where(users.c.id == uid))
    return keys


# ---------------------------------------------------------------- profiles


def get_profile(uid: str) -> dict:
    with db.engine().connect() as c:
        row = c.execute(select(profiles).where(profiles.c.user_id == uid)).one()
    p = dict(row._mapping)
    p["settings"] = {**DEFAULT_SETTINGS, **(p.get("settings") or {})}
    return p


def update_profile(uid: str, values: dict) -> dict:
    if values:
        with db.engine().begin() as c:
            c.execute(update(profiles).where(profiles.c.user_id == uid).values(**values, updated_at=db.now()))
    return get_profile(uid)


def age_on(birth: date | None, today: date | None = None) -> int | None:
    if birth is None:
        return None
    today = today or date.today()
    return today.year - birth.year - ((today.month, today.day) < (birth.month, birth.day))


# ---------------------------------------------------------------- videos


def add_video(
    uid: str, video_id: str, title: str, key: str, clip_type: str, drill: str | None, size: int, job_id: str
) -> None:
    with db.engine().begin() as c:
        c.execute(
            insert(videos).values(
                id=video_id,
                user_id=uid,
                title=title,
                video_key=key,
                clip_type=clip_type,
                drill=drill,
                size_bytes=size,
                job_id=job_id,
                created_at=db.now(),
            )
        )


def list_videos(uid: str, limit: int = 200) -> list[dict]:
    """The player's videos, newest first, each joined with its analysis job."""
    q = (
        select(videos, db.jobs.c.status, db.jobs.c.result, db.jobs.c.thumb_key, db.jobs.c.overlay_key)
        .select_from(videos.outerjoin(db.jobs, videos.c.job_id == db.jobs.c.id))
        .where(videos.c.user_id == uid)
        .order_by(videos.c.created_at.desc())
        .limit(limit)
    )
    with db.engine().connect() as c:
        return [_aware(dict(r._mapping)) for r in c.execute(q)]


def get_video(uid: str, video_id: str) -> dict | None:
    q = (
        select(
            videos,
            db.jobs.c.status,
            db.jobs.c.result,
            db.jobs.c.thumb_key,
            db.jobs.c.overlay_key,
            db.jobs.c.error,
        )
        .select_from(videos.outerjoin(db.jobs, videos.c.job_id == db.jobs.c.id))
        .where(videos.c.user_id == uid, videos.c.id == video_id)
    )
    with db.engine().connect() as c:
        row = c.execute(q).first()
        return _aware(dict(row._mapping)) if row else None


def rename_video(uid: str, video_id: str, title: str) -> bool:
    with db.engine().begin() as c:
        res = c.execute(
            update(videos).where(videos.c.user_id == uid, videos.c.id == video_id).values(title=title)
        )
        return res.rowcount == 1


def delete_video(uid: str, video_id: str) -> list[str]:
    v = get_video(uid, video_id)
    if v is None:
        return []
    keys = [k for k in (v["video_key"], v.get("thumb_key"), v.get("overlay_key")) if k]
    with db.engine().begin() as c:
        c.execute(delete(videos).where(videos.c.id == video_id))
        if v.get("job_id"):
            c.execute(delete(db.jobs).where(db.jobs.c.id == v["job_id"]))
    return keys


def _aware(d: dict) -> dict:
    if isinstance(d.get("created_at"), datetime) and d["created_at"].tzinfo is None:
        from datetime import UTC

        d["created_at"] = d["created_at"].replace(tzinfo=UTC)
    return d


# ---------------------------------------------------------------- sessions


def add_session(uid: str, expires_at: datetime) -> str:
    sid = new_id()
    with db.engine().begin() as c:
        c.execute(
            insert(sessions).values(
                id=sid, user_id=uid, expires_at=expires_at, revoked=False, created_at=db.now()
            )
        )
    return sid


def get_session(sid: str) -> dict | None:
    with db.engine().connect() as c:
        row = c.execute(select(sessions).where(sessions.c.id == sid)).first()
        return dict(row._mapping) if row else None


def revoke_session(sid: str) -> None:
    with db.engine().begin() as c:
        c.execute(update(sessions).where(sessions.c.id == sid).values(revoked=True))


def revoke_all_sessions(uid: str) -> None:
    with db.engine().begin() as c:
        c.execute(update(sessions).where(sessions.c.user_id == uid).values(revoked=True))
