"""GET /meetup-spots: the meetup spots for the caller's campus."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..auth import current_user
from ..campus import ensure_meetup_spots
from ..db import get_db
from ..models import User
from ..schemas import ItemsList, MeetupSpotOut
from ..serializers import meetup_spot_out

router = APIRouter(tags=["meetup spots"])


@router.get("/meetup-spots")
def get_meetup_spots(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> ItemsList[MeetupSpotOut]:
    spots = ensure_meetup_spots(db, user.campus_id)
    return ItemsList[MeetupSpotOut](items=[meetup_spot_out(s) for s in spots])
