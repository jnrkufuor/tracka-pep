"""
Guardian approval: a parent, guardian or coach says yes before an under-18
player's account opens up, and again before anything new (posting clips,
sharing their card, being findable).

    player                         Tracka                         guardian
    ──────                         ──────                         ────────
    adds guardian's phone  ──▶  text: "review at tracka.app/g/4F7K,
                                 or reply YES 4F7K"           ──▶  opens the page
                                                               ◀──  asks for a code
                              text: "your code is 4829"      ──▶
                                                               ◀──  types it, says yes
    "Ama said yes"         ◀──  account approved

Two ways to answer, because many guardians have a basic phone or no data:
the web page (with a one-time code texted to them), or a plain text reply
"YES 4F7K" / "NO 4F7K" (pep/players/guardian_routes.py, `sms_inbound`).

Security, in plain words (handbook chapter 10):
  - The 4-letter link code only FINDS the request. It's short so it can be
    typed from a text, which also makes it guessable, so opening the page
    shows only the child's first name until the guardian proves they hold
    the phone: a 4-digit code, texted to it, 10 minutes, 5 tries.
  - Codes are stored HASHED (like passwords): a database leak doesn't leak them.
  - The page session is a random token, also stored hashed, valid one day.
  - No answer in 7 days means no.

Some things are always on for under-18s and nobody can switch them off: no
messages, contact goes through the guardian, only the region is shown.

Texts are a PLACEHOLDER until an SMS provider is chosen: see sms.py.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import JSON, Column, DateTime, ForeignKey, Integer, String, Table, insert, select, update

from .. import db
from ..config import settings
from . import sms

# Things a guardian decides. "account" first; the others are asked for later.
# "delete" isn't a permission: it's a one-off yes to deleting an under-18's account.
KINDS = ("account", "post", "share_card", "search")
ASK_KINDS = (*KINDS, "delete")
ANSWER_DAYS = 7
CODE_MINUTES = 10
CODE_TRIES = 5
RESEND_SECONDS = 60
# No 0/O, 1/I/L, 2/Z, 5/S, 8/B: easy to read out and type from a text.
ALPHABET = "ACDEFGHJKMNPQRTUVWXY3479"

guardians = Table(
    "guardians",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("code", String(8), nullable=False, unique=True, index=True),  # the link: /g/4F7K
    Column("name", String(60)),
    Column("phone", String(24), nullable=False),  # normalised, private
    Column("relation", String(12)),  # parent | guardian | coach
    Column("status", String(12), nullable=False),  # pending | approved | declined | revoked
    Column("otp_hash", String(64)),
    Column("otp_expires_at", DateTime(timezone=True)),
    Column("otp_tries", Integer, nullable=False, default=0),
    Column("sent_at", DateTime(timezone=True)),
    Column("send_status", String(12)),  # logged | sent | failed
    Column("prefs", JSON, nullable=False, default=dict),  # texts the guardian wants
    Column("asked_at", DateTime(timezone=True), nullable=False),
    Column("decided_at", DateTime(timezone=True)),
)

guardian_requests = Table(
    "guardian_requests",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("kind", String(16), nullable=False),  # account | post | share_card | search
    Column("status", String(12), nullable=False),  # pending | yes | no
    Column("asked_at", DateTime(timezone=True), nullable=False),
    Column("decided_at", DateTime(timezone=True)),
    Column("via", String(8)),  # page | text
)

guardian_sessions = Table(
    "guardian_sessions",
    db.metadata,
    Column("token_hash", String(64), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("expires_at", DateTime(timezone=True), nullable=False),
)

TABLES = (guardian_sessions, guardian_requests, guardians)


def now() -> datetime:
    return datetime.now(UTC)


def _aware(d: datetime | None) -> datetime | None:
    return d.replace(tzinfo=UTC) if d is not None and d.tzinfo is None else d


def _hash(value: str) -> str:
    """Keyed hash: without the server secret, a stored hash can't be checked against guesses."""
    return hmac.new(settings().jwt_secret.encode(), value.encode(), hashlib.sha256).hexdigest()


