"""Notifications: review ready, respect (one per clip per day), guardian answers, the week sweep, prefs."""

from __future__ import annotations

import re
from datetime import UTC, date, datetime

from fastapi.testclient import TestClient
from test_guardian import PHONE, _verified
from test_player_api import complete_profile, headers, signup, upload

from pep.api.app import app
from pep.players import guardian, notifications, sms
from pep.worker import Worker


def _bell(client, h):
    return client.get("/v1/notifications", headers=headers(h)).json()


def test_review_ready_and_respect_and_mark_read(blank_video, fake_perceiver):
    with TestClient(app) as client:
        a = signup(client, "a@example.com")
        complete_profile(client, a, consent=True)
        vid = upload(client, a, blank_video, "Sunday match")
        Worker(perceiver=fake_perceiver).run(drain=True)
        Worker(perceiver=fake_perceiver).run(drain=True)  # nothing to do: no duplicate
        items = [i for i in _bell(client, a)["items"] if i["kind"] == "reviews"]
        assert (
            len(items) == 1
            and items[0]["title"].startswith("Pep's read on Sunday match")
            and items[0]["link"]["id"] == vid
        )
        assert items[0]["group"] == "pep"

        post = client.post("/v1/posts", json={"videoId": vid}, headers=headers(a)).json()
        for i, e in enumerate(("b@example.com", "c@example.com")):
            h = signup(client, e)
            complete_profile(client, h, consent=True)
            client.patch("/v1/me", json={"shirtName": f"FAN {i}"}, headers=headers(h))
            client.put(f"/v1/posts/{post['id']}/respect", headers=headers(h))
        resp = [i for i in _bell(client, a)["items"] if i["kind"] == "respect"]
        assert len(resp) == 1 and resp[0]["title"] == "FAN 1 and 1 other gave you respect"

        assert _bell(client, a)["unread"] > 0
        client.post("/v1/notifications/read", json={}, headers=headers(a))
        assert _bell(client, a)["unread"] == 0


def test_turned_off_kinds_dont_arrive(blank_video, fake_perceiver):
    with TestClient(app) as client:
        a = signup(client)
        complete_profile(client, a, consent=True)
        client.patch("/v1/me", json={"settings": {"notifications": {"reviews": False}}}, headers=headers(a))
        client.patch("/v1/me", json={"settings": {"notifications": {"respect": False}}}, headers=headers(a))
        me = client.get("/v1/me", headers=headers(a)).json()
        assert me["settings"]["notifications"] == {"reviews": False, "respect": False}  # merged, not replaced
        upload(client, a, blank_video)
        Worker(perceiver=fake_perceiver).run(drain=True)
        assert not [i for i in _bell(client, a)["items"] if i["kind"] == "reviews"]


def test_guardian_answer_reaches_the_player(monkeypatch):
    monkeypatch.setattr(guardian, "RESEND_SECONDS", 0)
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, birth="2011-05-05")
        client.put("/v1/guardian", json={"phone": PHONE}, headers=headers(h))
        link = re.search(r"/g/([A-Z0-9]{4})", sms.last_text_to(PHONE)).group(1)
        g = _verified(client, link)
        client.post(f"/v1/g/{link}/decide", json={"kind": "account", "yes": True, "agree": True}, headers=g)
        titles = [i["title"] for i in _bell(client, h)["items"]]
        assert "Your guardian said yes to your account" in titles


def test_sweep_makes_session_and_event_reminders_once():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        monday = date(2026, 11, 23)
        client.post(
            "/v1/events",
            json={"kind": "match", "title": "Saturday 5-a-side", "weekdays": [1], "time": "16:00"},
            headers=headers(h),
        )
        uid = client.get("/v1/me", headers=headers(h)).json()["id"]
        notifications.sweep(uid, monday)
        notifications.sweep(uid, monday)
        titles = [i["title"] for i in _bell(client, h)["items"]]
        assert "Saturday 5-a-side is tomorrow at 16:00" in titles
        assert sum(t.startswith("New challenge") for t in titles) == 1


def test_quiet_hours_always_on_for_under_18s():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, birth="2011-05-05", consent=True)
        client.patch("/v1/me", json={"settings": {"quietHours": False}}, headers=headers(h))
        uid = client.get("/v1/me", headers=headers(h)).json()["id"]
        late = datetime(2026, 11, 25, 22, 30, tzinfo=UTC)  # 10:30 pm in Accra (GMT)
        assert notifications.quiet_now(uid, late)
        noon = datetime(2026, 11, 25, 12, 0, tzinfo=UTC)
        assert not notifications.quiet_now(uid, noon)
