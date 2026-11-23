"""
The player API: what the Tracka mobile and web app talk to.

    POST   /v1/auth/signup          create an account          → tokens
    POST   /v1/auth/login           email + password           → tokens
    POST   /v1/auth/refresh         refresh token              → new tokens (rotation)
    POST   /v1/auth/logout          revoke this session
    GET    /v1/me                   account + profile + settings
    PATCH  /v1/me                   update profile / settings
    DELETE /v1/me                   delete the account and every video (privacy)
    GET    /v1/meta                 positions, regions, drills (for the app's forms)
    GET    /v1/videos               the player's library, newest first
    POST   /v1/videos               upload a clip (multipart) → queued for Pep
    GET    /v1/videos/{id}          one clip + its analysis
    PATCH  /v1/videos/{id}          rename
    DELETE /v1/videos/{id}          delete
    GET    /v1/coach                the coach summary across all clips
    GET    /v1/opportunities        empty for now ("coming soon")

Versioned under /v1: once phones have the app installed you can't update
them all at once, so breaking changes go to /v2 while /v1 keeps working.
That's API VERSIONING, and mobile apps make it non-optional.

Every route below `Depends(current_user)` only sees the logged-in player's
own data: queries always filter by `user_id`. That's AUTHORISATION (what you
may do), as opposed to AUTHENTICATION (who you are).
"""

from __future__ import annotations

import json
import re
import tempfile
import uuid
from datetime import date
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel

from .. import db
from ..contracts import POSITIONS, AnalysisRequest, Calibration, Point
from ..drills.runner import drill_catalogue
from ..log import get_logger
from ..storage import storage
from . import auth, store
from .coach import summary

log = get_logger(__name__)
router = APIRouter(prefix="/v1", tags=["player app"])

MAX_UPLOAD_BYTES = 300 * 1024 * 1024
EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
GHANA_REGIONS = (
    "Ahafo",
    "Ashanti",
    "Bono",
    "Bono East",
    "Central",
    "Eastern",
    "Greater Accra",
    "North East",
    "Northern",
    "Oti",
    "Savannah",
    "Upper East",
    "Upper West",
    "Volta",
    "Western",
    "Western North",
)


