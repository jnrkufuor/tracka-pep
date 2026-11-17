"""
A debug video: what Pep saw, drawn on the clip.

When a number looks wrong, the first question is always "what did the
tracker actually follow?". This draws the chosen player's box and skeleton,
their recent path, live speed, and the ball, and encodes an H.264 MP4 that
plays in any browser (the Pep Lab shows it next to the result).

We pipe raw frames into ffmpeg rather than using OpenCV's VideoWriter,
because OpenCV's default MP4 codec (mp4v) doesn't play in browsers.
`-preset veryfast` keeps encoding quick; quality is plenty for debugging.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import numpy as np

from .config import settings
from .pipeline import Analysis
from .video.frames import sample_frames
from .vision.types import apply_affine

NEON = (0, 255, 229)  # #E5FF00 in OpenCV's BGR order
WHITE = (240, 245, 244)
SKELETON = [
    (5, 7),
    (7, 9),
    (6, 8),
    (8, 10),
    (5, 6),
    (5, 11),
    (6, 12),
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
]


def render_overlay(video: Path, analysis: Analysis, out: Path) -> Path:
    import cv2

    s = settings()
    frames = sample_frames(video, s.samples_per_second, s.max_side)
    first = next(frames, None)
    if first is None:
        raise ValueError("no frames")
    h, w = first.image.shape[:2]
    w2, h2 = w - w % 2, h - h % 2  # H.264 needs even dimensions
    proc = subprocess.Popen(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "bgr24",
            "-s",
            f"{w2}x{h2}",
            "-r",
            str(s.samples_per_second),
            "-i",
            "-",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "26",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(out),
        ],
        stdin=subprocess.PIPE,
    )
    assert proc.stdin is not None
    # The trail is kept in reference coordinates (camera motion removed) and mapped
    # back into each frame, so it shows where the player really went, not where
    # they were on screen while the camera panned.
    trail: list[tuple[float, float]] = []

    def draw(index: int, image: np.ndarray) -> np.ndarray:
        img = image.copy()
        if index < len(analysis.samples):
            smp = analysis.samples[index]
            if smp.box is not None:
                b = smp.box
                cv2.rectangle(img, (int(b.x1), int(b.y1)), (int(b.x2), int(b.y2)), NEON, 2)
                if smp.feet is not None:
                    trail.append(smp.feet)
                speed = analysis.speed[index] if analysis.speed is not None else np.nan
                if np.isfinite(speed):
                    label = f"{speed * 3.6:4.1f} km/h"
                    cv2.rectangle(img, (int(b.x1), int(b.y1) - 24), (int(b.x1) + 118, int(b.y1)), NEON, -1)
                    cv2.putText(
                        img,
                        label,
                        (int(b.x1) + 6, int(b.y1) - 7),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.55,
                        (10, 12, 11),
                        2,
                    )
            if smp.keypoints is not None:
                kp = smp.keypoints
                for a, c in SKELETON:
                    if kp[a, 2] > 0.4 and kp[c, 2] > 0.4:
                        cv2.line(img, tuple(map(int, kp[a, :2])), tuple(map(int, kp[c, :2])), WHITE, 2)
            if smp.ball_frame is not None:
                cv2.circle(img, tuple(map(int, smp.ball_frame)), 9, NEON, 2)
        if index < len(analysis.obs) and len(trail) > 1:
            back = cv2.invertAffineTransform(analysis.obs[index].to_ref)
            pts = [tuple(int(v) for v in apply_affine(back, *p)) for p in trail[-25:]]
            for p, q in zip(pts[:-1], pts[1:], strict=False):
                cv2.line(img, p, q, NEON, 2)
        return img[:h2, :w2]

    proc.stdin.write(draw(first.index, first.image).tobytes())
    for f in frames:
        if f.image.shape[:2] != (h, w):
            continue
        proc.stdin.write(draw(f.index, f.image).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError("ffmpeg failed to write the overlay video")
    return out
