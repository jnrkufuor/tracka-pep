"""
Ball metrics: touches, keeping the ball close, heavy touches.

We don't know the ball's height off the ground (one camera can't tell), so
we compare the ball with the player's *feet* in the image and express
distances in body heights. "Within 0.6 of a body height of the feet" works
whether the player is near the camera or far away.

  ball_at_feet_share  of the frames where the ball is near (< 2 body heights),
                      the share where it's really at the feet (< 0.6)
  touches_per_min     the ball changes direction sharply while at the feet
  close_control_m     while running with the ball, the typical gap between
                      feet and ball, in metres (smaller = tighter dribbling)
  heavy_touches       the ball leaves the feet and runs away more than
                      ~2.5 m ahead of a running player: a touch they'd want back
"""

from __future__ import annotations

import numpy as np

from ..vision.target import TargetSample


def analyse_ball(samples: list[TargetSample], speed: np.ndarray, metres_per_px: np.ndarray):
    t = np.array([s.t for s in samples])
    n = len(samples)
    gap_bh = np.full(n, np.nan)  # ball-to-feet distance in body heights
    gap_m = np.full(n, np.nan)
    ball = np.full((n, 2), np.nan)
    for i, s in enumerate(samples):
        if s.ball is not None:
            ball[i] = s.ball
        if s.ball is None or s.feet is None or not s.box_h:
            continue
        d_px = float(np.hypot(s.ball[0] - s.feet[0], s.ball[1] - s.feet[1]))
        gap_bh[i] = d_px / s.box_h
        if np.isfinite(metres_per_px[i]):
            gap_m[i] = d_px * metres_per_px[i]

    near = gap_bh < 2.0
    at_feet = gap_bh < 0.6
    m: dict[str, float | None] = {"ball_frames": float(np.isfinite(gap_bh).sum())}
    events: list[tuple[float, str, str]] = []
    if near.sum() < 6:
        return m | {"ball_at_feet_share": None, "touches_per_min": None, "close_control_m": None}, events

    m["ball_at_feet_share"] = round(float(at_feet[near].mean()), 3)

    # Touches: sharp change in the ball's direction while it's at the feet.
    touches, last = 0, -1.0
    for i in range(1, n - 1):
        if not at_feet[i] or t[i] - last < 0.25:
            continue
        a, b = ball[i] - ball[i - 1], ball[i + 1] - ball[i]
        if not (np.isfinite(a).all() and np.isfinite(b).all()):
            continue
        na, nb = np.linalg.norm(a), np.linalg.norm(b)
        if na < 1 and nb < 1:
            continue  # ball basically still
        cos = float(a @ b / (na * nb)) if na > 0 and nb > 0 else -1.0
        if cos < 0.5:  # turned more than 60 degrees
            touches += 1
            last = t[i]
    seconds_near = float(np.sum(np.diff(t, prepend=t[0])[near]))
    m["touches_per_min"] = round(touches / max(seconds_near / 60, 1 / 60), 1) if seconds_near >= 2 else None
    m["touches"] = float(touches)

    running = near & np.isfinite(speed) & (speed > 3.0) & np.isfinite(gap_m)
    m["close_control_m"] = round(float(np.median(gap_m[running])), 2) if running.sum() >= 4 else None

    # Heavy touches: was at the feet, then 0.5 s later > 2.5 m away while the player runs.
    for i in map(int, np.flatnonzero(at_feet)):
        later = (t > t[i]) & (t <= t[i] + 0.6)
        if (later & (gap_m > 2.5) & (speed > 3.0)).any():
            events.append((float(t[i]), "WORK_ON", "Heavy touch: the ball ran away from you here."))
    events = _dedupe(events, 2.0)  # one heavy touch shows up in several frames
    m["heavy_touches"] = float(len(events))
    return m, events


def _dedupe(events: list[tuple[float, str, str]], within_s: float) -> list[tuple[float, str, str]]:
    out: list[tuple[float, str, str]] = []
    for e in sorted(events):
        if not out or e[0] - out[-1][0] > within_s:
            out.append(e)
    return out
