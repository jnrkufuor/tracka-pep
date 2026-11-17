"""
Measurements -> skills: the scores a player sees.

Each skill is built from one or more measurements (the "predictors" for
that skill), compared with the player's age band (norms.py), and comes with:
  - an explanation saying what was measured, in plain words, with the number;
  - a drill to practise, picked by score band (under 55 / 55-74 / 75+);
  - a source: "drill" (standard test), "measured" (from a normal clip) or
    "ai_observed" (the language model's judgement, see coach/);
  - a confidence: how much to trust it (see `confidence_for`).

This file is the rulebook. Change thresholds here, then bump MODEL_VERSION
in pep/__init__.py so results from before and after can be told apart.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

from ..contracts import Confidence, Skill
from .norms import Standing, standing

LEVELS: tuple[Confidence, ...] = ("LOW", "MEDIUM", "HIGH")


@dataclass
class Context:
    age: int | None = None
    sex: str | None = None
    clip_type: str = "match"
    method: str = "body"  # how pixels became metres: "homography" or "body"
    camera_reliability: float = 1.0
    seconds_tracked: float = 0.0


@dataclass
class SkillDef:
    name: str
    metrics: list[tuple[str, float]]  # (metric, weight)
    # Only called once every metric in `metrics` is present, so it may treat them as floats.
    explain: Callable[[dict[str, Any], list[Standing]], str]
    drills: tuple[str, str, str]  # for scores <55, 55-74, 75+
    needs: Callable[[dict[str, float | None], Context], bool] = lambda m, c: True
    uses_distance: bool = False  # depends on pixels->metres (so on calibration quality)
    from_drill: bool = False


@dataclass
class ScoredSkill:
    skill: Skill
    standings: list[Standing] = field(default_factory=list)


def _kmh(ms: float | None) -> str:
    return f"{ms * 3.6:.1f} km/h" if ms is not None else "?"


def _pct(st: list[Standing]) -> str:
    """'better than about 70% of u17 players...' with the share rounded to 5 and kept within 5-95."""
    p = sum(s.percentile for s in st) / len(st)
    band = st[0].band
    if p >= 50:
        share = min(95, max(50, round(p / 5) * 5))
        return f"better than about {share}% of {band} players in Pep's reference group"
    share = min(95, max(50, round((100 - p) / 5) * 5))
    return f"about {share}% of {band} players in Pep's reference group measure higher"


SKILLS: list[SkillDef] = [
    # ---------------------------------------------------------------- drills (most trusted)
    SkillDef(
        "Pace",
        [("sprint_30m_s", 1.0)],
        lambda m, st: f"30 m in {m['sprint_30m_s']:.2f} s from a standing start: {_pct(st)}.",
        (
            "Acceleration starts: 6 x 10 m from a standing start, full recovery between. Drive your arms, lean forward.",
            "Flying 20s: build up over 15 m, then 20 m flat out. 4-6 reps, 2 minutes rest.",
            "Resisted sprints (a partner holding a towel round your waist) 4 x 15 m, then 2 free 30 m.",
        ),
        from_drill=True,
    ),
    SkillDef(
        "Acceleration",
        [("split_10m_s", 1.0)],
        lambda m, st: f"First 10 m in {m['split_10m_s']:.2f} s: {_pct(st)}.",
        (
            "Falling starts: lean until you have to step, then sprint 10 m. 8 reps. Short, fast steps first.",
            "Partner-chase starts: react to a clap and sprint 10 m. 8 reps.",
            "Hill sprints, 6 x 10-15 m on a gentle slope. Keep the lean for the first 5 steps.",
        ),
        from_drill=True,
    ),
    SkillDef(
        "Agility",
        [("agility_5105_s", 1.0)],
        lambda m, st: f"5-10-5 in {m['agility_5105_s']:.2f} s: {_pct(st)}.",
        (
            "Cone T-drill at walking pace first, then jogging: low hips at every turn, plant the outside foot.",
            "5-10-5 reps with a 90-second rest: aim to touch each line with your hand to force a low turn.",
            "Mirror drill with a partner: 10 s on, 20 s off, react to their changes of direction.",
        ),
        from_drill=True,
    ),
    SkillDef(
        "Ball control",
        [("juggles_best", 1.0)],
        lambda m, st: f"Best run of {m['juggles_best']:.0f} keepy-ups: {_pct(st)}.",
        (
            "One bounce, one touch: let it bounce, touch it up, catch it. Then two touches. Both feet.",
            "Keepy-ups alternating feet; then thigh-foot-thigh. Count your best of five tries.",
            "Keepy-ups while walking a 10 m line, then using only your weaker foot.",
        ),
        from_drill=True,
    ),
    SkillDef(
        "Passing",
        [("wall_passes_30s", 1.0)],
        lambda m, st: f"{m['wall_passes_30s']:.0f} wall passes in 30 s: {_pct(st)}.",
        (
            "Wall passes with two touches: control across your body, then pass. 3 x 1 minute each foot.",
            "One-touch wall passes from 4 m, alternating feet. Count passes in 30 s and try to beat it.",
            "One-touch from 6 m, aiming at a marked square on the wall, weaker foot only for half of it.",
        ),
        from_drill=True,
    ),
    # ---------------------------------------------------------------- from normal clips
    SkillDef(
        "Pace",
        [("top_speed_ms", 1.0)],
        lambda m, st: f"Top speed about {_kmh(m['top_speed_ms'])} (best one-second average): {_pct(st)}.",
        (
            "Acceleration starts: 6 x 10 m from a standing start, full recovery between.",
            "Flying 20s: build up over 15 m, then 20 m flat out. 4-6 reps, 2 minutes rest.",
            "Record a 30 m sprint drill in Tracka so scouts see a fair, timed number.",
        ),
        needs=lambda m, c: (m.get("seconds_tracked") or 0) >= 3,
        uses_distance=True,
    ),
    SkillDef(
        "Acceleration",
        [("peak_accel_ms2", 1.0)],
        lambda m, st: f"Hardest speed-up about {m['peak_accel_ms2']:.1f} m/s every second: {_pct(st)}.",
        (
            "Falling starts: lean until you have to step, then sprint 10 m. 8 reps.",
            "Reaction starts from different positions (sitting, lying, backwards): 8 x 10 m.",
            "Record a 30 m sprint drill: its 10 m split is a fair, timed acceleration number.",
        ),
        uses_distance=True,
    ),
    SkillDef(
        "Agility",
        [("turns_per_min", 1.0)],
        lambda m, st: (
            f"{m['turns_per_min']:.1f} sharp changes of direction per minute of running: {_pct(st)}."
        ),
        (
            "Cone slalom, 6 cones 2 m apart, low hips, small steps into each turn. 6 reps.",
            "Box drill (4 cones, 5 m square): sprint, shuffle, backpedal, shuffle. 6 reps.",
            "Record a 5-10-5 agility drill in Tracka for a timed, comparable result.",
        ),
        # Turns only mean something if we watched them run for a while.
        needs=lambda m, c: c.seconds_tracked * (m.get("moving_share") or 0) >= 8,
        uses_distance=True,
    ),
    SkillDef(
        "Work rate",
        [("moving_share", 0.6), ("distance_per_min_m", 0.4)],
        lambda m, st: (
            f"Moving faster than a walk {m['moving_share'] * 100:.0f}% of the time, "
            f"about {m['distance_per_min_m'] or 0:.0f} m per minute: {_pct(st)}."
        ),
        (
            "Small-sided games (4 v 4) with a rule: everyone must be in the opposition half when you score.",
            "Interval runs: 15 s hard, 15 s jog, 10 minutes. Twice a week.",
            "Track your recovery runs in match clips: sprint back the moment the ball is lost.",
        ),
        needs=lambda m, c: c.clip_type in ("match", "training") and c.seconds_tracked >= 20,
        uses_distance=True,
    ),
    SkillDef(
        "Ball control",
        [("ball_at_feet_share", 0.6), ("touches_per_min", 0.4)],
        lambda m, st: (
            f"The ball was at your feet {m['ball_at_feet_share'] * 100:.0f}% of the time it was near you: {_pct(st)}."
        ),
        (
            "Wall passes with a cushioned first touch: kill the ball dead, then pass. 3 x 1 minute each foot.",
            "Receive on the half-turn: a partner passes, you open your body and take it across you.",
            "First touch away from pressure: a partner calls 'left' or 'right' as the pass comes.",
        ),
        needs=lambda m, c: m.get("ball_at_feet_share") is not None,
    ),
    SkillDef(
        "Dribbling",
        [("close_control_m", 1.0)],
        lambda m, st: (
            f"While running with the ball it stayed about {m['close_control_m']:.1f} m from your feet: {_pct(st)}."
        ),
        (
            "Dribble a 10 m line touching the ball every step, both feet. Then speed up.",
            "Cone weave at speed: touch the ball with the outside of the foot between every cone.",
            "1 v 1s in a 10 x 5 m channel: beat the defender and stop the ball on the end line.",
        ),
        uses_distance=True,
    ),
    SkillDef(
        "Body shape",
        [("ready_knee_deg", 1.0)],
        lambda m, st: (
            f"Knees bent to about {m['ready_knee_deg']:.0f} degrees when waiting for play: {_pct(st)}. "
            "Lower means more ready to move."
        ),
        (
            "'Ready position' habit: knees soft, weight on the balls of your feet, every time play stops.",
            "Reaction drill: a partner points left or right, you go from the ready position. 10 reps.",
            "Film your defending: check your stance before every duel.",
        ),
    ),
    SkillDef(
        "Scanning",
        [("head_checks_per_min", 1.0)],
        lambda m, st: (
            f"About {m['head_checks_per_min']:.0f} looks over your shoulder a minute: {_pct(st)}. "
            "This one is measured roughly, from your head's position."
        ),
        (
            "Before every pass you receive, look over each shoulder once. A partner holds up fingers; call the number.",
            "Rondos (4 v 1): say where your next pass is going before the ball arrives.",
            "In matches: aim for 2 looks in the 5 seconds before receiving.",
        ),
        needs=lambda m, c: c.clip_type in ("match", "training"),
    ),
    SkillDef(
        "Diving",
        [("dive_speed_ms", 1.0)],
        lambda m, st: (
            f"{m['dives']:.0f} dive(s); fastest sideways push about {_kmh(m['dive_speed_ms'])}: {_pct(st)}."
        ),
        (
            "Collapse dives from kneeling, both sides, 8 each: land on your side, never your stomach.",
            "Step-and-dive from standing: one step, push off the near foot. 6 each side.",
            "Reaction saves: a partner volleys from 8 m, you start in the set position.",
        ),
    ),
    SkillDef(
        "Set position",
        [("set_share", 1.0)],
        lambda m, st: f"Set (still, knees bent) {m['set_share'] * 100:.0f}% of the clip: {_pct(st)}.",
        (
            "Every time the ball moves, shuffle, then set: feet shoulder-width, knees bent, hands ready.",
            "Partner shoots on a whistle: be set before the whistle.",
            "Film shots against you: are you set when the shooter's foot hits the ball?",
        ),
    ),
]


def confidence_for(d: SkillDef, ctx: Context) -> Confidence:
    """
    How much to trust a skill score. Starts at HIGH and steps down for each
    reason to doubt it. Being explicit about doubt is how Pep earns scouts' trust.
    """
    level = 2
    if not d.from_drill:
        level -= 1  # a normal clip is never as fair as a standard test
    if d.uses_distance and ctx.method != "homography":
        level -= 1  # metres were estimated from body height
    if ctx.camera_reliability < 0.6:
        level -= 1  # we struggled to measure the camera's movement
    if ctx.clip_type == "highlight":
        level -= 1  # the player picked their best moments
    if ctx.age is None:
        level = min(level, 1)  # compared with an assumed age band
    return LEVELS[max(0, level)]


def drill_for(score: int, drills: tuple[str, str, str]) -> str:
    return drills[0 if score < 55 else 1 if score < 75 else 2]


def score_skills(m: dict[str, float | None], ctx: Context) -> list[ScoredSkill]:
    out: dict[str, ScoredSkill] = {}
    for d in SKILLS:
        if d.name in out:  # a drill version already scored this skill: it wins
            continue
        if not all(m.get(metric) is not None for metric, _ in d.metrics):
            continue
        if not d.needs(m, ctx):
            continue
        st = [standing(metric, m[metric], ctx.age, ctx.sex) for metric, _ in d.metrics]
        if any(s is None for s in st):
            continue
        sts = [s for s in st if s is not None]
        total_w = sum(w for _, w in d.metrics)
        score = round(sum(s.score * w for s, (_, w) in zip(sts, d.metrics, strict=True)) / total_w)
        out[d.name] = ScoredSkill(
            Skill(
                name=d.name,
                score=score,
                explanation=d.explain(m, sts)[:600],
                drill=drill_for(score, d.drills),
                source="drill" if d.from_drill else "measured",
                confidence=confidence_for(d, ctx),
            ),
            sts,
        )
    return list(out.values())
