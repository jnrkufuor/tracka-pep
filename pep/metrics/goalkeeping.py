"""
Goalkeeper metrics (first version: deliberately few, and honest about it).

  dives          the hip centre drops below ~45% of standing height, fast,
                 with sideways movement: the keeper went to ground to one side
  dive_speed_ms  peak sideways speed of the hips during a dive (explosiveness)
  set_share      share of the clip where the keeper is "set": still, with
                 knees bent. (Next step: only count the moments just before
                 a shot, once Pep can recognise shots.)

Proper goalkeeper analysis needs to know about shots (where from, how hard,
saved or not). That's action recognition: docs/handbook/09-improving.md.
"""

from __future__ import annotations

import numpy as np

from ..vision.target import TargetSample
from ..vision.types import L_ANKLE, L_HIP, R_ANKLE, R_HIP
from .technique import knee_angle

MIN_CONF = 0.4


def _hip_centre(kp: np.ndarray) -> np.ndarray | None:
    if kp[L_HIP, 2] < MIN_CONF or kp[R_HIP, 2] < MIN_CONF:
        return None
    return (kp[L_HIP, :2] + kp[R_HIP, :2]) / 2


def analyse_goalkeeping(samples: list[TargetSample], metres_per_px: np.ndarray) -> dict[str, float | None]:
    t = np.array([s.t for s in samples])
    hips = np.full((len(samples), 2), np.nan)
    ground = np.full(len(samples), np.nan)
    for i, s in enumerate(samples):
        if s.keypoints is None or s.box is None:
            continue
        hc = _hip_centre(s.keypoints)
        if hc is None:
            continue
        hips[i] = hc
        ankles = [s.keypoints[j, 1] for j in (L_ANKLE, R_ANKLE) if s.keypoints[j, 2] >= MIN_CONF]
        ground[i] = max(ankles) if ankles else s.box.y2

    standing = (
        np.nanmedian([s.box.h for s in samples if s.box is not None])
        if any(s.box for s in samples)
        else np.nan
    )
    m: dict[str, float | None] = {"dives": None, "dive_speed_ms": None, "set_share": None}
    if not np.isfinite(standing) or np.isfinite(hips[:, 0]).sum() < 10:
        return m

    hip_height = (ground - hips[:, 1]) / standing  # 0.5 standing, ~0.1-0.2 on the ground
    dives, peak = 0, []
    i = 0
    while i < len(t):
        if np.isfinite(hip_height[i]) and hip_height[i] < 0.22:
            back = (t >= t[i] - 0.7) & (t < t[i]) & np.isfinite(hip_height)
            if back.any() and np.nanmax(hip_height[back]) > 0.4:
                dives += 1
                window = np.flatnonzero(back)
                dx = np.diff(hips[window, 0]) * np.nan_to_num(metres_per_px[window[1:]], nan=0.0)
                dts = np.diff(t[window])
                if len(dx) and (dts > 0).all():
                    peak.append(float(np.nanmax(np.abs(dx / dts))))
                i += int(np.searchsorted(t, t[i] + 1.0) - i)  # skip the rest of this dive
                continue
        i += 1
    m["dives"] = float(dives)
    m["dive_speed_ms"] = round(max(peak), 2) if peak else None

    # "Set": knees bent (< 160 degrees) and nearly still, measured over the clip.
    set_frames = 0
    checked = 0
    for j, s in enumerate(samples):
        if s.keypoints is None or j == 0 or not np.isfinite(hips[j, 0]) or not np.isfinite(hips[j - 1, 0]):
            continue
        k = knee_angle(s.keypoints)
        if k is None:
            continue
        checked += 1
        still = abs(hips[j, 0] - hips[j - 1, 0]) < 0.03 * standing
        set_frames += int(still and k < 160)
    m["set_share"] = round(set_frames / checked, 3) if checked >= 10 else None
    return m
