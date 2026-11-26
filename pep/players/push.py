"""
Push messages to phones with Firebase Cloud Messaging (FCM).

How a push gets to a phone:

    app starts ──▶ asks Firebase for a device token ──▶ PUT /v1/devices (we keep it)
    something happens (review ready, respect) ──▶ notifications.notify()
        ──▶ push.send(uid, title, body) ──▶ FCM HTTP v1 API ──▶ the phone

Talking to FCM needs a short-lived Google access token. We make it ourselves
from the Firebase service account: sign a JWT with its private key (RS256),
swap it at Google's token endpoint for an access token, and reuse that for
up to an hour. That's the OAUTH 2.0 SERVICE ACCOUNT flow (handbook chapter 03);
the google-auth library does the same thing, we just don't need all of it.

Settings (env vars, never git; see docs/PUSH_SETUP.md):
    PEP_FCM_SERVICE_ACCOUNT   the service account JSON (the whole file, as text)
    PEP_FCM_PROJECT_ID        optional; read from the JSON if not set

Without them, `send()` only logs (the old placeholder), so nothing breaks in
dev or tests. Tokens FCM says are dead (app removed, token expired) are
deleted so we stop sending to them.
"""

from __future__ import annotations

import json
import time
from typing import Any

import httpx
import jwt
from sqlalchemy import delete, select

from .. import db
from ..config import settings
from ..log import get_logger

log = get_logger(__name__)

TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_cached: dict[str, Any] = {"token": None, "expires": 0.0}


def _account() -> dict | None:
    raw = settings().fcm_service_account
    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        log.warning("push.bad_service_account")
        return None


def configured() -> bool:
    return _account() is not None


def access_token(client: httpx.Client) -> str:
    """A Google access token for FCM, cached until a minute before it expires."""
    if _cached["token"] and _cached["expires"] > time.time() + 60:
        return _cached["token"]
    acc = _account()
    assert acc is not None
    now = int(time.time())
    assertion = jwt.encode(
        {"iss": acc["client_email"], "scope": SCOPE, "aud": TOKEN_URL, "iat": now, "exp": now + 3600},
        acc["private_key"],
        algorithm="RS256",
    )
    r = client.post(
        TOKEN_URL, data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion}
    )
    r.raise_for_status()
    body = r.json()
    _cached.update(token=body["access_token"], expires=now + int(body.get("expires_in", 3600)))
    return body["access_token"]


def send(
    uid: str, title: str, body: str, link: dict | None = None, client: httpx.Client | None = None
) -> int:
    """Send to every device the player has. Returns how many accepted it. Never raises."""
    from .notifications import devices

    with db.engine().connect() as c:
        tokens = [r.token for r in c.execute(select(devices.c.token).where(devices.c.user_id == uid))]
    if not tokens:
        return 0
    acc = _account()
    if acc is None:
        log.info("push.placeholder", user_id=uid, devices=len(tokens), title=title)
        return 0
    project = settings().fcm_project_id or acc.get("project_id")
    own = client is None
    client = client or httpx.Client(timeout=10)
    sent = 0
    try:
        token = access_token(client)
        for t in tokens:
            msg = {
                "message": {
                    "token": t,
                    "notification": {"title": title[:120], "body": body[:240]},
                    # Strings only in "data"; the app reads it to open the right screen.
                    "data": {k: str(v) for k, v in (link or {}).items()},
                }
            }
            r = client.post(
                f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
                headers={"Authorization": f"Bearer {token}"},
                json=msg,
            )
            if r.status_code == 200:
                sent += 1
            elif r.status_code == 404 or (r.status_code == 400 and "UNREGISTERED" in r.text):
                with db.engine().begin() as c:  # the app was removed or the token expired
                    c.execute(delete(devices).where(devices.c.token == t))
            else:
                log.warning("push.failed", status=r.status_code, body=r.text[:200])
    except Exception as exc:  # push is an extra: the notification is in the bell anyway
        log.warning("push.error", error=str(exc)[:200])
    finally:
        if own:
            client.close()
    return sent
