"""Onboarding v2: player details (new table), casual and looking-around paths, kit-aware drills."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_player_api import headers, signup

from pep.api.app import app
from pep.players import training

FULL = {
    "displayName": "Kwame Asante",
    "birthDate": "2010-03-14",
    "sex": "male",
    "positions": ["CM", "CDM", "CAM"],
    "region": "Ashanti",
    "town": "Kumasi",
    "shirtName": "K. ASANTE",
    "shirtNumber": 8,
    "level": "club",
    "goal": "academy",
    "style": "Playmaker",
    "foot": "right",
    "weakFoot": 3,
    "heightM": 1.74,
    "guardianPhone": "+233 24 123 4567",
    "guardianRelation": "parent",
}


def test_details_are_saved_and_returned():
    with TestClient(app) as client:
        h = signup(client)
        me = client.patch("/v1/me", json=FULL, headers=headers(h)).json()
        p = me["profile"]
        assert p["shirtName"] == "K. ASANTE" and p["shirtNumber"] == 8 and p["town"] == "Kumasi"
        assert p["goal"] == "academy" and p["level"] == "club" and p["weakFoot"] == 3
        assert p["guardianRelation"] == "parent" and me["profileComplete"] and me["needsGuardian"]
        # Partial updates keep the rest.
        p = client.patch("/v1/me", json={"style": "Box to box"}, headers=headers(h)).json()["profile"]
        assert p["style"] == "Box to box" and p["shirtNumber"] == 8


def test_bad_values_are_rejected():
    with TestClient(app) as client:
        h = signup(client)
        for bad in ({"shirtNumber": 0}, {"weakFoot": 6}, {"goal": "fame"}, {"guardianPhone": "call me"}):
            assert client.patch("/v1/me", json=bad, headers=headers(h)).status_code == 422, bad


def test_casual_and_looking_around_finish_without_positions_but_cant_upload(blank_video):
    with TestClient(app) as client:
        h = signup(client)
        me = client.patch(
            "/v1/me",
            json={
                "displayName": "Kofi Mensah",
                "birthDate": "1998-05-05",
                "goal": "fun",
                "casual": {"often": "weekly"},
            },
            headers=headers(h),
        ).json()
        assert (
            me["profileComplete"]
            and me["profile"]["positions"] == []
            and me["profile"]["casual"] == {"often": "weekly"}
        )
        with blank_video.open("rb") as f:
            r = client.post("/v1/videos", files={"video": ("c.mp4", f, "video/mp4")}, headers=headers(h))
        assert r.status_code == 409  # Pep needs positions to score a clip


def test_kit_and_voice_settings():
    with TestClient(app) as client:
        h = signup(client)
        s = client.get("/v1/me", headers=headers(h)).json()["settings"]
        assert s["kit"] == ["ball"] and s["pepVoice"] == "coach"
        s = client.patch(
            "/v1/me", json={"settings": {"kit": ["ball", "wall"], "pepVoice": "street"}}, headers=headers(h)
        ).json()["settings"]
        assert s["kit"] == ["ball", "wall"] and s["pepVoice"] == "street"
        assert (
            client.patch("/v1/me", json={"settings": {"kit": ["jetpack"]}}, headers=headers(h)).status_code
            == 422
        )


def test_drills_respect_the_players_kit():
    focus = [{"id": "passing_forward", "name": "Passing forward"}]
    no_wall = training.session_plan("pep-2026-11-24", "normal", focus, kit=["ball"])
    with_wall = training.session_plan("pep-2026-11-24", "normal", focus, kit=["ball", "wall"])
    assert all("wall" not in s["needs"] for s in no_wall["steps"])
    assert any("wall" in s["needs"] for s in with_wall["steps"])
