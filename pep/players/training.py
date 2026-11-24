"""
Training: the player's week, Pep's sessions, and how the body feels.

Concept: a PLAN is computed, not stored. We store only the facts the player
gives us (their team training and matches, sessions they moved or skipped,
sessions they finished, how their body feels) and rebuild the week from them
every time it's asked for. Nothing can get out of sync, and changing a rule
here changes every player's plan at once. That's "derived state": keep the
inputs, compute the outputs. See docs/handbook/02-designing-a-system.md.

The rules, in plain words:
  * Pep fits `sessionsPerWeek` sessions (default 3) around the player's own
    football: never on a match day or the day before one, preferring free
    days, and not two days in a row when it can avoid it.
  * The day before a match, anything that lands there becomes light.
  * In pain or injured → every session from today is a rest day; sore → light.
    Pep guides and refers; it never diagnoses (see pep/coach/llm.py rules).
  * A timed test is due when one was never done or is older than 14 days;
    it goes on the next normal session this week (one test a week).
  * A session's drills follow the player's focus areas (skill_areas.py):
    key areas for their position that are weakest, or not measured yet.

The drills are pep/data/training.json (football opinion: review with coaches).
"""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta
from functools import cache
from pathlib import Path
from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Table,
    delete,
    insert,
    select,
    update,
)

from .. import db

DATA = Path(__file__).resolve().parent.parent / "data" / "training.json"
WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
EVENT_KINDS = ("team", "match", "school", "game", "other")
HEALTH = ("fine", "sore", "pain", "injured")
EFFORTS = ("easy", "right", "hard")
BAND_ORDER = {"below": 0, "average": 1, "above": 2, "strong": 3, "standout": 4}

# ---------------------------------------------------------------- tables (all point at users.id)

