"""
Sending results back to Tracka: signed webhooks with retries.

A WEBHOOK is just an HTTP POST we make to a URL the other service gave us
(`callbackUrl`). Two problems to solve:

1. Trust. Anyone on the internet could POST a fake score to Tracka. So we
   sign the exact bytes we send with a shared secret:

       signature = hex(HMAC-SHA256(secret, body))

   Tracka recomputes it and compares (in constant time, to avoid timing
   attacks). Only someone who knows the secret can produce a valid
   signature, and changing one byte of the body breaks it.

2. Reliability. Tracka might be redeploying, asleep (Render free plans
   sleep), or briefly down. So delivery is retried with exponential backoff
   (db.callback_result), and is its own state machine separate from the
   analysis: a finished analysis is never re-run just because delivery failed.

The same signature function lives in tracka-api (validSignature in
src/services/coach.ts). Test both sides with the same example: tests/test_contracts.py.
"""

from __future__ import annotations

import hashlib
import hmac
import json

import httpx

from . import db
from .config import settings
from .log import get_logger

log = get_logger(__name__)


def sign(body: bytes, secret: str) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def verify(body: bytes, signature: str | None, secret: str) -> bool:
    if not signature:
        return False
    return hmac.compare_digest(sign(body, secret), signature)  # constant-time comparison


def encode(result: dict) -> bytes:
    # Compact, stable JSON: the signature is over these exact bytes.
    return json.dumps(result, separators=(",", ":"), ensure_ascii=False).encode()


def deliver(job: dict, client: httpx.Client | None = None) -> bool:
    url = (job["request"] or {}).get("callbackUrl")
    attempts = job["callback_attempts"] + 1
    if not url or not job.get("result"):
        db.callback_result(job["id"], True, None, attempts)
        return True
    body = encode(job["result"])
    headers = {
        "Content-Type": "application/json",
        "X-Tracka-Signature": sign(body, settings().webhook_secret),
    }
    own = client is None
    client = client or httpx.Client(timeout=15)
    try:
        resp = client.post(url, content=body, headers=headers)
        ok = 200 <= resp.status_code < 300
        error = None if ok else f"HTTP {resp.status_code}: {resp.text[:200]}"
    except httpx.HTTPError as exc:
        ok, error = False, f"{type(exc).__name__}: {exc}"
    finally:
        if own:
            client.close()
    db.callback_result(job["id"], ok, error, attempts)
    log.info("callback.sent" if ok else "callback.failed", job_id=job["id"], attempt=attempts, error=error)
    return ok


def deliver_due() -> int:
    """Sends every callback that's due. Called by the worker between jobs."""
    sent = 0
    for job in db.callbacks_due():
        sent += deliver(job)
    return sent
