"""Guardian approval: texts (placeholder outbox), the guardian page with a code, YES/NO replies."""

from __future__ import annotations

import re

from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup

from pep.api.app import app
from pep.config import settings
from pep.players import guardian, sms

PHONE = "024 123 4567"


def _minor(client):
    h = signup(client)
    complete_profile(client, h, birth="2011-05-05")  # 15
    return h


def _code_from_text() -> tuple[str, str]:
    text = sms.last_text_to(PHONE)
    link = re.search(r"/g/([A-Z0-9]{4})", text).group(1)
    return link, text


def _verified(client, link: str) -> dict:
    assert client.post(f"/v1/g/{link}/code").status_code == 202
    otp = re.search(r"code is (\d{4})", sms.last_text_to(PHONE)).group(1)
    token = client.post(f"/v1/g/{link}/verify", json={"code": otp}).json()["session"]
    return {"X-Guardian-Session": token}


def _no_wait(monkeypatch):
    monkeypatch.setattr(guardian, "RESEND_SECONDS", 0)


def test_full_flow_on_the_guardian_page(monkeypatch):
    _no_wait(monkeypatch)
    with TestClient(app) as client:
        h = _minor(client)
        v = client.put(
            "/v1/guardian", json={"phone": PHONE, "relation": "parent", "name": "Ama"}, headers=headers(h)
        ).json()
        assert v["status"] == "pending" and v["phone"] == "+233 24 ••• 4567" and not v["textsLive"]
        link, text = _code_from_text()
        assert text.startswith("Hello Ama.") and f"YES {link}" in text

        # Without a code, the page shows only the first name.
        assert client.get(f"/v1/g/{link}").json() == {
            "childFirstName": "Kofi",
            "needsCode": True,
            "phone": v["phone"],
        }
        assert client.post(f"/v1/g/{link}/verify", json={"code": "0000"}).status_code == 401

        g = _verified(client, link)
        page = client.get(f"/v1/g/{link}", headers=g).json()
        assert page["child"]["fullName"] and page["status"] == "pending"
        bad = client.post(f"/v1/g/{link}/decide", json={"kind": "account", "yes": True}, headers=g)
        assert bad.status_code == 422  # must agree to the terms
        page = client.post(
            f"/v1/g/{link}/decide",
            json={"kind": "account", "yes": True, "agree": True, "relation": "parent"},
            headers=g,
        ).json()
        assert page["status"] == "approved"
        me = client.get("/v1/me", headers=headers(h)).json()
        assert not me["needsGuardian"] and me["guardianStatus"] == "approved"

        # Something new needs a new yes.
        v = client.post("/v1/guardian/requests", json={"kind": "share_card"}, headers=headers(h)).json()
        assert not v["permissions"]["shareCard"] and "share" in sms.last_text_to(PHONE)
        client.post(f"/v1/g/{link}/decide", json={"kind": "share_card", "yes": True}, headers=g)
        assert client.get("/v1/guardian", headers=headers(h)).json()["permissions"]["shareCard"]

        # Take it all back: private again.
        client.post(f"/v1/g/{link}/revoke", headers=g)
        me = client.get("/v1/me", headers=headers(h)).json()
        assert me["needsGuardian"] and me["guardianStatus"] == "revoked"


def test_reply_by_text_from_the_guardians_number_only(monkeypatch):
    monkeypatch.setattr(settings(), "sms_webhook_secret", "s3cret")
    with TestClient(app) as client:
        h = _minor(client)
        client.put("/v1/guardian", json={"phone": PHONE}, headers=headers(h))
        link, _ = _code_from_text()
        hook = {"X-SMS-Secret": "s3cret"}
        assert (
            client.post(
                "/v1/sms/inbound", json={"from": "+233200000000", "text": f"YES {link}"}, headers=hook
            ).json()["ok"]
            is False
        )
        assert (
            client.post(
                "/v1/sms/inbound", json={"from": PHONE, "text": f"yes {link.lower()}"}, headers={}
            ).status_code
            == 404
        )
        r = client.post(
            "/v1/sms/inbound", json={"from": "+233 24 123 4567", "text": f"yes {link.lower()}."}, headers=hook
        ).json()
        assert r == {"ok": True, "kind": "account", "yes": True}
        assert "approved" in sms.last_text_to(PHONE)
        assert not client.get("/v1/me", headers=headers(h)).json()["needsGuardian"]


