"""Your profile photo: only real pictures, only for you, gone with your account."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup

from pep.api.app import app

JPG = b"\xff\xd8\xff\xe0" + b"\x00" * 200


def test_set_show_replace_and_clear_photo():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        assert client.get("/v1/me", headers=headers(h)).json()["profile"]["photoUrl"] is None
        r = client.put("/v1/me/photo", files={"photo": ("me.jpg", JPG, "image/jpeg")}, headers=headers(h))
        assert r.status_code == 200 and r.json()["photoUrl"]
        first = client.get("/v1/me", headers=headers(h)).json()["profile"]["photoUrl"]
        assert first
        client.put("/v1/me/photo", files={"photo": ("me2.jpg", JPG, "image/jpeg")}, headers=headers(h))
        assert client.get("/v1/me", headers=headers(h)).json()["profile"]["photoUrl"] != first
        assert client.delete("/v1/me/photo", headers=headers(h)).status_code == 204
        assert client.get("/v1/me", headers=headers(h)).json()["profile"]["photoUrl"] is None


def test_rejects_files_that_are_not_pictures():
    with TestClient(app) as client:
        h = signup(client)
        bad = client.put(
            "/v1/me/photo",
            files={"photo": ("x.jpg", b"not a picture at all", "image/jpeg")},
            headers=headers(h),
        )
        assert bad.status_code == 415
        wrong_type = client.put(
            "/v1/me/photo", files={"photo": ("x.gif", b"GIF89a", "image/gif")}, headers=headers(h)
        )
        assert wrong_type.status_code == 415
