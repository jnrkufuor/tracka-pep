"""
Home's progress cards (canvas: Home): how your timed tests changed, your
training streak, and how ready your profile is for an academy.

All of it is DERIVED from what's already stored (clips, results, the training
log), like the week and the review: nothing new to keep in step.

    Your progress     first and latest result of each timed test, and what
                      the change means in plain words ("about 2 metres ahead
                      over 30 m"). Numbers come from measurement only.
    Training streak   weeks in a row you did every session Pep planned.
                      Growth, not a finish line: there's no "week 3 of 8".
    Academy-ready     five things academies look for in a profile, ticked
                      off from your own data. Only shown for that goal.
"""

from __future__ import annotations

from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import func, select

from .. import db
from . import auth, details, store, training
from .card import BESTS

STREAK_WEEKS = 26


def test_progress(videos: list[dict]) -> list[dict]:
    """For each timed test with 2+ results: first, latest, and whether it got better."""
    out = []
    for metric, (label, unit, lower) in BESTS.items():
        series = [
            (v["created_at"].date(), float(v["result"]["metrics"][metric]))
            for v in reversed(videos)  # oldest first
            if v.get("status") == "READY"
            and ((v.get("result") or {}).get("metrics") or {}).get(metric) is not None
        ]
        if len(series) < 2:
            continue
        (d0, first), (d1, latest) = series[0], series[-1]
        change = latest - first
        better = change < 0 if lower else change > 0
        weeks = max(1, round((d1 - d0).days / 7))
        line = None
        if metric == "sprint_30m_s" and better:
            # Same race, two runners: the faster one is ahead by (speed × time saved).
            metres = 30 / latest * abs(change)
            line = f"Over a 30 m race, that puts you about {metres:.0f} metre{'s' if round(metres) != 1 else ''} ahead of where you were."
        out.append(
            {
                "metric": metric,
                "label": label,
                "unit": unit,
                "first": round(first, 2),
                "latest": round(latest, 2),
                "change": round(abs(change), 2),
                "better": better,
                "weeks": weeks,
                "line": line,
                "count": len(series),
            }
        )
    return out


def streak(uid: str, today: date, per_week: int, videos: list[dict]) -> dict:
    """Weeks in a row (before this one) where every planned Pep session was done."""
    if per_week <= 0:
        return {"weeks": 0, "best": 0, "thisWeek": None}
    run = best = 0
    current = None
    monday = training.monday_of(today)
    first = True
    for i in range(1, STREAK_WEEKS + 1):
        start = monday - timedelta(weeks=i)
        wk = training.week(uid, start, today, per_week, videos)
        pep = [it for d in wk["days"] for it in d["items"] if it["kind"] == "pep"]
        hit = (
            bool(pep)
            and all(it["status"] in ("done", "skipped") for it in pep)
            and any(it["status"] == "done" for it in pep)
        )
        if hit:
            run += 1
            best = max(best, run)
        else:
            if first:
                current = run
                first = False
            run = 0
    if first:
        current = run
    wk = training.week(uid, monday, today, per_week, videos)
    pep = [it for d in wk["days"] for it in d["items"] if it["kind"] == "pep"]
    return {
        "weeks": current or 0,
        "best": max(best, current or 0),
        "thisWeek": {"done": sum(it["status"] == "done" for it in pep), "planned": len(pep)},
    }


def readiness(uid: str, videos: list[dict]) -> dict:
    """Academy-ready profile: five things, each ticked from the player's own data."""
    from .pitchside import challenge_attempts

    p = store.get_profile(uid)
    d = details.get(uid)
    ready = [v for v in videos if v.get("status") == "READY"]
    with db.engine().connect() as c:
        tried = c.execute(
            select(func.count(func.distinct(challenge_attempts.c.challenge_id))).where(
                challenge_attempts.c.user_id == uid
            )
        ).scalar_one()
    steps = [
        (
            "tests",
            "Baseline tests",
            any(v["clip_type"] == "drill" and v.get("drill") in training.library()["tests"] for v in ready),
        ),
        ("reads", "Clips with Pep's read", len(ready) >= 3),
        ("details", "Your profile details", bool(p["positions"] and p["height_m"] and d["shirt_name"])),
        ("match", "A full-match clip", any(v["clip_type"] == "match" for v in ready)),
        ("challenges", "Challenge results in 3 skill areas", tried >= 3),
    ]
    return {
        "steps": [{"id": i, "name": n, "done": ok} for i, n, ok in steps],
        "done": sum(ok for *_, ok in steps),
        "total": len(steps),
        "next": next((n for _, n, ok in steps if not ok), None),
    }


router = APIRouter(tags=["player app: home"])


@router.get("/progress")
def progress(user: dict = Depends(auth.current_user)) -> dict:
    uid = user["id"]
    videos = store.list_videos(uid)
    per_week = int(store.get_profile(uid)["settings"].get("sessionsPerWeek", 3))
    today = date.today()
    return {
        "tests": test_progress(videos),
        "streak": streak(uid, today, per_week, videos),
        "readiness": readiness(uid, videos),
        "nextRetest": next(iter(training.tests_due(videos, today)), None),
    }
