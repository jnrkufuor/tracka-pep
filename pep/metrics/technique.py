"""
Body-shape metrics from pose keypoints.

The pose model gives 17 points per frame (shoulders, hips, knees...). Joint
angles come from plain vector maths: the angle at the knee is the angle
between the vectors knee->hip and knee->ankle:

    cos(theta) = (a . b) / (|a| |b|)

A straight leg is ~180 degrees; a deep athletic stance is ~120-140.

  ready_knee_deg       knee angle while (nearly) still. Lower = more ready
                       to move ("on your toes, knees bent").
  sprint_lean_deg      how far the torso leans forward from vertical while
                       sprinting. Good acceleration mechanics lean ~10-25 deg.
  head_checks_per_min  "scanning": how often the head turns well away from
                       the line of the shoulders and back. Top midfielders
                       scan many times in the seconds before receiving.
                       Measured crudely (nose position relative to the
                       shoulders), only from fairly front-on views, so its
                       confidence is always LOW.

Keypoints with low confidence (hidden behind the body, blurred) are ignored.
"""

from __future__ import annotations

import numpy as np

from ..vision.target import TargetSample
from ..vision.types import L_ANKLE, L_HIP, L_KNEE, L_SHOULDER, NOSE, R_ANKLE, R_HIP, R_KNEE, R_SHOULDER

MIN_KP_CONF = 0.4


def joint_angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Angle ABC in degrees (the angle at point b)."""
    ba, bc = a - b, c - b
    cos = float(ba @ bc / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-9))
    return float(np.degrees(np.arccos(np.clip(cos, -1.0, 1.0))))


def _pt(kp: np.ndarray, i: int) -> np.ndarray | None:
    return kp[i, :2] if kp[i, 2] >= MIN_KP_CONF else None


def knee_angle(kp: np.ndarray) -> float | None:
    angles = []
    for hip, knee, ankle in ((L_HIP, L_KNEE, L_ANKLE), (R_HIP, R_KNEE, R_ANKLE)):
        a, b, c = _pt(kp, hip), _pt(kp, knee), _pt(kp, ankle)
        if a is not None and b is not None and c is not None:
            angles.append(joint_angle(a, b, c))
    return float(np.mean(angles)) if angles else None


def torso_lean(kp: np.ndarray) -> float | None:
    """Degrees from vertical of the hip-centre -> shoulder-centre line (0 = upright)."""
    ls, rs, lh, rh = (_pt(kp, i) for i in (L_SHOULDER, R_SHOULDER, L_HIP, R_HIP))
    if ls is None or rs is None or lh is None or rh is None:
        return None
    shoulders = (ls + rs) / 2
    hips = (lh + rh) / 2
    v = shoulders - hips
    return float(np.degrees(np.arctan2(abs(v[0]), -v[1])))  # image y points down


def head_offset(kp: np.ndarray) -> float | None:
    """Nose left/right of the shoulder centre, in shoulder widths. Only for front-on views."""
    nose, ls, rs = _pt(kp, NOSE), _pt(kp, L_SHOULDER), _pt(kp, R_SHOULDER)
    if nose is None or ls is None or rs is None:
        return None
    width = abs(ls[0] - rs[0])
    if width < 8:  # side-on: shoulders overlap, can't judge head turns
        return None
    return float((nose[0] - (ls[0] + rs[0]) / 2) / width)


def analyse_technique(samples: list[TargetSample], speed: np.ndarray) -> dict[str, float | None]:
    t = np.array([s.t for s in samples])
    knees, leans, heads, head_t = [], [], [], []
    for i, s in enumerate(samples):
        if s.keypoints is None:
            continue
        sp = speed[i] if np.isfinite(speed[i]) else np.nan
        if np.isfinite(sp) and sp < 1.0:
            k = knee_angle(s.keypoints)
            if k is not None:
                knees.append(k)
        if np.isfinite(sp) and sp > 5.0:
            lean = torso_lean(s.keypoints)
            if lean is not None:
                leans.append(lean)
        h = head_offset(s.keypoints)
        if h is not None:
            heads.append(h)
            head_t.append(t[i])

    m: dict[str, float | None] = {
        "pose_frames": float(sum(s.keypoints is not None for s in samples)),
        "ready_knee_deg": round(float(np.median(knees)), 1) if len(knees) >= 5 else None,
        "sprint_lean_deg": round(float(np.median(leans)), 1) if len(leans) >= 4 else None,
        "head_checks_per_min": None,
    }

    # A head check: the head goes > 0.35 shoulder-widths to one side, then comes back.
    if len(heads) >= 20 and head_t[-1] - head_t[0] >= 5:
        checks, away = 0, False
        for h in heads:
            if not away and abs(h) > 0.35:
                away = True
            elif away and abs(h) < 0.15:
                checks += 1
                away = False
        m["head_checks_per_min"] = round(checks / ((head_t[-1] - head_t[0]) / 60), 1)
    return m
