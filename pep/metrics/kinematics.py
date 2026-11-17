"""
Movement metrics: speed, top speed, acceleration, distance, sprints, turns.

The raw positions from calibration are noisy: a box that jitters 5 pixels
becomes a fake 2 m/s wobble once you differentiate. Differentiating noise
amplifies it, so we never take raw differences. Instead:

KALMAN FILTER (forward pass)
  We model the player as a point moving with roughly constant velocity,
  where velocity changes by random accelerations (the "process noise").
  Each frame the filter:
    1. PREDICTS the new position and velocity from the old ones (physics),
    2. UPDATES that prediction with the measured position, trusting the
       measurement in proportion to how noisy we believe it is.
  The "Kalman gain" decides the blend. Frames where the player wasn't seen
  simply skip step 2.

RTS SMOOTHER (backward pass)
  Because we have the whole clip (we're not live), we can also run
  backwards and let later frames correct earlier estimates. The
  Rauch-Tung-Striebel smoother does this; it's why offline speed curves are
  much cleaner than live ones.

Then the metrics use ROBUST statistics: "top speed" is the best average
over one second, not the single fastest frame (one bad frame would win).

Thresholds follow common football conventions (e.g. high-speed running at
19.8 km/h = 5.5 m/s); docs/handbook/05-features.md explains each one.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

JOG_MS = 2.0  # 7.2 km/h: faster than a walk
HIGH_SPEED_MS = 5.5  # 19.8 km/h: "high-speed running" in most tracking systems
TURN_SPEED_MS = 2.5  # only count direction changes made while actually running
MAX_GAP_S = 1.0  # longer gaps split the track into separate segments


@dataclass
class Kinematics:
    t: np.ndarray
    pos: np.ndarray  # (N, 2) smoothed position, metres
    vel: np.ndarray  # (N, 2) metres/second
    speed: np.ndarray  # (N,) metres/second, NaN where unknown
    metrics: dict[str, float | None]
    events: list[tuple[float, str, str]]  # (seconds, GOOD/WORK_ON, text) worth showing


def kalman_rts(t: np.ndarray, z: np.ndarray, meas_sigma: np.ndarray, accel_sigma: float = 4.0):
    """
    Constant-velocity Kalman filter + RTS smoother in 2-D.

    t: (N,) times. z: (N, 2) measured positions (NaN = missing).
    meas_sigma: (N,) how noisy each measurement is, in metres.
    accel_sigma: how hard players can change velocity, m/s^2 (bigger = filter follows faster).
    Returns smoothed states (N, 4) = [x, y, vx, vy].
    """
    n = len(t)
    x = np.zeros((n, 4))
    p = np.zeros((n, 4, 4))
    x_pred = np.zeros((n, 4))
    p_pred = np.zeros((n, 4, 4))
    f_all = np.zeros((n, 4, 4))
    hm = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], dtype=float)  # we measure position, not velocity

    first = int(np.argmax(np.isfinite(z[:, 0])))
    state = np.array([z[first, 0], z[first, 1], 0.0, 0.0])
    cov = np.diag([1.0, 1.0, 25.0, 25.0])  # unsure about the starting velocity

    for i in range(n):
        dt = t[i] - t[i - 1] if i > 0 else 0.0
        f = np.array([[1, 0, dt, 0], [0, 1, 0, dt], [0, 0, 1, 0], [0, 0, 0, 1]], dtype=float)
        # Process noise for a random acceleration held over dt ("discrete white noise acceleration").
        q1 = np.array([[dt**4 / 4, dt**3 / 2], [dt**3 / 2, dt**2]]) * accel_sigma**2
        q = np.zeros((4, 4))
        q[np.ix_([0, 2], [0, 2])] = q1
        q[np.ix_([1, 3], [1, 3])] = q1

        # 1. predict
        state = f @ state
        cov = f @ cov @ f.T + q
        x_pred[i], p_pred[i], f_all[i] = state, cov, f

        # 2. update (only if we saw the player)
        if np.isfinite(z[i, 0]):
            r = np.eye(2) * meas_sigma[i] ** 2
            innovation = z[i] - hm @ state
            s = hm @ cov @ hm.T + r
            gain = cov @ hm.T @ np.linalg.inv(s)
            state = state + gain @ innovation
            cov = (np.eye(4) - gain @ hm) @ cov
        x[i], p[i] = state, cov

    # Backward pass (Rauch-Tung-Striebel).
    xs = x.copy()
    for i in range(n - 2, -1, -1):
        c = p[i] @ f_all[i + 1].T @ np.linalg.inv(p_pred[i + 1])
        xs[i] = x[i] + c @ (xs[i + 1] - x_pred[i + 1])
    return xs


def segments(t: np.ndarray, seen: np.ndarray, max_gap: float = MAX_GAP_S) -> list[tuple[int, int]]:
    """Index ranges [start, end) where the player is seen with no gap longer than max_gap."""
    idx = np.flatnonzero(seen)
    if len(idx) == 0:
        return []
    out, start = [], idx[0]
    for a, b in zip(idx[:-1], idx[1:], strict=False):
        if t[b] - t[a] > max_gap:
            out.append((start, a + 1))
            start = b
    out.append((start, idx[-1] + 1))
    return [(s, e) for s, e in out if e - s >= 3]


def rolling_mean(t: np.ndarray, v: np.ndarray, window_s: float) -> np.ndarray:
    """Mean of v over the window_s seconds ending at each point (NaN-aware)."""
    out = np.full_like(v, np.nan, dtype=float)
    for i in range(len(v)):
        win = (t > t[i] - window_s) & (t <= t[i]) & np.isfinite(v)
        if win.sum() >= 2 and t[i] - t[win][0] >= window_s * 0.7:
            out[i] = v[win].mean()
    return out


def analyse_movement(t: np.ndarray, xy: np.ndarray, method: str) -> Kinematics:
    n = len(t)
    seen = np.isfinite(xy[:, 0])
    pos = np.full((n, 2), np.nan)
    vel = np.full((n, 2), np.nan)

    # How much we trust each position: a homography is good to ~15 cm; the
    # body ruler gets worse with distance (a far player's box is small and jittery).
    if method == "homography":
        sigma = np.full(n, 0.15)
    else:
        depth = np.nan_to_num(np.abs(xy[:, 1]), nan=10.0)
        sigma = 0.2 + 0.04 * depth

    for s, e in segments(t, seen):
        states = kalman_rts(t[s:e], xy[s:e], sigma[s:e])
        pos[s:e], vel[s:e] = states[:, :2], states[:, 2:]

    speed = np.hypot(vel[:, 0], vel[:, 1])
    metrics, events = _summarise(t, speed, vel)
    return Kinematics(t, pos, vel, speed, metrics, events)


def _summarise(t, speed, vel) -> tuple[dict[str, float | None], list[tuple[float, str, str]]]:
    ok = np.isfinite(speed)
    dt = np.diff(t, prepend=t[0])
    tracked_s = float(dt[ok].sum())
    m: dict[str, float | None] = {"seconds_tracked": round(tracked_s, 2)}
    events: list[tuple[float, str, str]] = []
    if tracked_s < 2.0:
        return m | {"top_speed_ms": None, "peak_accel_ms2": None, "distance_m": None}, events

    one_s = rolling_mean(t, speed, 1.0)
    if np.isfinite(one_s).any():
        i = int(np.nanargmax(one_s))
        m["top_speed_ms"] = round(float(one_s[i]), 2)
        m["top_speed_at"] = round(float(t[i]), 2)
        if one_s[i] >= HIGH_SPEED_MS:
            events.append((float(t[i]), "GOOD", f"Top speed here: {one_s[i] * 3.6:.1f} km/h."))
    else:
        m["top_speed_ms"] = None

    # Acceleration: change of (half-second-averaged) speed over time.
    half = rolling_mean(t, speed, 0.5)
    accel = np.gradient(half, t) if len(t) > 2 else np.full_like(half, np.nan)
    accel[~np.isfinite(accel)] = np.nan
    m["peak_accel_ms2"] = round(float(np.nanmax(accel)), 2) if np.isfinite(accel).any() else None

    distance = float(np.nansum(speed * dt))
    m["distance_m"] = round(distance, 1)
    m["distance_per_min_m"] = round(distance / (tracked_s / 60), 1)
    m["moving_share"] = round(float(np.mean(speed[ok] > JOG_MS)), 3)
    m["high_speed_share"] = round(float(np.mean(speed[ok] > HIGH_SPEED_MS)), 3)

    # High-speed runs: at least 1 s above 5.5 m/s.
    runs, start = 0, None
    for i in range(len(t)):
        fast = ok[i] and speed[i] > HIGH_SPEED_MS
        if fast and start is None:
            start = t[i]
        if not fast and start is not None:
            runs += t[i] - start >= 1.0
            start = None
    m["high_speed_runs"] = float(runs)

    # Sharp turns: heading changes of 45 degrees or more within 0.8 s while running.
    heading = np.arctan2(vel[:, 1], vel[:, 0])
    turns, last_turn = 0, -10.0
    for i in range(len(t)):
        if not (ok[i] and speed[i] > TURN_SPEED_MS) or t[i] - last_turn < 0.8:
            continue
        back = (t >= t[i] - 0.8) & (t < t[i]) & ok & (speed > TURN_SPEED_MS)
        if back.any():
            diff = np.abs(np.angle(np.exp(1j * (heading[i] - heading[back]))))  # wrap to [0, pi]
            if diff.max() >= np.radians(45):
                turns += 1
                last_turn = t[i]
    m["turns_per_min"] = round(turns / (tracked_s / 60), 2)
    return m, events
