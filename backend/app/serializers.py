"""Shared builders that turn ORM rows into the API objects in docs/API.md.

Every endpoint that returns a User, Owner, Photo, ... uses these, so the shapes
stay identical everywhere. Later tasks add Listing, Request, Message and
Notification builders here.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .config import settings
from .models import Listing, MeetupSpot, Photo, User
from .schemas import CampusOut, MeetupSpotOut, OwnerOut, PhotoOut, Sizes, UserOut


def iso(dt: datetime | None) -> str | None:
    """ISO 8601 UTC, whole seconds, with Z: 2026-10-18T15:04:05Z.

    Naive datetimes (what MySQL DATETIME gives back) are taken as UTC.
    """
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(UTC).replace(tzinfo=None)
    return dt.replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def photo_url(photo_or_path: Photo | str | None) -> str | None:
    """Absolute public URL for a Photo (or its relative path) under /media."""
    if photo_or_path is None:
        return None
    path = photo_or_path if isinstance(photo_or_path, str) else photo_or_path.path
    return settings.media_url(path)


def photo_out(photo: Photo) -> PhotoOut:
    return PhotoOut(id=photo.id, url=photo_url(photo), kind=photo.kind)


def meetup_spot_out(spot: MeetupSpot | None) -> MeetupSpotOut | None:
    """{id, name}; None when a listing's spot was removed (Listing.meetup_spot is nullable)."""
    return None if spot is None else MeetupSpotOut(id=spot.id, name=spot.name)


def avatar_url(user: User) -> str | None:
    return photo_url(user.avatar_photo) if user.avatar_photo_id else None


# ---- items_shared ------------------------------------------------------------

def items_shared_counts(db: Session, user_ids: Iterable[int]) -> dict[int, int]:
    """items_shared for many users in one query: their listings with status completed."""
    ids = {i for i in user_ids if i is not None}
    if not ids:
        return {}
    rows = db.execute(
        select(Listing.owner_id, func.count())
        .where(Listing.owner_id.in_(ids), Listing.status == "completed")
        .group_by(Listing.owner_id)
    ).all()
    counts = {uid: 0 for uid in ids}
    counts.update({uid: n for uid, n in rows})
    return counts


def items_shared(db: Session, user_id: int) -> int:
    return items_shared_counts(db, [user_id]).get(user_id, 0)


# ---- User and Owner ----------------------------------------------------------

def user_out(db: Session, user: User) -> UserOut:
    """The full User object (the caller themself)."""
    return UserOut(
        id=user.id,
        name=user.name,
        email=user.email,
        campus=CampusOut(id=user.campus.id, name=user.campus.name),
        dorm=user.dorm,
        class_year=user.class_year,
        sizes=Sizes(top=user.size_top, bottom=user.size_bottom, shoe=user.size_shoe),
        avatar_url=avatar_url(user),
        items_shared=items_shared(db, user.id),
        created_at=iso(user.created_at),
    )


def owner_out(db: Session, user: User, shared: int | None = None) -> OwnerOut:
    """Another person, as an Owner. Pass `shared` (from items_shared_counts) when
    building many at once to avoid one count query per person."""
    return OwnerOut(
        id=user.id,
        name=user.name,
        dorm=user.dorm,
        avatar_url=avatar_url(user),
        items_shared=items_shared(db, user.id) if shared is None else shared,
    )
