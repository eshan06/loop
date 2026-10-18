"""Profile: GET /me, PATCH /me, GET /me/unread, GET /me/badges, GET /dorms."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..badges import badges_for
from ..db import get_db
from ..errors import ApiError
from ..models import Dorm, Listing, Message, Notification, Photo, Request, User
from ..schemas import BadgeOut, ItemsList, MePatch, UnreadOut, UserOut
from ..serializers import iso, user_out

router = APIRouter(tags=["me"])


def _bad(message: str) -> ApiError:
    return ApiError(400, "bad_request", message)


def _clean(value: str | None, field: str, max_len: int) -> str | None:
    """Trim; empty becomes None; longer than max_len is a 400."""
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    if len(value) > max_len:
        raise _bad(f"{field}: must be at most {max_len} characters.")
    return value


def campus_dorms(db: Session, campus_id: int) -> list[str]:
    return list(db.scalars(select(Dorm.name).where(Dorm.campus_id == campus_id).order_by(Dorm.name)))


@router.get("/me")
def get_me(user: User = Depends(current_user), db: Session = Depends(get_db)) -> UserOut:
    return user_out(db, user)


@router.patch("/me")
def patch_me(
    body: MePatch, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> UserOut:
    sent = body.model_fields_set

    if "name" in sent:
        name = _clean(body.name, "name", 80)
        if name is None:
            raise _bad("name: must be 1 to 80 characters.")
        user.name = name

    if "dorm" in sent:
        dorm = _clean(body.dorm, "dorm", 80)
        if dorm is not None:
            names = campus_dorms(db, user.campus_id)
            if names:
                match = next((n for n in names if n.casefold() == dorm.casefold()), None)
                if match is None:
                    raise _bad("dorm: pick one of the dorms for your campus.")
                dorm = match
        user.dorm = dorm

    if "class_year" in sent:
        year = body.class_year
        if year is not None and not 1000 <= year <= 9999:
            raise _bad("class_year: must be a four-digit year, like 2028.")
        user.class_year = year

    if "sizes" in sent:
        sizes = body.sizes
        user.size_top = _clean(sizes.top if sizes else None, "sizes.top", 16)
        user.size_bottom = _clean(sizes.bottom if sizes else None, "sizes.bottom", 16)
        user.size_shoe = _clean(sizes.shoe if sizes else None, "sizes.shoe", 16)

    if "avatar_photo_id" in sent:
        photo_id = body.avatar_photo_id
        if photo_id is not None:
            photo = db.get(Photo, photo_id)
            if photo is None or photo.owner_id != user.id:
                raise _bad("avatar_photo_id: upload the photo with POST /photos first.")
        user.avatar_photo_id = photo_id

    db.commit()
    db.refresh(user)
    return user_out(db, user)


@router.get("/me/unread")
def get_unread(user: User = Depends(current_user), db: Session = Depends(get_db)) -> UnreadOut:
    notifications = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == user.id, Notification.read_at.is_(None))
    )
    incoming = db.scalar(
        select(func.count())
        .select_from(Request)
        .join(Listing, Listing.id == Request.listing_id)
        .where(Listing.owner_id == user.id, Request.status == "pending")
    )
    # Messages from the other person newer than my read marker on each request.
    messages = db.scalar(
        select(func.count())
        .select_from(Message)
        .join(Request, Request.id == Message.request_id)
        .join(Listing, Listing.id == Request.listing_id)
        .where(
            Message.sender_id != user.id,
            or_(
                and_(Request.requester_id == user.id, Message.id > Request.requester_last_read_id),
                and_(Listing.owner_id == user.id, Message.id > Request.owner_last_read_id),
            ),
        )
    )
    return UnreadOut(
        notifications=notifications or 0, messages=messages or 0, incoming_requests=incoming or 0
    )


@router.get("/me/badges")
def get_badges(user: User = Depends(current_user), db: Session = Depends(get_db)) -> ItemsList[BadgeOut]:
    """Every badge, in rule order (app/badges.py), earned or not."""
    return ItemsList[BadgeOut](
        items=[BadgeOut(**{**b, "earned_at": iso(b["earned_at"])}) for b in badges_for(db, user)]
    )


@router.get("/dorms")
def get_dorms(user: User = Depends(current_user), db: Session = Depends(get_db)) -> ItemsList[str]:
    return ItemsList[str](items=campus_dorms(db, user.campus_id))
