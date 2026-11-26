"""Moderation: hidden clips reach staff, keep or take down, pause posting, safety reports, audit log."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_pitchside import _player
from test_player_api import headers, upload

from pep.api.app import app
from pep.worker import Worker


def test_staff_review_reported_clips_and_reports(blank_video, fake_perceiver):
    with TestClient(app) as client:
        a = _player(client, "a@example.com", "Ama Mensah", "A. MENSAH")
        vid = upload(client, a, blank_video)
        Worker(perceiver=fake_perceiver).run(drain=True)
        post = client.post("/v1/posts", json={"videoId": vid}, headers=headers(a)).json()
        for i in range(3):
            r = _player(client, f"r{i}@example.com")
            client.post(f"/v1/posts/{post['id']}/report", json={"reason": "unsafe"}, headers=headers(r))
        client.post(
            "/v1/feedback", json={"kind": "safety", "text": "Someone asked for my number"}, headers=headers(r)
        )

        q = client.get("/lab/moderation").json()
        (p,) = q["posts"]
        assert (
            p["hidden"]
            and p["reports"] == 3
            and p["reasons"] == {"unsafe": 3}
            and p["author"]["shirtName"] == "A. MENSAH"
        )
        assert q["reports"][0]["kind"] == "safety"

        # Keep: visible again, reports cleared.
        q = client.post(
            f"/lab/moderation/posts/{post['id']}", json={"action": "keep", "note": "a normal volley"}
        ).json()
        assert q["posts"] == []
        viewer = _player(client, "v@example.com")
        assert len(client.get("/v1/feed", headers=headers(viewer)).json()["posts"]) == 1

        # Pause posting: the author can't post and their posts leave the feed.
        uid = p["author"]["id"]
        client.put(f"/lab/moderation/holds/{uid}", json={"days": 7, "reason": "repeated reports"})
        assert client.get("/v1/feed", headers=headers(viewer)).json()["posts"] == []
        assert client.get("/v1/feed", headers=headers(a)).json()["canPost"] is False
        client.delete(f"/lab/moderation/holds/{uid}")

        # Take down, mark the report done; everything is in the log.
        client.post(f"/lab/moderation/posts/{post['id']}", json={"action": "take_down"})
        assert client.get("/v1/feed", headers=headers(viewer)).json()["posts"] == []
        q = client.post(f"/lab/moderation/reports/{q['reports'][0]['id']}/done").json()
        assert q["reports"] == []
        actions = [x["action"] for x in client.get("/lab/moderation/log").json()]
        assert actions == ["done", "take_down", "lift", "pause", "keep"]
