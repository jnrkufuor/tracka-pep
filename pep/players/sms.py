"""
Text messages (SMS): guardian approval texts, one-time codes, replies.

PLACEHOLDER. Tracka hasn't picked an SMS provider yet (or decided who pays
for the texts). Until then every text goes to the `LogSender`: it's written to
the `sms_outbox` table and the log instead of a phone. Everything around it
(the codes, the guardian page, replying YES 4F7K) is real and tested, so
switching on a provider is one class here and one setting:

    class ProviderSender:                       # e.g. Hubtel, Arkesel, mNotify, Twilio
        def send(self, to, text, user_id=None) -> Sent: ...  call their API

    PEP_SMS_PROVIDER=provider  (plus its API key, from env vars, never git)

While the provider is `log`, the app keeps the interim "they've already said
yes" tick for under-18s (PEP_GUARDIAN_SELF_CONFIRM), because no real text
can reach a guardian yet.

This is the ADAPTER pattern (handbook chapter 02): the rest of the code calls
`sender().send(...)` and never knows which company delivers the text.

Privacy: phone numbers are personal data. The outbox keeps texts for 30 days
at most (a cleanup job is a TODO with the provider), logs only show the last
3 digits, and codes are never logged outside dev and test.
"""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from sqlalchemy import Column, DateTime, ForeignKey, String, Table, Text, insert, select

from .. import db
from ..config import settings
from ..log import get_logger

log = get_logger(__name__)

sms_outbox = Table(
    "sms_outbox",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True),
    Column("to_number", String(24), nullable=False),
    Column("text", Text, nullable=False),
    Column("status", String(12), nullable=False),  # logged | sent | failed
    Column("created_at", DateTime(timezone=True), nullable=False),
)


@dataclass
class Sent:
    ok: bool
    status: str  # logged | sent | failed


class Sender(Protocol):
    def send(self, to: str, text: str, user_id: str | None = None) -> Sent: ...


def normalise(phone: str) -> str:
    """'024 123 4567' or '+233 24 123 4567' → '+233241234567' (Ghana by default)."""
    digits = re.sub(r"\D", "", phone)
    if digits.startswith("00"):
        digits = digits[2:]
    if len(digits) == 10 and digits.startswith("0"):
        digits = "233" + digits[1:]
    elif len(digits) == 9:
        digits = "233" + digits
    return "+" + digits


def mask(phone: str) -> str:
    """'+233241234567' → '+233 24 ••• 4567' (what the player sees)."""
    d = normalise(phone)
    return f"{d[:4]} {d[4:6]} ••• {d[-4:]}" if len(d) >= 10 else "•••"


class LogSender:
    """The placeholder: keeps the text in sms_outbox and the log. Nothing leaves the server."""

    def send(self, to: str, text: str, user_id: str | None = None) -> Sent:
        with db.engine().begin() as c:
            c.execute(
                insert(sms_outbox).values(
                    id=str(uuid.uuid4()),
                    user_id=user_id,
                    to_number=normalise(to),
                    text=text,
                    status="logged",
                    created_at=datetime.now(UTC),
                )
            )
        shown = text if settings().env != "prod" else "(hidden in prod)"
        log.info("sms.logged", to=f"…{normalise(to)[-3:]}", text=shown)
        return Sent(ok=True, status="logged")


def sender() -> Sender:
    # Add real providers here, chosen by PEP_SMS_PROVIDER.
    return LogSender()


def live() -> bool:
    """True once a real provider sends texts to phones."""
    return settings().sms_provider != "log"


def last_text_to(phone: str) -> str | None:
    """The newest text sent to a number (tests and the dev Lab use this to read codes)."""
    with db.engine().connect() as c:
        row = c.execute(
            select(sms_outbox.c.text)
            .where(sms_outbox.c.to_number == normalise(phone))
            .order_by(sms_outbox.c.created_at.desc())
        ).first()
    return row[0] if row else None
