"""Your data: export everything (no secrets), and Report a problem."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup

from pep.api.app import app


def test_export_has_my_data_and_no_secrets():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        client.patch("/v1/me", json={"town": "Bantama", "settings": {"textSize": "l"}}, headers=headers(h))
        client.post(
            "/v1/feedback", json={"text": "The upload got stuck", "appVersion": "1.0"}, headers=headers(h)
        )
        e = client.get("/v1/me/export", headers=headers(h)).json()
        assert e["account"]["email"] == "kofi@example.com"
        assert (
            e["profiles"][0]["display_name"] == "Kofi Mensah"
            and e["profiles"][0]["settings"]["textSize"] == "l"
        )
        assert (
            e["player_details"][0]["town"] == "Bantama" and e["feedback"][0]["text"] == "The upload got stuck"
        )
        flat = str(e)
        assert "password_hash" not in flat and "sessions" not in e


def test_feedback_needs_words():
    with TestClient(app) as client:
        h = signup(client)
        assert client.post("/v1/feedback", json={"text": ""}, headers=headers(h)).status_code == 422


def test_store_pages_say_how_to_delete_and_how_children_are_kept_safe():
    with TestClient(app) as client:
        d = client.get("/delete-account")
        assert d.status_code == 200 and "Delete my account" in d.text and "support@tracka.app" in d.text
        c = client.get("/child-safety")
        assert c.status_code == 200 and "CSAE" in c.text and "292" in c.text
