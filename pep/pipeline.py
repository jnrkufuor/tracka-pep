"""
The whole analysis, start to finish. Read this file first: it's the map.

    video file
      -> frames      sample ~10 frames a second, shrink them          video/frames.py
      -> perception  people + body keypoints + ball, with track IDs   vision/perception.py
      -> camera      cancel the phone's panning and zooming           vision/camera.py
      -> target      pick the player the clip is about                vision/target.py
      -> metres      pixels -> metres on the ground                   vision/calibration.py
      -> metrics     speed, accel, ball, body shape, keeper, drills   metrics/*, drills/
      -> skills      compare with age group, explain, pick drills     scoring/skills.py
      -> AI coach    a video model adds words and moments             coach/llm.py
      -> roles       role fit for scouts, overall score, confidence   scoring/roles.py
      -> CoachResult exactly what Tracka expects                       contracts.py

Every stage is timed (`timings`), because when the worker gets slow you
need to know *which* stage got slow. That's observability in miniature.
"""

from __future__ import annotations

import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import MODEL_VERSION
from .coach.llm import watch
from .coach.merge import merge, rules_summary
from .config import settings
from .contracts import AnalysisRequest, CoachResult, Moment
from .drills.runner import run_drill
from .log import get_logger
from .metrics.ball import analyse_ball
from .metrics.goalkeeping import analyse_goalkeeping
from .metrics.kinematics import analyse_movement
from .metrics.technique import analyse_technique
from .scoring.learned import predict_overall
from .scoring.roles import overall, overall_confidence, role_fits
from .scoring.skills import Context, score_skills
from .video.frames import probe, sample_frames
from .vision.calibration import ground_track
from .vision.camera import CameraMotion
from .vision.perception import Perceiver
from .vision.target import TargetSample, choose_target, follow
from .vision.types import FrameObs

log = get_logger(__name__)

MIN_SECONDS, MAX_SECONDS = 3.0, 180.0


class CantReadClip(Exception):
    """The clip can't be scored, for a reason the player should see. Keep messages short and kind."""


@dataclass
class Analysis:
    result: CoachResult
    timings: dict[str, float] = field(default_factory=dict)
    samples: list[TargetSample] = field(default_factory=list)
    speed: np.ndarray | None = None
    obs: list[FrameObs] = field(default_factory=list)


class Timer:
    def __init__(self) -> None:
        self.timings: dict[str, float] = {}

    @contextmanager
    def stage(self, name: str):
        start = time.perf_counter()
        try:
            yield
        finally:
            self.timings[name] = round(time.perf_counter() - start, 3)