def link(code: str) -> str:
    base = (settings().web_url or settings().public_url).rstrip("/")
    return f"{base}/g/{code}"


# ---------------------------------------------------------------- reading


def get(uid: str) -> dict | None:
    with db.engine().connect() as c:
        row = c.execute(select(guardians).where(guardians.c.user_id == uid)).first()
    return dict(row._mapping) if row else None


def by_code(code: str) -> dict | None:
    with db.engine().connect() as c:
        row = c.execute(select(guardians).where(guardians.c.code == code.upper())).first()
    return dict(row._mapping) if row else None


def requests(uid: str) -> list[dict]:
    """All requests, newest first, with 'pending' past 7 days shown as 'expired'."""
    with db.engine().connect() as c:
        rows = [
            dict(r._mapping)
            for r in c.execute(
                select(guardian_requests)
                .where(guardian_requests.c.user_id == uid)
                .order_by(guardian_requests.c.asked_at.desc())
            )
        ]
    cutoff = now() - timedelta(days=ANSWER_DAYS)
    for r in rows:
        if r["status"] == "pending" and (_aware(r["asked_at"]) or now()) < cutoff:
            r["status"] = "expired"
    return rows


def latest(uid: str, kind: str) -> dict | None:
    return next((r for r in requests(uid) if r["kind"] == kind), None)


def status(uid: str) -> str:
    """none | pending | approved | declined | revoked | expired (the account request)."""
    g = get(uid)
    if g is None:
        return "none"
    if g["status"] == "pending":
        r = latest(uid, "account")
        return "expired" if r is not None and r["status"] == "expired" else "pending"
    return g["status"]


def allowed(uid: str, kind: str, age: int | None, self_confirmed: bool = False) -> bool:
    """
    May this player do `kind` (account, post, share_card, search)?
    Adults decide for themselves (their own settings); under-18s need their guardian.
    `self_confirmed`: the interim "they've already said yes" tick, honoured only
    while texts can't reach guardians (sms.py placeholder).
    """
    if age is None or age >= 18:
        return True
    account = status(uid) == "approved" or (
        self_confirmed and settings().guardian_self_confirm and not sms.live() and status(uid) != "revoked"
    )
    if kind == "account" or not account:
        return account
    r = latest(uid, kind)
    return r is not None and r["status"] == "yes"


def needs_guardian_to_delete(uid: str, age: int | None) -> bool:
    """
    Under 18 with a guardian who approved the account: deleting it needs their yes
    too (canvas: Settings › Your data). If no guardian ever approved, there's nobody
    to ask, and the account never opened up, so the player can delete it themselves.
    """
    return age is not None and age < 18 and status(uid) == "approved"


def permissions(uid: str, age: int | None, self_confirmed: bool = False) -> dict[str, bool]:
    return {to_camel(k): allowed(uid, k, age, self_confirmed) for k in KINDS}


def to_camel(k: str) -> str:
    head, *rest = k.split("_")
    return head + "".join(w.title() for w in rest)


# ---------------------------------------------------------------- writing


def _new_code() -> str:
    while True:
        code = "".join(secrets.choice(ALPHABET) for _ in range(4))
        if by_code(code) is None:
            return code


def _ask(c, uid: str, kind: str) -> str:
    rid = str(uuid.uuid4())
    c.execute(
        insert(guardian_requests).values(id=rid, user_id=uid, kind=kind, status="pending", asked_at=now())
    )
    return rid


