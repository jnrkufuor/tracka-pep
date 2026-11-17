"""
The real models on a clip with a known answer. Slow (downloads YOLO weights,
runs PyTorch), so it's skipped by default:  pytest -m slow
"""

import subprocess
import sys
import uuid
from pathlib import Path

import pytest

pytestmark = pytest.mark.slow
ROOT = Path(__file__).resolve().parent.parent


def test_top_speed_on_synthetic_clip(tmp_path):
    from pep.contracts import AnalysisRequest
    from pep.pipeline import analyse
    from pep.vision.perception import YoloPerceiver

    clip = tmp_path / "run.mp4"
    subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "make_test_clip.py"), str(clip)], check=True, cwd=tmp_path
    )
    req = AnalysisRequest(
        analysis_id=str(uuid.uuid4()),
        video_url=str(clip),
        positions=["RW"],
        age_years=17,
        player_height_m=1.75,
    )
    out = analyse(clip, req, YoloPerceiver())
    top = out.result.metrics["top_speed_ms"]
    # Ground truth is 7.0 m/s. The body-ruler method is expected within ~10% on a clean clip.
    assert top == pytest.approx(7.0, rel=0.10), top
    assert out.result.status == "READY"
