"""
The player's training API (Home's week, the Pep tab's schedule and sessions).

    GET    /v1/week?start=YYYY-MM-DD      the week (Monday start): football + Pep sessions + tests
    GET    /v1/sessions/{key}             one Pep session: warm-up, drills for your focus, cool-down
    POST   /v1/sessions/{key}/move        move it to another day          {"to": "2026-11-28"}
    POST   /v1/sessions/{key}/skip        skip it (Pep keeps the rest of the week)
    POST   /v1/sessions/{key}/restore     undo a move or skip
    POST   /v1/sessions/{key}/done        log it: {"effort": "easy"|"right"|"hard", "hurt": false}
    GET    /v1/events                     your own football: team training, matches, school, games
    POST   /v1/events                     add one (repeating weekdays, or a one-off date)
    PATCH  /v1/events/{id}                change it
    DELETE /v1/events/{id}                remove it
    GET    /v1/health                     how your body feels
    PUT    /v1/health                     {"status": "fine"|"sore"|"pain"|"injured", "area": "left ankle"}

Like every /v1 route, each query is filtered by the logged-in player (see
tests/test_training.py, which checks one player can't touch another's events).
The week is computed from these facts on every request: see pep/players/training.py.
"""

from __future__ import annotations

from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

from . import auth, store, training
from .skill_areas import skill_areas

# No prefix here: routes.py includes this router into its own /v1 router.
router = APIRouter(tags=["player app: training"])


class Body(BaseModel):
    """camelCase on the wire (like routes.py), and unknown fields rejected."""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


TIME = r"^([01]\d|2[0-3]):[0-5]\d$"


def _today() -> date:
    return date.today()


def _per_week(uid: str) -> int:
    return int(store.get_profile(uid)["settings"].get("sessionsPerWeek", 3))


def _focus(uid: str, videos: list[dict]) -> list[dict]:
    p = store.get_profile(uid)
    return training.focus_areas(skill_areas(videos, p["positions"], store.age_on(p["birth_date"]), p["sex"]))


def _find_session(uid: str, key: str) -> tuple[dict, dict]:
    """The session's item in its week (wherever it was moved to), plus that week."""
    try:
        original = training.date_of(key)
    except ValueError as e:
        raise HTTPException(404, "No such session.") from e
    change = training.changes(uid).get(key)
    on = change["to_date"] if change and change["action"] == "move" and change["to_date"] else original
    videos = store.list_videos(uid)
    wk = training.week(uid, training.monday_of(on), _today(), _per_week(uid), videos)
    for d in wk["days"]:
        for item in d["items"]:
            if item["id"] == key:
                return {**item, "date": d["date"]}, wk
    raise HTTPException(404, "No such session.")


# ---------------------------------------------------------------- the week


@router.get("/week")
def get_week(start: date | None = None, user: dict = Depends(auth.current_user)) -> dict:
    today = _today()
    monday = training.monday_of(start or today)
    return training.week(user["id"], monday, today, _per_week(user["id"]), store.list_videos(user["id"]))


# ---------------------------------------------------------------- sessions


@router.get("/sessions/{key}")
def get_session(key: str, user: dict = Depends(auth.current_user)) -> dict:
    item, wk = _find_session(user["id"], key)
    day = next(d for d in wk["days"] if d["date"] == item["date"])
    test = next((i["drill"] for i in day["items"] if i["kind"] == "test"), None)
    videos = store.list_videos(user["id"])
    plan = training.session_plan(key, item.get("mode", "normal"), _focus(user["id"], videos), test)
    return {**plan, "date": item["date"], "status": item["status"]}


class MoveIn(Body):
    to: date


@router.post("/sessions/{key}/move")
def move_session(key: str, body: MoveIn, user: dict = Depends(auth.current_user)) -> dict:
    item, _ = _find_session(user["id"], key)
    if item["status"] == "done":
        raise HTTPException(409, "You've already done this session.")
    if body.to < _today():
        raise HTTPException(422, "Pick today or a day after.")
    if training.date_of(key) == body.to:
        training.clear_change(user["id"], key)
    else:
        training.set_change(user["id"], key, "move", body.to)
    return get_week(training.monday_of(body.to), user)


@router.post("/sessions/{key}/skip")
def skip_session(key: str, user: dict = Depends(auth.current_user)) -> dict:
    item, _ = _find_session(user["id"], key)
    if item["status"] == "done":
        raise HTTPException(409, "You've already done this session.")
    training.set_change(user["id"], key, "skip")
    return get_week(training.monday_of(date.fromisoformat(item["date"])), user)


@router.post("/sessions/{key}/restore")
def restore_session(key: str, user: dict = Depends(auth.current_user)) -> dict:
    _find_session(user["id"], key)
    training.clear_change(user["id"], key)
    return get_week(training.monday_of(training.date_of(key)), user)


