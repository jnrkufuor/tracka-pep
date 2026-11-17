"""The learned scorer trains, beats a bad baseline, saves a model card, and is used for predictions."""

import sys
from pathlib import Path

import numpy as np

from pep import db

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "training"))


def _fake_rated_clips(n: int = 120) -> None:
    rng = np.random.default_rng(0)
    for i in range(n):
        speed = rng.uniform(5.5, 8.5)
        scout = 30 + (speed - 5.5) / 3.0 * 60 + rng.normal(0, 3)  # scouts love pace, in this toy world
        req = {"analysisId": f"a{i}", "videoUrl": "x", "ageYears": 16, "playerLabel": f"player{i % 40}"}
        job = db.enqueue(req, "lab")
        res = {
            "status": "READY",
            "overallScore": 60,
            "metrics": {"top_speed_ms": speed, "seconds_tracked": 10.0},
        }
        claimed = db.claim("w", 60)
        assert claimed and claimed["id"] == job["id"]
        db.finish(job["id"], "w", res, {}, None, callback=False)
        db.add_rating(job["id"], "scout", int(round(scout)), None, None, None)


def test_training_beats_the_rules_and_is_used(tmp_path, monkeypatch):
    import train_scorer

    from pep.config import settings
    from pep.scoring import learned

    _fake_rated_clips()
    out = tmp_path / "scorer.joblib"
    monkeypatch.setattr(sys, "argv", ["train_scorer", "--min-ratings", "50", "--out", str(out)])
    assert train_scorer.main() == 0
    assert out.exists()

    monkeypatch.setattr(settings(), "learned_scorer_path", out)
    learned._load.cache_clear()
    fast = learned.predict_overall({"top_speed_ms": 8.3}, {"age": 16})
    slow = learned.predict_overall({"top_speed_ms": 5.7}, {"age": 16})
    assert fast and slow and fast[0] > slow[0] + 20
    learned._load.cache_clear()
