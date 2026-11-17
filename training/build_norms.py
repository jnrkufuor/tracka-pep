"""
Rebuilds pep/data/norms.json from Tracka's own players.

    python training/build_norms.py --min-per-band 200 > new_norms.json

The starter norms are rough priors from published youth testing. Once enough
Ghanaian players have been analysed, their own distribution is the fair
reference: "faster than 70% of U17 players on Tracka" means something
concrete to a local scout.

ROBUST STATISTICS: the mean and standard deviation are dragged around by a
few broken measurements (a tracking glitch reading 45 km/h). So we use the
median for the centre and the MAD (median absolute deviation, x 1.4826 to be
comparable with a standard deviation) for the spread. One crazy value barely
moves either.

Only measurements from clips with MEDIUM or HIGH confidence are used, and a
player counts once per band (their best clip), so one prolific uploader
can't define "normal" for everyone.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict

import numpy as np

from pep import db
from pep.scoring.norms import age_band, norms


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-per-band", type=int, default=200)
    args = ap.parse_args()

    current = norms()
    values: dict[tuple[str, str], dict[str, float]] = defaultdict(dict)  # (metric, band) -> player -> best
    for job in db.list_jobs(limit=100000):
        res, req = job.get("result") or {}, job.get("request") or {}
        if res.get("status") != "READY" or res.get("confidence") == "LOW" or req.get("sex") == "female":
            continue
        band = age_band(req.get("ageYears"))
        player = req.get("playerLabel") or job["id"]
        for metric, spec in current["metrics"].items():
            v = (res.get("metrics") or {}).get(metric)
            if v is None:
                continue
            prev = values[(metric, band)].get(player)
            better = prev is None or (v - prev) * spec["direction"] > 0
            if better:
                values[(metric, band)][player] = v

    updated = json.loads(json.dumps(current))
    updated["version"] = "tracka-data"
    for (metric, band), per_player in values.items():
        xs = np.array(list(per_player.values()), dtype=float)
        if len(xs) < args.min_per_band:
            continue
        if current["metrics"][metric].get("log"):
            centre = float(np.expm1(np.median(np.log1p(xs))))
            spread = float(1.4826 * np.median(np.abs(np.log1p(xs) - np.log1p(centre))))
        else:
            centre = float(np.median(xs))
            spread = float(1.4826 * np.median(np.abs(xs - centre)))
        updated["metrics"][metric]["bands"][band] = [round(centre, 3), round(max(spread, 1e-3), 3)]
        print(
            f"{metric:<20} {band:<7} n={len(xs):<5} centre={centre:.2f} spread={spread:.2f}", file=sys.stderr
        )
    print(json.dumps(updated, indent=1))


if __name__ == "__main__":
    main()
