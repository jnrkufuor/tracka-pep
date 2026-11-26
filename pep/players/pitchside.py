"""
Pitchside: the Feed, weekly challenges, and places to play near you.

    Feed         clips players chose to post. "For you" puts players your age
                 and from your region first; "Following" is the players you
                 follow. Respect (a like), save, follow, report, block.
    Challenges   one measured challenge a week (a Tracka drill, so the result
                 is a number Pep measured, and it counts on Me) plus a few just
                 for fun. Attempts stay private unless you post them.
    Near you     pitches players add in their region. A pitch shows to others
                 once 2 other players confirm it (crowd-sourcing with a check,
                 so one person can't fill the map with made-up pitches).

Safety rules this module keeps (and tests check, tests/test_pitchside.py):
  - Pep never appears on other players' clips: feed items carry no review,
    no tips, no scores. Pep's words are for the player who filmed the clip.
  - No messages. Players can follow and give respect, nothing more.
  - Under 18: posting needs the guardian's `post` yes and showing up in
    search needs `search` (guardian.py). Checked every time, so a guardian
    taking it back hides the posts at once.
  - Others see the shirt name, position, age group and region. Never the
    full name or town.
  - Blocking hides both players from each other. Three reports hide a post
    until someone reviews it (moderation tooling is a TODO).
"""

from __future__ import annotations

import json
import uuid
from datetime import UTC, date, datetime, timedelta
from functools import cache
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    String,
    Table,
    delete,
    func,
    insert,
    select,
    update,
)

from .. import db
from ..scoring.norms import age_band, standing
from ..storage import storage
from . import auth, card, details, guardian, store
from .skill_areas import AGE_LABEL, band_for

DATA = Path(__file__).resolve().parent.parent / "data" / "challenges.json"
REPORTS_TO_HIDE = 3
CONFIRMS_NEEDED = 2
PAGE = 20

posts = Table(
    "posts",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("video_id", String(36), ForeignKey("videos.id", ondelete="CASCADE"), nullable=False, unique=True),
    Column("caption", String(200), nullable=False, default=""),
    Column("challenge_id", String(40)),
    Column("hidden", Boolean, nullable=False, default=False),  # hidden after reports, until reviewed
    Column("created_at", DateTime(timezone=True), nullable=False, index=True),
)

