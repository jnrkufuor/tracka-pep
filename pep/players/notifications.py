"""
Notifications: the bell on Home, and (later) push messages to the phone.

Two kinds of notification, made two ways:

    EVENTS     something just happened: Pep finished a clip, someone gave you
               respect, your pitch was confirmed, your guardian answered.
               The code that saw it happen calls a function here.
    SCHEDULE   something is coming up: a Pep session today, a game tomorrow,
               a new weekly challenge. `sweep()` works these out from the
               player's week. It runs when the app opens the bell (and can run
               from a cron job once push is live).

Every notification has a DEDUPE KEY ("review:<clip id>", "event:<id>:<date>"),
unique per player, so running `sweep()` twice, or a worker retrying a job,
never makes the same notification twice. Same idea as the upload queue's
idempotency key (handbook chapter 10).

The player chooses which kinds they get (Settings › Notifications). Quiet
hours (9 pm to 7 am, Ghana time) hold back push messages; for under-18s
quiet hours are always on. Guardian and safety notices always come through.

Push goes through Firebase Cloud Messaging (push.py). Until the Firebase
settings are in place it only logs; the in-app list works either way.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel
from sqlalchemy import JSON, Column, DateTime, ForeignKey, String, Table, insert, select, update

from .. import db
from ..log import get_logger
from . import auth, review, store

log = get_logger(__name__)
GHANA = ZoneInfo("Africa/Accra")
QUIET = (time(21, 0), time(7, 0))
# Settings › Notifications. Each kind is on unless the player turns it off.
KINDS = ("tips", "reviews", "reminders", "events", "respect")
ALWAYS = ("guardian", "safety", "pitch", "challenge")  # small, important, or rare
FROM_PEP = ("tips", "reviews", "reminders")

notifications = Table(
    "notifications",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("kind", String(12), nullable=False),
    Column("dedupe", String(120), nullable=False),
    Column("title", String(120), nullable=False),
    Column("body", String(240), nullable=False, default=""),
    Column("link", JSON),  # where a tap goes: {"screen": "video", "id": "..."}
    Column("created_at", DateTime(timezone=True), nullable=False, index=True),
    Column("read_at", DateTime(timezone=True)),
)

devices = Table(
    "devices",
    db.metadata,
    Column("token", String(255), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("platform", String(12), nullable=False),  # android | ios | web
    Column("created_at", DateTime(timezone=True), nullable=False),
)


def now() -> datetime:
    return datetime.now(UTC)


def prefs(uid: str) -> dict[str, bool]:
    s = store.get_profile(uid)["settings"].get("notifications") or {}
    return {k: bool(s.get(k, True)) for k in KINDS}


def quiet_now(uid: str, at: datetime | None = None) -> bool:
    """Inside quiet hours (Ghana time)? Under 18 it's always on; adults can turn it off."""
    p = store.get_profile(uid)
    age = store.age_on(p["birth_date"])
    on = (age is not None and age < 18) or p["settings"].get("quietHours", True)
    t = (at or now()).astimezone(GHANA).time()
    start, end = QUIET
    return bool(on) and (t >= start or t < end)


def push(uid: str, title: str, body: str, link: dict | None = None) -> None:
    """Send to the player's phones (pep/players/push.py; only logs until Firebase is set up)."""
    from . import push as fcm

    fcm.send(uid, title, body, link)


def notify(
    uid: str,
    kind: str,
    dedupe: str,
    title: str,
    body: str = "",
    link: dict | None = None,
    *,
    update_existing: bool = False,
) -> bool:
    """Add a notification unless the player turned this kind off or it already exists.
    `update_existing`: refresh the words of an existing one instead (respect counts) and mark it unread."""
    if kind in KINDS and not prefs(uid)[kind]:
        return False
    with db.engine().begin() as c:
        row = c.execute(
            select(notifications.c.id).where(notifications.c.user_id == uid, notifications.c.dedupe == dedupe)
        ).first()
        if row is not None:
            if update_existing:
                c.execute(
                    update(notifications)
                    .where(notifications.c.id == row.id)
                    .values(title=title[:120], body=body[:240], created_at=now(), read_at=None)
                )
            return False
        c.execute(
            insert(notifications).values(
                id=str(uuid.uuid4()),
                user_id=uid,
                kind=kind,
                dedupe=dedupe,
                title=title[:120],
                body=body[:240],
                link=link,
                created_at=now(),
            )
        )
    if not quiet_now(uid):
        push(uid, title, body, link)
    return True


