"""Pitchside: posting, the feed (no Pep on others' clips), follow/block/report, search, challenges, pitches."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup, upload

from pep.api.app import app
from pep.players import pitchside
from pep.worker import Worker


def _player(client, email, name="Kofi Mensah", shirt=None, birth="2008-03-01"):
    h = signup(client, email)
    complete_profile(client, h, birth=birth, consent=True)
    client.patch(
        "/v1/me",
        json={"displayName": name, "town": "Bantama", **({"shirtName": shirt} if shirt else {})},
        headers=headers(h),
    )
    return h


def test_post_feed_respect_follow_block_report(blank_video, fake_perceiver):
    with TestClient(app) as client:
        a = _player(client, "a@example.com", "Ama Mensah", "A. MENSAH")
        b = _player(client, "b@example.com", "Yaw Darko")
        vid = upload(client, a, blank_video, "Weak-foot volley")
        Worker(perceiver=fake_perceiver).run(drain=True)

        post = client.post(
            "/v1/posts", json={"videoId": vid, "caption": "Took me weeks."}, headers=headers(a)
        ).json()
        assert client.post("/v1/posts", json={"videoId": vid}, headers=headers(a)).status_code == 409
        feed = client.get("/v1/feed", headers=headers(b)).json()["posts"]
        assert [p["id"] for p in feed] == [post["id"]]
        item = feed[0]
        assert item["author"]["shirtName"] == "A. MENSAH"
        flat = str(item).lower()
        for leak in ("ama mensah", "bantama", "review", "tips", "analysis", "score", "summary"):
            assert leak not in flat, leak  # no full name, no town, and never Pep on others' clips

        client.put(f"/v1/posts/{post['id']}/respect", headers=headers(b))
        client.put(f"/v1/posts/{post['id']}/save", headers=headers(b))
        item = client.get("/v1/feed", headers=headers(b)).json()["posts"][0]
        assert item["respect"] == 1 and item["respected"] and item["saved"]

        uid_a = item["author"]["id"]
        assert client.get("/v1/feed?tab=following", headers=headers(b)).json()["posts"] == []
        client.put(f"/v1/players/{uid_a}/follow", headers=headers(b))
        assert len(client.get("/v1/feed?tab=following", headers=headers(b)).json()["posts"]) == 1
        prof = client.get(f"/v1/players/{uid_a}", headers=headers(b)).json()
        assert (
            prof["clips"] == 1
            and prof["respect"] == 1
            and prof["followers"] == 1
            and prof["player"]["following"]
        )

        client.put(f"/v1/players/{uid_a}/block", headers=headers(b))
        assert client.get("/v1/feed", headers=headers(b)).json()["posts"] == []
        assert client.get(f"/v1/players/{uid_a}", headers=headers(b)).status_code == 404
        client.delete(f"/v1/players/{uid_a}/block", headers=headers(b))

        # Three different players report it: hidden for everyone until reviewed.
        for i in range(3):
            r = _player(client, f"r{i}@example.com")
            client.post(f"/v1/posts/{post['id']}/report", json={"reason": "unsafe"}, headers=headers(r))
        assert client.get("/v1/feed", headers=headers(b)).json()["posts"] == []


def test_under_18_posting_and_search_need_the_guardian(blank_video, fake_perceiver):
    with TestClient(app) as client:
        kid = _player(client, "kid@example.com", birth="2011-05-05")
        vid = upload(client, kid, blank_video)
        Worker(perceiver=fake_perceiver).run(drain=True)
        assert client.post("/v1/posts", json={"videoId": vid}, headers=headers(kid)).status_code == 403
        assert client.get("/v1/feed", headers=headers(kid)).json()["canPost"] is False

        client.patch("/v1/me", json={"settings": {"findable": True}}, headers=headers(kid))
        adult = _player(client, "adult@example.com", "Kojo Boateng", "K. BOATENG")
        client.patch("/v1/me", json={"settings": {"findable": True}}, headers=headers(adult))
        other = _player(client, "other@example.com")
        res = client.get("/v1/players?q=k.", headers=headers(other)).json()
        assert [p["shirtName"] for p in res["players"]] == [
            "K. BOATENG"
        ]  # the kid's guardian hasn't said yes


def test_challenge_attempts_and_this_weeks_card(blank_video):
    with TestClient(app) as client:
        h = _player(client, "c@example.com")
        cur = pitchside.this_week()
        with blank_video.open("rb") as f:
            r = client.post(
                "/v1/videos",
                files={"video": ("c.mp4", f, "video/mp4")},
                data={"meta": f'{{"title": "Go", "challenge": "{cur["id"]}"}}'},
                headers=headers(h),
            )
        assert r.status_code == 202
        v = client.get(f"/v1/videos/{r.json()['id']}", headers=headers(h)).json()
        assert v["clipType"] == "drill" and v["drill"] == cur["drill"]
        ch = client.get("/v1/challenges", headers=headers(h)).json()
        assert (
            ch["thisWeek"]["id"] == cur["id"]
            and ch["thisWeek"]["tries"] == 1
            and ch["thisWeek"]["playersIn"] == 1
        )
        assert {c["id"] for c in ch["fun"]} == {"crossbar", "keepy_friend", "trick_bin"}
        bad = client.post(
            "/v1/videos",
            files={"video": ("c.mp4", b"x", "video/mp4")},
            data={"meta": '{"challenge": "nope"}'},
            headers=headers(h),
        )
        assert bad.status_code == 422


def test_pitches_show_once_two_other_players_confirm():
    with TestClient(app) as client:
        a, b, c = (_player(client, f"{x}@example.com") for x in "abc")
        v = client.post(
            "/v1/pitches",
            json={
                "name": "Bantama community field",
                "surface": "grass",
                "size": "full size",
                "town": "Kumasi",
            },
            headers=headers(a),
        ).json()
        pid = v["pitches"][0]["id"]
        assert v["pitches"][0]["needs"] == 2
        assert client.put(f"/v1/pitches/{pid}/confirm", headers=headers(a)).status_code == 409
        client.put(f"/v1/pitches/{pid}/confirm", headers=headers(b))
        v = client.put(f"/v1/pitches/{pid}/confirm", headers=headers(c)).json()
        assert v["pitches"][0]["confirmed"] and v["pitches"][0]["confirmedByMe"]