respect = Table(
    "respect",
    db.metadata,
    Column("post_id", String(36), ForeignKey("posts.id", ondelete="CASCADE"), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

saves = Table(
    "saves",
    db.metadata,
    Column("post_id", String(36), ForeignKey("posts.id", ondelete="CASCADE"), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
)

follows = Table(
    "follows",
    db.metadata,
    Column("follower_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("followee_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

blocks = Table(
    "blocks",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("blocked_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
)

reports = Table(
    "reports",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
    Column("post_id", String(36), ForeignKey("posts.id", ondelete="CASCADE")),
    Column("reason", String(40), nullable=False),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

challenge_attempts = Table(
    "challenge_attempts",
    db.metadata,
    Column("video_id", String(36), ForeignKey("videos.id", ondelete="CASCADE"), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("challenge_id", String(40), nullable=False, index=True),
    Column("week", String(8), nullable=False),  # ISO week, "2026-W48"
    Column("created_at", DateTime(timezone=True), nullable=False),
)

pitches = Table(
    "pitches",
    db.metadata,
    Column("id", String(36), primary_key=True),
    Column("name", String(80), nullable=False),
    Column("surface", String(12), nullable=False),  # grass | astro | dirt | sand | indoor
    Column("size", String(12), nullable=False),  # 5-a-side | 7-a-side | full size
    Column("town", String(60), nullable=False),
    Column("region", String(40), nullable=False, index=True),
    Column("added_by", String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
    Column("created_at", DateTime(timezone=True), nullable=False),
)

pitch_confirms = Table(
    "pitch_confirms",
    db.metadata,
    Column("pitch_id", String(36), ForeignKey("pitches.id", ondelete="CASCADE"), primary_key=True),
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
)


def now() -> datetime:
    return datetime.now(UTC)


def week_key(d: date | None = None) -> str:
    y, w, _ = (d or date.today()).isocalendar()
    return f"{y}-W{w:02d}"


@cache
def catalogue() -> dict:
    return json.loads(DATA.read_text())


def this_week(d: date | None = None) -> dict:
    weekly = catalogue()["weekly"]
    return weekly[(d or date.today()).isocalendar()[1] % len(weekly)]


def challenge(cid: str) -> tuple[str, dict] | None:
    for kind in ("weekly", "fun"):
        for c in catalogue()[kind]:
            if c["id"] == cid:
                return kind, c
    return None


def _rows(q) -> list[dict]:
    with db.engine().connect() as c:
        return [dict(r._mapping) for r in c.execute(q)]


def _age(p: dict) -> int | None:
    return store.age_on(p["birth_date"])


def can_post(uid: str) -> bool:
    """Guardian's yes for under-18s, and not paused by moderation (moderation.py)."""
    from .moderation import on_hold

    p = store.get_profile(uid)
    return guardian.allowed(uid, "post", _age(p), p["guardian_consent"]) and not on_hold(uid)


def findable(uid: str) -> bool:
    """Shows up in search only if they chose to (and, under 18, their guardian agreed)."""
    p = store.get_profile(uid)
    return bool(p["settings"].get("findable")) and guardian.allowed(
        uid, "search", _age(p), p["guardian_consent"]
    )


def blocked_between(uid: str) -> set[str]:
    rows = _rows(select(blocks).where((blocks.c.user_id == uid) | (blocks.c.blocked_id == uid)))
    return {r["blocked_id"] if r["user_id"] == uid else r["user_id"] for r in rows}


def author(uid: str) -> dict:
    """How other players see someone: never the full name or town."""
    p = store.get_profile(uid)
    d = details.get(uid)
    age = _age(p)
    shirt = card.shirt_name(p, d)
    pos = (p["positions"] or [None])[0]
    return {
        "id": uid,
        "shirtName": shirt,
        "initials": card._initials(shirt, p["display_name"]),
        "position": pos,
        "positionName": card.POSITION_NAMES.get(pos or "", None),
        "ageGroup": AGE_LABEL[age_band(age)] if age is not None else None,
        "region": p["region"],
        "under18": age is not None and age < 18,
    }


# ---------------------------------------------------------------- posts and the feed


def _link(key: str, base: str) -> str:
    u = storage().url(key)
    return base.rstrip("/") + u if u.startswith("/") else u


def _post_views(rows: list[dict], viewer: str, base: str) -> list[dict]:
    if not rows:
        return []
    ids = [r["id"] for r in rows]
    counts = {
        r["post_id"]: r["n"]
        for r in _rows(
            select(respect.c.post_id, func.count().label("n"))
            .where(respect.c.post_id.in_(ids))
            .group_by(respect.c.post_id)
        )
    }
    mine = {
        r["post_id"]
        for r in _rows(
            select(respect.c.post_id).where(respect.c.post_id.in_(ids), respect.c.user_id == viewer)
        )
    }
    saved = {
        r["post_id"]
        for r in _rows(select(saves.c.post_id).where(saves.c.post_id.in_(ids), saves.c.user_id == viewer))
    }
    following = {
        r["followee_id"] for r in _rows(select(follows.c.followee_id).where(follows.c.follower_id == viewer))
    }
    vids = {
        r["id"]: r
        for r in _rows(
            select(store.videos.c.id, store.videos.c.video_key, db.jobs.c.thumb_key)
            .select_from(store.videos.outerjoin(db.jobs, store.videos.c.job_id == db.jobs.c.id))
            .where(store.videos.c.id.in_([r["video_id"] for r in rows]))
        )
    }
    authors: dict[str, dict] = {}
    out = []
    for r in rows:
        v = vids.get(r["video_id"])
        if v is None:
            continue
        a = authors.setdefault(r["user_id"], author(r["user_id"]))
        ch = challenge(r["challenge_id"]) if r["challenge_id"] else None
        out.append(
            {
                "id": r["id"],
                "author": a | {"following": r["user_id"] in following},
                "caption": r["caption"],
                "challenge": ch[1]["name"] if ch else None,
                "videoUrl": _link(v["video_key"], base),
                "thumbnailUrl": _link(v["thumb_key"], base) if v.get("thumb_key") else None,
                "createdAt": guardian._aware(r["created_at"]).isoformat(),  # type: ignore[union-attr]
                "respect": counts.get(r["id"], 0),
                "respected": r["id"] in mine,
                "saved": r["id"] in saved,
                "mine": r["user_id"] == viewer,
                # Never Pep's review, tips or numbers here: Pep is only for the player who filmed it.
            }
        )
    return out


def feed(viewer: str, tab: str, base: str, before: str | None = None) -> list[dict]:
    q = select(posts).where(posts.c.hidden.is_(False)).order_by(posts.c.created_at.desc()).limit(200)
    if before:
        q = q.where(posts.c.created_at < datetime.fromisoformat(before))
    rows = _rows(q)
    hide = blocked_between(viewer)
    reported = {r["post_id"] for r in _rows(select(reports.c.post_id).where(reports.c.user_id == viewer))}
    rows = [r for r in rows if r["user_id"] not in hide and r["id"] not in reported]
    allowed = {u: can_post(u) for u in {r["user_id"] for r in rows}}  # guardian may have taken it back
    rows = [r for r in rows if allowed[r["user_id"]]]
    if tab == "following":
        mine = {
            r["followee_id"]
            for r in _rows(select(follows.c.followee_id).where(follows.c.follower_id == viewer))
        }
        rows = [r for r in rows if r["user_id"] in mine]
    else:  # for you: players your age and region first, newest first within each
        me = store.get_profile(viewer)
        band, region = age_band(_age(me)), me["region"]
        profiles = {u: store.get_profile(u) for u in {r["user_id"] for r in rows}}

        def rank(r: dict) -> int:
            p = profiles[r["user_id"]]
            return (age_band(_age(p)) != band) + (p["region"] != region)

        rows.sort(key=rank)  # stable: keeps newest-first inside each rank
    return _post_views(rows[:PAGE], viewer, base)


# ---------------------------------------------------------------- challenges


def _best(values: list[float], lower: bool) -> float | None:
    return (min(values) if lower else max(values)) if values else None


def challenges_view(uid: str) -> dict:
    p = store.get_profile(uid)
    age, sex = _age(p), p["sex"]
    wk = week_key()
    cur = this_week()
    attempts = _rows(select(challenge_attempts).where(challenge_attempts.c.user_id == uid))
    vids = {v["id"]: v for v in store.list_videos(uid)}

    def values(cid: str, metric: str, week: str | None = None) -> list[float]:
        out = []
        for a in attempts:
            if a["challenge_id"] == cid and (week is None or a["week"] == week):
                m = ((vids.get(a["video_id"]) or {}).get("result") or {}).get("metrics") or {}
                if m.get(metric) is not None:
                    out.append(float(m[metric]))
        return out

    def band(metric: str, x: float | None) -> str | None:
        st = standing(metric, x, age, sex) if x is not None else None
        return card.BAND_WORDS[band_for(st.percentile)] if st else None

    def show(x: float | None, unit: str) -> str | None:
        return None if x is None else (f"{x:.1f} s" if unit == "s" else f"{x:.0f}")

    players_in = _rows(
        select(func.count(func.distinct(challenge_attempts.c.user_id)).label("n")).where(
            challenge_attempts.c.challenge_id == cur["id"], challenge_attempts.c.week == wk
        )
    )[0]["n"]
    best = _best(values(cur["id"], cur["metric"], wk), cur["lower"])
    fun_counts = {
        r["challenge_id"]: r["n"]
        for r in _rows(
            select(
                challenge_attempts.c.challenge_id,
                func.count(func.distinct(challenge_attempts.c.user_id)).label("n"),
            ).group_by(challenge_attempts.c.challenge_id)
        )
    }
    past = []
    for c in catalogue()["weekly"]:
        b = _best(values(c["id"], c["metric"]), c["lower"])
        if b is not None and not (c["id"] == cur["id"] and not values(c["id"], c["metric"], None)):
            past.append(
                {
                    "id": c["id"],
                    "name": c["short"],
                    "group": c["group"],
                    "best": show(b, c["unit"]),
                    "band": band(c["metric"], b),
                }
            )
    end = date.today() + timedelta(days=6 - date.today().weekday())
    return {
        "thisWeek": {
            "id": cur["id"],
            "name": cur["name"],
            "group": cur["group"],
            "how": cur["how"],
            "steps": cur["steps"],
            "drill": cur["drill"],
            "endsOn": end.isoformat(),
            "best": show(best, cur["unit"]),
            "band": band(cur["metric"], best),
            "tries": len([a for a in attempts if a["challenge_id"] == cur["id"] and a["week"] == wk]),
            "playersIn": players_in,
        },
        "fun": [c | {"playersIn": fun_counts.get(c["id"], 0)} for c in catalogue()["fun"]],
        "past": past,
        "comparedWith": f"{AGE_LABEL[age_band(age)]} players",
    }


def record_attempt(uid: str, video_id: str, cid: str) -> None:
    with db.engine().begin() as c:
        c.execute(
            insert(challenge_attempts).values(
                video_id=video_id, user_id=uid, challenge_id=cid, week=week_key(), created_at=now()
            )
        )


# ---------------------------------------------------------------- pitches


def pitches_view(uid: str) -> dict:
    p = store.get_profile(uid)
    region = p["region"]
    rows = (
        _rows(select(pitches).where(pitches.c.region == region).order_by(pitches.c.created_at))
        if region
        else []
    )
    confirms = (
        _rows(select(pitch_confirms).where(pitch_confirms.c.pitch_id.in_([r["id"] for r in rows])))
        if rows
        else []
    )
    out = []
    for r in rows:
        by = {c["user_id"] for c in confirms if c["pitch_id"] == r["id"]} - {r["added_by"]}
        confirmed = len(by) >= CONFIRMS_NEEDED
        out.append(
            {
                "id": r["id"],
                "name": r["name"],
                "surface": r["surface"],
                "size": r["size"],
                "town": r["town"],
                "confirmations": len(by),
                "confirmed": confirmed,
                "needs": max(0, CONFIRMS_NEEDED - len(by)),
                "confirmedByMe": uid in by,
                "addedByMe": r["added_by"] == uid,
            }
        )
    out.sort(key=lambda x: (not x["confirmed"], -x["confirmations"]))
    return {"region": region, "pitches": out}


# ---------------------------------------------------------------- routes

router = APIRouter(tags=["player app: pitchside"])


class Body(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


@router.get("/feed")
def get_feed(
    req: Request,
    tab: Literal["for_you", "following"] = "for_you",
    before: str | None = None,
    user: dict = Depends(auth.current_user),
) -> dict:
    return {"posts": feed(user["id"], tab, str(req.base_url), before), "canPost": can_post(user["id"])}


class PostIn(Body):
    video_id: str
    caption: str = Field("", max_length=200)


@router.post("/posts", status_code=201)
def create_post(body: PostIn, req: Request, user: dict = Depends(auth.current_user)) -> dict:
    if not can_post(user["id"]):
        raise HTTPException(403, "Your guardian needs to say yes before you can post clips.")
    v = store.get_video(user["id"], body.video_id)
    if v is None:
        raise HTTPException(404, "Video not found.")
    if v.get("status") != "READY":
        raise HTTPException(409, "Wait until Pep has watched this clip.")
    if _rows(select(posts.c.id).where(posts.c.video_id == body.video_id)):
        raise HTTPException(409, "You've already posted this clip.")
    att = _rows(
        select(challenge_attempts.c.challenge_id).where(challenge_attempts.c.video_id == body.video_id)
    )
    pid = str(uuid.uuid4())
    with db.engine().begin() as c:
        c.execute(
            insert(posts).values(
                id=pid,
                user_id=user["id"],
                video_id=body.video_id,
                caption=body.caption.strip(),
                challenge_id=att[0]["challenge_id"] if att else None,
                hidden=False,
                created_at=now(),
            )
        )
    return _post_views(_rows(select(posts).where(posts.c.id == pid)), user["id"], str(req.base_url))[0]


def _post(pid: str) -> dict:
    rows = _rows(select(posts).where(posts.c.id == pid))
    if not rows:
        raise HTTPException(404, "Post not found.")
    return rows[0]


@router.delete("/posts/{pid}", status_code=204)
def delete_post(pid: str, user: dict = Depends(auth.current_user)) -> None:
    if _post(pid)["user_id"] != user["id"]:
        raise HTTPException(404, "Post not found.")
    with db.engine().begin() as c:
        for t in (respect, saves, reports):
            c.execute(delete(t).where(t.c.post_id == pid))
        c.execute(delete(posts).where(posts.c.id == pid))


def _toggle(table: Table, pid: str, uid: str, on: bool, **extra) -> None:
    _post(pid)
    with db.engine().begin() as c:
        c.execute(delete(table).where(table.c.post_id == pid, table.c.user_id == uid))
        if on:
            c.execute(insert(table).values(post_id=pid, user_id=uid, **extra))


@router.put("/posts/{pid}/respect", status_code=204)
def give_respect(pid: str, user: dict = Depends(auth.current_user)) -> None:
    already = bool(_rows(select(respect).where(respect.c.post_id == pid, respect.c.user_id == user["id"])))
    _toggle(respect, pid, user["id"], True, created_at=now())
    p = _post(pid)
    if not already and p["user_id"] != user["id"]:
        from . import notifications

        n = _rows(select(func.count().label("n")).where(respect.c.post_id == pid))[0]["n"]
        notifications.respect_given(p["user_id"], pid, author(user["id"])["shirtName"], n)


@router.delete("/posts/{pid}/respect", status_code=204)
def take_respect(pid: str, user: dict = Depends(auth.current_user)) -> None:
    _toggle(respect, pid, user["id"], False)


@router.put("/posts/{pid}/save", status_code=204)
def save_post(pid: str, user: dict = Depends(auth.current_user)) -> None:
    _toggle(saves, pid, user["id"], True)


@router.delete("/posts/{pid}/save", status_code=204)
def unsave_post(pid: str, user: dict = Depends(auth.current_user)) -> None:
    _toggle(saves, pid, user["id"], False)


class ReportIn(Body):
    reason: Literal["unsafe", "bullying", "not_football", "fake", "other"]


@router.post("/posts/{pid}/report", status_code=202)
def report(pid: str, body: ReportIn, user: dict = Depends(auth.current_user)) -> dict:
    """Hides the post for the person reporting; enough reports hide it for everyone until reviewed."""
    _post(pid)
    with db.engine().begin() as c:
        c.execute(
            insert(reports).values(
                id=str(uuid.uuid4()), user_id=user["id"], post_id=pid, reason=body.reason, created_at=now()
            )
        )
        n = c.execute(
            select(func.count(func.distinct(reports.c.user_id))).where(reports.c.post_id == pid)
        ).scalar_one()
        if n >= REPORTS_TO_HIDE:
            c.execute(update(posts).where(posts.c.id == pid).values(hidden=True))
    return {"ok": True}


@router.get("/players")
def search(q: str = "", user: dict = Depends(auth.current_user)) -> dict:
    """Only players who chose to be seen (and, under 18, whose guardian agreed)."""
    me = store.get_profile(user["id"])
    hide = blocked_between(user["id"]) | {user["id"]}
    ids = [r["user_id"] for r in _rows(select(store.profiles.c.user_id))]
    found, near = [], []
    following = {
        r["followee_id"]
        for r in _rows(select(follows.c.followee_id).where(follows.c.follower_id == user["id"]))
    }
    for uid in ids:
        if uid in hide or not findable(uid):
            continue
        a = author(uid) | {"following": uid in following}
        if q.strip() and q.strip().lower() in a["shirtName"].lower():
            found.append(a)
        p = store.get_profile(uid)
        if p["region"] == me["region"] and age_band(_age(p)) == age_band(_age(me)):
            near.append(a)
    return {"players": found[:30], "nearYou": near[:10]}


@router.get("/players/{uid}")
def player(uid: str, req: Request, user: dict = Depends(auth.current_user)) -> dict:
    if uid in blocked_between(user["id"]) or store.user_by_id(uid) is None:
        raise HTTPException(404, "Player not found.")
    rows = (
        _rows(
            select(posts)
            .where(posts.c.user_id == uid, posts.c.hidden.is_(False))
            .order_by(posts.c.created_at.desc())
        )
        if can_post(uid)
        else []
    )
    if not rows and not findable(uid) and uid != user["id"]:
        raise HTTPException(404, "Player not found.")
    post_ids = [r["id"] for r in rows]
    total_respect = (
        _rows(select(func.count().label("n")).where(respect.c.post_id.in_(post_ids)))[0]["n"]
        if post_ids
        else 0
    )
    followers = _rows(select(func.count().label("n")).where(follows.c.followee_id == uid))[0]["n"]
    following = bool(
        _rows(select(follows).where(follows.c.follower_id == user["id"], follows.c.followee_id == uid))
    )
    d = details.get(uid)
    return {
        "player": author(uid)
        | {"following": following, "style": d["style"], "level": card.LEVEL_WORDS.get(d["level"] or "")},
        "clips": len(rows),
        "respect": total_respect,
        "followers": followers,
        "posts": _post_views(rows[:30], user["id"], str(req.base_url)),
    }


@router.put("/players/{uid}/follow", status_code=204)
def follow(uid: str, user: dict = Depends(auth.current_user)) -> None:
    if uid == user["id"] or store.user_by_id(uid) is None or uid in blocked_between(user["id"]):
        raise HTTPException(404, "Player not found.")
    with db.engine().begin() as c:
        c.execute(delete(follows).where(follows.c.follower_id == user["id"], follows.c.followee_id == uid))
        c.execute(insert(follows).values(follower_id=user["id"], followee_id=uid, created_at=now()))


@router.delete("/players/{uid}/follow", status_code=204)
def unfollow(uid: str, user: dict = Depends(auth.current_user)) -> None:
    with db.engine().begin() as c:
        c.execute(delete(follows).where(follows.c.follower_id == user["id"], follows.c.followee_id == uid))


@router.put("/players/{uid}/block", status_code=204)
def block(uid: str, user: dict = Depends(auth.current_user)) -> None:
    """Hides both players from each other and removes any follow either way."""
    if uid == user["id"] or store.user_by_id(uid) is None:
        raise HTTPException(404, "Player not found.")
    with db.engine().begin() as c:
        c.execute(delete(blocks).where(blocks.c.user_id == user["id"], blocks.c.blocked_id == uid))
        c.execute(insert(blocks).values(user_id=user["id"], blocked_id=uid))
        c.execute(
            delete(follows).where(
                ((follows.c.follower_id == user["id"]) & (follows.c.followee_id == uid))
                | ((follows.c.follower_id == uid) & (follows.c.followee_id == user["id"]))
            )
        )


@router.delete("/players/{uid}/block", status_code=204)
def unblock(uid: str, user: dict = Depends(auth.current_user)) -> None:
    with db.engine().begin() as c:
        c.execute(delete(blocks).where(blocks.c.user_id == user["id"], blocks.c.blocked_id == uid))


@router.get("/challenges")
def get_challenges(user: dict = Depends(auth.current_user)) -> dict:
    return challenges_view(user["id"])


@router.get("/pitches")
def get_pitches(user: dict = Depends(auth.current_user)) -> dict:
    return pitches_view(user["id"])


class PitchIn(Body):
    name: str = Field(min_length=3, max_length=80)
    surface: Literal["grass", "astro", "dirt", "sand", "indoor"]
    size: Literal["5-a-side", "7-a-side", "full size"]
    town: str = Field(min_length=2, max_length=60)


@router.post("/pitches", status_code=201)
def add_pitch(body: PitchIn, user: dict = Depends(auth.current_user)) -> dict:
    p = store.get_profile(user["id"])
    if not p["region"]:
        raise HTTPException(409, "Add your region first.")
    with db.engine().begin() as c:
        c.execute(
            insert(pitches).values(
                id=str(uuid.uuid4()),
                name=body.name.strip(),
                surface=body.surface,
                size=body.size,
                town=body.town.strip(),
                region=p["region"],
                added_by=user["id"],
                created_at=now(),
            )
        )
    return pitches_view(user["id"])


@router.put("/pitches/{pid}/confirm", status_code=200)
def confirm_pitch(pid: str, user: dict = Depends(auth.current_user)) -> dict:
    rows = _rows(select(pitches).where(pitches.c.id == pid))
    if not rows or rows[0]["region"] != store.get_profile(user["id"])["region"]:
        raise HTTPException(404, "Pitch not found.")
    if rows[0]["added_by"] == user["id"]:
        raise HTTPException(409, "Other players need to confirm a pitch you added.")
    with db.engine().begin() as c:
        c.execute(
            delete(pitch_confirms).where(
                pitch_confirms.c.pitch_id == pid, pitch_confirms.c.user_id == user["id"]
            )
        )
        c.execute(insert(pitch_confirms).values(pitch_id=pid, user_id=user["id"]))
    return pitches_view(user["id"])