# ---------------------------------------------------------------- events


def clock(seconds: float) -> str:
    """12:40, like a match clock (the app shows times the same way)."""
    t = round(seconds)
    return f"{t // 60}:{t % 60:02d}"


def clip_finished(job_id: str) -> None:
    """Called by the worker after it saves a result. Never raises: notifications are extras."""
    try:
        with db.engine().connect() as c:
            v = c.execute(select(store.videos).where(store.videos.c.job_id == job_id)).first()
        if v is None:
            return
        full = store.get_video(v.user_id, v.id)
        if full is None:
            return
        title = full.get("title") or "your clip"
        if full.get("status") not in ("READY", "FAILED"):
            return  # going to be retried
        if full.get("status") == "FAILED":
            notify(
                v.user_id,
                "reviews",
                f"review:{v.id}",
                f"Pep couldn't read {title}",
                "Tap to see why and how to film it.",
                {"screen": "video", "id": v.id},
            )
            return
        r = review.review(full.get("result"))
        tips = len(r["tips"]) if r else 0
        first = (r["workOn"] or r["wentWell"] or [{}])[0].get("atSeconds") if r else None
        body = (
            f"{tips} tip{'s' if tips != 1 else ''}"
            + (f", starting at {clock(first)}" if first is not None else "")
            if tips
            else "See what went well."
        )
        if v.drill and full.get("clip_type") == "drill":
            notify(
                v.user_id,
                "tips",
                f"review:{v.id}",
                "Pep counted your attempt",
                body,
                {"screen": "video", "id": v.id},
            )
        else:
            notify(
                v.user_id,
                "reviews",
                f"review:{v.id}",
                f"Pep's read on {title} is ready",
                body,
                {"screen": "video", "id": v.id},
            )
    except Exception as exc:  # the clip is saved either way
        log.warning("notify.clip_failed", job_id=job_id, error=str(exc)[:200])


def respect_given(owner: str, post_id: str, giver_name: str, count: int) -> None:
    """One notification per clip per day, updated as respect comes in ('Ama and 3 others')."""
    who = giver_name if count <= 1 else f"{giver_name} and {count - 1} other{'s' if count > 2 else ''}"
    notify(
        owner,
        "respect",
        f"respect:{post_id}:{date.today().isoformat()}",
        f"{who} gave you respect",
        "On your clip",
        {"screen": "post", "id": post_id},
        update_existing=True,
    )


def pitch_confirmed(uid: str, pitch_id: str, name: str) -> None:
    notify(
        uid,
        "pitch",
        f"pitch:{pitch_id}",
        "Your pitch was confirmed",
        f"{name} now shows in Places to play",
        {"screen": "pitchside", "id": "near"},
    )


def guardian_answered(uid: str, kind: str, yes: bool) -> None:
    what = {
        "account": "your account",
        "delete": "deleting your account",
        "post": "posting clips",
        "share_card": "sharing your card",
        "search": "showing up in search",
    }[kind]
    notify(
        uid,
        "guardian",
        f"guardian:{kind}:{uuid.uuid4().hex[:8]}",
        f"Your guardian said {'yes' if yes else 'not yet'} to {what}",
        "Everything's open now." if yes and kind == "account" else "",
        {"screen": "guardian"},
    )


# ---------------------------------------------------------------- schedule


