"""
Scores the pipeline on a benchmark and writes a report.

    python training/evaluate.py benchmark/ --report report.md --max-speed-error 0.12

labels.json lists clips with whatever ground truth you have for each:
    {"clip": "a.mp4", "top_speed_ms": 7.0, "sprint_30m_s": 4.31, "scout_overall": 68, ...}

For each measured quantity we report MAPE (mean absolute percentage error)
and the worst clip. The command fails (exit code 1) if top-speed MAPE is over
the limit, which is what lets CI block a change that made Pep less accurate.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("benchmark", type=Path)
    ap.add_argument("--report", type=Path, default=Path("report.md"))
    ap.add_argument(
        "--max-speed-error", type=float, default=0.12, help="largest acceptable mean error (0.12 = 12%)"
    )
    args = ap.parse_args()

    from pep import MODEL_VERSION
    from pep.contracts import AnalysisRequest
    from pep.evaluation import agreement
    from pep.pipeline import CantReadClip, analyse
    from pep.vision.perception import YoloPerceiver

    labels = json.loads((args.benchmark / "labels.json").read_text())
    perceiver = YoloPerceiver()
    rows, errors, scout_pairs = [], {}, []
    for item in labels:
        clip = args.benchmark / item["clip"]
        req = AnalysisRequest(
            analysis_id=str(uuid.uuid4()),
            video_url=str(clip),
            positions=item.get("positions", []),
            age_years=item.get("age"),
            player_height_m=item.get("player_height_m"),
            clip_type=item.get("clip_type", "match"),
            drill=item.get("drill"),
        )
        start = time.perf_counter()
        try:
            out = analyse(clip, req, perceiver)
        except CantReadClip as exc:
            rows.append(f"| {item['clip']} | unreadable: {exc} | | |")
            continue
        seconds = time.perf_counter() - start
        m = out.result.metrics
        for key in ("top_speed_ms", "sprint_30m_s", "split_10m_s", "agility_5105_s", "juggles_best"):
            if key in item and m.get(key) is not None:
                errors.setdefault(key, []).append(abs(m[key] - item[key]) / item[key])
        if "scout_overall" in item and out.result.overall_score is not None:
            scout_pairs.append((out.result.overall_score, item["scout_overall"]))
        truth = item.get("top_speed_ms")
        rows.append(f"| {item['clip']} | {m.get('top_speed_ms')} | {truth} | {seconds:.1f} s |")

    lines = [
        f"# Pep evaluation: {MODEL_VERSION}",
        "",
        "| clip | top speed measured | truth | time |",
        "|---|---|---|---|",
        *rows,
        "",
    ]
    lines.append("| measurement | clips | mean error | worst |")
    lines.append("|---|---|---|---|")
    for key, errs in errors.items():
        lines.append(f"| {key} | {len(errs)} | {100 * sum(errs) / len(errs):.1f}% | {100 * max(errs):.1f}% |")
    if scout_pairs:
        lines += ["", f"Agreement with scouts: {agreement(scout_pairs)}"]
    args.report.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))

    speed = errors.get("top_speed_ms")
    if speed and sum(speed) / len(speed) > args.max_speed_error:
        print(f"FAIL: top-speed error above {args.max_speed_error:.0%}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
