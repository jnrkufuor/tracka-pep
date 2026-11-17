"""Homography, joint angles and drill timing."""

import numpy as np
import pytest

from pep.drills.runner import crossing_time, sprint_30m
from pep.metrics.kinematics import analyse_movement
from pep.metrics.technique import joint_angle
from pep.vision.calibration import apply_homography, fit_homography


def test_homography_maps_cones_to_metres():
    # A 30 x 4 m rectangle seen in perspective: the far end looks narrower.
    image = np.array([[100, 600], [180, 400], [1100, 600], [1020, 400]], dtype=float)
    world = np.array([[0, 0], [0, 4], [30, 0], [30, 4]], dtype=float)
    h = fit_homography(image, world)
    for (u, v), (x, y) in zip(image, world, strict=True):
        assert apply_homography(h, u, v) == pytest.approx((x, y), abs=1e-6)
    mid = apply_homography(h, 600, 600)  # halfway along the near edge
    assert 10 < mid[0] < 20 and abs(mid[1]) < 1e-6


def test_joint_angle():
    assert joint_angle(np.array([0, 1.0]), np.array([0, 0.0]), np.array([1.0, 0])) == pytest.approx(
        90, abs=0.01
    )
    assert joint_angle(np.array([0, 1.0]), np.array([0, 0.0]), np.array([0, -1.0])) == pytest.approx(
        180, abs=0.01
    )


def test_crossing_time_interpolates():
    t = np.array([0.0, 0.1, 0.2])
    x = np.array([9.0, 9.5, 10.5])
    assert crossing_time(t, x, 10.0) == pytest.approx(0.15)


def test_sprint_30m_timing():
    # Accelerate uniformly from rest at 3 m/s^2 after standing for 1 s: x = 1.5 * t^2.
    # The clock starts once they've moved 20 cm (t = sqrt(0.2/1.5) = 0.37 s into the run),
    # so 30 m reads sqrt(20) - 0.37 = 4.11 s and 10 m reads sqrt(10/1.5) - 0.37 = 2.22 s.
    fps = 25.0
    t = np.arange(0, 7, 1 / fps)
    move = np.clip(t - 1.0, 0, None)
    x = np.minimum(1.5 * move**2, 40)
    xy = np.stack([x, np.zeros_like(x)], axis=1)
    kin = analyse_movement(t, xy, "homography")
    out = sprint_30m(kin, [])
    offset = np.sqrt(0.2 / 1.5)
    assert out["sprint_30m_s"] == pytest.approx(np.sqrt(20) - offset, abs=0.08)
    assert out["split_10m_s"] == pytest.approx(np.sqrt(10 / 1.5) - offset, abs=0.08)
