"""
Error tracking: when something breaks, tell a person, with enough detail to fix it.

WHY (handbook chapter 10, "Observability"): logs record everything, but nobody
reads every line. An error tracker groups the same crash into one issue, counts
how often it happens, shows the stack trace, and can email you the first time a
new one appears. Sentry is the best known; GlitchTip is a free, self-hostable
tool that speaks the same protocol, so the same DSN setting works for both.

PRIVACY FIRST: most Tracka players are children. Error reports leave our
servers, so they carry the crash and nothing about the person:
  - no user details (IP addresses, cookies, user names) and no local
    variables from the stack;
  - `_scrub` drops request bodies, headers and query strings (tokens, emails,
    phone numbers live there) and replaces emails and phone numbers in the
    message with placeholders;
  - no performance tracing, so no record of which pages someone visited.

Off until `PEP_SENTRY_DSN` is set. With it empty, errors still go to the logs.
"""

from __future__ import annotations

import re
from typing import Any

from . import MODEL_VERSION
from .config import settings
from .log import get_logger

log = get_logger(__name__)

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
PHONE = re.compile(r"\+?\d[\d \-]{7,}\d")


def scrub_text(text: str) -> str:
    """Hide emails and phone numbers in free text (error messages, app reports)."""
    return PHONE.sub("<phone>", EMAIL.sub("<email>", text))


def _scrub(event: dict[str, Any], hint: dict[str, Any] | None = None) -> dict[str, Any]:
    """Sentry's `before_send` hook: the last look at a report before it leaves."""
    req = event.get("request")
    if isinstance(req, dict):
        event["request"] = {k: req[k] for k in ("method", "url") if k in req}
        if "url" in event["request"]:
            event["request"]["url"] = str(event["request"]["url"]).split("?")[0]
    event.pop("user", None)
    for exc in (event.get("exception") or {}).get("values") or []:
        if isinstance(exc.get("value"), str):
            exc["value"] = scrub_text(exc["value"])
    if isinstance(event.get("message"), str):
        event["message"] = scrub_text(event["message"])
    return event


def setup_error_tracking() -> bool:
    """Start the error tracker if a DSN is set. Returns True when it's on."""
    dsn = settings().sentry_dsn
    if not dsn:
        return False
    try:
        import sentry_sdk
    except ImportError:  # pragma: no cover - it's a normal dependency
        log.warning("errors.sentry_missing")
        return False
    options: dict[str, Any] = {
        "dsn": dsn,
        "environment": settings().env,
        "release": f"pep@{MODEL_VERSION}",
        "traces_sample_rate": 0.0,
        "before_send": _scrub,
    }
    # No user details, and no local variables from the stack (they can hold an
    # email or a phone number). Version 3 of the SDK renamed these options.
    if int(sentry_sdk.VERSION.split(".")[0]) >= 3:
        options["data_collection"] = {
            "user_info": False,
            "http_bodies": [],
            "stack_frame_variables": False,
            "database_query_data": False,
        }
    else:
        options |= {"send_default_pii": False, "include_local_variables": False}
    sentry_sdk.init(**options)
    log.info("errors.on", env=settings().env)
    return True


def capture_message(text: str, **extra: Any) -> None:
    """Send one message to the tracker (if it's on). Used for crashes the app reports."""
    if not settings().sentry_dsn:
        return
    import sentry_sdk

    with sentry_sdk.new_scope() as scope:
        for k, v in extra.items():
            scope.set_tag(k, str(v)[:200])
        sentry_sdk.capture_message(scrub_text(text), level="error")
