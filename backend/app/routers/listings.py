"""Listings: the campus feed, create, read, edit, delete, GET /me/listings,
saves (PUT/DELETE /listings/{id}/save, GET /me/saved), similar items
(GET /listings/{id}/similar), Style it (POST /listings/{id}/style, app/style.py), and
reports (POST /listings/{id}/report).

Every query is scoped to the caller's campus; another campus's listing is 404.
A `hidden` listing is 404 for everyone but its owner.
"""

from __future__ import annotations

from fastapi import APIRouter, Body, Depends, Query, Response
from sqlalchemy import String, cast, delete, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import events
from ..auth import current_user
from ..db import get_db
from ..errors import ApiError
from ..models import Listing, MeetupSpot, Photo, Report, Save, User
from ..paging import Paging, paged, paging_params
from ..schemas import ItemsList, ListingIn, ListingOut, Page, ReportIn, StyleOut
from ..style import ideas_for
from ..serializers import listing_out, listings_out

router = APIRouter(tags=["listings"])

SHARE_TYPES = ("swap", "free", "donate")
CONDITIONS = ("new", "like_new", "good", "worn")
CATEGORIES = ("tops", "bottoms", "outerwear", "dresses", "shoes", "accessories", "bags")

MAX_PHOTOS = 5
MAX_TAGS = 10
MAX_TAG_LEN = 30
# field -> max length, for the optional free-text fields
TEXT_LIMITS = {"size": 20, "color": 60, "brand": 80, "condition_note": 140, "description": 2000}
TITLE_MAX = 120
SIMILAR_DEFAULT = 6
SIMILAR_MAX = 20
REASON_MAX = 200
HIDE_AFTER = 3  # distinct reporters
HIDEABLE = ("active", "pending")  # a completed listing is history: reports are kept, it stays


def _bad(message: str) -> ApiError:
    return ApiError(400, "bad_request", message)


def _enum(value: str | None, field: str, allowed: tuple[str, ...]) -> str:
    v = (value or "").strip().lower()
    if v not in allowed:
        raise _bad(f"{field}: must be one of {', '.join(allowed)}.")
    return v


def _text(value: str | None, field: str, max_len: int) -> str | None:
    """Trim; empty becomes None; over max_len is a 400."""
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    if len(value) > max_len:
        raise _bad(f"{field}: must be at most {max_len} characters.")
    return value


def _tags(values: list[str] | None) -> list[str]:
    if values is None:
        return []
    if len(values) > MAX_TAGS:
        raise _bad(f"tags: at most {MAX_TAGS} tags.")
    out: list[str] = []
    seen: set[str] = set()
    for raw in values:
        tag = raw.strip()
        if not tag:
            continue
        if len(tag) > MAX_TAG_LEN:
            raise _bad(f"tags: each tag must be at most {MAX_TAG_LEN} characters.")
        if tag.casefold() not in seen:
            seen.add(tag.casefold())
            out.append(tag)
    return out


def _photos(db: Session, user: User, photo_ids: list[int] | None, listing_id: int | None) -> list[Photo]:
    """The caller's photos for these IDs, in order. Each must be theirs and not on
    another listing (photos already on `listing_id` are fine, for PATCH)."""
    if not photo_ids:
        raise _bad("photo_ids: add at least one photo.")
    if len(photo_ids) > MAX_PHOTOS:
        raise ApiError(400, "too_many_photos", f"A listing can have at most {MAX_PHOTOS} photos.")
    if len(set(photo_ids)) != len(photo_ids):
        raise _bad("photo_ids: the same photo is listed twice.")
    found = {p.id: p for p in db.scalars(select(Photo).where(Photo.id.in_(photo_ids)))}
    photos = []
    for pid in photo_ids:
        p = found.get(pid)
        if p is None or p.owner_id != user.id:
            raise _bad(f"photo_ids: photo {pid} isn't one of your uploads.")
        if p.listing_id is not None and p.listing_id != listing_id:
            raise _bad(f"photo_ids: photo {pid} is already on another listing.")
        photos.append(p)
    return photos


