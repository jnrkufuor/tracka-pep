"""
Camera-motion compensation.

Phone clips pan, tilt and zoom to follow the player. If we measured the
player's movement on screen, a player standing still while the camera pans
would look like they're running. So we measure how the *background* moves
between frames and take that away.

How:
  1. Find corners in the previous frame that are good to follow
     (`goodFeaturesToTrack`, the Shi-Tomasi detector), avoiding people:
     they move on their own and would confuse the estimate.
  2. Follow those corners into the current frame with Lucas-Kanade optical
     flow (`calcOpticalFlowPyrLK`).
  3. Fit one similarity transform (move + rotate + zoom) that explains most
     corner movements, ignoring outliers with RANSAC
     (`estimateAffinePartial2D`).
  4. Chain the transforms so every frame maps into the first frame's
     coordinates ("reference" coordinates).

RANSAC (RANdom SAmple Consensus) is worth understanding properly: fit a
model to a random minimal sample, count how many points agree ("inliers"),
repeat, keep the best. It's how you fit anything robustly when some data is
garbage. See docs/handbook/06-computer-vision.md (workbook at the end).

Limits: a pitch with no texture (plain grass, sky) gives few corners; then we
assume the camera held still for that step and lower our confidence.
"""

from __future__ import annotations

import numpy as np

from .types import Box


class CameraMotion:
    def __init__(self, max_corners: int = 400) -> None:
        self.max_corners = max_corners
        self.prev_gray: np.ndarray | None = None
        self.to_ref = np.array([[1.0, 0, 0], [0, 1.0, 0]])
        self.weak_steps = 0  # steps where we couldn't measure the camera
        self.steps = 0

    def update(self, image: np.ndarray, people: list[Box]) -> np.ndarray:
        """Returns the 2x3 matrix mapping this frame's pixels to the first frame's pixels."""
        import cv2

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        if self.prev_gray is None or self.prev_gray.shape != gray.shape:
            self.prev_gray = gray
            return self.to_ref.copy()

        mask = np.full(gray.shape, 255, dtype=np.uint8)
        for b in people:  # don't follow corners on people
            pad = 0.15 * b.h
            mask[
                max(0, int(b.y1 - pad)) : int(b.y2 + pad),
                max(0, int(b.x1 - pad)) : int(b.x2 + pad),
            ] = 0

        self.steps += 1
        step = None
        pts = cv2.goodFeaturesToTrack(self.prev_gray, self.max_corners, 0.01, 8, mask=mask)
        if pts is not None and len(pts) >= 12:
            nxt, status, _ = cv2.calcOpticalFlowPyrLK(self.prev_gray, gray, pts, None)  # type: ignore[call-overload]
            good = status.reshape(-1) == 1
            if good.sum() >= 12:
                # current -> previous (so chaining gives current -> reference)
                step, inliers = cv2.estimateAffinePartial2D(
                    nxt[good], pts[good], method=cv2.RANSAC, ransacReprojThreshold=2.0
                )
                if step is None or inliers is None or inliers.sum() < 8:
                    step = None

        if step is None:
            self.weak_steps += 1
            step = np.array([[1.0, 0, 0], [0, 1.0, 0]])

        # Compose: ref <- prev <- current. Affines compose as 3x3 matrices.
        self.to_ref = (_h(self.to_ref) @ _h(step))[:2]
        self.prev_gray = gray
        return self.to_ref.copy()

    @property
    def reliability(self) -> float:
        """Share of steps where the camera movement was actually measured."""
        return 1.0 - self.weak_steps / self.steps if self.steps else 1.0


def _h(m: np.ndarray) -> np.ndarray:
    """2x3 affine -> 3x3 so matrices can be multiplied (homogeneous coordinates)."""
    return np.vstack([m, [0.0, 0.0, 1.0]])
