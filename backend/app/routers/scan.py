"""POST /scan: save 1-3 photos, then ask the AI for a listing draft (app/ai.py).

Every upload is validated before any is saved, and the photos are committed
before the AI runs, so an AI failure or timeout never loses them. AI problems
are never an error response: they come back as source "none".
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from .. import ai
from ..auth import current_user
from ..config import settings
from ..db import get_db
from ..errors import ApiError
from ..models import User
from ..photos import read_upload, save_photo
from ..schemas import ScanDraftOut, ScanOut
from ..serializers import photo_out

router = APIRouter(tags=["scan"])

MAX_PHOTOS = 3
SCAN_KINDS = ("front", "back", "label", "other")


def _parse_kinds(kinds: str | None, count: int) -> list[str]:
    parts = [k.strip().lower() for k in (kinds or "").split(",")] if kinds and kinds.strip() else []
    if len(parts) != count:
        raise ApiError(400, "bad_request",
                       f"kinds: send one kind per photo, comma-separated (got {len(parts)} for {count}).")
    for kind in parts:
        if kind not in SCAN_KINDS:
            raise ApiError(400, "bad_request", f"kinds: each must be one of {', '.join(SCAN_KINDS)}.")
    return parts


@router.post("/scan")
def post_scan(
    photos: list[UploadFile] | None = File(None),
    kinds: str | None = Form(None),
    labels: str | None = Form(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ScanOut:
    uploads = photos or []
    if not uploads:
        raise ApiError(400, "bad_request", "photos: add at least one photo.")
    if len(uploads) > MAX_PHOTOS:
        raise ApiError(400, "too_many_photos", "You can scan up to 3 photos.")
    kind_list = _parse_kinds(kinds, len(uploads))
    datas = [read_upload(u, "photos") for u in uploads]

    saved = [save_photo(db, user, data, kind) for data, kind in zip(datas, kind_list)]
    photos_out = [photo_out(p) for p in saved]
    # The saved files are the normalized JPEGs (upright, <= 1600 px); the AI reads those.
    media_dir = Path(settings.media_dir).expanduser()
    jpegs = [(media_dir / p.path).read_bytes() for p in saved]
    db.commit()

    draft, source = ai.scan_draft(jpegs, labels, kind_list)
    return ScanOut(photos=photos_out, draft=ScanDraftOut(**draft), source=source)

