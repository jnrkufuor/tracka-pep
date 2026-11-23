"""
Skill areas: what the Me tab shows instead of an overall score.

Concept: a single number out of 100 hides everything that matters (and
invites "I'm a 62, so I'm bad"). So each skill area gets four honest parts:

  band        how the measured value compares with players in the same age
              group: Below average · Average · Above average · Strong · Standout
  average     the measured value itself, in plain words ("10 m in 1.92 s")
  confidence  how much to trust it: how many clips measured it, and whether
              those were timed tests (fair) or match clips (noisier)
  trend       which way it's going: growing, steady, dipping, or new

Only things Pep actually MEASURED get a band. The rest say why not:
"Not seen yet" (film the right clip), "Coming later" (Pep can't detect it
yet) or "Pep can't see this" (video can't show it; a coach can).

Numbers come from measurement, never from the language model (CLAUDE.md).
The catalogue (which skills, which measurements, key skills per position)
is pep/data/skill_areas.json. See docs/handbook/07-numbers-to-scores.md.
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from functools import cache
from pathlib import Path

from ..scoring.norms import age_band, standing

DATA = Path(__file__).resolve().parent.parent / "data" / "skill_areas.json"

WINDOW = 6  # newest measurements per metric that count
# Percentile cut-offs for the bands (the share of same-age players below you).
# Below 30 → Below average; 30-60 Average; 60-80 Above average; 80-93 Strong; 93+ Standout.
BANDS = ((30.0, "below"), (60.0, "average"), (80.0, "above"), (93.0, "strong"), (101.0, "standout"))
# Timed tests (a standard drill, metres known from cones) are fairer than match clips.
TIMED = {"sprint_30m_s", "split_10m_s", "agility_5105_s", "juggles_best", "wall_passes_30s"}
TREND_STEP = 5.0  # percentile points between the older and newer half to call it growing/dipping
AGE_LABEL = {"u13": "U13", "u15": "U15", "u17": "U17", "u20": "U20", "senior": "Adult"}


@cache
def catalogue() -> dict:
    return json.loads(DATA.read_text())


def band_for(percentile: float) -> str:
    for cut, name in BANDS:
        if percentile < cut:
            return name
    return "standout"


def confidence_for(metric: str, n: int) -> str:
    """More measurements → more trust; timed tests earn it faster than match clips."""
    if n == 0:
        return "low"
    if metric in TIMED:
        return "high" if n >= 2 else "medium"
    return "high" if n >= 4 else "medium" if n >= 2 else "low"


def trend_for(percentiles: Sequence[float]) -> str:
    """percentiles: newest first. Compare the newer half with the older half."""
    if len(percentiles) < 2:
        return "new"
    half = len(percentiles) // 2
    newer = sum(percentiles[:half]) / half
    older = sum(percentiles[half:]) / (len(percentiles) - half)
    if newer - older >= TREND_STEP:
        return "growing"
    if older - newer >= TREND_STEP:
        return "dipping"
    return "steady"


def say(template: str, value: float) -> str:
    """Fill an 'average' template: {v} value, {kmh} m/s as km/h, {pct} a share as %."""
    return template.format(v=value, kmh=f"{value * 3.6:.1f}", pct=f"{value * 100:.0f}")


def _series(videos: list[dict], metric: str) -> list[float]:
    """The metric's values from analysed clips, newest first (videos come newest first)."""
    out: list[float] = []
    for v in videos:
        if v.get("status") != "READY":
            continue
        value = ((v.get("result") or {}).get("metrics") or {}).get(metric)
        if isinstance(value, int | float):
            out.append(float(value))
            if len(out) == WINDOW:
                break
    return out


def _item(spec: dict, videos: list[dict], age: int | None, sex: str | None, positions: set[str]) -> dict:
    out = {
        "id": spec["id"],
        "name": spec["name"],
        "key": bool(positions & set(spec.get("key", []))),
        "state": spec.get("state", "not_seen"),
        "band": None,
        "average": None,
        "confidence": "low",
        "trend": "new",
        "measurements": 0,
        "howToMeasure": spec.get("how"),
    }
    if "metrics" not in spec:
        return out
    # The first metric (in catalogue order) that has data drives the average and confidence;
    # the band uses every metric with data, so a timed test and match speed both count.
    percentiles_now: list[float] = []
    lead: tuple[str, list[float], str] | None = None
    for metric, template in zip(spec["metrics"], spec["average"], strict=True):
        values = _series(videos, metric)
        if not values:
            continue
        ranked = [s.percentile for x in values if (s := standing(metric, x, age, sex)) is not None]
        if not ranked:
            continue
        percentiles_now.append(sum(ranked[:3]) / len(ranked[:3]))
        if lead is None:
            lead = (metric, values, template)
            out["trend"] = trend_for(ranked)
    if lead is None:
        return out
    metric, values, template = lead
    recent = values[:3]
    out.update(
        state="measured",
        band=band_for(sum(percentiles_now) / len(percentiles_now)),
        average=say(template, sum(recent) / len(recent)),
        confidence=confidence_for(metric, len(values)),
        measurements=len(values),
        howToMeasure=None,
    )
    return out


def skill_areas(
    videos: list[dict], positions: Sequence[str] | None, age: int | None, sex: str | None
) -> dict:
    """
    videos: the player's videos joined with their analysis (store.list_videos), newest first.
    Returns the groups and items for the Me tab, compared with the player's age group.
    """
    mine = {p.upper() for p in positions or []}
    group = age_band(age)
    groups = []
    for g in catalogue()["groups"]:
        if g.get("positions") and not mine & set(g["positions"]):
            continue
        items = [
            _item(spec, videos, age, sex, mine)
            for spec in g["items"]
            if not spec.get("positions") or mine & set(spec["positions"])
        ]
        # Key skills for your position first, then measured ones, keeping catalogue order otherwise.
        items.sort(key=lambda i: (not i["key"], i["state"] != "measured"))
        groups.append({"name": g["name"], "items": items})
    measured = sum(i["state"] == "measured" for g in groups for i in g["items"])
    return {
        "ageGroup": AGE_LABEL[group],
        "comparedWith": f"{AGE_LABEL[group]} players",
        "measured": measured,
        "groups": groups,
        "version": catalogue()["version"],
    }
