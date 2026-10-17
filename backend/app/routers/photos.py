"""POST /photos: upload one JPEG (avatars, or photos added without a scan)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..models import User
from ..photos import save_upload
from ..schemas import PhotoOut
from ..serializers import photo_out

router = APIRouter(tags=["photos"])


@router.post("/photos", status_code=201)
def post_photo(
    file: UploadFile = File(...),
    kind: str = Form(...),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> PhotoOut:
    photo = save_upload(db, user, file, kind)
    db.commit()
    db.refresh(photo)
    return photo_out(photo)
