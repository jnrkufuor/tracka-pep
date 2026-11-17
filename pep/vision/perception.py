"""
Perception: finding people (with their body keypoints) and the ball.

Two neural networks, both Ultralytics YOLO26 (docs/handbook/04-models.md):

  * a POSE model (yolo26n-pose.pt) finds every person and 17 body keypoints
    each. Run in *tracking* mode, Ultralytics also gives each person an ID
    that stays the same from frame to frame (ByteTrack, see below).
  * a DETECTION model (yolo26s.pt), asked only for COCO class 32
    "sports ball".

Why the ball gets special treatment: in a wide phone shot the ball is 8-15
pixels across. YOLO looks at the frame shrunk to 640 px, so the ball can be
2-3 pixels: invisible. When the whole-frame pass misses it, we look again in
a crop around each of the two biggest players' feet, enlarged. This is the
idea behind SAHI ("slicing aided hyper inference"): small things become big
enough to detect if you zoom in on where they're likely to be.

ByteTrack (Zhang et al., 2022) in one paragraph: predict where each known
track will be with a Kalman filter, match high-confidence detections to
predictions by box overlap (IoU) using the Hungarian algorithm, then give
*low*-confidence detections a second chance to match leftover tracks (that's
its trick: a half-hidden player still keeps their ID). Unmatched tracks are
kept alive for a while in case the player reappears.

Everything here sits behind the `Perceiver` protocol, so tests and the
training scripts can swap in a fake perceiver without PyTorch installed.
"""

from __future__ import annotations

from typing import Protocol

import numpy as np

from ..config import settings
from ..log import get_logger
from .types import Box, Person

log = get_logger(__name__)

PERSON, SPORTS_BALL = 0, 32


class Perceiver(Protocol):
    """Anything that can look at one frame and return people and the ball."""

    def observe(self, image: np.ndarray) -> tuple[list[Person], Box | None]: ...

    def reset(self) -> None: ...


class YoloPerceiver:
    def __init__(self) -> None:
        from ultralytics import YOLO  # imported here so the API never needs PyTorch

        s = settings()
        self.device = s.device or None
        self.tracker = s.tracker
        self.pose = YOLO(_weights(s.pose_model))
        self.detector = YOLO(_weights(s.detector_model))
        log.info("perception.loaded", pose=s.pose_model, detector=s.detector_model, device=self.device)

    def reset(self) -> None:
        """Forget tracks between clips (each clip's IDs start fresh)."""
        predictor = getattr(self.pose, "predictor", None)
        if predictor is not None and getattr(predictor, "trackers", None):
            for tracker in predictor.trackers:
                tracker.reset()

    def observe(self, image: np.ndarray) -> tuple[list[Person], Box | None]:
        people = self._people(image)
        ball = self._ball(image, people)
        return people, ball

    def _people(self, image: np.ndarray) -> list[Person]:
        res = self.pose.track(
            image,
            persist=True,
            tracker=self.tracker,
            classes=[PERSON],
            conf=0.25,
            verbose=False,
            device=self.device,
        )[0]
        out: list[Person] = []
        if res.boxes is None or len(res.boxes) == 0:
            return out
        xyxy = res.boxes.xyxy.cpu().numpy()
        conf = res.boxes.conf.cpu().numpy()
        ids = res.boxes.id.cpu().numpy().astype(int) if res.boxes.id is not None else np.full(len(xyxy), -1)
        kps = res.keypoints.data.cpu().numpy() if res.keypoints is not None else None
        for i, (b, c, tid) in enumerate(zip(xyxy, conf, ids, strict=False)):
            out.append(
                Person(
                    track_id=int(tid),
                    box=Box(*map(float, b), conf=float(c)),
                    keypoints=kps[i] if kps is not None else None,
                )
            )
        return out

    def _ball(self, image: np.ndarray, people: list[Person]) -> Box | None:
        res = self.detector.predict(
            image, classes=[SPORTS_BALL], conf=0.2, verbose=False, device=self.device
        )[0]
        best = _best(res)
        if best is not None:
            return best
        # Second look: zoom in around the feet of the two biggest people.
        h, w = image.shape[:2]
        for p in sorted(people, key=lambda p: -p.box.h)[:2]:
            b = p.box
            size = max(b.h * 1.4, 160)
            cx, cy = b.feet
            x1, y1 = int(max(0, cx - size / 2)), int(max(0, cy - size * 0.7))
            x2, y2 = int(min(w, cx + size / 2)), int(min(h, cy + size * 0.3))
            if x2 - x1 < 16 or y2 - y1 < 16:
                continue
            crop = image[y1:y2, x1:x2]
            res = self.detector.predict(
                crop, classes=[SPORTS_BALL], conf=0.15, imgsz=320, verbose=False, device=self.device
            )[0]
            found = _best(res)
            if found is not None:
                return Box(found.x1 + x1, found.y1 + y1, found.x2 + x1, found.y2 + y1, found.conf)
        return None


def _best(res) -> Box | None:
    if res.boxes is None or len(res.boxes) == 0:
        return None
    i = int(res.boxes.conf.argmax())
    x1, y1, x2, y2 = map(float, res.boxes.xyxy[i].cpu().numpy())
    return Box(x1, y1, x2, y2, float(res.boxes.conf[i]))


def _weights(name: str) -> str:
    """Model files live in PEP_MODELS_DIR; Ultralytics downloads them there the first time."""
    from pathlib import Path

    local = Path(settings().models_dir) / name
    if local.exists():
        return str(local)
    # Ultralytics downloads known names (yolo26s.pt...) itself. A custom fine-tuned
    # model should be put in models_dir (or a path given) - see training/finetune_detector.py.
    return name
