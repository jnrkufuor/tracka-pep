"""
Trains the learned scorer: predict what a scout would rate a clip.

    python training/train_scorer.py                    # from the database (Lab ratings)
    python training/train_scorer.py --min-ratings 150  # refuse to train on too little data

THE IDEA (supervised learning)
  Inputs X  = Pep's measurements for a clip (pep/scoring/learned.py FEATURES)
  Target y  = the scout's overall rating of that clip
  Learn f so that f(X) ~ y on clips the model has never seen.

THE MODEL: gradient-boosted decision trees (scikit-learn's
HistGradientBoostingRegressor). Why this and not a neural network:
  * tabular data with a few hundred rows: trees beat neural nets here;
  * missing values (NaN) are handled natively;
  * MONOTONIC CONSTRAINTS: we can promise "a faster top speed never
    lowers the prediction", which keeps the model sensible and explainable
    when data is thin.

HONEST VALIDATION: GroupKFold by player.
  The same player can have several clips. If clip A of Kofi is in training
  and clip B of Kofi in validation, the model can "recognise Kofi" and look
  better than it is. That's DATA LEAKAGE. Grouping folds by player makes
  validation answer the real question: how good is Pep on players it has
  never seen?

We compare against the BASELINE (the hand-written rules). Only ship the
learned model if it beats the rules on validation MAE. The saved file
carries a model card: features, version, data size, validation scores.
"""

from __future__ import annotations

import argparse
import math
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from pep import db
from pep.config import settings
from pep.scoring.learned import FEATURES, feature_row

# +1: more is never worse. -1: more is never better. 0: no promise.
MONOTONIC = {
    "top_speed_ms": 1,
    "peak_accel_ms2": 1,
    "sprint_30m_s": -1,
    "split_10m_s": -1,
    "agility_5105_s": -1,
    "juggles_best": 1,
    "close_control_m": -1,
    "heavy_touches": -1,
}


def load_dataset() -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """X, y (scout score), groups (player), baseline (Pep's rule-based overall)."""
    xs, ys, groups, base = [], [], [], []
    for r in db.list_ratings():
        job = db.get_job(r["job_id"])
        if not job or not job.get("result") or job["result"].get("status") != "READY":
            continue
        req, res = job["request"], job["result"]
        m = res.get("metrics", {})
        ctx = {
            "age": req.get("ageYears"),
            "sex": req.get("sex"),
            "clip_type": req.get("clipType", "match"),
            "method": "homography" if req.get("calibration") else "body",
            "camera_reliability": m.get("camera_reliability"),
        }
        xs.append(feature_row(m, ctx))
        ys.append(r["overall"])
        groups.append(req.get("playerLabel") or job["id"])
        base.append(res.get("overallScore") or math.nan)
    return np.array(xs, float), np.array(ys, float), np.array(groups), np.array(base, float)


def main() -> int:
    from sklearn.ensemble import HistGradientBoostingRegressor
    from sklearn.model_selection import GroupKFold

    ap = argparse.ArgumentParser()
    ap.add_argument("--min-ratings", type=int, default=100)
    ap.add_argument("--out", type=Path, default=settings().learned_scorer_path)
    args = ap.parse_args()

    x, y, groups, baseline = load_dataset()
    print(f"{len(y)} rated clips from {len(set(groups))} players")
    if len(y) < args.min_ratings:
        print(f"Not enough ratings to train (need {args.min_ratings}). Keep rating clips in the Lab.")
        return 1

    def make():
        return HistGradientBoostingRegressor(
            max_iter=300,
            learning_rate=0.05,
            max_leaf_nodes=15,
            min_samples_leaf=10,
            l2_regularization=1.0,  # regularisation: prefer simpler trees, overfit less
            monotonic_cst=[MONOTONIC.get(f, 0) for f in FEATURES],
            random_state=0,
        )

    # Features nobody has measured yet (e.g. no drills recorded) are all-NaN columns, which the
    # tree binning can't handle. Make them constant: a constant column is never used for a split.
    x[:, np.isnan(x).all(axis=0)] = 0.0

    folds = GroupKFold(n_splits=min(5, len(set(groups))))
    pred = np.full_like(y, np.nan)
    for train, test in folds.split(x, y, groups):
        pred[test] = make().fit(x[train], y[train]).predict(x[test])

    mae = float(np.mean(np.abs(pred - y)))
    ok = np.isfinite(baseline)
    base_mae = float(np.mean(np.abs(baseline[ok] - y[ok]))) if ok.any() else math.inf
    print(f"validation MAE: learned {mae:.2f}  vs  rules {base_mae:.2f}")
    if mae >= base_mae:
        print("The learned model doesn't beat the rules yet. Not saving it.")
        return 1

    import joblib

    model = make().fit(x, y)  # final model on all the data
    version = f"scorer-{datetime.now(UTC):%Y%m%d}"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(
        {
            "model": model,
            "features": FEATURES,
            "version": version,
            "cv_mae": round(mae, 2),
            "rules_mae": round(base_mae, 2),
            "n": int(len(y)),
            "players": int(len(set(groups))),
        },
        args.out,
    )
    print(f"saved {version} to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
