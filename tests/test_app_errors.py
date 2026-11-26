"""Crash reports: scrubbed, grouped, capped, deleted with the account; Sentry scrubbing."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_player_api import headers, signup

from pep.api.app import app
from pep.errors import _scrub, scrub_text
from pep.players import app_errors


def test_report_is_scrubbed_grouped_and_kept_with_the_player():
    with TestClient(app) as client:
        h = signup(client)
        body = {
            "message": "Bad state for kofi@example.com on +233 24 123 4567",
            "stack": "#0 Home.build (home_screen.dart:12)\n#1 x",
            "screen": "home",
            "appVersion": "0.1.0",
            "platform": "android",
        }
        for _ in range(3):
            assert client.post("/v1/app-errors", json=body, headers=headers(h)).json() == {"kept": True}
        rows = client.get("/lab/app-errors").json()
        assert len(rows) == 1 and rows[0]["count"] == 3 and rows[0]["players"] == 1
        assert "example.com" not in rows[0]["message"] and "4567" not in rows[0]["message"]
        assert "<email>" in rows[0]["message"] and "<phone>" in rows[0]["message"]
        one = client.get(f"/lab/app-errors/{rows[0]['fingerprint']}").json()
        assert "home_screen.dart" in one["stack"] and "user_id" not in one
        # In "Download my data", and gone with the account.
        assert len(client.get("/v1/me/export", headers=headers(h)).json()["app_errors"]) == 3
        assert client.delete("/v1/me", headers=headers(h)).status_code == 204
        assert client.get("/lab/app-errors").json() == []


def test_crashes_before_login_count_and_reports_are_capped(monkeypatch):
    monkeypatch.setattr(app_errors, "ANON_PER_DAY", 2)
    with TestClient(app) as client:
        r = [client.post("/v1/app-errors", json={"message": "boom"}).json()["kept"] for _ in range(3)]
        assert r == [True, True, False]
        # A bad token is treated as logged out, not an error.
        bad = {"Authorization": "Bearer nope"}
        assert client.post("/v1/app-errors", json={"message": "boom"}, headers=bad).json() == {"kept": False}


def test_sentry_reports_carry_no_personal_data():
    event = {
        "request": {
            "method": "POST",
            "url": "https://api/v1/me?token=abc",
            "headers": {"Authorization": "x"},
            "data": "pw",
        },
        "user": {"id": "u1", "email": "a@b.co"},
        "exception": {"values": [{"value": "no user ama@example.com"}]},
    }
    out = _scrub(event)
    assert out["request"] == {"method": "POST", "url": "https://api/v1/me"}
    assert "user" not in out and out["exception"]["values"][0]["value"] == "no user <email>"
    assert scrub_text("call 0241234567") == "call <phone>"