def analyse(video: Path, req: AnalysisRequest, perceiver: Perceiver) -> Analysis:
    timer = Timer()
    s = settings()

    with timer.stage("probe"):
        info = probe(video)
        length = info.duration
        if length < MIN_SECONDS:
            raise CantReadClip("This clip is too short. Send at least 3 seconds.")
        if length > MAX_SECONDS + 1:
            raise CantReadClip("This clip is over 3 minutes. Trim it to the part that shows you best.")

    # ---------------------------------------------------------------- see
    obs: list[FrameObs] = []
    camera = CameraMotion()
    perceiver.reset()
    with timer.stage("perception"):
        for frame in sample_frames(video, s.samples_per_second, s.max_side, MAX_SECONDS):
            people, ball = perceiver.observe(frame.image)
            to_ref = camera.update(frame.image, [p.box for p in people])
            h, w = frame.image.shape[:2]
            obs.append(FrameObs(frame.index, frame.t, w, h, people, ball, to_ref))
    if not obs:
        raise CantReadClip("We couldn't read any frames from this clip.")

    with timer.stage("target"):
        hint = (req.target.x, req.target.y) if req.target else None
        chain = choose_target(obs, hint, req.target_at_seconds)
        if not chain:
            raise CantReadClip(
                "We couldn't find a player in this clip. Film in daylight with the player clearly in shot."
            )
        samples = follow(obs, chain)
        seen = sum(x.feet is not None for x in samples) / len(samples)
        if seen < 0.25:
            raise CantReadClip(
                "You're only in shot for a short part of this clip. Keep the camera on the player."
            )

    # ---------------------------------------------------------------- measure
    with timer.stage("metrics"):
        ground = ground_track(samples, obs, req.player_height_m, req.calibration)
        kin = analyse_movement(ground.t, ground.xy, ground.method)
        ball_m, ball_events = analyse_ball(samples, kin.speed, ground.metres_per_px)
        tech_m = analyse_technique(samples, kin.speed)
        metrics: dict[str, float | None] = {**kin.metrics, **ball_m, **tech_m}
        if "GK" in {p.upper() for p in req.positions}:
            metrics.update(analyse_goalkeeping(samples, ground.metres_per_px))
        if req.clip_type == "drill" and req.drill:
            if req.drill in ("sprint_30m", "agility_5105") and ground.method != "homography":
                raise CantReadClip("This drill needs the cones marked so Pep can measure the distance.")
            metrics.update(run_drill(req.drill, kin, samples))
        metrics["camera_reliability"] = round(camera.reliability, 2)
        metrics["seen_share"] = round(seen, 2)

    ctx = Context(
        age=req.age_years,
        sex=req.sex,
        clip_type=req.clip_type,
        method=ground.method,
        camera_reliability=camera.reliability,
        seconds_tracked=float(metrics.get("seconds_tracked") or 0.0),
    )
    with timer.stage("scoring"):
        scored = score_skills(metrics, ctx)
        skills = [x.skill for x in scored]
        moments = [Moment(at_seconds=round(t, 1), kind=k, text=txt) for t, k, txt in kin.events + ball_events]

    # ---------------------------------------------------------------- coach
    with timer.stage("coach"):
        notes = (
            None
            if not req.coach_notes
            else watch(
                video,
                {
                    "who": _describe_target(samples, obs),
                    "positions": req.positions,
                    "age": req.age_years,
                    "clip_type": req.clip_type,
                    "length": length,
                    "metrics": {k: v for k, v in metrics.items() if v is not None},
                    "skills": {sk.name: sk.score for sk in skills},
                },
            )
        )
        skills, moments, summary = merge(skills, moments, notes, length)

    if not skills:
        raise CantReadClip(
            "This clip didn't show enough to score. Try a longer clip with you running, on the ball, or a Tracka drill."
        )

    with timer.stage("roles"):
        fits = role_fits(skills)
        score = overall(skills, fits, req.positions)
        version = MODEL_VERSION
        learned = predict_overall(metrics, {**ctx.__dict__, "clip_type": req.clip_type})
        if learned is not None and score is not None:
            # Blend: the learned model (agrees with scouts) and the rules (explainable).
            score = round(0.5 * score + 0.5 * learned[0])
            version = f"{MODEL_VERSION}+{learned[1]}"[:60]

    result = CoachResult(
        analysis_id=req.analysis_id,
        status="READY",
        model_version=version,
        overall_score=score,
        confidence=overall_confidence(skills, fits, req.positions),
        skills=skills,
        moments=moments,
        clip_type=req.clip_type,
        role_fit=fits,
        metrics={k: (round(v, 3) if isinstance(v, float) else v) for k, v in metrics.items()},
        summary=summary or rules_summary(skills),
        coach_source="gemini" if notes else "rules",
    )
    log.info("analysis.done", analysis_id=req.analysis_id, score=score, timings=timer.timings)
    return Analysis(result, timer.timings, samples, kin.speed, obs)


def _describe_target(samples: list[TargetSample], obs: list[FrameObs]) -> str:
    """Tells the video model which player we mean: where they are in the first frame they appear."""
    for sample, o in zip(samples, obs, strict=False):
        if sample.box is not None:
            cx, cy = sample.box.center
            side = "left" if cx < o.width / 3 else "right" if cx > 2 * o.width / 3 else "middle"
            return (
                f"the player who is in the {side} of the picture at {sample.t:.1f} s "
                f"(about {cx / o.width:.0%} across, {cy / o.height:.0%} down), followed through the clip"
            )
    return "the main player in the clip"
