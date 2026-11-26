"""The player card: private by default, a share link, what's shown, guardian rules for under-18s."""

from __future__ import annotations

import re

from fastapi.testclient import TestClient
from test_guardian import PHONE, _verified
from test_player_api import complete_profile, headers, signup, upload

from pep.api.app import app
from pep.players import guardian, sms
from pep.worker import Worker


def test_adult_shares_a_link_and_only_safe_fields_show(blank_video, fake_perceiver):
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h)
        client.patch(
            "/v1/me",
            json={"shirtName": "K. MENSAH", "shirtNumber": 8, "town": "Bantama", "style": "Playmaker"},
            headers=headers(h),
        )
        vid = upload(client, h, blank_video, "Sunday match")
        Worker(perceiver=fake_perceiver).run(drain=True)

        v = client.get("/v1/card", headers=headers(h)).json()
        assert v["canShare"] and not v["link"]["on"]  # private until you choose
        v = client.patch("/v1/card", json={"portfolio": [vid, "not-mine"]}, headers=headers(h)).json()
        assert v["portfolio"] == [vid]
        v = client.put("/v1/card/link", json={"on": True}, headers=headers(h)).json()
        token = v["link"]["url"].rsplit("/c/", 1)[1]

        c = client.get(f"/v1/c/{token}").json()
        assert c["shirtName"] == "K. MENSAH" and c["shirtNumber"] == 8 and c["style"] == "Playmaker"
        assert c["clips"][0]["id"] == vid
        flat = str(c)
        for private in ("Bantama", "kofi@example.com", "birth", "displayName", "overallScore"):
            assert private not in flat
        page = client.get(f"/c/{token}")
        assert page.status_code == 200 and "K. MENSAH" in page.text and "Bantama" not in page.text

        # Hide clips; then a new link stops the old one.
        assert (
            client.patch("/v1/card", json={"show": {"clips": False}}, headers=headers(h)).json()["card"][
                "clips"
            ]
            == []
        )
        v = client.put("/v1/card/link", json={"on": True, "newLink": True}, headers=headers(h)).json()
        assert client.get(f"/v1/c/{token}").status_code == 404
        client.put("/v1/card/link", json={"on": False}, headers=headers(h))
        assert client.get(f"/v1/c/{v['link']['url'].rsplit('/c/', 1)[1]}").status_code == 404


def test_under_18_needs_the_guardians_yes_and_loses_it_on_revoke(monkeypatch):
    monkeypatch.setattr(guardian, "RESEND_SECONDS", 0)
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, birth="2011-05-05")
        client.put("/v1/guardian", json={"phone": PHONE}, headers=headers(h))
        link = re.search(r"/g/([A-Z0-9]{4})", sms.last_text_to(PHONE)).group(1)
        g = _verified(client, link)
        client.post(f"/v1/g/{link}/decide", json={"kind": "account", "yes": True, "agree": True}, headers=g)

        assert client.put("/v1/card/link", json={"on": True}, headers=headers(h)).status_code == 403
        client.post("/v1/guardian/requests", json={"kind": "share_card"}, headers=headers(h))
        page = client.get(f"/v1/g/{link}", headers=g).json()
        assert page["card"]["under18"] and "Bantama" not in str(page["card"])  # the guardian sees the preview
        client.post(f"/v1/g/{link}/decide", json={"kind": "share_card", "yes": True}, headers=g)
        v = client.put("/v1/card/link", json={"on": True}, headers=headers(h)).json()
        token = v["link"]["url"].rsplit("/c/", 1)[1]
        assert client.get(f"/v1/c/{token}").json()["under18"]

        client.post(f"/v1/g/{link}/revoke", headers=g)
        assert client.get(f"/v1/c/{token}").status_code == 404  # stops at once
        assert "isn't shared" in client.get(f"/c/{token}").text


def test_card_page_escapes_what_players_type():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h)
        client.patch("/v1/me", json={"style": "<script>alert(1)</script>"}, headers=headers(h))
        url = client.put("/v1/card/link", json={"on": True}, headers=headers(h)).json()["link"]["url"]
        html = client.get("/c/" + url.rsplit("/c/", 1)[1]).text
        assert "<script>alert" not in html and "&lt;script&gt;" in html
