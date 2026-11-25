"""
The player card and who can see it (canvas: Me › Share your card, What
others see, Who can see your profile).

A player's profile is PRIVATE by default. They can make a share link
(tracka.app/c/k7Qm2xPa) and send it to a coach, a scout or friends. Anyone
with the link sees the card; nobody else does. The player can turn the link
off, or make a new one so the old one stops working.

What the card shows is decided here, in one place, and it is deliberately
small (data minimisation, handbook chapter 12):

    shown          shirt name and number, positions, stronger foot, region,
                   level, age group, style, measured skill areas (bands, never
                   a 0-100 score), timed bests, the clips the player picked
    never shown    full name, date of birth, town, school, email, phone,
                   anything Pep wrote about a clip, any way to message them

Under 18: sharing needs the guardian's yes (guardian.py, `share_card`). If
the guardian takes it back, the link stops working at once: the permission
is checked on every view, not copied when the link was made.

The link token is random and long (10 characters from 64 = 60 bits), so
links can't be guessed by counting. Words to know: *capability URL*.
"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel
from sqlalchemy import (
    JSON,
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Table,
    delete,
    insert,
    select,
    update,
)

from .. import db
from ..config import settings
from ..scoring.norms import age_band
from ..storage import storage
from . import auth, details, guardian, store
from .skill_areas import AGE_LABEL, skill_areas

share_links = Table(
    "share_links",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("token", String(16), nullable=False, unique=True, index=True),
    Column("on", Boolean, nullable=False, default=False),
    Column("show", JSON, nullable=False, default=dict),  # {"bests": true, "skills": true, "clips": true}
    Column("updated_at", DateTime(timezone=True), nullable=False),
)

portfolio = Table(
    "portfolio",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("video_id", String(36), ForeignKey("videos.id", ondelete="CASCADE"), primary_key=True),
    Column("position", Integer, nullable=False, default=0),
)

MAX_CLIPS = 6
DEFAULT_SHOW = {"bests": True, "skills": True, "clips": True}

POSITION_NAMES = {
    "GK": "Goalkeeper",
    "CB": "Centre-back",
    "LB": "Left-back",
    "RB": "Right-back",
    "LWB": "Left wing-back",
    "RWB": "Right wing-back",
    "CDM": "Defensive midfielder",
    "CM": "Central midfielder",
    "CAM": "Attacking midfielder",
    "LM": "Left midfielder",
    "RM": "Right midfielder",
    "LW": "Left winger",
    "RW": "Right winger",
    "CF": "Centre-forward",
    "ST": "Striker",
}
BAND_WORDS = {
    "below": "Below average",
    "average": "Average",
    "above": "Above average",
    "strong": "Strong",
    "standout": "Standout",
}
LEVEL_WORDS = {
    "fun": "Plays for fun",
    "amateur": "Amateur league",
    "school": "School team",
    "club": "Local club",
    "academy": "Academy",
    "pro": "Semi-pro or pro",
}
# Timed tests and counts worth showing as bests: metric → (label, unit, lower is better).
BESTS = {
    "sprint_30m_s": ("30 m sprint", "s", True),
    "split_10m_s": ("10 m split", "s", True),
    "agility_5105_s": ("5-10-5 shuttle", "s", True),
    "juggles_best": ("Juggles in a row", "", False),
    "wall_passes_30s": ("Wall passes in 30 s", "", False),
}


def now() -> datetime:
    return datetime.now(UTC)


# ---------------------------------------------------------------- data


def get_link(uid: str) -> dict | None:
    with db.engine().connect() as c:
        row = c.execute(select(share_links).where(share_links.c.user_id == uid)).first()
    return dict(row._mapping) if row else None


def by_token(token: str) -> dict | None:
    with db.engine().connect() as c:
        row = c.execute(select(share_links).where(share_links.c.token == token)).first()
    return dict(row._mapping) if row else None


def _token() -> str:
    return secrets.token_urlsafe(8)[:10]


def set_link(uid: str, on: bool, new_token: bool = False) -> dict:
    link = get_link(uid)
    with db.engine().begin() as c:
        if link is None:
            c.execute(
                insert(share_links).values(
                    user_id=uid, token=_token(), on=on, show=DEFAULT_SHOW, updated_at=now()
                )
            )
        else:
            values: dict[str, Any] = {"on": on, "updated_at": now()}
            if new_token:
                values["token"] = _token()
            c.execute(update(share_links).where(share_links.c.user_id == uid).values(**values))
    return get_link(uid)  # type: ignore[return-value]


def set_show(uid: str, show: dict[str, bool]) -> None:
    link = get_link(uid) or set_link(uid, False)
    with db.engine().begin() as c:
        c.execute(
            update(share_links)
            .where(share_links.c.user_id == uid)
            .values(show={**DEFAULT_SHOW, **(link["show"] or {}), **show}, updated_at=now())
        )


def clips(uid: str) -> list[str]:
    with db.engine().connect() as c:
        return [
            r.video_id
            for r in c.execute(
                select(portfolio).where(portfolio.c.user_id == uid).order_by(portfolio.c.position)
            )
        ]


def set_clips(uid: str, video_ids: list[str]) -> None:
    mine = {v["id"]: v for v in store.list_videos(uid)}
    keep = [v for v in dict.fromkeys(video_ids) if v in mine and mine[v].get("status") == "READY"][:MAX_CLIPS]
    with db.engine().begin() as c:
        c.execute(delete(portfolio).where(portfolio.c.user_id == uid))
        for i, vid in enumerate(keep):
            c.execute(insert(portfolio).values(user_id=uid, video_id=vid, position=i))


def can_share(uid: str) -> bool:
    p = store.get_profile(uid)
    return guardian.allowed(uid, "share_card", store.age_on(p["birth_date"]), p["guardian_consent"])


def _initials(shirt: str | None, display: str) -> str:
    words = [w for w in (display or shirt or "").replace(".", " ").split() if w]
    return "".join(w[0] for w in words[:2]).upper() or "?"


def card_data(uid: str, base: str = "") -> dict:
    """The public card: only what's listed in the module docstring, nothing else."""
    p = store.get_profile(uid)
    d = details.get(uid)
    age = store.age_on(p["birth_date"])
    link = get_link(uid)
    show = {**DEFAULT_SHOW, **((link or {}).get("show") or {})}
    videos = store.list_videos(uid)
    positions = p["positions"] or []
    surname = (p["display_name"] or "").split(" ")[-1] if p["display_name"] else ""
    first = (p["display_name"] or " ").strip()[:1]
    shirt = d["shirt_name"] or (f"{first}. {surname}".upper() if surname else "")

    def link_for(key: str) -> str:
        u = storage().url(key)
        return base.rstrip("/") + u if u.startswith("/") else u

    areas = skill_areas(videos, positions, age, p["sex"])
    measured = [i for g in areas["groups"] for i in g["items"] if i["state"] == "measured"]
    measured.sort(key=lambda i: not i["key"])
    best_areas = [i["name"] for i in measured if i["band"] in ("standout", "strong", "above")][:3]

    bests = []
    for metric, (label, unit, lower) in BESTS.items():
        vals = [
            v["result"]["metrics"][metric]
            for v in videos
            if ((v.get("result") or {}).get("metrics") or {}).get(metric) is not None
        ]
        if vals:
            x = min(vals) if lower else max(vals)
            bests.append({"label": label, "value": f"{x:.2f}" if unit == "s" else f"{x:.0f}", "unit": unit})

    by_id = {v["id"]: v for v in videos}
    portfolio_clips = []
    for vid in clips(uid):
        v = by_id.get(vid)
        if v is None or v.get("status") != "READY":
            continue
        portfolio_clips.append(
            {
                "id": vid,
                "title": v.get("title") or "",
                "clipType": v["clip_type"],
                "date": v["created_at"].date().isoformat(),
                "videoUrl": link_for(v["video_key"]),
                "thumbnailUrl": link_for(v["thumb_key"]) if v.get("thumb_key") else None,
            }
        )

    return {
        "shirtName": shirt,
        "shirtNumber": d["shirt_number"],
        "initials": _initials(shirt, p["display_name"]),
        "positions": positions,
        "positionName": POSITION_NAMES.get(positions[0], positions[0]) if positions else None,
        "foot": p["foot"],
        "region": p["region"],
        "level": LEVEL_WORDS.get(d["level"] or ""),
        "ageGroup": AGE_LABEL[age_band(age)] if age is not None else None,
        "style": d["style"],
        "pepSees": best_areas,
        "bests": bests if show["bests"] else [],
        "skills": [
            {
                "name": i["name"],
                "band": BAND_WORDS.get(i["band"] or "", ""),
                "average": i["average"],
                "confidence": i["confidence"],
                "trend": i["trend"],
                "key": i["key"],
            }
            for i in measured[:6]
        ]
        if show["skills"]
        else [],
        "comparedWith": areas["comparedWith"],
        "clips": portfolio_clips if show["clips"] else [],
        "under18": age is not None and age < 18,
    }