events = Table(
    "events",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("kind", String(12), nullable=False),  # team | match | school | game | other
    Column("title", String(80), nullable=False, default=""),
    Column("weekdays", JSON, nullable=False, default=list),  # repeating: 0 = Monday … 6 = Sunday
    Column("on_date", Date),  # or a one-off date
    Column("time", String(5)),  # "16:00"
    Column("duration_min", Integer, nullable=False, default=90),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

# A session the player moved or skipped. `session_key` is "pep-<original date>".
session_changes = Table(
    "session_changes",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("session_key", String(20), primary_key=True),
    Column("action", String(8), nullable=False),  # "move" | "skip"
    Column("to_date", Date),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

training_log = Table(
    "training_log",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("session_key", String(20), nullable=False),
    Column("on_date", Date, nullable=False),
    Column("effort", String(8), nullable=False),  # easy | right | hard
    Column("hurt", Boolean, nullable=False, default=False),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

health = Table(
    "health",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("status", String(8), nullable=False, default="fine"),  # fine | sore | pain | injured
    Column("area", String(60)),  # where, in the player's words ("left ankle")
    Column("updated_at", DateTime(timezone=True), nullable=False),
)

TABLES = (events, session_changes, training_log, health)


@cache
def library() -> dict:
    return json.loads(DATA.read_text())


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def key_for(d: date) -> str:
    return f"pep-{d.isoformat()}"


def date_of(key: str) -> date:
    if not key.startswith("pep-"):
        raise ValueError("not a session key")
    return date.fromisoformat(key[4:])


# ---------------------------------------------------------------- storage


def _rows(q) -> list[dict]:
    with db.engine().connect() as c:
        return [dict(r._mapping) for r in c.execute(q)]


def list_events(uid: str) -> list[dict]:
    return _rows(select(events).where(events.c.user_id == uid).order_by(events.c.created_at))


def get_event(uid: str, event_id: str) -> dict | None:
    rows = _rows(select(events).where(events.c.user_id == uid, events.c.id == event_id))
    return rows[0] if rows else None


def add_event(uid: str, values: dict[str, Any]) -> dict:
    row = {
        "id": str(uuid.uuid4()),
        "user_id": uid,
        "created_at": db.now(),
        "title": "",
        "weekdays": [],
        **values,
    }
    with db.engine().begin() as c:
        c.execute(insert(events).values(**row))
    return row


def update_event(uid: str, event_id: str, values: dict[str, Any]) -> dict | None:
    with db.engine().begin() as c:
        c.execute(update(events).where(events.c.user_id == uid, events.c.id == event_id).values(**values))
    return get_event(uid, event_id)


def delete_event(uid: str, event_id: str) -> bool:
    with db.engine().begin() as c:
        return c.execute(delete(events).where(events.c.user_id == uid, events.c.id == event_id)).rowcount > 0


def set_change(uid: str, key: str, action: str, to: date | None = None) -> None:
    with db.engine().begin() as c:
        c.execute(
            delete(session_changes).where(
                session_changes.c.user_id == uid, session_changes.c.session_key == key
            )
        )
        c.execute(
            insert(session_changes).values(
                user_id=uid, session_key=key, action=action, to_date=to, created_at=db.now()
            )
        )


def clear_change(uid: str, key: str) -> None:
    with db.engine().begin() as c:
        c.execute(
            delete(session_changes).where(
                session_changes.c.user_id == uid, session_changes.c.session_key == key
            )
        )


def changes(uid: str) -> dict[str, dict]:
    return {
        r["session_key"]: r for r in _rows(select(session_changes).where(session_changes.c.user_id == uid))
    }


def log_done(uid: str, key: str, on: date, effort: str, hurt: bool) -> dict:
    row = {
        "id": str(uuid.uuid4()),
        "user_id": uid,
        "session_key": key,
        "on_date": on,
        "effort": effort,
        "hurt": hurt,
        "created_at": db.now(),
    }
    with db.engine().begin() as c:
        c.execute(
            delete(training_log).where(training_log.c.user_id == uid, training_log.c.session_key == key)
        )
        c.execute(insert(training_log).values(**row))
    return row


def done_keys(uid: str) -> dict[str, dict]:
    return {r["session_key"]: r for r in _rows(select(training_log).where(training_log.c.user_id == uid))}


def get_health(uid: str) -> dict:
    rows = _rows(select(health).where(health.c.user_id == uid))
    if not rows:
        return {"status": "fine", "area": None, "updated_at": None}
    return rows[0]


def set_health(uid: str, status: str, area: str | None) -> dict:
    with db.engine().begin() as c:
        c.execute(delete(health).where(health.c.user_id == uid))
        c.execute(insert(health).values(user_id=uid, status=status, area=area, updated_at=db.now()))
    return get_health(uid)


def delete_all(uid: str) -> None:
    """Used when an account is deleted (store.delete_user)."""
    with db.engine().begin() as c:
        for t in TABLES:
            c.execute(delete(t).where(t.c.user_id == uid))


# ---------------------------------------------------------------- the plan (computed)


def _events_on(evts: list[dict], d: date) -> list[dict]:
    return [e for e in evts if (d.weekday() in (e["weekdays"] or [])) or e["on_date"] == d]


def place_sessions(days: list[date], evts: list[dict], per_week: int) -> list[date]:
    """
    Pick the days for Pep's sessions in this week. Never a match day or the day before
    one; free days first; avoid back-to-back days; then fill from days with other football.
    """
    match = {d for d in days if any(e["kind"] == "match" for e in _events_on(evts, d))}
    before_match = {d - timedelta(days=1) for d in match}
    allowed = [d for d in days if d not in match and d not in before_match]
    free = [d for d in allowed if not _events_on(evts, d)]
    busy = [d for d in allowed if _events_on(evts, d)]
    chosen: list[date] = []
    for pool in (free, busy):
        for d in pool:  # first pass: not next to an already chosen day
            if len(chosen) < per_week and all(abs((d - c).days) > 1 for c in chosen):
                chosen.append(d)
        for d in pool:  # second pass: fill up, even back to back
            if len(chosen) < per_week and d not in chosen:
                chosen.append(d)
    return sorted(chosen)


def tests_due(videos: list[dict], today: date) -> list[str]:
    """Standard tests never done, or done longer ago than `retest_days`, oldest first."""
    lib = library()
    last: dict[str, date] = {}
    for v in videos:
        if v.get("status") != "READY" or v.get("clip_type") != "drill" or not v.get("drill"):
            continue
        created: datetime = v["created_at"]
        last.setdefault(v["drill"], created.date())  # videos are newest first
    due = []
    for drill in lib["tests"]:
        when = last.get(drill)
        if when is None or (today - when).days > lib["retest_days"]:
            due.append((when or date.min, drill))
    return [d for _, d in sorted(due)]


def week(
    uid: str,
    start: date,
    today: date,
    per_week: int,
    videos: list[dict],
) -> dict:
    days = [start + timedelta(days=i) for i in range(7)]
    evts = list_events(uid)
    moved = changes(uid)
    done = done_keys(uid)
    body = get_health(uid)
    match = {d for d in days if any(e["kind"] == "match" for e in _events_on(evts, d))}

    # Pep's sessions: placed by the rules, then moved/skipped by the player.
    sessions: dict[date, list[dict]] = {d: [] for d in days}
    originals = place_sessions(days, evts, per_week)
    incoming = [r for r in moved.values() if r["action"] == "move" and r["to_date"] in days]
    keys = {key_for(d): d for d in originals} | {r["session_key"]: r["to_date"] for r in incoming}
    for key, original in sorted(keys.items()):
        change = moved.get(key)
        on = change["to_date"] if change and change["action"] == "move" else original
        if on not in sessions:
            continue  # moved to another week
        status = "done" if key in done else "skipped" if change and change["action"] == "skip" else "planned"
        mode = "normal"
        if on >= today and body["status"] in ("pain", "injured"):
            mode = "rest"
        elif on >= today and body["status"] == "sore" or on + timedelta(days=1) in match or on in match:
            mode = "light"
        sessions[on].append(
            {"key": key, "mode": mode, "status": status, "moved": bool(change and change["action"] == "move")}
        )

    # One timed test a week, on the next normal session from today.
    due = tests_due(videos, today)
    test_on: tuple[date, str] | None = None
    if due:
        for d in days:
            if d >= today and any(s["mode"] == "normal" and s["status"] == "planned" for s in sessions[d]):
                test_on = (d, due[0])
                break

    out_days = []
    for d in days:
        items: list[dict] = []
        for e in _events_on(evts, d):
            items.append(
                {
                    "id": e["id"],
                    "kind": e["kind"],
                    "title": e["title"] or default_title(e["kind"]),
                    "time": e["time"],
                    "durationMin": e["duration_min"],
                    "repeats": bool(e["weekdays"]),
                    "status": "planned",
                }
            )
        for s in sessions[d]:
            items.append(
                {
                    "id": s["key"],
                    "kind": "rest" if s["mode"] == "rest" else "pep",
                    "title": session_title(s["mode"]),
                    "time": None,
                    "durationMin": session_minutes(s["mode"]),
                    "mode": s["mode"],
                    "status": s["status"],
                    "moved": s["moved"],
                }
            )
        if test_on and test_on[0] == d:
            t = library()["tests"][test_on[1]]
            items.append(
                {
                    "id": f"test-{test_on[1]}",
                    "kind": "test",
                    "title": t["name"],
                    "drill": test_on[1],
                    "status": "planned",
                }
            )
        out_days.append(
            {
                "date": d.isoformat(),
                "weekday": WEEKDAYS[d.weekday()],
                "isToday": d == today,
                "matchDay": d in match,
                "items": items,
            }
        )
    return {
        "start": start.isoformat(),
        "today": today.isoformat(),
        "sessionsPerWeek": per_week,
        "health": {"status": body["status"], "area": body["area"]},
        "testsDue": due,
        "days": out_days,
    }


def default_title(kind: str) -> str:
    return {
        "team": "Team training",
        "match": "Match",
        "school": "School training",
        "game": "Game with friends",
    }.get(kind, "Football")


def session_title(mode: str) -> str:
    return {"rest": "Rest and recover", "light": "Light session"}.get(mode, "Pep session")


def session_minutes(mode: str) -> int:
    lib = library()
    if mode == "rest":
        return 0
    if mode == "light":
        return lib["light"]["minutes"] + lib["cooldown"]["minutes"]
    return 30


def focus_areas(areas: dict, limit: int = 2) -> list[dict]:
    """The areas a session works on: weakest key areas first, then key areas not measured yet."""
    items = [i for g in areas.get("groups", []) for i in g["items"] if i["state"] in ("measured", "not_seen")]
    trainable = {a for d in library()["drills"] for a in d["areas"]}
    items = [i for i in items if i["id"] in trainable]

    def rank(i: dict) -> tuple:
        measured = i["state"] == "measured"
        return (not i["key"], not measured, BAND_ORDER.get(i["band"] or "", 9))

    return [{"id": i["id"], "name": i["name"]} for i in sorted(items, key=rank)[:limit]]


def can_do(drill: dict, kit: list[str] | None) -> bool:
    """
    Can the player do this drill with what they've got? Cones can be shoes or bottles,
    and friends aren't kit, so only a ball and a wall really limit what Pep picks.
    """
    have = set(kit or ["ball"]) | {"nothing", "cones", "friends"}
    return set(drill.get("needs", [])) <= have


def session_plan(
    key: str, mode: str, focus: list[dict], test: str | None = None, kit: list[str] | None = None
) -> dict:
    """The steps of one session: warm-up, drills for the focus areas (or a test), cool-down."""
    lib = library()
    if mode == "rest":
        return {
            "key": key,
            "mode": mode,
            "title": session_title(mode),
            "minutes": 0,
            "focus": [],
            "steps": [],
            "safety": "Rest today. If it still hurts in a few days, or it's swollen or you can't put weight on it, "
            "see a doctor or physio. Tell an adult or your coach.",
        }
    if mode == "light":
        steps = [lib["light"], lib["cooldown"]]
        return {
            "key": key,
            "mode": mode,
            "title": session_title(mode),
            "minutes": sum(s["minutes"] for s in steps),
            "focus": [],
            "steps": [_step(s) for s in steps],
            "safety": "Keep it easy. Stop if anything hurts, and tell an adult or your coach.",
        }
    picked: list[dict] = []
    if test:
        drill = next((d for d in lib["drills"] if d.get("film") == test), None)
        if drill:
            picked.append({**drill, "name": lib["tests"][test]["name"], "test": test})
    for f in focus:
        if len(picked) >= 2:
            break
        options = [d for d in lib["drills"] if f["id"] in d["areas"] and d not in picked]
        drill = next(
            (d for d in options if can_do(d, kit)), None
        )  # nothing they can do for it: skip this area
        if drill and all(p["id"] != drill["id"] for p in picked):
            picked.append(drill)
    if not picked:
        picked = [next((d for d in lib["drills"] if can_do(d, kit)), lib["drills"][0])]
    steps = [lib["warmup"], *picked, lib["cooldown"]]
    return {
        "key": key,
        "mode": mode,
        "title": session_title(mode),
        "minutes": sum(s["minutes"] for s in steps),
        "focus": focus,
        "steps": [_step(s) for s in steps],
        "safety": "Warm up first. Stop if anything hurts. Pep can't see injuries, so rest and tell an adult or your coach.",
    }


def _step(s: dict) -> dict:
    return {
        "id": s["id"],
        "name": s["name"],
        "minutes": s["minutes"],
        "how": s["how"],
        "needs": s.get("needs", []),
        "film": s.get("film"),
        "test": s.get("test"),
    }
