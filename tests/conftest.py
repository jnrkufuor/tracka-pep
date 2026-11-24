"""
Shared test setup (pytest loads conftest.py automatically).

Every test session gets its own throwaway SQLite database and file folder,
and the AI coach is switched off, so tests are fast, offline and repeatable.
CI runs the queue tests a second time against a real Postgres (see
.github/workflows/ci.yml) by setting PEP_DATABASE_URL.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

import numpy as np
import pytest

_tmp = Path(tempfile.mkdtemp(prefix="pep-test-"))
os.environ.setdefault("PEP_DATABASE_URL", f"sqlite:///{_tmp / 'test.db'}")
os.environ["PEP_STORAGE_DIR"] = str(_tmp / "files")
os.environ["PEP_COACH_PROVIDER"] = "none"
os.environ["PEP_ENV"] = "test"
os.environ["COACH_API_KEY"] = "test-key"
os.environ["COACH_WEBHOOK_SECRET"] = "test-secret"
os.environ["PEP_LEARNED_SCORER_PATH"] = str(_tmp / "no-scorer.joblib")


@pytest.fixture(autouse=True)
def clean_db():
    """Empty tables before each test so tests can't affect each other."""
    from pep import db
    from pep.players import details, store, training

    with db.engine().begin() as c:
        for table in (
            *training.TABLES,
            details.player_details,
            store.videos,
            store.sessions,
            store.profiles,
            store.users,
            db.jobs,
            db.ratings,
        ):
            c.execute(table.delete())
    yield


class FakePerceiver:
    """
    Stands in for YOLO: one 'player' box moving right at a known speed.
    Lets us test everything after perception without PyTorch or model files.
    """

    def __init__(self, px_per_s: float = 300.0, height_px: float = 200.0) -> None:
        self.px_per_s, self.h, self.calls = px_per_s, height_px, 0

    def reset(self) -> None:
        self.calls = 0

    def observe(self, image: np.ndarray):
        from pep.vision.types import Box, Person

        t = self.calls / 10.0  # the tests sample at 10 frames a second
        self.calls += 1
        x = 50 + self.px_per_s * t
        y2 = image.shape[0] * 0.85
        player = Person(1, Box(x, y2 - self.h, x + self.h * 0.4, y2, 0.9))
        ball = Box(x + 70, y2 - 12, x + 82, y2, 0.6)
        return [player], ball


@pytest.fixture
def fake_perceiver() -> FakePerceiver:
    return FakePerceiver()


@pytest.fixture
def blank_video(tmp_path: Path) -> Path:
    """A 6-second textured video (the fake perceiver supplies the 'player')."""
    import cv2

    path = tmp_path / "blank.mp4"
    out = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 30, (640, 360))
    rng = np.random.default_rng(1)
    base = rng.integers(0, 255, (360, 640, 3), dtype=np.uint8)  # texture so camera motion reads "still"
    for _ in range(180):
        out.write(base)
    out.release()
    return path
