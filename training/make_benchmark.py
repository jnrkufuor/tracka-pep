"""
Builds a small synthetic benchmark: clips with known top speeds.

    python training/make_benchmark.py benchmark/

A benchmark is a fixed set of clips with known answers (labels.json) that
you re-run after every model change. Synthetic clips are a start; the real
benchmark should be Tracka clips where the truth was measured another way
(timing gates, GPS vests, or a calibrated drill). See docs/handbook/12-cost-privacy-next.md.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "benchmark")
    out.mkdir(parents=True, exist_ok=True)
    labels = []
    for i, speed in enumerate([5.0, 6.5, 8.0]):
        clip = out / f"synthetic_{i}.mp4"
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "make_test_clip.py"),
                str(clip),
                "--top-speed",
                str(speed),
            ],
            check=True,
        )
        labels.append(
            {
                "clip": clip.name,
                "top_speed_ms": speed,
                "player_height_m": 1.75,
                "positions": ["RW"],
                "age": 17,
            }
        )
    (out / "labels.json").write_text(json.dumps(labels, indent=2))
    print(f"benchmark with {len(labels)} clips in {out}")


if __name__ == "__main__":
    main()
