"""
The player's coach summary: what the Home and Pep tabs show.

One clip is noisy (a bad angle, an off day). The summary looks across the
player's clips, using the same rules as Tracka's Journey so the two never
disagree:
  * no overall score until 3 analysed clips;
  * the score is the mean of the newest 5; the change compares with the 5 before;
  * each skill averages its newest 5 measurements;
  * confidence is LOW under 5 clips, at most MEDIUM under 10, and never above
    what the clips themselves report.

It also picks what to work on (the two lowest skills, with their drills),
strengths (the two highest), a suggested standard drill to record next, and
one weekly score per week for the trend chart.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Sequence
from datetime import datetime, timedelta

from ..drills.runner import drill_catalogue

CLIPS_NEEDED = 3
WINDOW = 5
RANK = {"LOW": 0, "MEDIUM": 1, "HIGH": 2}
LEVELS = ("LOW", "MEDIUM", "HIGH")

# Which standard drill gives a fair, timed number for each skill.
DRILL_FOR_SKILL = {
    "Pace": "sprint_30m",
    "Acceleration": "sprint_30m",
    "Agility": "agility_5105",
    "Ball control": "juggling",
    "Passing": "wall_passes",
    "Dribbling": "juggling",
}


def _mean(xs: Sequence[float]) -> float | None:
    return sum(xs) / len(xs) if xs else None


def summary(videos: list[dict], positions: list[str] | None = None) -> dict:
    """
    videos: the player's videos joined with their jobs, newest first (store.list_videos).
    positions: the player's positions; roles for those positions are listed first.
    """
    ready = [
        v
        for v in videos
        if v.get("status") == "READY" and (v.get("result") or {}).get("overallScore") is not None
    ]
    out: dict = {
        "clipsUploaded": len(videos),
        "clipsAnalysed": len(ready),
        "clipsNeeded": CLIPS_NEEDED,
        "processing": sum(v.get("status") in ("QUEUED", "RUNNING") for v in videos),
        "overallScore": None,
        "change": None,
        "confidence": "LOW",
        "skills": [],
        "focus": [],
        "strengths": [],
        "trend": [],
        "recentMoments": [],
        "suggestedDrill": None,
        "bestRoles": [],
    }
    if not ready:
        return out

    scores = [v["result"]["overallScore"] for v in ready]
    if len(ready) >= CLIPS_NEEDED:
        now = _mean(scores[:WINDOW])
        out["overallScore"] = round(now) if now is not None else None
        before = scores[WINDOW : 2 * WINDOW]
        if before and now is not None:
            out["change"] = round(now - (_mean(before) or now))

    # Confidence: the median of the newest clips, capped by how many clips there are.
    recent = sorted(RANK[v["result"].get("confidence") or "LOW"] for v in ready[:WINDOW])
    typical = recent[len(recent) // 2]
    cap = 0 if len(ready) < WINDOW else 1 if len(ready) < 10 else 2
    out["confidence"] = LEVELS[min(typical, cap)]

    # Skills: newest 5 per skill, keeping the newest explanation and drill.
    per_skill: dict[str, list[dict]] = defaultdict(list)
    for v in ready:
        for s in v["result"].get("skills", []):
            if len(per_skill[s["name"]]) < WINDOW:
                per_skill[s["name"]].append(s)
    skills = []
    for name, items in per_skill.items():
        skills.append(
            {
                "name": name,
                "score": round(_mean([i["score"] for i in items]) or 0),
                "clips": len(items),
                "explanation": items[0].get("explanation", ""),
                "drill": items[0].get("drill", ""),
                "source": items[0].get("source"),
                "confidence": items[0].get("confidence"),
            }
        )
    skills.sort(key=lambda s: -s["score"])
    out["skills"] = skills
    measured = [s for s in skills if s["source"] != "ai_observed"]
    out["strengths"] = measured[:2]
    out["focus"] = sorted(measured, key=lambda s: s["score"])[:2]

    # A standard drill to record next: the one that measures their weakest skill fairly.
    catalogue = drill_catalogue()
    for s in out["focus"]:
        d = DRILL_FOR_SKILL.get(s["name"])
        if d in catalogue:
            out["suggestedDrill"] = {
                "id": d,
                "label": catalogue[d]["label"],
                "how": catalogue[d]["how"],
                "forSkill": s["name"],
            }
            break

    # Trend: the mean overall score per ISO week, last 8 weeks with clips.
    weeks: dict[str, list[int]] = defaultdict(list)
    for v in ready:
        created: datetime = v["created_at"]
        monday = (created - timedelta(days=created.weekday())).date().isoformat()
        weeks[monday].append(v["result"]["overallScore"])
    out["trend"] = [{"week": w, "score": round(_mean(s) or 0)} for w, s in sorted(weeks.items())][-8:]

    # Roles the player fits best across recent clips (coverage-weighted), for "your game suits…".
    roles: dict[str, list[int]] = defaultdict(list)
    labels: dict[str, str] = {}
    for v in ready[:WINDOW]:
        for f in v["result"].get("roleFit", []):
            if f.get("coverage", 0) >= 0.35:
                roles[f["role"]].append(f["score"])
                labels[f["role"]] = f["label"]
    from ..scoring.roles import roles as role_catalogue

    wanted = {p.upper() for p in positions or []}
    catalogue = role_catalogue()
    mine = {r: s for r, s in roles.items() if wanted & set(catalogue[r]["positions"])}
    best = sorted(((round(_mean(s) or 0), r) for r, s in (mine or roles).items()), reverse=True)[:3]
    out["bestRoles"] = [{"role": r, "label": labels[r], "score": score} for score, r in best]

    for v in ready[:3]:
        for m in v["result"].get("moments", [])[:3]:
            out["recentMoments"].append(
                {**m, "videoId": v["id"], "videoTitle": v.get("title") or "Your clip"}
            )
    return out
