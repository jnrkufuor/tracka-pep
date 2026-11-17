"""
Turning a video file into the frames we analyse.

A phone clip is usually 30 or 60 frames per second. We don't need all of
them: a player at full sprint covers about 30 cm in 1/30 s, and the tracker
copes fine at 10 samples a second. Analysing fewer frames is the single
biggest cost lever in the whole pipeline (GPU seconds scale with frames).

We also shrink frames so their longest side is `max_side` pixels. YOLO
resizes internally anyway (to 640 by default); decoding 4K and throwing
most of it away wastes memory.

This module uses a *generator* (`yield`): frames are produced one at a time
as the caller asks for them, so a 10-minute clip never sits in memory all at
once. That pattern is worth knowing: see docs/handbook/11-python-toolbox.md.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class VideoInfo:
    fps: float
    frame_count: int
    width: int
    height: int

    @property
    def duration(self) -> float:
        return self.frame_count / self.fps if self.fps else 0.0


@dataclass
class Frame:
    index: int  # sample number (0, 1, 2...), not the frame number in the file
    t: float  # seconds from the start of the clip
    image: np.ndarray  # BGR pixels, shape (height, width, 3): OpenCV's layout
    scale: float  # how much the original was shrunk (0.5 = half size)


def probe(path: str | Path) -> VideoInfo:
    import cv2

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise ValueError("This file can't be read as a video.")
    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        # Some phones write a nonsense fps (e.g. 90000) in the header. Clamp it.
        fps = fps if 1 <= fps <= 240 else 30.0
        return VideoInfo(
            fps=fps,
            frame_count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT)),
            width=int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
            height=int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
        )
    finally:
        cap.release()


def sample_frames(
    path: str | Path,
    samples_per_second: float = 10.0,
    max_side: int = 1280,
    max_seconds: float | None = 180.0,
) -> Iterator[Frame]:
    """
    Yields evenly spaced frames from the video.

    We step through the file with `grab()` (cheap: no decoding) and only
    `retrieve()` (decode) the frames we keep. Seeking by time is unreliable
    on many phone files, so reading in order is both safer and fast enough.
    """
    import cv2

    info = probe(path)
    cap = cv2.VideoCapture(str(path))
    step = max(1.0, info.fps / samples_per_second)  # keep every `step`-th frame
    next_keep = 0.0
    frame_no = 0
    index = 0
    try:
        while True:
            if not cap.grab():
                break
            if frame_no >= next_keep:
                ok, image = cap.retrieve()
                if not ok:
                    break
                t = frame_no / info.fps
                if max_seconds is not None and t > max_seconds:
                    break
                h, w = image.shape[:2]
                scale = min(1.0, max_side / max(h, w))
                if scale < 1.0:
                    image = cv2.resize(
                        image, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA
                    )
                yield Frame(index=index, t=t, image=image, scale=scale)
                index += 1
                next_keep += step
            frame_no += 1
    finally:
        cap.release()  # always free the decoder, even if the caller stops early
