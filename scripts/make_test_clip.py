"""
Makes a test clip where we KNOW the truth: a player runs at a known speed
while the camera pans after them.

Why: you can't test a speed measurement against "looks about right". This
clip has a ground truth (top speed exactly 7.0 m/s = 25.2 km/h, distance
known), so `pep analyse` on it tells you how far off the pipeline is. The
slow test (tests/test_pipeline_slow.py) runs exactly this.

The player is cut out of a photo with a segmentation model (they don't move
their legs, so it's a test of measurement, not of pose). The pitch is
procedurally drawn grass with lines, so the camera-motion code has texture
to follow, like a real pitch.

    python scripts/make_test_clip.py out.mp4 [--image photo.jpg]
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

import numpy as np

FPS = 30
W, H = 1280, 720
PERSON_PX = 300  # the player's height on screen
PLAYER_M = 1.75
PX_PER_M = PERSON_PX / PLAYER_M
TOP_SPEED = 7.0


def speed_at(t: float) -> float:
    """Ground truth speed profile in m/s: stand, accelerate, cruise, slow down."""
    if t < 1.0:
        return 0.0
    if t < 3.0:
        return TOP_SPEED * (t - 1.0) / 2.0
    if t < 6.0:
        return TOP_SPEED
    if t < 8.0:
        return TOP_SPEED - (TOP_SPEED - 2.0) * (t - 6.0) / 2.0
    return 2.0


def cut_out_player(image_path: str) -> tuple[np.ndarray, np.ndarray]:
    """RGBA cut-out of the biggest person in the photo, using YOLO26 segmentation."""
    import cv2
    from ultralytics import YOLO

    img = cv2.imread(image_path)
    res = YOLO("yolo26n-seg.pt")(img, classes=[0], verbose=False)[0]
    i = int(np.argmax((res.boxes.xyxy[:, 3] - res.boxes.xyxy[:, 1]).cpu().numpy()))
    x1, y1, x2, y2 = map(int, res.boxes.xyxy[i].cpu().numpy())
    mask = res.masks.data[i].cpu().numpy()
    mask = cv2.resize(mask, (img.shape[1], img.shape[0])) > 0.5
    crop, m = img[y1:y2, x1:x2], mask[y1:y2, x1:x2].astype(np.uint8) * 255
    scale = PERSON_PX / crop.shape[0]
    size = (max(1, round(crop.shape[1] * scale)), PERSON_PX)
    return cv2.resize(crop, size), cv2.resize(m, size)


def pitch(width_px: int) -> np.ndarray:
    """Grass with mowing stripes, noise and white lines: something for optical flow to hold on to."""
    import cv2

    rng = np.random.default_rng(7)
    g = np.zeros((H, width_px, 3), np.uint8)
    g[:] = (40, 120, 50)
    stripe = int(5 * PX_PER_M)
    for x in range(0, width_px, stripe * 2):
        g[:, x : x + stripe] = (45, 135, 58)
    noise = rng.normal(0, 14, (H, width_px, 1)).astype(np.int16)
    g = np.clip(g.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    for x in range(0, width_px, int(10 * PX_PER_M)):
        cv2.line(g, (x, 240), (x + 60, H), (235, 235, 235), 4)
    cv2.line(g, (0, 260), (width_px, 260), (235, 235, 235), 4)
    for _ in range(400):  # tufts and marks
        x, y = int(rng.integers(0, width_px)), int(rng.integers(270, H))
        cv2.circle(g, (x, y), int(rng.integers(2, 5)), (30, 95, 40), -1)
    return g


def main() -> None:
    global TOP_SPEED  # speed_at() reads it; --top-speed overrides it
    import cv2

    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--image", default=None, help="photo with a person in it (default: Ultralytics' bus.jpg)")
    ap.add_argument("--seconds", type=float, default=9.0)
    ap.add_argument("--top-speed", type=float, default=TOP_SPEED, help="m/s (default 7.0)")
    args = ap.parse_args()
    TOP_SPEED = args.top_speed

    if args.image is None:
        import ultralytics

        args.image = str(Path(ultralytics.__file__).parent / "assets" / "bus.jpg")
    person, alpha = cut_out_player(args.image)
    world = pitch(int(PX_PER_M * 70) + W)

    n = int(args.seconds * FPS)
    x_m, cam = 3.0, 0.0
    feet_y = 560
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
            f"{W}x{H}",
            "-r",
            str(FPS),
            "-i",
            "-",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            args.out,
        ],
        stdin=subprocess.PIPE,
    )
    assert proc.stdin is not None
    distance = 0.0
    for i in range(n):
        t = i / FPS
        v = speed_at(t)
        x_m += v / FPS
        distance += v / FPS
        px = x_m * PX_PER_M
        cam += ((px - W * 0.45) - cam) * 0.08  # the "camera operator" follows smoothly, with lag
        c = int(max(0, cam))
        frame = world[:, c : c + W].copy()
        sx = int(px - c - person.shape[1] / 2)
        sy = feet_y - person.shape[0]
        _paste(frame, person, alpha, sx, sy)
        bx = int(px - c + 0.45 * PX_PER_M)  # ball 45 cm in front of the feet
        cv2.circle(frame, (bx, feet_y - 10), 11, (245, 245, 245), -1)
        cv2.circle(frame, (bx, feet_y - 10), 11, (40, 40, 40), 1)
        proc.stdin.write(frame.tobytes())
    proc.stdin.close()
    proc.wait()
    print(
        f"wrote {args.out}: top speed {TOP_SPEED} m/s ({TOP_SPEED * 3.6:.1f} km/h), distance {distance:.1f} m, "
        f"player height {PLAYER_M} m"
    )


def _paste(frame, img, alpha, x, y) -> None:
    h, w = img.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(frame.shape[1], x + w), min(frame.shape[0], y + h)
    if x1 <= x0 or y1 <= y0:
        return
    a = alpha[y0 - y : y1 - y, x0 - x : x1 - x, None] / 255.0
    region = frame[y0:y1, x0:x1]
    frame[y0:y1, x0:x1] = (a * img[y0 - y : y1 - y, x0 - x : x1 - x] + (1 - a) * region).astype(np.uint8)


if __name__ == "__main__":
    main()
