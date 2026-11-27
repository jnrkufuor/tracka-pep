"""
Your profile photo: PUT /v1/me/photo to set it, DELETE /v1/me/photo to remove it.

Concept: a photo is a file, so it lives in storage (R2 or the local folder),
not in the database. The database keeps only its KEY (the file's name in
storage) in a new table that points at `users` (CLAUDE.md: new tables, not
new columns). The app gets a short-lived signed link to show it.

Privacy, because most players are under 18:
- Only you see it, in your own app. It is not shown on Pitchside, in the
  feed or on the public card (that would need a guardian's yes first).
- Face and shoulders, no team badges (the app says so when you pick one).
- Deleting your account deletes the file too (store.delete_user collects
  every key, see `photo_key`).
See docs/handbook/02-designing-a-system.md (workbook) and 12-cost-privacy-next.md.
"""

from __future__ import annotations

import contextlib
import tempfile
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import Column, DateTime, ForeignKey, String, Table, delete, insert, select, update

from .. import db
from ..storage import storage
from . import auth

MAX_PHOTO_BYTES = 5 * 1024 * 1024
TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}

profile_photos = Table(
    "profile_photos",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("photo_key", String(255), nullable=False),
    Column("updated_at", DateTime(timezone=True), nullable=False),
)

router = APIRouter()


def photo_key(uid: str) -> str | None:
    with db.engine().connect() as c:
        row = c.execute(select(profile_photos.c.photo_key).where(profile_photos.c.user_id == uid)).first()
    return row[0] if row else None


def photo_url(uid: str) -> str | None:
    """A signed link to your photo for the next hour, or None."""
    key = photo_key(uid)
    if key is None:
        return None
    try:
        return storage().url(key, expires_s=3600)
    except Exception:  # storage down: show initials instead of failing /v1/me
        return None


def _looks_like_image(head: bytes) -> bool:
    """Magic numbers: the first bytes say what a file really is, whatever its name claims."""
    return (
        head.startswith(b"\xff\xd8\xff")
        or head.startswith(b"\x89PNG")
        or (head[:4] == b"RIFF" and head[8:12] == b"WEBP")
    )


@router.put("/me/photo")
async def set_photo(photo: UploadFile = File(...), user: dict = Depends(auth.current_user)) -> dict:
    suffix = TYPES.get(photo.content_type or "")
    if suffix is None:
        raise HTTPException(415, "Use a JPG, PNG or WebP picture.")
    data = await photo.read(MAX_PHOTO_BYTES + 1)
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(413, "That picture is over 5 MB. Pick a smaller one.")
    if not _looks_like_image(data[:16]):
        raise HTTPException(415, "That file isn't a picture.")
    key = f"players/{user['id']}/photo/{uuid.uuid4()}{suffix}"
    with tempfile.NamedTemporaryFile(suffix=suffix) as tmp:
        tmp.write(data)
        tmp.flush()
        storage().put(key, Path(tmp.name), photo.content_type or "image/jpeg")
    old = photo_key(user["id"])
    with db.engine().begin() as c:
        if old is None:
            c.execute(insert(profile_photos).values(user_id=user["id"], photo_key=key, updated_at=db.now()))
        else:
            c.execute(
                update(profile_photos)
                .where(profile_photos.c.user_id == user["id"])
                .values(photo_key=key, updated_at=db.now())
            )
    if old:
        # The new one is saved; a leftover old file would be harmless.
        with contextlib.suppress(Exception):
            storage().delete(old)
    return {"photoUrl": photo_url(user["id"])}


@router.delete("/me/photo", status_code=204)
def clear_photo(user: dict = Depends(auth.current_user)) -> None:
    old = photo_key(user["id"])
    with db.engine().begin() as c:
        c.execute(delete(profile_photos).where(profile_photos.c.user_id == user["id"]))
    if old:
        with contextlib.suppress(Exception):
            storage().delete(old)
