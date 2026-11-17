"""Speed and movement maths, checked against trajectories where we know the answer."""

import numpy as np

from pep.metrics.kinematics import analyse_movement, kalman_rts, rolling_mean, segments


def straight_run(speed: float, seconds: float = 8.0, noise_m: float = 0.15, fps: float = 10.0, seed: int = 0):
    t = np.arange(0, seconds, 1 / fps)
    rng = np.random.default_rng(seed)
    xy = np.stack([speed * t, np.full_like(t, 10.0)], axis=1) + rng.normal(0, noise_m, (len(t), 2))
    return t, xy


def test_constant_speed_is_recovered_despite_noise():
    t, xy = straight_run(6.0)
    kin = analyse_movement(t, xy, "homography")
    assert abs(kin.metrics["top_speed_ms"] - 6.0) < 0.3
    assert abs(kin.metrics["distance_m"] - 6.0 * 7.9) < 3.0


def test_raw_differences_would_be_much_worse():
    """Why we filter: naive frame-to-frame speed from the same noisy data swings wildly."""
    t, xy = straight_run(6.0)
    naive = np.hypot(*np.diff(xy, axis=0).T) / np.diff(t)
    smooth = analyse_movement(t, xy, "homography").speed
    assert np.std(naive) > 4 * np.nanstd(smooth[5:-5])


def test_standing_still_reads_as_still():
    t, xy = straight_run(0.0)
    kin = analyse_movement(t, xy, "homography")
    assert kin.metrics["top_speed_ms"] < 0.6
    assert kin.metrics["moving_share"] == 0.0


def test_gaps_split_segments():
    t = np.arange(0, 10, 0.1)
    seen = np.ones_like(t, dtype=bool)
    seen[30:50] = False  # 2 s gap
    assert segments(t, seen) == [(0, 30), (50, 100)]


def test_kalman_handles_missing_measurements():
    t, xy = straight_run(5.0, noise_m=0.05)
    xy[20:25] = np.nan
    states = kalman_rts(t, xy, np.full(len(t), 0.05))
    assert np.all(np.isfinite(states))
    assert abs(states[22, 2] - 5.0) < 0.5  # velocity still known through the gap


def test_turns_are_counted():
    # zig-zag: run 1.5 s one way, then turn 90 degrees, repeatedly, at 5 m/s
    fps, v = 10.0, 5.0
    pts, p, d = [], np.array([0.0, 0.0]), np.array([1.0, 0.0])
    for i in range(int(12 * fps)):
        if i and i % 15 == 0:
            d = np.array([-d[1], d[0]]) if (i // 15) % 2 else np.array([d[1], -d[0]])
        p = p + d * v / fps
        pts.append(p.copy())
    t = np.arange(len(pts)) / fps
    kin = analyse_movement(t, np.array(pts), "homography")
    assert kin.metrics["turns_per_min"] >= 20


def test_rolling_mean_needs_a_full_window():
    t = np.arange(0, 3, 0.1)
    v = np.ones_like(t)
    out = rolling_mean(t, v, 1.0)
    assert np.isnan(out[0]) and out[-1] == 1.0
