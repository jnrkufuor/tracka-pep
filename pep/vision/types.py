"""
Small shared shapes for the vision steps.

Coordinates are pixels in the (resized) frame unless a name says otherwise.
Boxes are (x1, y1, x2, y2): top-left and bottom-right corners.

Keypoints follow the COCO-17 layout every common pose model uses:

    0 nose   1 left eye   2 right eye   3 left ear   4 right ear
    5 left shoulder   6 right shoulder   7 left elbow   8 right elbow
    9 left wrist   10 right wrist   11 left hip   12 right hip
    13 left knee   14 right knee   15 left ankle   16 right ankle

Each keypoint is (x, y, confidence). "Left" is the player's left, not yours.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

NOSE, L_SHOULDER, R_SHOULDER = 0, 5, 6
L_ELBOW, R_ELBOW, L_WRIST, R_WRIST = 7, 8, 9, 10
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE = 11, 12, 13, 14, 15, 16


@dataclass
class Box:
    x1: float
    y1: float
    x2: float
    y2: float
    conf: float = 1.0

    @property
    def w(self) -> float:
        return self.x2 - self.x1

    @property
    def h(self) -> float:
        return self.y2 - self.y1

    @property
    def center(self) -> tuple[float, float]:
        return ((self.x1 + self.x2) / 2, (self.y1 + self.y2) / 2)

    @property
    def feet(self) -> tuple[float, float]:
        """Bottom middle of the box: where the player touches the ground."""
        return ((self.x1 + self.x2) / 2, self.y2)

    def contains(self, x: float, y: float, pad: float = 0.0) -> bool:
        return self.x1 - pad <= x <= self.x2 + pad and self.y1 - pad <= y <= self.y2 + pad

    def iou(self, other: Box) -> float:
        """Intersection over union: 1 = same box, 0 = no overlap. The workhorse of tracking."""
        ix = max(0.0, min(self.x2, other.x2) - max(self.x1, other.x1))
        iy = max(0.0, min(self.y2, other.y2) - max(self.y1, other.y1))
        inter = ix * iy
        union = self.w * self.h + other.w * other.h - inter
        return inter / union if union > 0 else 0.0


@dataclass
class Person:
    track_id: int  # given by the tracker; -1 when the tracker hasn't confirmed it yet
    box: Box
    keypoints: np.ndarray | None = None  # (17, 3) or None if no pose


@dataclass
class FrameObs:
    """Everything perception saw in one sampled frame."""

    index: int
    t: float
    width: int
    height: int
    people: list[Person] = field(default_factory=list)
    ball: Box | None = None
    # 2x3 affine matrix taking this frame's pixels into the first frame's pixels
    # ("reference" or "scene" coordinates): it cancels the camera's own movement.
    to_ref: np.ndarray = field(default_factory=lambda: np.array([[1.0, 0, 0], [0, 1.0, 0]]))


def apply_affine(m: np.ndarray, x: float, y: float) -> tuple[float, float]:
    return (float(m[0, 0] * x + m[0, 1] * y + m[0, 2]), float(m[1, 0] * x + m[1, 1] * y + m[1, 2]))


def affine_scale(m: np.ndarray) -> float:
    """How much an affine matrix zooms (1 = no zoom)."""
    return float(np.sqrt(abs(np.linalg.det(m[:, :2]))))
