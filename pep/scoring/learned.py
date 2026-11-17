"""
The learned scorer: a model trained to agree with real scouts.

The rules in skills.py and roles.py are opinions written by hand. Once
scouts have rated enough clips in the Pep Lab (Calibrate tab), we can learn
the mapping from measurements to "what a scout thinks" instead.

FEATURES below are the model's predictors. They're the measurements most
likely to carry signal, plus context the model needs to interpret them
(age changes what a good sprint is; a highlight clip flatters everyone).
Missing values are allowed: the model (gradient-boosted trees) handles NaN
natively by learning which way to send them at each split.

Training lives in training/train_scorer.py; this module only loads the
saved model and predicts. The model file carries its own "model card"
(features, version, validation error), so you always know what's running.
"""

from __future__ import annotations

import math
from functools import cache
from pathlib import Path

from ..config import settings
from ..log import get_logger

log = get_logger(__name__)

FEATURES: list[str] = [
    # movement
    "top_speed_ms",
    "peak_accel_ms2",
    "distance_per_min_m",
    "moving_share",
    "high_speed_share",
    "high_speed_runs",
    "turns_per_min",
    # ball
    "ball_at_feet_share",
    "touches_per_min",
    "close_control_m",
    "heavy_touches",
    # body
    "ready_knee_deg",
    "sprint_lean_deg",
    "head_checks_per_min",
    # goalkeeping
    "dive_speed_ms",
    "set_share",
    # drills
    "sprint_30m_s",
    "split_10m_s",
    "agility_5105_s",
    "juggles_best",
    "wall_passes_30s",
    # context: how to read everything above
    "age_years",
    "is_female",
    "clip_is_match",
    "clip_is_drill",
    "clip_is_highlight",
    "calibrated",
    "camera_reliability",
    "seconds_tracked",
]


def feature_row(metrics: dict[str, float | None], ctx: dict) -> list[float]:
    """One row of numbers in FEATURES order (NaN where unknown)."""
    row: dict[str, float | None] = {**metrics}
    row["age_years"] = ctx.get("age")
    row["is_female"] = 1.0 if ctx.get("sex") == "female" else 0.0 if ctx.get("sex") == "male" else None
    clip = ctx.get("clip_type", "match")
    row["clip_is_match"] = float(clip in ("match", "training"))
    row["clip_is_drill"] = float(clip == "drill")
    row["clip_is_highlight"] = float(clip == "highlight")
    row["calibrated"] = float(ctx.get("method") == "homography")
    row["camera_reliability"] = ctx.get("camera_reliability")
    return [float(v) if (v := row.get(f)) is not None else math.nan for f in FEATURES]


@cache
def _load(path: str):
    p = Path(path)
    if not p.exists():
        return None
    import joblib

    bundle = joblib.load(p)
    if bundle.get("features") != FEATURES:
        log.warning("scorer.features_mismatch", path=path)  # retrain after changing FEATURES
        return None
    log.info("scorer.loaded", version=bundle.get("version"), mae=bundle.get("cv_mae"))
    return bundle


def predict_overall(metrics: dict[str, float | None], ctx: dict) -> tuple[int, str] | None:
    """(score, model version) from the trained model, or None if there isn't one."""
    bundle = _load(str(settings().learned_scorer_path))
    if bundle is None:
        return None
    pred = float(bundle["model"].predict([feature_row(metrics, ctx)])[0])
    return int(round(min(95, max(30, pred)))), str(bundle["version"])
