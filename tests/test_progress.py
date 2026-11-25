"""Home progress: timed tests over time, training streak, academy-ready profile."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup

from pep.api.app import app
from pep.players import progress


def _v(days_ago: int, value: float) -> dict:
    return {
        "status": "READY",
        "clip_type": "drill",
        "drill": "sprint_30m",
        "created_at": datetime.now(UTC) - timedelta(days=days_ago),
        "result": {"metrics": {"sprint_30m_s": value}},
    }


def test_sprint_progress_in_plain_words():
    videos = [_v(0, 4.6), _v(14, 4.75), _v(28, 4.9)]  # newest first, like store.list_videos
    (p,) = progress.test_progress(videos)
    assert p["first"] == 4.9 and p["latest"] == 4.6 and p["better"] and p["weeks"] == 4
    assert p["line"] == "Over a 30 m race, that puts you about 2 metres ahead of where you were."


def test_progress_route_and_readiness_start_empty():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        r = client.get("/v1/progress", headers=headers(h)).json()
        assert r["tests"] == [] and r["streak"]["weeks"] == 0
        assert r["readiness"]["done"] == 0 and r["readiness"]["next"] == "Baseline tests"
        client.patch(
            "/v1/me", json={"settings": {"homeCards": ["road", "today", "noticed"]}}, headers=headers(h)
        )
        assert client.get("/v1/me", headers=headers(h)).json()["settings"]["homeCards"] == [
            "road",
            "today",
            "noticed",
        ]