def set_guardian(uid: str, phone: str, relation: str | None, name: str | None) -> dict:
    """Add the guardian, or change their number. A new number starts a new account request."""
    phone = sms.normalise(phone)
    g = get(uid)
    with db.engine().begin() as c:
        if g is None:
            c.execute(
                insert(guardians).values(
                    user_id=uid,
                    code=_new_code(),
                    phone=phone,
                    relation=relation,
                    name=name,
                    status="pending",
                    otp_tries=0,
                    prefs={"eachRequest": True, "monthlySummary": False},
                    asked_at=now(),
                )
            )
            _ask(c, uid, "account")
        else:
            values: dict[str, Any] = {"relation": relation or g["relation"], "name": name or g["name"]}
            if phone != g["phone"]:
                values |= {
                    "phone": phone,
                    "status": "pending",
                    "asked_at": now(),
                    "otp_hash": None,
                    "sent_at": None,
                }
                c.execute(
                    update(guardian_requests)
                    .where(guardian_requests.c.user_id == uid, guardian_requests.c.status == "pending")
                    .values(status="no", decided_at=now(), via="page")
                )
                _ask(c, uid, "account")
            c.execute(update(guardians).where(guardians.c.user_id == uid).values(**values))
    return get(uid)  # type: ignore[return-value]


def ask(uid: str, kind: str) -> dict:
    """The player asks for something new (post, share_card, search). Reuses a pending ask."""
    r = latest(uid, kind)
    if r is not None and r["status"] == "pending":
        return r
    with db.engine().begin() as c:
        _ask(c, uid, kind)
    return latest(uid, kind)  # type: ignore[return-value]


def can_resend(g: dict) -> datetime | None:
    """When the next text may go (None = now). Stops anyone flooding a guardian's phone."""
    sent = _aware(g.get("sent_at"))
    if sent is None:
        return None
    nxt = sent + timedelta(seconds=RESEND_SECONDS)
    return nxt if nxt > now() else None


def text_guardian(uid: str, child_first: str, sex: str | None, kind: str = "account") -> sms.Sent:
    """Send (or re-send) the request text. The caller checks `can_resend` first."""
    g = get(uid)
    assert g is not None
    his = "her" if sex == "female" else "his" if sex == "male" else "their"
    hello = f"Hello {g['name']}." if g.get("name") else "Hello."
    what = {
        "account": f"{child_first} wants to use Tracka, a football training app. As {his} guardian, you decide what "
        f"{child_first} can do.",
        "post": f"{child_first} is asking to post clips on Tracka for other players to see.",
        "share_card": f"{child_first} is asking to share {his} player card with a link.",
        "search": f"{child_first} is asking to let other players {his} age find {his} profile.",
        "delete": f"{child_first} has asked to delete {his} Tracka account. Everything is deleted for good: "
        "profile, clips and training.",
    }[kind]
    reply = "approve" if kind == "account" else "say yes"
    text = (
        f"{hello} {what} Review here: {link(g['code'])} "
        f"No internet? Reply YES {g['code']} to {reply} or NO {g['code']} to say no."
    )
    sent = sms.sender().send(g["phone"], text, user_id=uid)
    with db.engine().begin() as c:
        c.execute(
            update(guardians).where(guardians.c.user_id == uid).values(sent_at=now(), send_status=sent.status)
        )
    return sent


def send_code(uid: str) -> sms.Sent:
    """A fresh one-time code for the guardian page, texted to the guardian's phone."""
    g = get(uid)
    assert g is not None
    code = f"{secrets.randbelow(10_000):04d}"
    with db.engine().begin() as c:
        c.execute(
            update(guardians)
            .where(guardians.c.user_id == uid)
            .values(
                otp_hash=_hash(f"{uid}:{code}"),
                otp_expires_at=now() + timedelta(minutes=CODE_MINUTES),
                otp_tries=0,
                sent_at=now(),
            )
        )
    return sms.sender().send(
        g["phone"], f"Your Tracka code is {code}. It works for {CODE_MINUTES} minutes.", user_id=uid
    )