def _spot(db: Session, user: User, spot_id: int | None) -> int:
    if spot_id is None:
        raise _bad("meetup_spot_id: pick a meetup spot.")
    spot = db.get(MeetupSpot, spot_id)
    if spot is None or spot.campus_id != user.campus_id:
        raise _bad("meetup_spot_id: pick one of the meetup spots for your campus.")
    return spot.id


def _apply(db: Session, user: User, listing: Listing, body: ListingIn, creating: bool) -> list[Photo] | None:
    """Validate the sent fields and set them on `listing`. POST sends every field
    (missing ones count as null); PATCH only the ones in the body. Returns the new
    photo list when photo_ids was sent, else None."""
    sent = set(ListingIn.model_fields) if creating else body.model_fields_set

    if "title" in sent:
        title = _text(body.title, "title", TITLE_MAX)
        if title is None:
            raise _bad(f"title: must be 1 to {TITLE_MAX} characters.")
        listing.title = title
    if "category" in sent:
        listing.category = _enum(body.category, "category", CATEGORIES)
    if "condition" in sent:
        listing.condition = _enum(body.condition, "condition", CONDITIONS)
    if "share_type" in sent:
        listing.share_type = _enum(body.share_type, "share_type", SHARE_TYPES)
    for field, max_len in TEXT_LIMITS.items():
        if field in sent:
            setattr(listing, field, _text(getattr(body, field), field, max_len))
    if "tags" in sent:
        listing.tags = _tags(body.tags)
    if "meetup_spot_id" in sent:
        listing.meetup_spot_id = _spot(db, user, body.meetup_spot_id)
    if "photo_ids" in sent:
        return _photos(db, user, body.photo_ids, listing.id)
    return None


def _attach(db: Session, listing: Listing, photos: list[Photo]) -> None:
    """Make `photos` (in order) the listing's photos; detach any others."""
    keep = [p.id for p in photos]
    db.execute(
        update(Photo)
        .where(Photo.listing_id == listing.id, Photo.id.not_in(keep))
        .values(listing_id=None, position=None)
    )
    for i, p in enumerate(photos):
        p.listing_id = listing.id
        p.position = i


def _visible(db: Session, user: User, listing_id: int) -> Listing:
    """A listing the caller may see: same campus, and not hidden unless theirs."""
    listing = db.get(Listing, listing_id)
    if (
        listing is None
        or listing.campus_id != user.campus_id
        or (listing.status == "hidden" and listing.owner_id != user.id)
    ):
        raise ApiError(404, "not_found", "That listing isn't available.")
    return listing


def _editable(db: Session, user: User, listing_id: int) -> Listing:
    listing = _visible(db, user, listing_id)
    if listing.owner_id != user.id:
        raise ApiError(403, "forbidden", "You can only change your own listings.")
    if listing.status == "completed":
        raise ApiError(409, "wrong_status", "This item has already been exchanged, so it can't be changed.")
    return listing


def _tag_set(tags) -> set[str]:
    return {t.strip().lower() for t in (tags or []) if isinstance(t, str) and t.strip()}


def _filter(value: str | None, field: str, allowed: tuple[str, ...]) -> str | None:
    if value is None or not value.strip():
        return None
    return _enum(value, field, allowed)


def _like(text: str) -> str:
    """Case-insensitive substring pattern; `!` escapes LIKE wildcards in the text."""
    escaped = text.lower().replace("!", "!!").replace("%", "!%").replace("_", "!_")
    return f"%{escaped}%"


# ---- Routes ------------------------------------------------------------------

