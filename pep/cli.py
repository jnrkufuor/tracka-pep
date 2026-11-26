"""
The `pep` command.

    pep analyse clip.mp4 --positions ST --age 16 [--overlay out.mp4] [--json]
    pep worker                 # take jobs from the queue until stopped
    pep serve                  # run the API + Pep Lab on http://localhost:8000
    pep drain                  # process every queued job, then exit (used on Modal)

argparse is in the standard library; for a CLI this size it's all you need.
"""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path

from .errors import setup_error_tracking
from .log import setup_logging


def main(argv: list[str] | None = None) -> int:
    setup_logging()
    setup_error_tracking()  # the worker's crashes are tracked too (pep/errors.py)
    ap = argparse.ArgumentParser(prog="pep", description="Tracka's AI coach")
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("analyse", help="analyse one clip and print the result")
    a.add_argument("video", type=Path)
    a.add_argument("--positions", default="", help="comma-separated, e.g. ST,LW")
    a.add_argument("--age", type=int)
    a.add_argument("--sex", choices=["male", "female"])
    a.add_argument("--height", type=float, help="player height in metres")
    a.add_argument("--clip-type", default="match", choices=["match", "training", "drill", "highlight"])
    a.add_argument("--drill")
    a.add_argument("--overlay", type=Path, help="write a debug video here")
    a.add_argument("--json", action="store_true", help="print the full JSON result")

    sub.add_parser("worker", help="run the job worker")
    sub.add_parser("drain", help="process queued jobs, then exit")
    s = sub.add_parser("serve", help="run the API and Pep Lab")
    s.add_argument("--port", type=int, default=8000)
    s.add_argument("--host", default="127.0.0.1")

    args = ap.parse_args(argv)

    if args.cmd == "analyse":
        from .contracts import AnalysisRequest
        from .pipeline import CantReadClip, analyse
        from .vision.perception import YoloPerceiver

        req = AnalysisRequest(
            analysis_id=str(uuid.uuid4()),
            video_url=str(args.video),
            positions=[p for p in args.positions.split(",") if p],
            age_years=args.age,
            sex=args.sex,
            player_height_m=args.height,
            clip_type=args.clip_type,
            drill=args.drill,
        )
        try:
            out = analyse(args.video, req, YoloPerceiver())
        except CantReadClip as e:
            print(f"Can't read clip: {e}", file=sys.stderr)
            return 2
        if args.overlay:
            from .overlay import render_overlay

            render_overlay(args.video, out, args.overlay)
        if args.json:
            print(json.dumps(out.result.to_wire(), indent=2))
        else:
            _print_human(out)
        return 0

    if args.cmd in ("worker", "drain"):
        from .worker import Worker

        Worker().run(drain=args.cmd == "drain")
        return 0

    if args.cmd == "serve":
        import uvicorn

        uvicorn.run("pep.api.app:app", host=args.host, port=args.port)
        return 0
    return 1


def _print_human(out) -> None:
    r = out.result
    print(f"\nOverall {r.overall_score}  ({r.confidence} confidence, {r.model_version})")
    m = r.metrics
    if m.get("top_speed_ms"):
        print(
            f"Top speed {m['top_speed_ms'] * 3.6:.1f} km/h   distance {m.get('distance_m')} m   tracked {m.get('seconds_tracked')} s"
        )
    for s in r.skills:
        print(f"  {s.name:<16} {s.score:>3}  {s.source:<11} {s.confidence:<6} {s.explanation}")
    for f in r.role_fit[:4]:
        print(f"  role {f.label:<26} {f.score:>3}  coverage {f.coverage:.0%}")
    for mo in r.moments:
        print(f"  {mo.at_seconds:>5.1f}s {mo.kind:<8} {mo.text}")
    print(f"\n{r.summary}\n\nstage seconds: {out.timings}")


if __name__ == "__main__":
    raise SystemExit(main())