def sweep(uid: str, today: date | None = None) -> None:
    """Coming-up notifications from the player's week, plus the new weekly challenge."""
    from . import pitchside, training

    today = today or datetime.now(GHANA).date()
    try:
        per_week = int(store.get_profile(uid)["settings"].get("sessionsPerWeek", 3))
        wk = training.week(uid, training.monday_of(today), today, per_week, store.list_videos(uid))
        days = {d["date"]: d for d in wk["days"]}
        tomorrow = today + timedelta(days=1)
        for it in (days.get(today.isoformat()) or {}).get("items", []):
            if it["kind"] == "pep" and it.get("status") == "planned":
                notify(
                    uid,
                    "reminders",
                    f"session:{today.isoformat()}",
                    f"Pep session today: {it['title']}",
                    "Short and doable. Warm up first.",
                    {"screen": "week"},
                )
        if tomorrow.isoformat() in days:
            for it in days[tomorrow.isoformat()].get("items", []):
                if it["kind"] in ("team", "match", "game", "school", "other"):
                    at = f" at {it['time']}" if it.get("time") else ""
                    notify(
                        uid,
                        "events",
                        f"event:{it.get('id', it['title'])}:{tomorrow.isoformat()}",
                        f"{it['title']} is tomorrow{at}",
                        "",
                        {"screen": "week"},
                    )
        if today.weekday() < 3:  # early in the week
            ch = pitchside.this_week(today)
            notify(
                uid,
                "challenge",
                f"challenge:{pitchside.week_key(today)}",
                f"New challenge: {ch['short'].lower()}",
                "Ends Sunday",
                {"screen": "pitchside", "id": "challenges"},
            )
    except Exception as exc:
        log.warning("notify.sweep_failed", user_id=uid, error=str(exc)[:200])


# ---------------------------------------------------------------- routes

router = APIRouter(tags=["player app: notifications"])


class Body(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


def _view(r: Any) -> dict:
    created = r.created_at if r.created_at.tzinfo else r.created_at.replace(tzinfo=UTC)
    return {
        "id": r.id,
        "kind": r.kind,
        "group": "pep" if r.kind in FROM_PEP else "activity",
        "title": r.title,
        "body": r.body,
        "link": r.link,
        "createdAt": created.isoformat(),
        "read": r.read_at is not None,
    }


@router.get("/notifications")
def list_notifications(user: dict = Depends(auth.current_user)) -> dict:
    sweep(user["id"])
    with db.engine().connect() as c:
        rows = c.execute(
            select(notifications)
            .where(notifications.c.user_id == user["id"])
            .order_by(notifications.c.created_at.desc())
            .limit(60)
        ).all()
    items = [_view(r) for r in rows]
    return {"items": items, "unread": sum(not i["read"] for i in items), "quietNow": quiet_now(user["id"])}


class ReadIn(Body):
    ids: list[str] | None = Field(None, max_length=100)  # none = mark all read


@router.post("/notifications/read")
def mark_read(body: ReadIn, user: dict = Depends(auth.current_user)) -> dict:
    q = update(notifications).where(notifications.c.user_id == user["id"], notifications.c.read_at.is_(None))
    if body.ids is not None:
        q = q.where(notifications.c.id.in_(body.ids))
    with db.engine().begin() as c:
        c.execute(q.values(read_at=now()))
    return {"ok": True}


class DeviceIn(Body):
    token: str = Field(min_length=10, max_length=255)
    platform: str = Field(pattern=r"^(android|ios|web)$")


@router.put("/devices", status_code=204)
def register_device(body: DeviceIn, user: dict = Depends(auth.current_user)) -> None:
    """Where push messages go: the Firebase device token from the app."""
    with db.engine().begin() as c:
        c.execute(devices.delete().where(devices.c.token == body.token))
        c.execute(
            insert(devices).values(
                token=body.token, user_id=user["id"], platform=body.platform, created_at=now()
            )
        )


@router.delete("/devices/{token}", status_code=204)
def forget_device(token: str, user: dict = Depends(auth.current_user)) -> None:
    """Log out: stop sending pushes to this phone."""
    with db.engine().begin() as c:
        c.execute(devices.delete().where(devices.c.token == token, devices.c.user_id == user["id"]))
