"""Push via FCM: the service-account token, sending to every device, dropping dead tokens."""

from __future__ import annotations

import json

import httpx
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup

from pep.api.app import app
from pep.config import settings
from pep.players import push


def _account() -> str:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    return json.dumps(
        {
            "client_email": "pep@tracka.iam.gserviceaccount.com",
            "private_key": pem,
            "project_id": "tracka-test",
        }
    )


def test_sends_to_each_device_and_forgets_dead_tokens(monkeypatch):
    monkeypatch.setattr(settings(), "fcm_service_account", _account())
    push._cached.update(token=None, expires=0)
    seen: list[dict] = []

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url.host == "oauth2.googleapis.com":
            assert b"jwt-bearer" in req.content
            return httpx.Response(200, json={"access_token": "ya29.test", "expires_in": 3600})
        assert req.headers["authorization"] == "Bearer ya29.test" and "/projects/tracka-test/" in str(req.url)
        body = json.loads(req.content)
        seen.append(body)
        if body["message"]["token"] == "dead-token-0123":
            return httpx.Response(
                404, json={"error": {"status": "NOT_FOUND", "details": [{"errorCode": "UNREGISTERED"}]}}
            )
        return httpx.Response(200, json={"name": "projects/tracka-test/messages/1"})

    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        for t in ("good-token-0123", "dead-token-0123"):
            assert (
                client.put(
                    "/v1/devices", json={"token": t, "platform": "android"}, headers=headers(h)
                ).status_code
                == 204
            )
        uid = client.get("/v1/me", headers=headers(h)).json()["id"]
        http = httpx.Client(transport=httpx.MockTransport(handler))
        n = push.send(uid, "Pep's read is ready", "3 tips", {"screen": "video", "id": "v1"}, client=http)
        assert n == 1 and seen[0]["message"]["data"] == {"screen": "video", "id": "v1"}
        # The dead token is gone: next time only one send.
        seen.clear()
        assert push.send(uid, "Again", "", client=http) == 1 and len(seen) == 1


def test_without_firebase_it_only_logs(monkeypatch):
    monkeypatch.setattr(settings(), "fcm_service_account", "")
    with TestClient(app) as client:
        h = signup(client)
        client.put(
            "/v1/devices", json={"token": "some-token-0123", "platform": "android"}, headers=headers(h)
        )
        uid = client.get("/v1/me", headers=headers(h)).json()["id"]
        assert push.send(uid, "Hello", "") == 0
