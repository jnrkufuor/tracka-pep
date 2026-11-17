"""
From pixels to metres.

Speed needs metres. A video only gives pixels. Two ways across, depending on
what the player gave us:

1) HOMOGRAPHY (drills, best).
   The player puts cones at known spots (e.g. 0 m and 30 m apart, 5 m wide)
   and marks them on a frame. A homography is a 3x3 matrix H that maps
   points on one plane (the ground in the image) to another plane (the
   ground in metres):

        [X, Y, 1]^T  ~  H @ [u, v, 1]^T      (~ means "equal after dividing by the last number")

   Four point pairs determine H exactly (8 unknowns, 2 equations per point);
   more points are fitted by least squares. It handles perspective properly,
   which is why broadcast tracking systems calibrate exactly this way using
   pitch lines. Assumes the camera holds still (tripod) or that our
   camera-motion compensation is good.

2) PINHOLE "BODY RULER" (everything else, rougher).
   We know (or assume) the player's height, H metres. A pinhole camera with
   focal length f pixels sees an object of height H at distance Z as
   h = f * H / Z pixels tall. So from the player's box height h:

        Z = f * H / h          (how far away they are)
        X = (u - cx) * Z / f   (how far left/right of the camera's centre line)

   That gives a position on the ground (X, Z) in metres every frame, which
   copes with running towards the camera (the box grows) as well as across.
   We don't know f, so we assume a typical phone field of view (~66 degrees
   horizontal). Errors in f scale distances a little but cancel out when the
   player runs across the frame.

   Box heights are noisy (arms up, crouching, the detector's box jitter),
   so heights are smoothed hard before use. Even so, expect +-10-15% on
   speeds from a hand-held phone. The result says which method was used so
   the scores can carry the right confidence.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from ..contracts import Calibration
from .target import TargetSample
from .types import FrameObs, apply_affine

DEFAULT_HEIGHT_M = 1.72
# A standing player's box is a bit shorter than their height once they bend into a run.
BOX_TO_STATURE = 0.96
PHONE_HFOV_DEG = 66.0


@dataclass
class GroundTrack:
    t: np.ndarray  # seconds, shape (N,)
    xy: np.ndarray  # metres on the ground, shape (N, 2); NaN where the player wasn't seen
    metres_per_px: np.ndarray  # local scale at the player's feet (for ball distances), NaN if unseen
    method: str  # "homography" or "body"


def ground_track(
    samples: list[TargetSample],
    obs: list[FrameObs],
    player_height_m: float | None,
    calibration: Calibration | None,
) -> GroundTrack:
    t = np.array([s.t for s in samples])
    if calibration is not None:
        return _by_homography(samples, obs, calibration, t)
    return _by_body(samples, obs, player_height_m or DEFAULT_HEIGHT_M, t)


def fit_homography(image_px: np.ndarray, world_m: np.ndarray) -> np.ndarray:
    """Least-squares homography from >= 4 point pairs (DLT, then OpenCV refines it)."""
    import cv2

    h, _ = cv2.findHomography(image_px.astype(np.float64), world_m.astype(np.float64), method=0)
    if h is None:
        raise ValueError("The calibration points don't define a ground plane. Mark four cones not in a line.")
    return h


def apply_homography(h: np.ndarray, x: float, y: float) -> tuple[float, float]:
    v = h @ np.array([x, y, 1.0])
    return float(v[0] / v[2]), float(v[1] / v[2])


def _by_homography(samples, obs, cal: Calibration, t) -> GroundTrack:
    # The marked points belong to the frame nearest cal.at_seconds; move them to reference coordinates.
    frame = min(obs, key=lambda o: abs(o.t - cal.at_seconds))
    img = np.array(
        [apply_affine(frame.to_ref, p.x * frame.width, p.y * frame.height) for p in cal.image_points]
    )
    world = np.array(cal.world_points_m, dtype=float)
    h = fit_homography(img, world)

    xy = np.full((len(samples), 2), np.nan)
    mpp = np.full(len(samples), np.nan)
    for i, s in enumerate(samples):
        if s.feet is None:
            continue
        xy[i] = apply_homography(h, *s.feet)
        # local scale: how many metres one pixel to the side is, at the feet
        x2 = apply_homography(h, s.feet[0] + 1.0, s.feet[1])
        mpp[i] = math.dist(x2, tuple(xy[i]))
    return GroundTrack(t, xy, mpp, "homography")


def _by_body(samples, obs, height_m: float, t) -> GroundTrack:
    width = obs[0].width if obs else 1280
    f = (width / 2) / math.tan(math.radians(PHONE_HFOV_DEG / 2))
    cx = width / 2
    heights = np.array([s.box_h if s.box_h else np.nan for s in samples], dtype=float)
    heights = smooth_heights(heights, t)
    stature_px_scale = height_m * BOX_TO_STATURE

    xy = np.full((len(samples), 2), np.nan)
    mpp = np.full(len(samples), np.nan)
    for i, s in enumerate(samples):
        h = heights[i]
        if s.feet is None or not np.isfinite(h) or h < 8:
            continue
        z = f * stature_px_scale / h
        x = (s.feet[0] - cx) * z / f
        xy[i] = (x, z)
        mpp[i] = stature_px_scale / h
    return GroundTrack(t, xy, mpp, "body")


def smooth_heights(h: np.ndarray, t: np.ndarray, window_s: float = 1.2) -> np.ndarray:
    """
    Rolling median, then rolling mean, over gaps-aware windows.

    The median throws away single bad boxes (arms raised, a crouch); the mean
    then smooths what's left. NaNs (frames where the player wasn't seen) stay NaN.
    """
    out = np.full_like(h, np.nan)
    ok = np.isfinite(h)
    for i in range(len(h)):
        if not ok[i]:
            continue
        win = ok & (np.abs(t - t[i]) <= window_s / 2)
        out[i] = np.median(h[win])
    smoothed = np.full_like(out, np.nan)
    for i in range(len(out)):
        if not ok[i]:
            continue
        win = ok & (np.abs(t - t[i]) <= window_s / 4)
        smoothed[i] = np.mean(out[win])
    return smoothed