@router.get("/listings")
def get_feed(
    share_type: str | None = Query(None),
    category: str | None = Query(None),
    size: str | None = Query(None),
    q: str | None = Query(None),
    paging: Paging = Depends(paging_params),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Page[ListingOut]:
    stmt = select(Listing).where(Listing.campus_id == user.campus_id, Listing.status == "active")
    if (st := _filter(share_type, "share_type", SHARE_TYPES)) is not None:
        stmt = stmt.where(Listing.share_type == st)
    if (cat := _filter(category, "category", CATEGORIES)) is not None:
        stmt = stmt.where(Listing.category == cat)
    if size is not None and size.strip():
        stmt = stmt.where(func.lower(Listing.size) == size.strip().lower())
    if q is not None and q.strip():
        pattern = _like(q.strip())
        stmt = stmt.where(
            or_(
                func.lower(Listing.title).like(pattern, escape="!"),
                func.lower(Listing.brand).like(pattern, escape="!"),
                func.lower(cast(Listing.tags, String)).like(pattern, escape="!"),
            )
        )
    stmt = stmt.order_by(Listing.created_at.desc(), Listing.id.desc())
    rows, total = paged(db, stmt, paging)
    return Page[ListingOut](
        items=listings_out(db, rows, user), total=total, next_offset=paging.next_offset(len(rows), total)
    )


@router.post("/listings", status_code=201)
def create_listing(
    body: ListingIn, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> ListingOut:
    listing = Listing(owner_id=user.id, campus_id=user.campus_id, status="active")
    photos = _apply(db, user, listing, body, creating=True)
    db.add(listing)
    db.flush()
    _attach(db, listing, photos or [])
    db.execute(update(User).where(User.id == user.id)
               .values(listings_created=User.listings_created + 1)
               .execution_options(synchronize_session=False))
    db.refresh(user, ["listings_created"])
    events.on_listing_created(db, listing, user)
    db.commit()
    return listing_out(db, listing, user)


@router.get("/listings/{listing_id}")
def get_listing(
    listing_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> ListingOut:
    return listing_out(db, _visible(db, user, listing_id), user)


@router.get("/listings/{listing_id}/similar")
def get_similar(
    listing_id: int,
    limit: int = Query(SIMILAR_DEFAULT),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ItemsList[ListingOut]:
    """Active, unhidden listings on the caller's campus ranked against the source:
    shared tags (case-insensitive) x3 + same category x2 + same size x1, then
    newest, then id. Never the source itself or the caller's own listings.
    Zero-score listings only fill the row when there aren't enough matches.
    Candidates are ranked in Python: demo scale."""
    if limit < 1:
        raise _bad("limit: must be at least 1.")
    limit = min(limit, SIMILAR_MAX)
    source = _visible(db, user, listing_id)
    src_tags = _tag_set(source.tags)
    src_cat = source.category
    src_size = (source.size or "").strip().lower()

    rows = db.execute(
        select(Listing.id, Listing.tags, Listing.category, Listing.size, Listing.created_at).where(
            Listing.campus_id == user.campus_id,
            Listing.status == "active",
            Listing.id != source.id,
            Listing.owner_id != user.id,
        )
    ).all()

    def score(r) -> int:
        s = len(src_tags & _tag_set(r.tags)) * 3
        if src_cat and r.category == src_cat:
            s += 2
        if src_size and (r.size or "").strip().lower() == src_size:
            s += 1
        return s

    ranked = sorted(((score(r), r.created_at, r.id) for r in rows), reverse=True)
    ids = [rid for _, _, rid in ranked[:limit]]
    by_id = {l.id: l for l in db.scalars(select(Listing).where(Listing.id.in_(ids)))} if ids else {}
    return ItemsList[ListingOut](items=listings_out(db, [by_id[i] for i in ids], user))


@router.post("/listings/{listing_id}/style")
def style_listing(
    listing_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> StyleOut:
    """2-3 outfit ideas: cached per listing, else the text model (then cached), else
    template ideas from category and color (not cached). Never 502."""
    return StyleOut(ideas=ideas_for(db, _visible(db, user, listing_id)))


@router.patch("/listings/{listing_id}")
def patch_listing(
    listing_id: int, body: ListingIn, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> ListingOut:
    listing = _editable(db, user, listing_id)
    photos = _apply(db, user, listing, body, creating=False)
    if photos is not None:
        _attach(db, listing, photos)
    db.commit()
    db.refresh(listing)
    return listing_out(db, listing, user)


@router.delete("/listings/{listing_id}", status_code=204)
def delete_listing(
    listing_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Response:
    _editable(db, user, listing_id)
    # Plain SQL delete: MySQL cascades requests, messages, saves and reports, and
    # sets photos.listing_id / notifications.listing_id to NULL (see CLAUDE.md Gotchas).
    db.execute(delete(Listing).where(Listing.id == listing_id))
    db.commit()
    return Response(status_code=204)


@router.get("/me/listings")
def get_my_listings(
    status: str = Query("active"),
    paging: Paging = Depends(paging_params),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Page[ListingOut]:
    tab = status.strip().lower()
    if tab == "active":
        statuses = ("active", "pending", "hidden")
    elif tab == "completed":
        statuses = ("completed",)
    else:
        raise _bad("status: must be active or completed.")
    stmt = (
        select(Listing)
        .where(Listing.owner_id == user.id, Listing.status.in_(statuses))
        .order_by(Listing.created_at.desc(), Listing.id.desc())
    )
    rows, total = paged(db, stmt, paging)
    return Page[ListingOut](
        items=listings_out(db, rows, user), total=total, next_offset=paging.next_offset(len(rows), total)
    )


# ---- Saves -------------------------------------------------------------------
# PUT and DELETE are idempotent 204s on any listing the caller can see (any status,
# including their own: the contract only forbids requesting/reporting your own).
# Saving again keeps the original save time.

@router.put("/listings/{listing_id}/save", status_code=204)
def save_listing(
    listing_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Response:
    listing = _visible(db, user, listing_id)
    if db.get(Save, (user.id, listing.id)) is None:
        db.add(Save(user_id=user.id, listing_id=listing.id))
        try:
            db.commit()
        except IntegrityError:  # a concurrent PUT saved it first: same result
            db.rollback()
    return Response(status_code=204)


@router.delete("/listings/{listing_id}/save", status_code=204)
def unsave_listing(
    listing_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Response:
    listing = _visible(db, user, listing_id)
    db.execute(delete(Save).where(Save.user_id == user.id, Save.listing_id == listing.id))
    db.commit()
    return Response(status_code=204)


@router.get("/me/saved")
def get_my_saved(
    paging: Paging = Depends(paging_params),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Page[ListingOut]:
    """Saved listings in any status except hidden, most recently saved first."""
    stmt = (
        select(Listing)
        .join(Save, Save.listing_id == Listing.id)
        .where(
            Save.user_id == user.id,
            Listing.campus_id == user.campus_id,
            Listing.status != "hidden",
        )
        .order_by(Save.created_at.desc(), Listing.id.desc())
    )
    rows, total = paged(db, stmt, paging)
    return Page[ListingOut](
        items=listings_out(db, rows, user), total=total, next_offset=paging.next_offset(len(rows), total)
    )


# ---- Reports -----------------------------------------------------------------
# One report per user per listing (unique key); a repeat is a 204 that changes
# nothing. The listing row is locked first, so concurrent reports count in order
# and exactly one of them hides it. At HIDE_AFTER distinct reporters an active or
# pending listing becomes hidden. Open requests on it are left alone: the owner
# can't accept (the listing isn't active) but can decline, the requester can
# cancel, and an accepted exchange can still chat and complete. Cancelling an
# accepted request only reopens a `pending` listing, so hidden stays hidden.

@router.post("/listings/{listing_id}/report", status_code=204)
def report_listing(
    listing_id: int,
    body: ReportIn | None = Body(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Response:
    reason = _text(body.reason if body else None, "reason", REASON_MAX)
    listing = db.scalar(
        select(Listing).where(Listing.id == listing_id).with_for_update()
        .execution_options(populate_existing=True)
    )
    if listing is None or listing.campus_id != user.campus_id or (
        listing.status == "hidden" and listing.owner_id != user.id
    ):
        raise ApiError(404, "not_found", "That listing isn't available.")
    if listing.owner_id == user.id:
        raise ApiError(409, "own_listing", "This is your own listing.")
    exists = db.scalar(
        select(Report.id).where(Report.listing_id == listing.id, Report.reporter_id == user.id)
    )
    if exists is None:
        db.add(Report(listing_id=listing.id, reporter_id=user.id, reason=reason))
        db.flush()
        count = db.scalar(
            select(func.count(func.distinct(Report.reporter_id))).where(Report.listing_id == listing.id)
        )
        if count >= HIDE_AFTER and listing.status in HIDEABLE:
            listing.status = "hidden"
    try:
        db.commit()
    except IntegrityError:  # same user reported twice at once: counts once
        db.rollback()
    return Response(status_code=204)
