"""
Pep's review of one clip, shaped for the app (Pep › Reviews, Pep › Tips).

The analysis result (pep/contracts.py `CoachResult`) is written for machines:
a list of moments, a summary, some tips. A player needs it as a story:

    headline       "You looked around more"  + one or two sentences
    went well      moments with a time you can tap to jump the video there
    to work on     the same, in gold
    tips           one thing to practise, tied to a moment AND a skill area,
                   with a drill Pep picked for the kit the player has
    where it goes  the skill areas this clip touched (Me › Growth)

This is a VIEW: it's computed from the stored result each time it's asked for,
never stored. That's the same idea as the training week (training.py): store
the facts once, derive the presentation. Change the wording here and every
old clip gets the new wording; there is nothing to migrate.

Two rules carry over from the coach (handbook chapter 07):
  - Numbers come from measurement. A tip has words and a drill, never a score.
  - Without the AI coach (no key, it failed, the player turned notes off) the
    review still works: titles and tips come from rules below.

Words to know: *derived state*, *view model*, *fallback*.
"""

from __future__ import annotations

from typing import Any

from . import training
from .skill_areas import catalogue

# Rule tips: used when a WORK_ON moment has an area but the AI gave no tip for it.
# Plain words, one thing to do. Football opinion: review these with coaches.
RULE_TIPS: dict[str, tuple[str, str]] = {
    "close_control": (
        "Keep the ball closer",
        "Here the ball ran away from you. Use small touches with the inside and outside of your foot.",
    ),
    "scanning": (
        "Look before you get the ball",
        "A quick look over your shoulder shows you where the space is before the ball arrives.",
    ),
    "passing_forward": (
        "Keep your ankle firm when you pass",
        "Lock the ankle and hit the middle of the ball so it goes where you aim.",
    ),
    "turning": (
        "Turn away from pressure",
        "Open your body as the ball comes so your first touch takes you away from the defender.",
    ),
    "short_speed": (
        "Get off the mark faster",
        "Lean forward and drive your arms for the first few steps.",
    ),
    "keeps_moving": (
        "Keep moving when you don't have the ball",
        "Small movements make you easier to find. Stay on your toes.",
    ),
}


def _areas() -> dict[str, dict]:
    """Skill area id → {name, group}."""
    return {
        i["id"]: {"name": i["name"], "group": g["name"]} for g in catalogue()["groups"] for i in g["items"]
    }


def pick_drill(area: str, kit: list[str] | None) -> dict | None:
    """The best drill for an area that the player can do with their kit.
    Drills that list the area first are the ones made for it."""
    fits = [d for d in training.library()["drills"] if area in d["areas"] and training.can_do(d, kit)]
    if not fits:
        return None
    d = min(fits, key=lambda d: d["areas"].index(area))
    return {k: d[k] for k in ("id", "name", "minutes", "how", "needs") if k in d}


def _moment(m: dict, areas: dict[str, dict]) -> dict:
    area = m.get("area")
    a = areas.get(area or "")
    title = m.get("title") or (
        a["name"] if a else ("Good moment" if m["kind"] == "GOOD" else "Something to work on")
    )
    return {
        "atSeconds": m["atSeconds"],
        "kind": m["kind"],
        "title": title,
        "text": m["text"],
        "area": area if a else None,
        "areaName": a["name"] if a else None,
    }


def review(result: dict[str, Any] | None, kit: list[str] | None = None) -> dict | None:
    """The review for one READY result (camelCase, as stored). None if not ready."""
    if not result or result.get("status") != "READY":
        return None
    areas = _areas()
    moments = [_moment(m, areas) for m in result.get("moments") or []]
    good = [m for m in moments if m["kind"] == "GOOD"]
    work = [m for m in moments if m["kind"] == "WORK_ON"]

    tips: list[dict] = []
    for t in result.get("tips") or []:
        if t.get("area") in areas:
            tips.append(
                {"area": t["area"], "title": t["title"], "text": t["text"], "atSeconds": t.get("atSeconds")}
            )
    covered = {t["area"] for t in tips}
    for m in work:  # rule tips for areas the AI didn't cover
        if m["area"] and m["area"] not in covered and m["area"] in RULE_TIPS:
            title, text = RULE_TIPS[m["area"]]
            tips.append({"area": m["area"], "title": title, "text": text, "atSeconds": m["atSeconds"]})
            covered.add(m["area"])
    for t in tips[:3]:
        a = areas[t["area"]]
        t |= {"areaName": a["name"], "group": a["group"], "drill": pick_drill(t["area"], kit)}
        if t["atSeconds"] is None:  # link to the closest moment about the same area
            same = [m for m in work if m["area"] == t["area"]]
            t["atSeconds"] = same[0]["atSeconds"] if same else None
    tips = tips[:3]

    touched: list[dict] = []
    for m in work + good:
        if m["area"] and m["area"] not in {x["id"] for x in touched}:
            touched.append(
                {
                    "id": m["area"],
                    "name": m["areaName"],
                    "group": areas[m["area"]]["group"],
                    "kind": m["kind"],
                }
            )

    title = result.get("headline") or (good[0]["title"] if good else "Here's what I saw")
    return {
        "headline": {"title": title, "text": result.get("summary") or ""},
        "wentWell": good,
        "workOn": work,
        "tips": tips,
        "areas": touched[:4],
        "source": result.get("coachSource") or "rules",
        "note": note(len(good), len(work), len(tips), result.get("headline")),
    }


def note(good: int, work: int, tips: int, headline: str | None = None) -> str:
    """The one line under a review in the list: 'You looked around more. 3 tips inside.'"""
    if headline and tips:
        return f"{headline}. {tips} tip{'s' if tips != 1 else ''} inside."
    parts = []
    if good:
        parts.append(f"{good} thing{'s' if good != 1 else ''} went well")
    if work:
        parts.append(f"{work} to work on")
    return (", ".join(parts) + ".") if parts else "Nothing stood out this time. Try a longer clip."


def all_tips(videos: list[dict], kit: list[str] | None = None) -> list[dict]:
    """Every tip from the player's ready clips, newest clip first (Pep › Tips)."""
    out = []
    for v in videos:
        r = review(v.get("result"), kit)
        if r is None:
            continue
        for t in r["tips"]:
            out.append(
                t | {"videoId": v["id"], "videoTitle": v.get("title") or "", "clipType": v["clip_type"]}
            )
    return out


def recent_work_on(videos: list[dict], limit: int = 2) -> list[str]:
    """Areas the newest review said to work on, so the training plan can pick them up
    ('New drill in your plan'). Videos come newest first from store.list_videos."""
    for v in videos:
        r = review(v.get("result"))
        if r is not None:
            ids = [t["area"] for t in r["tips"]] + [m["area"] for m in r["workOn"] if m["area"]]
            return list(dict.fromkeys(ids))[:limit]
    return []