def verify_code(uid: str, code: str) -> str | None:
    """Checks the code. Right: a page session token. Wrong, expired or out of tries: None."""
    g = get(uid)
    if g is None or not g["otp_hash"] or g["otp_tries"] >= CODE_TRIES:
        return None
    expires = _aware(g["otp_expires_at"])
    if expires is None or expires < now():
        return None
    if not hmac.compare_digest(g["otp_hash"], _hash(f"{uid}:{code.strip()}")):
        with db.engine().begin() as c:
            c.execute(
                update(guardians).where(guardians.c.user_id == uid).values(otp_tries=g["otp_tries"] + 1)
            )
        return None
    token = secrets.token_urlsafe(32)
    with db.engine().begin() as c:
        c.execute(update(guardians).where(guardians.c.user_id == uid).values(otp_hash=None))
        c.execute(
            insert(guardian_sessions).values(
                token_hash=_hash(token), user_id=uid, expires_at=now() + timedelta(days=1)
            )
        )
    return token


def session_user(code: str, token: str | None) -> str | None:
    """The player whose guardian holds this page session, if it's valid for this link."""
    g = by_code(code)
    if g is None or not token:
        return None
    with db.engine().connect() as c:
        row = c.execute(
            select(guardian_sessions).where(
                guardian_sessions.c.token_hash == _hash(token), guardian_sessions.c.user_id == g["user_id"]
            )
        ).first()
    if row is None or _aware(row.expires_at) < now():  # type: ignore[operator]
        return None
    return g["user_id"]


def decide(uid: str, kind: str, yes: bool, via: str = "page", relation: str | None = None) -> None:
    """The guardian answers. Saying no to the account says no to everything."""
    pend = [r for r in requests(uid) if r["kind"] == kind and r["status"] in ("pending", "expired")]
    with db.engine().begin() as c:
        if pend:
            c.execute(
                update(guardian_requests)
                .where(guardian_requests.c.id == pend[0]["id"])
                .values(status="yes" if yes else "no", decided_at=now(), via=via)
            )
        else:  # the guardian changed a setting directly on their page
            c.execute(
                insert(guardian_requests).values(
                    id=str(uuid.uuid4()),
                    user_id=uid,
                    kind=kind,
                    status="yes" if yes else "no",
                    asked_at=now(),
                    decided_at=now(),
                    via=via,
                )
            )
        if kind == "account":
            values: dict[str, Any] = {"status": "approved" if yes else "declined", "decided_at": now()}
            if relation:
                values["relation"] = relation
            c.execute(update(guardians).where(guardians.c.user_id == uid).values(**values))
    from . import notifications  # here, not at the top: notifications imports the player store

    notifications.guardian_answered(uid, kind, yes)


def withdraw(request_id: str) -> None:
    """The player takes a request back before it's answered."""
    with db.engine().begin() as c:
        c.execute(
            update(guardian_requests)
            .where(guardian_requests.c.id == request_id, guardian_requests.c.status == "pending")
            .values(status="withdrawn", decided_at=now(), via="player")
        )


def revoke_all(uid: str) -> None:
    """'Take back all approvals': private mode again. Training and clips stay."""
    with db.engine().begin() as c:
        c.execute(
            update(guardians).where(guardians.c.user_id == uid).values(status="revoked", decided_at=now())
        )
        c.execute(
            update(guardian_requests)
            .where(guardian_requests.c.user_id == uid, guardian_requests.c.status.in_(("pending", "yes")))
            .values(status="no", decided_at=now(), via="page")
        )


def set_prefs(uid: str, prefs: dict) -> None:
    g = get(uid)
    assert g is not None
    with db.engine().begin() as c:
        c.execute(
            update(guardians).where(guardians.c.user_id == uid).values(prefs={**(g["prefs"] or {}), **prefs})
        )


def parse_reply(text: str) -> tuple[bool, str] | None:
    """'yes 4f7k' → (True, '4F7K'); 'NO 4F7K.' → (False, '4F7K'); anything else → None."""
    words = text.strip().upper().replace(".", " ").replace(",", " ").split()
    if len(words) >= 2 and words[0] in ("YES", "NO", "Y", "N"):
        return words[0].startswith("Y"), words[1]
    return None