def test_codes_run_out_and_resends_wait():
    with TestClient(app) as client:
        h = _minor(client)
        client.put("/v1/guardian", json={"phone": PHONE}, headers=headers(h))
        assert client.post("/v1/guardian/resend", headers=headers(h)).status_code == 429  # just sent
        link, _ = _code_from_text()
        assert client.post(f"/v1/g/{link}/code").status_code == 429
        uid = guardian.by_code(link)["user_id"]
        guardian.send_code(uid)
        otp = re.search(r"code is (\d{4})", sms.last_text_to(PHONE)).group(1)
        wrong = "0000" if otp != "0000" else "1111"
        for _ in range(guardian.CODE_TRIES):
            assert client.post(f"/v1/g/{link}/verify", json={"code": wrong}).status_code == 401
        assert client.post(f"/v1/g/{link}/verify", json={"code": otp}).status_code == 401  # locked


def test_adults_dont_need_a_guardian_and_interim_tick_still_works():
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h)  # adult
        assert client.put("/v1/guardian", json={"phone": PHONE}, headers=headers(h)).status_code == 409
        h2 = signup(client, "young@example.com")
        me = complete_profile(client, h2, birth="2011-05-05", consent=True)
        assert not me["needsGuardian"]  # texts are a placeholder, so the tick counts


def test_parse_reply_and_phone_numbers():
    assert guardian.parse_reply("Yes 4f7k") == (True, "4F7K")
    assert guardian.parse_reply("NO, 4F7K") == (False, "4F7K")
    assert guardian.parse_reply("maybe") is None
    assert sms.normalise("024 123 4567") == sms.normalise("+233241234567") == "+233241234567"


def test_guardian_web_page_is_served():
    with TestClient(app) as client:
        r = client.get("/g/ABCD")
        assert r.status_code == 200 and "textContent" in r.text and r.headers["cache-control"] == "no-store"


def test_deleting_an_under_18_account_goes_through_the_guardian(monkeypatch):
    monkeypatch.setattr(guardian, "RESEND_SECONDS", 0)
    with TestClient(app) as client:
        h = _minor(client)
        client.put("/v1/guardian", json={"phone": PHONE, "name": "Ama"}, headers=headers(h))
        link, _ = _code_from_text()
        g = _verified(client, link)
        client.post(f"/v1/g/{link}/decide", json={"kind": "account", "yes": True, "agree": True}, headers=g)

        assert client.delete("/v1/me", headers=headers(h)).status_code == 409  # needs the guardian now
        v = client.post("/v1/guardian/requests", json={"kind": "delete"}, headers=headers(h)).json()
        assert any(r["kind"] == "delete" and r["status"] == "pending" for r in v["requests"])
        assert "delete" in sms.last_text_to(PHONE)
        # The player can take it back, then ask again.
        v = client.delete("/v1/guardian/requests/delete", headers=headers(h)).json()
        assert not any(r["kind"] == "delete" and r["status"] == "pending" for r in v["requests"])
        client.post("/v1/guardian/requests", json={"kind": "delete"}, headers=headers(h))

        page = client.get(f"/v1/g/{link}", headers=g).json()
        assert [p["kind"] for p in page["pending"]] == ["delete"]
        done = client.post(f"/v1/g/{link}/decide", json={"kind": "delete", "yes": True}, headers=g).json()
        assert done == {"deleted": True, "childFirstName": "Kofi"}
        assert "deleted" in sms.last_text_to(PHONE)
        assert client.get("/v1/me", headers=headers(h)).status_code == 401  # the account is gone


def test_under_18_without_an_approving_guardian_can_delete_themselves():
    with TestClient(app) as client:
        h = _minor(client)
        assert (
            client.post("/v1/guardian/requests", json={"kind": "delete"}, headers=headers(h)).status_code
            == 409
        )
        assert client.delete("/v1/me", headers=headers(h)).status_code == 204


def test_guardian_can_answer_a_delete_request_by_text(monkeypatch):
    monkeypatch.setattr(settings(), "sms_webhook_secret", "s3cret")
    monkeypatch.setattr(guardian, "RESEND_SECONDS", 0)
    with TestClient(app) as client:
        h = _minor(client)
        client.put("/v1/guardian", json={"phone": PHONE}, headers=headers(h))
        link, _ = _code_from_text()
        hook = {"X-SMS-Secret": "s3cret"}
        client.post("/v1/sms/inbound", json={"from": PHONE, "text": f"YES {link}"}, headers=hook)
        client.post("/v1/guardian/requests", json={"kind": "delete"}, headers=headers(h))
        r = client.post("/v1/sms/inbound", json={"from": PHONE, "text": f"YES {link}"}, headers=hook).json()
        assert r["kind"] == "delete" and client.get("/v1/me", headers=headers(h)).status_code == 401