class Body(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


# ---------------------------------------------------------------- auth


class Credentials(Body):
    email: str = Field(max_length=254)
    password: str = Field(min_length=8, max_length=200)


class RefreshIn(Body):
    refresh_token: str


@router.post("/auth/signup", status_code=201)
def signup(body: Credentials) -> dict:
    email = body.email.strip().lower()
    if not EMAIL.match(email):
        raise HTTPException(422, "That doesn't look like an email address.")
    if store.user_by_email(email):
        raise HTTPException(409, "There's already an account with this email. Log in instead.")
    user = store.create_user(email, auth.hash_password(body.password))
    log.info("player.signup", user_id=user["id"])
    return auth.issue_tokens(user)


@router.post("/auth/login")
def login(body: Credentials) -> dict:
    user = store.user_by_email(body.email.strip().lower())
    # Same message whether the email or the password was wrong: don't reveal which emails have accounts.
    if user is None or not auth.check_password(body.password, user["password_hash"]):
        raise HTTPException(401, "Wrong email or password.")
    return auth.issue_tokens(user)


@router.post("/auth/refresh")
def refresh(body: RefreshIn) -> dict:
    return auth.refresh(body.refresh_token)


@router.post("/auth/logout", status_code=204)
def logout(body: RefreshIn) -> None:
    claims = auth.decode(body.refresh_token, "refresh")
    store.revoke_session(claims["sid"])


# ---------------------------------------------------------------- profile


class SettingsIn(Body):
    units: Literal["kmh", "mph"] | None = None
    coach_notes: bool | None = None
    notify_when_ready: bool | None = None
    share_with_scouts: bool | None = None
    # Design-system settings (added Nov 2026; new fields only, so installed apps keep working).
    main_colour: Literal["volt", "blue", "pink", "ice", "aqua"] | None = None
    reduce_motion: bool | None = None
    upload_on_wifi_only: bool | None = None


class ProfileIn(Body):
    display_name: str | None = Field(None, max_length=80)
    birth_date: date | None = None
    sex: Literal["male", "female"] | None = None
    height_m: float | None = Field(None, ge=1.0, le=2.3)
    positions: list[str] | None = Field(None, max_length=4)
    foot: Literal["left", "right", "both"] | None = None
    region: str | None = Field(None, max_length=40)
    club: str | None = Field(None, max_length=80)
    bio: str | None = Field(None, max_length=400)
    guardian_email: str | None = Field(None, max_length=254)
    guardian_consent: bool | None = None
    settings: SettingsIn | None = None


def _me(user: dict) -> dict:
    p = store.get_profile(user["id"])
    age = store.age_on(p["birth_date"])
    return {
        "id": user["id"],
        "email": user["email"],
        "role": user["role"],
        "profile": {
            "displayName": p["display_name"],
            "birthDate": p["birth_date"].isoformat() if p["birth_date"] else None,
            "age": age,
            "sex": p["sex"],
            "heightM": p["height_m"],
            "positions": p["positions"] or [],
            "foot": p["foot"],
            "region": p["region"],
            "club": p["club"],
            "bio": p["bio"],
            "guardianEmail": p["guardian_email"],
            "guardianConsent": p["guardian_consent"],
        },
        "settings": p["settings"],
        # The app shows onboarding until these are filled in.
        "profileComplete": bool(p["display_name"] and p["birth_date"] and p["positions"]),
        "needsGuardian": age is not None and age < 18 and not p["guardian_consent"],
    }


@router.get("/me")
def me(user: dict = Depends(auth.current_user)) -> dict:
    return _me(user)


@router.patch("/me")
def update_me(body: ProfileIn, user: dict = Depends(auth.current_user)) -> dict:
    values = body.model_dump(exclude_unset=True, exclude={"settings"})
    if "positions" in values:
        bad = [p for p in values["positions"] or [] if p not in POSITIONS]
        if bad:
            raise HTTPException(422, f"Unknown position: {', '.join(bad)}")
    if values.get("region") and values["region"] not in GHANA_REGIONS:
        raise HTTPException(422, "Pick a region from the list.")
    if values.get("guardian_email") and not EMAIL.match(values["guardian_email"]):
        raise HTTPException(422, "The guardian's email doesn't look right.")
    if body.settings is not None:
        current = store.get_profile(user["id"])["settings"]
        changes = {to_camel(k): v for k, v in body.settings.model_dump(exclude_unset=True).items()}
        values["settings"] = {**current, **changes}
    store.update_profile(user["id"], values)
    return _me(user)


@router.delete("/me", status_code=204)
def delete_me(user: dict = Depends(auth.current_user)) -> None:
    keys = store.delete_user(user["id"])
    for key in keys:
        try:
            storage().delete(key)
        except Exception as exc:  # keep going: the account is already gone
            log.warning("delete.storage_failed", key=key, error=str(exc))
    log.info("player.deleted", user_id=user["id"], files=len(keys))


@router.get("/meta")
def meta() -> dict:
    return {"positions": POSITIONS, "regions": GHANA_REGIONS, "drills": drill_catalogue()}


# ---------------------------------------------------------------- videos


class UploadMeta(Body):
    title: str = Field("", max_length=120)
    clip_type: Literal["match", "training", "drill", "highlight"] = "match"
    drill: str | None = None
    target: Point | None = None
    target_at_seconds: float = 0.0
    calibration: Calibration | None = None


def _video_view(v: dict, base: str, full: bool = False) -> dict:
    """base: this API's own address. Local-disk storage gives links like /files/...,
    which only work from another website (the app) once they're absolute."""

    def link(key: str) -> str:
        u = storage().url(key)
        return base.rstrip("/") + u if u.startswith("/") else u

    r = v.get("result") or {}
    view = {
        "id": v["id"],
        "title": v.get("title") or "",
        "clipType": v["clip_type"],
        "drill": v.get("drill"),
        "createdAt": v["created_at"].isoformat(),
        "status": v.get("status") or "QUEUED",
        "overallScore": r.get("overallScore"),
        "confidence": r.get("confidence"),
        "thumbnailUrl": link(v["thumb_key"]) if v.get("thumb_key") else None,
    }
    if full:
        view |= {
            "videoUrl": link(v["video_key"]),
            "overlayUrl": link(v["overlay_key"]) if v.get("overlay_key") else None,
            "error": r.get("error") or v.get("error"),
            "analysis": r if v.get("status") == "READY" else None,
        }
    return view


@router.get("/videos")
def my_videos(req: Request, user: dict = Depends(auth.current_user)) -> list[dict]:
    return [_video_view(v, str(req.base_url)) for v in store.list_videos(user["id"])]


@router.post("/videos", status_code=202)
async def upload(
    background: BackgroundTasks,
    video: UploadFile = File(...),
    meta: str = Form("{}"),
    user: dict = Depends(auth.current_user),
) -> dict:
    """Store the clip, queue it for Pep, and answer at once. The app polls GET /videos/{id}."""
    me_ = _me(user)
    if not me_["profileComplete"]:
        raise HTTPException(
            409, "Finish your profile first: Pep needs your age and positions to score you fairly."
        )
    if me_["needsGuardian"]:
        raise HTTPException(403, "Players under 18 need a parent or guardian's consent before uploading.")
    try:
        m = UploadMeta.model_validate(json.loads(meta or "{}"))
    except ValueError as exc:
        raise HTTPException(422, f"Bad clip details: {exc}") from None
    if m.clip_type == "drill" and m.drill not in drill_catalogue():
        raise HTTPException(422, "Pick which drill this is.")

    video_id = str(uuid.uuid4())
    suffix = Path(video.filename or "clip.mp4").suffix.lower() or ".mp4"
    key = f"players/{user['id']}/videos/{video_id}{suffix}"
    with tempfile.NamedTemporaryFile(suffix=suffix) as tmp:
        size = 0
        while chunk := await video.read(1 << 20):
            size += len(chunk)
            if size > MAX_UPLOAD_BYTES:
                raise HTTPException(413, "This clip is over 300 MB. Trim it or record at 720p.")
            tmp.write(chunk)
        tmp.flush()
        if size == 0:
            raise HTTPException(422, "The file is empty.")
        storage().put(key, Path(tmp.name), video.content_type or "video/mp4")

    p = me_["profile"]
    request = AnalysisRequest(
        analysis_id=video_id,
        video_url=key,
        positions=p["positions"],
        clip_type=m.clip_type,
        drill=m.drill if m.clip_type == "drill" else None,
        player_height_m=p["heightM"],
        age_years=p["age"],
        sex=p["sex"],
        target=m.target,
        target_at_seconds=m.target_at_seconds,
        calibration=m.calibration,
        player_label=p["displayName"],
        coach_notes=bool(me_["settings"].get("coachNotes", True)),
    )
    job = db.enqueue(request.to_wire(), source="app", video_key=key)
    store.add_video(user["id"], video_id, m.title or "", key, m.clip_type, request.drill, size, job["id"])

    from ..api.app import kick_workers

    background.add_task(kick_workers)
    log.info("player.upload", user_id=user["id"], video_id=video_id, bytes=size)
    return {"id": video_id, "status": "QUEUED"}


@router.get("/videos/{video_id}")
def one_video(video_id: str, req: Request, user: dict = Depends(auth.current_user)) -> dict:
    v = store.get_video(user["id"], video_id)
    if v is None:
        raise HTTPException(404, "Video not found.")
    return _video_view(v, str(req.base_url), full=True)


class RenameIn(Body):
    title: str = Field(max_length=120)


@router.patch("/videos/{video_id}")
def rename(video_id: str, body: RenameIn, req: Request, user: dict = Depends(auth.current_user)) -> dict:
    if not store.rename_video(user["id"], video_id, body.title.strip()):
        raise HTTPException(404, "Video not found.")
    return one_video(video_id, req, user)


@router.delete("/videos/{video_id}", status_code=204)
def remove(video_id: str, user: dict = Depends(auth.current_user)) -> None:
    keys = store.delete_video(user["id"], video_id)
    if not keys:
        raise HTTPException(404, "Video not found.")
    for key in keys:
        try:
            storage().delete(key)
        except Exception as exc:
            log.warning("delete.storage_failed", key=key, error=str(exc))


# ---------------------------------------------------------------- coach + opportunities


@router.get("/coach")
def coach(user: dict = Depends(auth.current_user)) -> dict:
    return summary(store.list_videos(user["id"]), store.get_profile(user["id"])["positions"])


@router.get("/opportunities")
def opportunities(user: dict = Depends(auth.current_user)) -> dict:
    """Trials, academies and tournaments will appear here. Not built yet: the app shows 'coming soon'."""
    return {"comingSoon": True, "items": []}
