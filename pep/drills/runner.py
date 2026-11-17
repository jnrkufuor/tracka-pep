"""
Standard drills: the fairest way to compare players.

A match clip shows what a player chose to show, filmed however it was
filmed. A drill is the same test for everyone: same distance, same cones,
same rules. That's why scouts trust a 30 m sprint time more than "looked
fast in a highlight", and why Pep marks drill-based skills as `source:
"drill"` with higher confidence.

Each drill reads the already-computed movement (positions in metres from
the homography) or ball path, and returns a few numbers. Definitions live
in pep/data/drills.json, so adding a drill is: add it there, add a function
here, register it in DRILLS, add norms to pep/data/norms.json.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from functools import cache
from pathlib import Path

import numpy as np

from ..metrics.kinematics import Kinematics
from ..vision.target import TargetSample

DATA = Path(__file__).resolve().parent.parent / "data" / "drills.json"


@cache
def drill_catalogue() -> dict:
    return {k: v for k, v in json.loads(DATA.read_text()).items() if not k.startswith("_")}


def crossing_time(
    t: np.ndarray, x: np.ndarray, line: float, after: float = -np.inf, direction: int = 1
) -> float | None:
    """
    First time after `after` that x crosses `line` going in `direction` (+1 increasing x).
    Linear interpolation between the two samples either side gives sub-frame precision:
    at 10 samples/s, that's the difference between +-0.1 s and about +-0.02 s.
    """
    for i in range(1, len(t)):
        if t[i] <= after or not (np.isfinite(x[i - 1]) and np.isfinite(x[i])):
            continue
        a, b = (x[i - 1] - line) * direction, (x[i] - line) * direction
        if a < 0 <= b:
            frac = -a / (b - a) if b != a else 0.0
            return float(t[i - 1] + frac * (t[i] - t[i - 1]))
    return None


START_MOVE_M = 0.2


def start_time(t: np.ndarray, pos: np.ndarray, speed: np.ndarray) -> float | None:
    """
    When the player starts: the moment they've moved START_MOVE_M (20 cm) from
    where they stood. Like timing gates (which sit a little in front of the
    start line), this ignores the tiny rocking before a start, and it's the
    same rule for everyone, which is what makes times comparable.
    """
    moving = np.flatnonzero(np.isfinite(speed) & (speed > 0.8))
    if not len(moving):
        return None
    before = (t <= t[moving[0]]) & np.isfinite(pos[:, 0])
    if not before.any():
        return float(t[moving[0]])
    rest = np.median(pos[before][: max(3, int(before.sum() // 2))], axis=0)
    dist = np.hypot(pos[:, 0] - rest[0], pos[:, 1] - rest[1])
    for i in range(1, len(t)):
        if np.isfinite(dist[i]) and dist[i] >= START_MOVE_M and np.isfinite(dist[i - 1]):
            d0, d1 = dist[i - 1], dist[i]
            frac = (START_MOVE_M - d0) / (d1 - d0) if d1 != d0 else 0.0
            return float(t[i - 1] + frac * (t[i] - t[i - 1]))
    return float(t[moving[0]])


def sprint_30m(kin: Kinematics, samples: list[TargetSample]) -> dict[str, float | None]:
    x = kin.pos[:, 0]
    direction = 1 if np.nanmedian(np.diff(x[np.isfinite(x)])) >= 0 else -1
    start_line, finish = (0.0, 30.0) if direction == 1 else (30.0, 0.0)
    go = start_time(kin.t, kin.pos, kin.speed)
    if go is None:
        return {"sprint_30m_s": None, "split_10m_s": None}
    end = crossing_time(kin.t, x, finish, after=go, direction=direction)
    ten = crossing_time(kin.t, x, start_line + 10 * direction, after=go, direction=direction)
    return {
        "sprint_30m_s": round(end - go, 2) if end else None,
        "split_10m_s": round(ten - go, 2) if ten else None,
    }


def agility_5105(kin: Kinematics, samples: list[TargetSample]) -> dict[str, float | None]:
    x = kin.pos[:, 0]
    go = start_time(kin.t, kin.pos, kin.speed)
    if go is None:
        return {"agility_5105_s": None}
    # The run visits both turn lines (|x| ~ 5), then finishes back through the middle line.
    seen = np.isfinite(x) & (kin.t >= go)
    if not ((x[seen] > 4.0).any() and (x[seen] < -4.0).any()):
        return {"agility_5105_s": None}
    last_turn = max(kin.t[seen & (x > 4.0)].max(), kin.t[seen & (x < -4.0)].max())
    direction = -1 if x[seen & (kin.t == last_turn)].mean() > 0 else 1
    end = crossing_time(kin.t, x, 0.0, after=last_turn, direction=direction)
    return {"agility_5105_s": round(end - go, 2) if end else None}


def juggling(kin: Kinematics, samples: list[TargetSample]) -> dict[str, float | None]:
    """
    A touch = the ball's lowest point in a bounce (image y has a local maximum,
    since image y grows downwards), above the feet. A drop = the ball comes
    down to the feet's level, or vanishes for over a second.
    """
    t = np.array([s.t for s in samples])
    by = np.array([s.ball[1] if s.ball else np.nan for s in samples])
    feet_y = np.array([s.feet[1] if s.feet else np.nan for s in samples])
    h = np.array([s.box_h or np.nan for s in samples])
    best = total = streak = 0
    last_seen = None
    for i in range(1, len(t) - 1):
        if not np.isfinite(by[i]):
            if last_seen is not None and t[i] - last_seen > 1.0:
                best, streak = max(best, streak), 0
            continue
        last_seen = t[i]
        if np.isfinite(feet_y[i]) and np.isfinite(h[i]) and by[i] > feet_y[i] - 0.03 * h[i]:
            best, streak = max(best, streak), 0  # on the ground
            continue
        if np.isfinite(by[i - 1]) and np.isfinite(by[i + 1]) and by[i] >= by[i - 1] and by[i] > by[i + 1]:
            streak += 1
            total += 1
    best = max(best, streak)
    return {"juggles_best": float(best), "juggles_total": float(total)}


def wall_passes(kin: Kinematics, samples: list[TargetSample]) -> dict[str, float | None]:
    """Count the ball coming back to the feet after being far away, in the first 30 s."""
    count, away = 0, False
    t0 = samples[0].t if samples else 0.0
    for s in samples:
        if s.t - t0 > 30 or s.ball is None or s.feet is None or not s.box_h:
            continue
        gap = np.hypot(s.ball[0] - s.feet[0], s.ball[1] - s.feet[1]) / s.box_h
        if gap > 1.5:
            away = True
        elif away and gap < 0.6:
            count += 1
            away = False
    return {"wall_passes_30s": float(count)}


DRILLS: dict[str, Callable[[Kinematics, list[TargetSample]], dict[str, float | None]]] = {
    "sprint_30m": sprint_30m,
    "agility_5105": agility_5105,
    "juggling": juggling,
    "wall_passes": wall_passes,
}


def run_drill(drill: str, kin: Kinematics, samples: list[TargetSample]) -> dict[str, float | None]:
    if drill not in DRILLS:
        raise ValueError(f"Unknown drill '{drill}'. Known: {', '.join(DRILLS)}")
    return DRILLS[drill](kin, samples)
