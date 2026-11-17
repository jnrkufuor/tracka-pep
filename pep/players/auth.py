"""
Accounts and logins: password hashing and tokens.

PASSWORDS are never stored, only a slow, salted hash of them:
  * SALT: random bytes stored with the hash, so two players with the same
    password get different hashes (and precomputed "rainbow tables" are useless).
  * SLOW on purpose: scrypt needs a lot of memory and CPU for each guess, so a
    stolen database can't be brute-forced quickly. `hashlib.scrypt` is in
    Python's standard library.
  * Compared in CONSTANT TIME (`hmac.compare_digest`), so response timing
    doesn't leak how many characters matched.

TOKENS (JWT, "JSON Web Token"): after login the app gets two tokens:
  * an ACCESS token: short-lived (30 min), sent with every request as
    `Authorization: Bearer <token>`. It's signed (HMAC-SHA256) with our secret,
    so the server can trust it without a database lookup: it says who you are
    and when it expires.
  * a REFRESH token: long-lived (60 days), used only to get a new pair. It
    names a row in the `sessions` table, so it can be revoked (log out, change
    password). Each refresh ROTATES it: the old one is revoked and a new one
    issued. If a revoked refresh token is ever used again, someone copied it,
    so we revoke every session for that player.

Why two tokens: a stolen access token is only useful for minutes; the
long-lived one is checked against the database and can be cancelled.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Header, HTTPException

from ..config import settings
from . import store

SCRYPT_N, SCRYPT_R, SCRYPT_P = 2**14, 8, 1  # ~16 MB and tens of ms per hash


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P, dklen=32)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(digest).decode()


def check_password(password: str, stored: str) -> bool:
    try:
        _, salt_b64, digest_b64 = stored.split("$")
        salt, digest = base64.b64decode(salt_b64), base64.b64decode(digest_b64)
    except ValueError:
        return False
    test = hashlib.scrypt(password.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P, dklen=len(digest))
    return hmac.compare_digest(test, digest)


def _encode(claims: dict) -> str:
    return jwt.encode(claims, settings().jwt_secret, algorithm="HS256")


def issue_tokens(user: dict) -> dict:
    s = settings()
    now = datetime.now(UTC)
    refresh_expires = now + timedelta(days=s.refresh_token_days)
    sid = store.add_session(user["id"], refresh_expires)
    access = _encode(
        {
            "sub": user["id"],
            "role": user["role"],
            "typ": "access",
            "iat": now,
            "exp": now + timedelta(minutes=s.access_token_minutes),
        }
    )
    refresh = _encode({"sub": user["id"], "sid": sid, "typ": "refresh", "iat": now, "exp": refresh_expires})
    return {"accessToken": access, "refreshToken": refresh, "expiresIn": s.access_token_minutes * 60}


def decode(token: str, typ: str) -> dict:
    try:
        claims = jwt.decode(token, settings().jwt_secret, algorithms=["HS256"])  # pin the algorithm!
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "Your session has expired. Log in again.") from None
    except jwt.InvalidTokenError:
        raise HTTPException(401, "Not logged in.") from None
    if claims.get("typ") != typ:
        raise HTTPException(401, "Wrong kind of token.")
    return claims


def refresh(token: str) -> dict:
    claims = decode(token, "refresh")
    session = store.get_session(claims["sid"])
    if session is None:
        raise HTTPException(401, "Log in again.")
    if session["revoked"]:
        # A rotated-away token came back: assume it was stolen; log out everywhere.
        store.revoke_all_sessions(claims["sub"])
        raise HTTPException(401, "Log in again.")
    store.revoke_session(claims["sid"])
    user = store.user_by_id(claims["sub"])
    if user is None:
        raise HTTPException(401, "Log in again.")
    return issue_tokens(user)


def current_user(authorization: str | None = Header(None)) -> dict:
    """FastAPI dependency: the logged-in player, from the Bearer access token."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Not logged in.")
    claims = decode(authorization.removeprefix("Bearer "), "access")
    user = store.user_by_id(claims["sub"])
    if user is None:
        raise HTTPException(401, "This account no longer exists.")
    return user
