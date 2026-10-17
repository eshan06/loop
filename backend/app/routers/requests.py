"""Requests: create, list, read, and the accept / decline / complete / cancel actions.

State machine (docs/API.md):
    pending  -> accepted   (owner; listing -> pending; every other pending request
                            on the listing -> declined)
    pending  -> declined   (owner)
    accepted -> completed  (either side; listing -> completed)
    pending  -> cancelled  (requester)
    accepted -> cancelled  (requester; listing -> active again)

Every change locks the listing row first (SELECT ... FOR UPDATE), then the
request rows, so two taps at once can't both accept or both request. Each
action is one transaction, and the app.events hooks run inside it.
"""

from __future__ import annotations

from fastapi import APIRouter, Body, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import events
from ..auth import current_user
from ..db import get_db
from ..errors import ApiError
from ..models import Listing, Request, User, utcnow
from ..paging import Paging, paged, paging_params
from ..schemas import Page, RequestIn, RequestOut
from ..serializers import request_out, requests_out

router = APIRouter(tags=["requests"])

NOTE_MAX = 280
OPEN = ("pending", "accepted")


def _lock_listing(db: Session, listing_id: int) -> Listing | None:
    return db.scalar(
        select(Listing)
        .where(Listing.id == listing_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )


def _visible_listing(db: Session, user: User, listing_id: int) -> Listing:
    """The listing, locked: same campus, and not hidden unless it's the caller's."""
    listing = _lock_listing(db, listing_id)
    if (
        listing is None
        or listing.campus_id != user.campus_id
        or (listing.status == "hidden" and listing.owner_id != user.id)
    ):
        raise ApiError(404, "not_found", "That listing isn't available.")
    return listing


def find_request(db: Session, user: User, request_id: int, lock: bool = False) -> tuple[Request, Listing]:
    """A request and its listing. Another campus (or no such request) is 404;
    someone on the campus who isn't one of the two people is 403. The messages
    router uses this too, so chat has the same access rules as GET /requests/{id}. With `lock`,
    the listing and then the request are locked and re-read for an update."""
    req = db.get(Request, request_id)
    if req is None:
        raise ApiError(404, "not_found", "That request isn't available.")
    listing = _lock_listing(db, req.listing_id) if lock else db.get(Listing, req.listing_id)
    if listing is None or listing.campus_id != user.campus_id:
        raise ApiError(404, "not_found", "That request isn't available.")
    if user.id not in (req.requester_id, listing.owner_id):
        raise ApiError(403, "forbidden", "Only the two people on this request can see it.")
    if lock:
        db.refresh(req, with_for_update=True)
    return req, listing


def _wrong_status(message: str) -> ApiError:
    return ApiError(409, "wrong_status", message)


def _done(db: Session, req: Request, user: User) -> RequestOut:
    db.commit()
    return request_out(db, req, user)


# ---- Create ------------------------------------------------------------------

@router.post("/listings/{listing_id}/requests", status_code=201)
def create_request(
    listing_id: int,
    body: RequestIn | None = Body(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> RequestOut:
    note = (body.note if body else None) or ""
    note = note.strip() or None
    if note is not None and len(note) > NOTE_MAX:
        raise ApiError(400, "bad_request", f"note: must be at most {NOTE_MAX} characters.")

    listing = _visible_listing(db, user, listing_id)
    if listing.owner_id == user.id:
        raise ApiError(409, "own_listing", "This is your own listing.")
    open_req = db.scalar(
        select(Request.id).where(
            Request.listing_id == listing.id,
            Request.requester_id == user.id,
            Request.status.in_(OPEN),
        )
    )
    if open_req is not None:
        raise ApiError(409, "already_requested", "You've already requested this item.")
    if listing.status != "active":
        raise ApiError(409, "listing_unavailable", "This item isn't available anymore.")

    req = Request(listing_id=listing.id, requester_id=user.id, note=note, status="pending")
    db.add(req)
    db.flush()
    events.on_request_created(db, req, user)
    return _done(db, req, user)


# ---- Read --------------------------------------------------------------------

@router.get("/me/requests")
def get_my_requests(
    role: str | None = Query(None),
    paging: Paging = Depends(paging_params),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Page[RequestOut]:
    which = (role or "").strip().lower()
    if which == "incoming":
        stmt = select(Request).join(Listing, Listing.id == Request.listing_id).where(
            Listing.owner_id == user.id
        )
    elif which == "outgoing":
        stmt = select(Request).where(Request.requester_id == user.id)
    else:
        raise ApiError(400, "bad_request", "role: must be incoming or outgoing.")
    stmt = stmt.order_by(Request.updated_at.desc(), Request.id.desc())
    rows, total = paged(db, stmt, paging)
    return Page[RequestOut](
        items=requests_out(db, rows, user), total=total, next_offset=paging.next_offset(len(rows), total)
    )


@router.get("/requests/{request_id}")
def get_request(
    request_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> RequestOut:
    req, _ = find_request(db, user, request_id)
    return request_out(db, req, user)


# ---- Actions -----------------------------------------------------------------

@router.post("/requests/{request_id}/accept")
def accept_request(
    request_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> RequestOut:
    req, listing = find_request(db, user, request_id, lock=True)
    if listing.owner_id != user.id:
        raise ApiError(403, "forbidden", "Only the owner can accept a request.")
    if req.status != "pending":
        raise _wrong_status(f"This request is {req.status}, so it can't be accepted.")
    if listing.status != "active":
        raise _wrong_status("This item isn't available, so the request can't be accepted.")

    req.status = "accepted"
    listing.status = "pending"
    events.on_request_accepted(db, req, user)
    others = db.scalars(
        select(Request)
        .where(Request.listing_id == listing.id, Request.id != req.id, Request.status == "pending")
        .with_for_update()
    ).all()
    for other in others:
        other.status = "declined"
        events.on_request_declined(db, other, user, auto=True)
    return _done(db, req, user)


@router.post("/requests/{request_id}/decline")
def decline_request(
    request_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> RequestOut:
    req, listing = find_request(db, user, request_id, lock=True)
    if listing.owner_id != user.id:
        raise ApiError(403, "forbidden", "Only the owner can decline a request.")
    if req.status != "pending":
        raise _wrong_status(f"This request is {req.status}, so it can't be declined.")
    req.status = "declined"
    events.on_request_declined(db, req, user)
    return _done(db, req, user)


@router.post("/requests/{request_id}/complete")
def complete_request(
    request_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> RequestOut:
    req, listing = find_request(db, user, request_id, lock=True)
    if req.status != "accepted":
        raise _wrong_status(f"This request is {req.status}, so it can't be marked done.")
    req.status = "completed"
    req.completed_at = utcnow()
    listing.status = "completed"
    events.on_request_completed(db, req, user)
    return _done(db, req, user)


@router.post("/requests/{request_id}/cancel")
def cancel_request(
    request_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> RequestOut:
    req, listing = find_request(db, user, request_id, lock=True)
    if req.requester_id != user.id:
        raise ApiError(403, "forbidden", "Only the person who sent the request can cancel it.")
    if req.status not in OPEN:
        raise _wrong_status(f"This request is {req.status}, so it can't be cancelled.")
    was_accepted = req.status == "accepted"
    req.status = "cancelled"
    if was_accepted and listing.status == "pending":
        listing.status = "active"
    events.on_request_cancelled(db, req, user, was_accepted)
    return _done(db, req, user)