# ---------------------------------------------------------------- routes

router = APIRouter(tags=["player app: card"])


class Body(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


def _url(req: Request, token: str) -> str:
    base = (settings().web_url or settings().public_url).rstrip("/")
    return f"{base}/c/{token}"


def _view(uid: str, req: Request) -> dict:
    link = get_link(uid)
    allowed = can_share(uid)
    return {
        "link": {
            "on": bool(link and link["on"] and allowed),
            "url": _url(req, link["token"]) if link else None,
        },
        "show": {**DEFAULT_SHOW, **((link or {}).get("show") or {})},
        "portfolio": clips(uid),
        "canShare": allowed,
        "card": card_data(uid, str(req.base_url)),
    }


@router.get("/card")
def my_card(req: Request, user: dict = Depends(auth.current_user)) -> dict:
    """Your card as people with your link see it, plus the link and what's shown."""
    return _view(user["id"], req)


class LinkIn(Body):
    on: bool
    new_link: bool = False  # make a new link; the old one stops working


@router.put("/card/link")
def put_link(body: LinkIn, req: Request, user: dict = Depends(auth.current_user)) -> dict:
    if body.on and not can_share(user["id"]):
        raise HTTPException(403, "Your guardian needs to say yes before you can share your card.")
    set_link(user["id"], body.on, body.new_link)
    return _view(user["id"], req)


class CardIn(Body):
    show: dict[str, bool] | None = None
    portfolio: list[str] | None = Field(None, max_length=MAX_CLIPS)


@router.patch("/card")
def patch_card(body: CardIn, req: Request, user: dict = Depends(auth.current_user)) -> dict:
    if body.show is not None:
        set_show(user["id"], {k: v for k, v in body.show.items() if k in DEFAULT_SHOW})
    if body.portfolio is not None:
        set_clips(user["id"], body.portfolio)
    return _view(user["id"], req)


def public(token: str, base: str) -> dict:
    """The card behind a share link, or 404 if the link is off, unknown, or no longer allowed."""
    link = by_token(token)
    if link is None or not link["on"] or not can_share(link["user_id"]):
        raise HTTPException(404, "This card isn't shared any more.")
    return card_data(link["user_id"], base)


@router.get("/c/{token}")
def public_card(token: str, req: Request) -> dict:
    return public(token, str(req.base_url))
