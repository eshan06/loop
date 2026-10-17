"""Saving uploaded photos: validate, normalize, write to MEDIA_DIR, insert a row.

POST /photos uses `save_upload`. POST /scan validates every file first with
`read_upload`, then saves each with `save_photo`, so a bad third photo doesn't
leave the first two behind.

Every saved file is a JPEG (EXIF orientation applied, RGB, longest side at most
MAX_SIDE, quality JPEG_QUALITY) named with random hex, e.g. "3f9c...e1.jpg".
"""

from __future__ import annotations

import io
import secrets
from pathlib import Path

from fastapi import UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy.orm import Session

from .config import settings
from .errors import ApiError
from .models import Photo, User

MAX_BYTES = 5 * 1024 * 1024  # docs/API.md: 5 MB max per photo
MAX_SIDE = 1600
JPEG_QUALITY = 85
KINDS = ("front", "back", "label", "other", "avatar")

# Refuse absurd pixel counts (decompression bombs) well before Pillow's own limit.
Image.MAX_IMAGE_PIXELS = 60_000_000


def check_kind(kind: str | None, field: str = "kind") -> str:
    kind = (kind or "").strip().lower()
    if kind not in KINDS:
        raise ApiError(400, "bad_request", f"{field}: must be one of {', '.join(KINDS)}.")
    return kind


def read_upload(upload: UploadFile, field: str = "file") -> bytes:
    """The upload's bytes, or 400 photo_too_large / bad_request if it isn't a JPEG."""
    data = upload.file.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ApiError(400, "photo_too_large", "That photo is over 5 MB. Try a smaller one.")
    if not data:
        raise ApiError(400, "bad_request", f"{field}: the file is empty.")
    try:
        with Image.open(io.BytesIO(data)) as img:
            fmt = img.format
            img.verify()
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError):
        fmt = None
    if fmt != "JPEG":
        raise ApiError(400, "bad_request", f"{field}: must be a JPEG photo.")
    return data


def normalize_jpeg(data: bytes) -> bytes:
    """Upright, RGB, longest side <= MAX_SIDE, re-encoded as JPEG."""
    try:
        with Image.open(io.BytesIO(data)) as img:
            img = ImageOps.exif_transpose(img)
            if img.mode != "RGB":
                img = img.convert("RGB")
            img.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
            out = io.BytesIO()
            img.save(out, "JPEG", quality=JPEG_QUALITY, optimize=True)
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        raise ApiError(400, "bad_request", "file: that photo couldn't be read.") from exc
    return out.getvalue()


def save_photo(db: Session, user: User, data: bytes, kind: str) -> Photo:
    """Normalize and write the JPEG, add a photos row (flushed, not committed)."""
    jpeg = normalize_jpeg(data)
    media_dir = Path(settings.media_dir).expanduser()
    media_dir.mkdir(parents=True, exist_ok=True)
    name = f"{secrets.token_hex(16)}.jpg"
    (media_dir / name).write_bytes(jpeg)
    photo = Photo(owner_id=user.id, listing_id=None, kind=kind, path=name)
    db.add(photo)
    db.flush()
    return photo


def save_upload(db: Session, user: User, upload: UploadFile, kind: str) -> Photo:
    """Validate one upload and save it. Caller commits."""
    return save_photo(db, user, read_upload(upload), check_kind(kind))
