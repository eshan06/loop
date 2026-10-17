"""Shared builders that turn ORM rows into the API objects in docs/API.md.

Every endpoint that returns a User, Owner, Photo, Listing, ... uses these, so the
shapes stay identical everywhere. A later task adds the Notification builder
here.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session, selectinload

from .config import settings
from .impact import impact_for
from .models import Listing, MeetupSpot, Message, Photo, Request, Save, User
from .schemas import (
    CampusOut,
    ImpactOut,
    ListingOut,
    MeetupSpotOut,
    MessageOut,
    OwnerOut,
    PhotoOut,
    RequestListingOut,
    RequestOut,
    Sizes,
    UserOut,
)


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


# ---- Listing -----------------------------------------------------------------

def listings_out(db: Session, listings: list[Listing], viewer: User) -> list[ListingOut]:
    """Many Listings as seen by `viewer`, in the given order, in a fixed handful of
    queries (photos, owners with avatars, items_shared, spots, requests, saves)
    no matter how many listings."""
    if not listings:
        return []
    ids = [lst.id for lst in listings]

    photos: dict[int, list[Photo]] = {i: [] for i in ids}
    for p in db.scalars(
        select(Photo).where(Photo.listing_id.in_(ids)).order_by(Photo.position, Photo.id)
    ):
        photos[p.listing_id].append(p)

    owner_ids = {lst.owner_id for lst in listings}
    owners = {
        u.id: u
        for u in db.scalars(
            select(User).where(User.id.in_(owner_ids)).options(selectinload(User.avatar_photo))
        )
    }
    shared = items_shared_counts(db, owner_ids)

    spot_ids = {lst.meetup_spot_id for lst in listings if lst.meetup_spot_id is not None}
    spots = (
        {s.id: s for s in db.scalars(select(MeetupSpot).where(MeetupSpot.id.in_(spot_ids)))}
        if spot_ids
        else {}
    )

    # Every request on these listings, oldest first: small at demo scale, one query.
    mine: dict[int, tuple[int, str]] = {}  # listing_id -> (my latest request id, status)
    pending: dict[int, int] = {}
    accepted: dict[int, int] = {}
    for rid, lid, requester_id, status in db.execute(
        select(Request.id, Request.listing_id, Request.requester_id, Request.status)
        .where(Request.listing_id.in_(ids))
        .order_by(Request.id)
    ):
        if requester_id == viewer.id:
            mine[lid] = (rid, status)
        if status == "pending":
            pending[lid] = pending.get(lid, 0) + 1
        elif status == "accepted":
            accepted[lid] = rid

    saved = set(
        db.scalars(select(Save.listing_id).where(Save.user_id == viewer.id, Save.listing_id.in_(ids)))
    )

    out = []
    for lst in listings:
        is_mine = lst.owner_id == viewer.id
        my_req = mine.get(lst.id)
        out.append(
            ListingOut(
                id=lst.id,
                title=lst.title,
                category=lst.category,
                size=lst.size,
                color=lst.color,
                brand=lst.brand,
                condition=lst.condition,
                description=lst.description,
                tags=list(lst.tags or []),
                share_type=lst.share_type,
                status=lst.status,
                photos=[photo_out(p) for p in photos[lst.id]],
                meetup_spot=meetup_spot_out(spots.get(lst.meetup_spot_id)),
                owner=owner_out(db, owners[lst.owner_id], shared.get(lst.owner_id, 0)),
                impact=ImpactOut(**impact_for(lst.category)),
                is_mine=is_mine,
                saved_by_me=lst.id in saved,
                my_request_status=my_req[1] if my_req else None,
                my_request_id=my_req[0] if my_req else None,
                pending_request_count=pending.get(lst.id, 0) if is_mine else 0,
                accepted_request_id=(
                    accepted.get(lst.id) if is_mine and lst.status == "pending" else None
                ),
                created_at=iso(lst.created_at),
            )
        )
    return out


def listing_out(db: Session, listing: Listing, viewer: User) -> ListingOut:
    """One Listing as seen by `viewer`."""
    return listings_out(db, [listing], viewer)[0]


# ---- Request -----------------------------------------------------------------

def unread_counts(db: Session, request_ids: Iterable[int], viewer_id: int) -> dict[int, int]:
    """Per request: messages from the other person newer than the viewer's read marker
    (requester_last_read_id if the viewer is the requester, else owner_last_read_id)."""
    ids = list(set(request_ids))
    if not ids:
        return {}
    last_read = case(
        (Request.requester_id == viewer_id, Request.requester_last_read_id),
        else_=Request.owner_last_read_id,
    )
    rows = db.execute(
        select(Message.request_id, func.count())
        .join(Request, Request.id == Message.request_id)
        .where(Message.request_id.in_(ids), Message.sender_id != viewer_id, Message.id > last_read)
        .group_by(Message.request_id)
    ).all()
    return dict(rows)


def requests_out(db: Session, reqs: list[Request], viewer: User) -> list[RequestOut]:
    """Many Requests as seen by `viewer`, in the given order, in a fixed handful of
    queries (listings, first photos, people with avatars, items_shared, unread)."""
    if not reqs:
        return []
    listing_ids = {r.listing_id for r in reqs}
    listings = {lst.id: lst for lst in db.scalars(select(Listing).where(Listing.id.in_(listing_ids)))}

    first_photo: dict[int, Photo] = {}
    for p in db.scalars(
        select(Photo).where(Photo.listing_id.in_(listing_ids)).order_by(Photo.position, Photo.id)
    ):
        first_photo.setdefault(p.listing_id, p)

    user_ids = {r.requester_id for r in reqs} | {lst.owner_id for lst in listings.values()}
    users = {
        u.id: u
        for u in db.scalars(
            select(User).where(User.id.in_(user_ids)).options(selectinload(User.avatar_photo))
        )
    }
    shared = items_shared_counts(db, user_ids)
    unread = unread_counts(db, [r.id for r in reqs], viewer.id)

    out = []
    for r in reqs:
        lst = listings[r.listing_id]
        out.append(
            RequestOut(
                id=r.id,
                listing=RequestListingOut(
                    id=lst.id,
                    title=lst.title,
                    photo_url=photo_url(first_photo.get(lst.id)),
                    share_type=lst.share_type,
                    status=lst.status,
                ),
                requester=owner_out(db, users[r.requester_id], shared.get(r.requester_id, 0)),
                owner=owner_out(db, users[lst.owner_id], shared.get(lst.owner_id, 0)),
                note=r.note,
                status=r.status,
                unread_messages=unread.get(r.id, 0),
                created_at=iso(r.created_at),
                updated_at=iso(r.updated_at),
            )
        )
    return out


def request_out(db: Session, req: Request, viewer: User) -> RequestOut:
    """One Request as seen by `viewer`."""
    return requests_out(db, [req], viewer)[0]


# ---- Message -----------------------------------------------------------------

def message_out(msg: Message) -> MessageOut:
    return MessageOut(
        id=msg.id,
        request_id=msg.request_id,
        sender_id=msg.sender_id,
        body=msg.body,
        created_at=iso(msg.created_at),
    )
