"""Training: the computed week, Pep sessions around the player's football, tests due, health, privacy."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup

from pep.api.app import app
from pep.players import training, training_routes

MON = date(2026, 11, 23)  # a Monday


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch):
    monkeypatch.setattr(training_routes, "_today", lambda: MON)


def ev(kind: str, weekdays: list[int]) -> dict:
    return {"kind": kind, "weekdays": weekdays, "on_date": None}


def test_sessions_avoid_match_day_and_the_day_before():
    days = [MON + timedelta(days=i) for i in range(7)]
    picked = training.place_sessions(days, [ev("match", [5])], 3)  # Saturday match
    assert len(picked) == 3
    assert all(d.weekday() not in (4, 5) for d in picked)  # not Friday or Saturday


def test_sessions_prefer_free_days_and_avoid_back_to_back():
    days = [MON + timedelta(days=i) for i in range(7)]
    picked = training.place_sessions(days, [ev("team", [1, 3])], 3)  # team on Tue, Thu
    assert [d.weekday() for d in picked] == [0, 2, 4]


def test_tests_due_when_never_done_or_old():
    old = {
        "status": "READY",
        "clip_type": "drill",
        "drill": "sprint_30m",
        "created_at": datetime(2026, 11, 1, tzinfo=UTC),
    }
    fresh = {
        "status": "READY",
        "clip_type": "drill",
        "drill": "juggling",
        "created_at": datetime(2026, 11, 20, tzinfo=UTC),
    }
    due = training.tests_due([fresh, old], MON)
    assert "juggling" not in due and "sprint_30m" in due


def test_focus_prefers_weak_key_areas():
    areas = {
        "groups": [
            {
                "name": "x",
                "items": [
                    {
                        "id": "scanning",
                        "name": "Looking around",
                        "key": True,
                        "state": "measured",
                        "band": "below",
                    },
                    {
                        "id": "top_speed",
                        "name": "Top speed",
                        "key": False,
                        "state": "measured",
                        "band": "below",
                    },
                    {
                        "id": "passing_forward",
                        "name": "Passing forward",
                        "key": True,
                        "state": "measured",
                        "band": "strong",
                    },
                ],
            }
        ]
    }
    assert [f["id"] for f in training.focus_areas(areas)] == ["scanning", "passing_forward"]


def test_week_events_sessions_move_skip_done_and_health():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        r = client.post(
            "/v1/events", json={"kind": "match", "weekdays": [5], "time": "15:00"}, headers=headers(h)
        )
        assert r.status_code == 201 and r.json()["title"] == "Match"
        wk = client.get("/v1/week", headers=headers(h)).json()
        assert wk["start"] == MON.isoformat() and len(wk["days"]) == 7 and wk["days"][0]["isToday"]
        sessions = [i for d in wk["days"] for i in d["items"] if i["kind"] == "pep"]
        assert len(sessions) == 3 and wk["days"][5]["matchDay"]
        # A test is due (none done yet): it sits on the first session from today.
        assert any(i["kind"] == "test" for d in wk["days"] for i in d["items"])

        key = sessions[0]["id"]
        plan = client.get(f"/v1/sessions/{key}", headers=headers(h)).json()
        assert plan["steps"][0]["id"] == "warmup" and plan["steps"][-1]["id"] == "cooldown" and plan["safety"]

        # Move the second session to Friday (the day before the match): it becomes light.
        second = sessions[1]["id"]
        wk = client.post(f"/v1/sessions/{second}/move", json={"to": "2026-11-27"}, headers=headers(h)).json()
        friday = next(i for i in wk["days"][4]["items"] if i["id"] == second)
        assert friday["mode"] == "light" and friday["moved"]
        assert (
            client.post(
                f"/v1/sessions/{second}/move", json={"to": "2026-11-01"}, headers=headers(h)
            ).status_code
            == 422
        )

        # Skip the third, then log the first as done.
        third = sessions[2]["id"]
        wk = client.post(f"/v1/sessions/{third}/skip", headers=headers(h)).json()
        assert next(i for d in wk["days"] for i in d["items"] if i["id"] == third)["status"] == "skipped"
        done = client.post(
            f"/v1/sessions/{key}/done", json={"effort": "hard", "hurt": True}, headers=headers(h)
        ).json()
        assert done["logged"] and done["health"] == "sore"
        wk = client.get("/v1/week", headers=headers(h)).json()
        assert next(i for d in wk["days"] for i in d["items"] if i["id"] == key)["status"] == "done"

        # Injured: every session from today becomes a rest day with guidance.
        hh = client.put(
            "/v1/health", json={"status": "injured", "area": "left ankle"}, headers=headers(h)
        ).json()
        assert hh["status"] == "injured" and "doctor or physio" in hh["advice"]
        wk = client.get("/v1/week", headers=headers(h)).json()
        rest = [
            i
            for d in wk["days"]
            for i in d["items"]
            if i["id"].startswith("pep-") and i["status"] == "planned"
        ]
        assert rest and all(i["kind"] == "rest" for i in rest)
        assert client.get(f"/v1/sessions/{rest[0]['id']}", headers=headers(h)).json()["steps"] == []


def test_events_validation_and_privacy():
    with TestClient(app) as client:
        a, b = signup(client, "a@example.com"), signup(client, "b@example.com")
        complete_profile(client, a, consent=True)
        assert (
            client.post("/v1/events", json={"kind": "team"}, headers=headers(a)).status_code == 422
        )  # no day
        assert (
            client.post("/v1/events", json={"kind": "team", "weekdays": [9]}, headers=headers(a)).status_code
            == 422
        )
        e = client.post(
            "/v1/events", json={"kind": "team", "weekdays": [1, 3], "time": "16:00"}, headers=headers(a)
        ).json()
        # Another player can't see, change or delete it.
        assert client.get("/v1/events", headers=headers(b)).json() == []
        assert (
            client.patch(f"/v1/events/{e['id']}", json={"time": "17:00"}, headers=headers(b)).status_code
            == 404
        )
        assert client.delete(f"/v1/events/{e['id']}", headers=headers(b)).status_code == 404
        assert (
            client.patch(f"/v1/events/{e['id']}", json={"time": "17:00"}, headers=headers(a)).json()["time"]
            == "17:00"
        )
        assert client.delete(f"/v1/events/{e['id']}", headers=headers(a)).status_code == 204
        assert client.get("/v1/sessions/not-a-key", headers=headers(a)).status_code == 404


def test_deleting_the_account_removes_training_data():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        client.post("/v1/events", json={"kind": "team", "weekdays": [1]}, headers=headers(h))
        client.put("/v1/health", json={"status": "sore"}, headers=headers(h))
        assert client.delete("/v1/me", headers=headers(h)).status_code in (200, 204)
        from sqlalchemy import select

        from pep import db

        with db.engine().connect() as c:
            assert c.execute(select(training.events)).first() is None
            assert c.execute(select(training.health)).first() is None


def test_focus_and_tests_view():
    from fastapi.testclient import TestClient
    from test_player_api import complete_profile, headers, signup

    from pep.api.app import app

    with TestClient(app) as client:
        h = signup(client, "focus@example.com")
        complete_profile(client, h, consent=True)
        f = client.get("/v1/focus", headers=headers(h)).json()
        assert len(f["focus"]) >= 1 and all("band" in x for x in f["focus"])
        assert f["nextTest"]["drill"] in ("sprint_30m", "agility_5105", "juggling", "wall_passes")
        assert f["bests"] == [] and "score" not in str(f).lower()