class DoneIn(Body):
    effort: Literal["easy", "right", "hard"]
    hurt: bool = False


@router.post("/sessions/{key}/done")
def finish_session(key: str, body: DoneIn, user: dict = Depends(auth.current_user)) -> dict:
    item, _ = _find_session(user["id"], key)
    on = date.fromisoformat(item["date"])
    if on > _today():
        raise HTTPException(409, "This session is on a later day.")
    training.log_done(user["id"], key, on, body.effort, body.hurt)
    # Something hurt: Pep switches to "sore" (light sessions) until the player says otherwise,
    # and points them to a professional. It never guesses what the injury is.
    if body.hurt and training.get_health(user["id"])["status"] == "fine":
        training.set_health(user["id"], "sore", None)
    return {
        "logged": True,
        "health": training.get_health(user["id"])["status"],
        "next": "If it still hurts tomorrow, rest and tell an adult or your coach."
        if body.hurt
        else "Nice work. Pep will use this to set your next sessions.",
    }


# ---------------------------------------------------------------- your own football (events)


class EventIn(Body):
    kind: Literal["team", "match", "school", "game", "other"]
    title: str = Field("", max_length=80)
    weekdays: list[int] = Field(default_factory=list, max_length=7)
    on_date: date | None = None
    time: str | None = Field(None, pattern=TIME)
    duration_min: int = Field(90, ge=10, le=240)

    @model_validator(mode="after")
    def when(self) -> EventIn:
        if any(d < 0 or d > 6 for d in self.weekdays):
            raise ValueError("weekdays are 0 (Monday) to 6 (Sunday)")
        if bool(self.weekdays) == bool(self.on_date):
            raise ValueError("give repeating weekdays or one date, not both")
        return self


class EventPatch(Body):
    title: str | None = Field(None, max_length=80)
    weekdays: list[int] | None = Field(None, max_length=7)
    time: str | None = Field(None, pattern=TIME)
    duration_min: int | None = Field(None, ge=10, le=240)


def _event_out(e: dict) -> dict:
    return {
        "id": e["id"],
        "kind": e["kind"],
        "title": e["title"] or training.default_title(e["kind"]),
        "weekdays": e["weekdays"] or [],
        "onDate": e["on_date"].isoformat() if e["on_date"] else None,
        "time": e["time"],
        "durationMin": e["duration_min"],
    }


@router.get("/events")
def list_events(user: dict = Depends(auth.current_user)) -> list[dict]:
    return [_event_out(e) for e in training.list_events(user["id"])]


@router.post("/events", status_code=201)
def add_event(body: EventIn, user: dict = Depends(auth.current_user)) -> dict:
    values = body.model_dump()
    values["weekdays"] = sorted(set(values["weekdays"]))
    return _event_out(training.add_event(user["id"], values))


@router.patch("/events/{event_id}")
def change_event(event_id: str, body: EventPatch, user: dict = Depends(auth.current_user)) -> dict:
    if training.get_event(user["id"], event_id) is None:
        raise HTTPException(404, "No such event.")
    values = body.model_dump(exclude_unset=True)
    if "weekdays" in values:
        if any(d < 0 or d > 6 for d in values["weekdays"] or []):
            raise HTTPException(422, "weekdays are 0 (Monday) to 6 (Sunday)")
        values["weekdays"] = sorted(set(values["weekdays"] or []))
    e = training.update_event(user["id"], event_id, values)
    assert e is not None
    return _event_out(e)


@router.delete("/events/{event_id}", status_code=204)
def remove_event(event_id: str, user: dict = Depends(auth.current_user)) -> None:
    if not training.delete_event(user["id"], event_id):
        raise HTTPException(404, "No such event.")


# ---------------------------------------------------------------- how your body feels


class HealthIn(Body):
    status: Literal["fine", "sore", "pain", "injured"]
    area: str | None = Field(None, max_length=60)


ADVICE = {
    "fine": "Good. Pep keeps your plan as it is.",
    "sore": "Pep has made your sessions lighter. Stop if anything hurts.",
    "pain": "Rest today. Don't play through pain. Tell an adult or your coach.",
    "injured": "Rest, and see a doctor or physio. Pep pauses your training until you say you're ready.",
}


@router.get("/health")
def get_health(user: dict = Depends(auth.current_user)) -> dict:
    h = training.get_health(user["id"])
    return {"status": h["status"], "area": h["area"], "advice": ADVICE[h["status"]]}


@router.put("/health")
def put_health(body: HealthIn, user: dict = Depends(auth.current_user)) -> dict:
    h = training.set_health(user["id"], body.status, body.area if body.status != "fine" else None)
    return {"status": h["status"], "area": h["area"], "advice": ADVICE[h["status"]]}
