"""
Guardian approval over HTTP (the rules live in guardian.py).

Two audiences, two kinds of route:

  /v1/guardian...      the PLAYER, logged in: add the guardian's phone, see the
                       status, re-send the text, ask for something new.
  /v1/g/{code}...      the GUARDIAN, not a Tracka user: open the link from the
                       text, get a code, say yes or no, change settings.
  /v1/sms/inbound      the SMS provider, when a guardian replies "YES 4F7K".

The guardian's routes never use the player's login. They use a short-lived
page session, earned with the code texted to the guardian's phone. Handbook
chapter 10 (Reliability and safety) walks through why.
"""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel

from ..config import settings
from ..log import get_logger
from ..scoring.norms import age_band
from . import auth, details, guardian, sms, store
from .skill_areas import AGE_LABEL

log = get_logger(__name__)
router = APIRouter(tags=["player app: guardian"])


class Body(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


def _first(display_name: str) -> str:
    return (display_name or "").split(" ")[0] or "Your child"


def _child(uid: str) -> tuple[dict, int | None]:
    p = store.get_profile(uid)
    return p, store.age_on(p["birth_date"])


def _iso(d) -> str | None:
    d = guardian._aware(d)
    return d.isoformat() if d else None


def player_view(uid: str) -> dict:
    """What the player's app shows (Waiting for your guardian, Me › Privacy)."""
    p, age = _child(uid)
    g = guardian.get(uid)
    nxt = guardian.can_resend(g) if g else None
    return {
        "needed": age is not None and age < 18,
        "status": guardian.status(uid),
        "name": g["name"] if g else None,
        "relation": g["relation"] if g else None,
        "phone": sms.mask(g["phone"]) if g else None,
        "sendStatus": g["send_status"] if g else None,
        "resendAt": nxt.isoformat() if nxt else None,
        "permissions": guardian.permissions(uid, age, p["guardian_consent"]),
        "requests": [
            {"id": r["id"], "kind": r["kind"], "status": r["status"], "askedAt": _iso(r["asked_at"])}
            for r in guardian.requests(uid)
        ],
        # Texts are a placeholder (sms.py) until a provider is chosen. The app shows
        # the interim tick while this is false.
        "textsLive": sms.live(),
        "selfConfirm": settings().guardian_self_confirm and not sms.live(),
    }


# ---------------------------------------------------------------- the player


class GuardianIn(Body):
    phone: str = Field(max_length=24, pattern=r"^\+?[0-9 ]{7,20}$")
    relation: Literal["parent", "guardian", "coach"] | None = None
    name: str | None = Field(None, max_length=60)


@router.get("/guardian")
def get_guardian(user: dict = Depends(auth.current_user)) -> dict:
    return player_view(user["id"])


@router.put("/guardian")
def put_guardian(body: GuardianIn, user: dict = Depends(auth.current_user)) -> dict:
    """Add the guardian or change their number. Sends the request text right away."""
    p, age = _child(user["id"])
    if age is None or age >= 18:
        raise HTTPException(409, "Only players under 18 need a guardian's approval.")
    before = guardian.get(user["id"])
    g = guardian.set_guardian(user["id"], body.phone, body.relation, body.name)
    details.save(user["id"], {"guardian_phone": g["phone"], "guardian_relation": g["relation"]})
    if before is None or before["phone"] != g["phone"] or guardian.can_resend(g) is None:
        guardian.text_guardian(user["id"], _first(p["display_name"]), p["sex"])
    log.info("guardian.set", user_id=user["id"])
    return player_view(user["id"])


@router.post("/guardian/resend")
def resend(user: dict = Depends(auth.current_user)) -> dict:
    g = guardian.get(user["id"])
    if g is None:
        raise HTTPException(404, "Add your guardian's number first.")
    if guardian.can_resend(g) is not None:
        raise HTTPException(429, "We just sent it. Give it a minute before sending again.")
    pending = next((r for r in guardian.requests(user["id"]) if r["status"] in ("pending", "expired")), None)
    p, _ = _child(user["id"])
    guardian.text_guardian(
        user["id"], _first(p["display_name"]), p["sex"], pending["kind"] if pending else "account"
    )
    return player_view(user["id"])


class AskIn(Body):
    kind: Literal["post", "share_card", "search"]


@router.post("/guardian/requests", status_code=201)
def ask(body: AskIn, user: dict = Depends(auth.current_user)) -> dict:
    """Ask the guardian for something new: posting clips, sharing the card, being findable."""
    p, age = _child(user["id"])
    if age is None or age >= 18:
        raise HTTPException(409, "You decide this yourself in Settings.")
    if (
        not guardian.allowed(user["id"], "account", age, p["guardian_consent"])
        or guardian.get(user["id"]) is None
    ):
        raise HTTPException(409, "Your guardian needs to approve your account first.")
    if guardian.allowed(user["id"], body.kind, age):
        return player_view(user["id"])
    before = guardian.latest(user["id"], body.kind)
    guardian.ask(user["id"], body.kind)
    if before is None or before["status"] != "pending":
        g = guardian.get(user["id"])
        if g and (g["prefs"] or {}).get("eachRequest", True):
            guardian.text_guardian(user["id"], _first(p["display_name"]), p["sex"], body.kind)
    return player_view(user["id"])


# ---------------------------------------------------------------- the guardian's page


def _session(code: str, token: str | None) -> str:
    uid = guardian.session_user(code, token)
    if uid is None:
        raise HTTPException(401, "Ask for a new code to continue.")
    return uid


def guardian_page(uid: str) -> dict:
    """Everything the guardian sees once they've proved it's them."""
    p, age = _child(uid)
    g = guardian.get(uid)
    assert g is not None
    d = details.get(uid)
    reqs = guardian.requests(uid)
    return {
        "child": {
            "firstName": _first(p["display_name"]),
            "fullName": p["display_name"],
            "ageGroup": AGE_LABEL[age_band(age)] if age is not None else None,
            "town": d["town"],
            "region": p["region"],
        },
        "guardian": {"name": g["name"], "relation": g["relation"]},
        "status": guardian.status(uid),
        "permissions": guardian.permissions(uid, age),
        "pending": [
            {"id": r["id"], "kind": r["kind"], "askedAt": _iso(r["asked_at"])}
            for r in reqs
            if r["status"] == "pending"
        ],
        "history": [
            {"kind": r["kind"], "status": r["status"], "decidedAt": _iso(r["decided_at"])}
            for r in reqs
            if r["status"] in ("yes", "no") and r["decided_at"]
        ],
        "prefs": g["prefs"] or {},
        "alwaysOn": [
            "No messages from anyone",
            "Contact comes to you first",
            "Only the region is shown, never the town",
        ],
    }


@router.get("/g/{code}")
def open_link(code: str, x_guardian_session: str | None = Header(None)) -> dict:
    """Without a session: just enough to say whose request it is. With one: the full page."""
    g = guardian.by_code(code)
    if g is None:
        raise HTTPException(404, "This link doesn't work. Check the text for the right code.")
    uid = guardian.session_user(code, x_guardian_session)
    if uid is None:
        p, _ = _child(g["user_id"])
        return {"childFirstName": _first(p["display_name"]), "needsCode": True, "phone": sms.mask(g["phone"])}
    return guardian_page(uid)


@router.post("/g/{code}/code", status_code=202)
def send_page_code(code: str) -> dict:
    g = guardian.by_code(code)
    if g is None:
        raise HTTPException(404, "This link doesn't work.")
    if guardian.can_resend(g) is not None:
        raise HTTPException(429, "We just sent a code. Give it a minute.")
    guardian.send_code(g["user_id"])
    return {"sentTo": sms.mask(g["phone"])}


class CodeIn(Body):
    code: str = Field(min_length=4, max_length=8)


@router.post("/g/{code}/verify")
def verify(code: str, body: CodeIn) -> dict:
    g = guardian.by_code(code)
    if g is None:
        raise HTTPException(404, "This link doesn't work.")
    token = guardian.verify_code(g["user_id"], body.code)
    if token is None:
        raise HTTPException(401, "That code isn't right, or it's too old. Ask for a new one.")
    return {"session": token}


class DecideIn(Body):
    kind: Literal["account", "post", "share_card", "search"]
    yes: bool
    relation: Literal["parent", "guardian", "coach"] | None = None
    agree: bool = False  # agreed to the terms and privacy policy for the child


@router.post("/g/{code}/decide")
def decide(code: str, body: DecideIn, x_guardian_session: str | None = Header(None)) -> dict:
    uid = _session(code, x_guardian_session)
    if body.kind == "account" and body.yes and not body.agree:
        raise HTTPException(422, "Please agree to the terms and privacy policy first.")
    if body.kind != "account" and body.yes and guardian.status(uid) != "approved":
        raise HTTPException(409, "Approve the account first.")
    guardian.decide(uid, body.kind, body.yes, via="page", relation=body.relation)
    log.info("guardian.decided", user_id=uid, kind=body.kind, yes=body.yes, via="page")
    return guardian_page(uid)


class PrefsIn(Body):
    each_request: bool | None = None
    monthly_summary: bool | None = None


@router.patch("/g/{code}/prefs")
def prefs(code: str, body: PrefsIn, x_guardian_session: str | None = Header(None)) -> dict:
    uid = _session(code, x_guardian_session)
    guardian.set_prefs(uid, {to_camel(k): v for k, v in body.model_dump(exclude_none=True).items()})
    return guardian_page(uid)


@router.post("/g/{code}/revoke")
def revoke(code: str, x_guardian_session: str | None = Header(None)) -> dict:
    uid = _session(code, x_guardian_session)
    guardian.revoke_all(uid)
    log.info("guardian.revoked", user_id=uid)
    return guardian_page(uid)


# ---------------------------------------------------------------- text replies


class InboundIn(BaseModel):
    from_: str = Field(alias="from", max_length=24)
    text: str = Field(max_length=480)


@router.post("/sms/inbound")
def sms_inbound(body: InboundIn, x_sms_secret: str | None = Header(None)) -> dict:
    """
    A guardian replied by text: "YES 4F7K" or "NO 4F7K". The provider calls this
    (PLACEHOLDER: wire the real provider's webhook here). Only a reply from the
    guardian's own number counts.
    """
    secret = settings().sms_webhook_secret
    if not secret or x_sms_secret != secret:
        raise HTTPException(404)
    parsed = guardian.parse_reply(body.text)
    if parsed is None:
        return {"ok": False, "reason": "not a YES or NO reply"}
    yes, code = parsed
    g = guardian.by_code(code)
    if g is None or sms.normalise(body.from_) != g["phone"]:
        return {"ok": False, "reason": "unknown code or number"}
    pending = next(
        (r for r in guardian.requests(g["user_id"]) if r["status"] in ("pending", "expired")), None
    )
    kind = pending["kind"] if pending else "account"
    guardian.decide(g["user_id"], kind, yes, via="text")
    p, _ = _child(g["user_id"])
    first = _first(p["display_name"])
    thanks = (
        f"Thank you. {first}'s account is approved. You can change this any time at {guardian.link(code)}"
        if yes and kind == "account"
        else f"Thank you. We've saved your answer. You can change it any time at {guardian.link(code)}"
    )
    sms.sender().send(g["phone"], thanks, user_id=g["user_id"])
    log.info("guardian.decided", user_id=g["user_id"], kind=kind, yes=yes, via="text")
    return {"ok": True, "kind": kind, "yes": yes}
