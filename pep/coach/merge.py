"""
Putting measurements and the AI coach's notes together into one result.

Measured skills keep their numbers; the coach can add a sentence to their
explanation and a better-fitting drill tip. Skills the coach only observed
are added as `ai_observed` with LOW confidence. Moments from both sources
are merged, clamped to the clip, and de-duplicated.

When there are no AI notes (no API key, timeout, error), `rules_summary`
writes a short summary from the numbers alone, so the player always gets
something useful.
"""

from __future__ import annotations

from ..contracts import Moment, Skill
from .llm import CoachNotes

RATING_TO_SCORE = {1: 35, 2: 48, 3: 62, 4: 76, 5: 90}

OBSERVED_DRILLS = {
    "Passing": "Wall passes: 3 x 1 minute each foot, then one-touch from 5 m.",
    "Finishing": "10 shots from the edge of the box after one touch, picking a corner before you shoot.",
    "Defending": "1 v 1 in a 10 m channel: stay side-on, show them one way, don't dive in.",
    "Decision making": "Rondos (4 v 1 or 5 v 2): decide your next pass before the ball reaches you.",
    "First touch": "Receive passes from different heights; first touch into space, away from a cone 'defender'.",
}


def merge(
    skills: list[Skill],
    moments: list[Moment],
    notes: CoachNotes | None,
    length_s: float,
) -> tuple[list[Skill], list[Moment], str | None]:
    skills = [s.model_copy() for s in skills]
    by_name = {s.name: s for s in skills}
    all_moments = list(moments)
    summary = None

    if notes is not None:
        summary = notes.summary[:600]
        for tip in notes.tips:
            s = by_name.get(tip.skill)
            if s is not None and tip.tip:
                s.drill = tip.tip[:600]
        for ob in notes.observed:
            if ob.skill in by_name:  # never overwrite something we measured
                continue
            sk = Skill(
                name=ob.skill,
                score=RATING_TO_SCORE[ob.rating],
                explanation=f"From watching the clip: {ob.evidence}"[:600],
                drill=OBSERVED_DRILLS.get(ob.skill, ""),
                source="ai_observed",
                confidence="LOW",
            )
            skills.append(sk)
            by_name[sk.name] = sk
        for nm in notes.moments:
            if 0 <= nm.at_seconds <= length_s + 0.5:
                all_moments.append(
                    Moment(at_seconds=round(nm.at_seconds, 1), kind=nm.kind, text=nm.text[:300])
                )

    return skills[:12], dedupe_moments(all_moments)[:30], summary


def dedupe_moments(moments: list[Moment], within_s: float = 1.5) -> list[Moment]:
    out: list[Moment] = []
    for m in sorted(moments, key=lambda m: m.at_seconds):
        if out and m.at_seconds - out[-1].at_seconds < within_s and m.kind == out[-1].kind:
            continue
        out.append(m)
    return out


def rules_summary(skills: list[Skill]) -> str | None:
    measured = [s for s in skills if s.source != "ai_observed"]
    if not measured:
        return None
    best = max(measured, key=lambda s: s.score)
    worst = min(measured, key=lambda s: s.score)
    if best is worst:
        return f"{best.name} is where this clip shows you best ({best.score}). Post more clips so Pep can see more of your game."
    return (
        f"Your strongest area in this clip is {best.name.lower()} ({best.score}). "
        f"The one to work on is {worst.name.lower()} ({worst.score}): {worst.drill}"
    )[:600]
