"""Writing notifications (docs/API.md "Notification").

`notify` is the one way to add a row; the builders below write the request and
message notifications, and app/events.py calls them from the request/message
hooks. Badge code (S-22) calls `notify(db, user_id, "badge_earned", title, body)`
with both IDs None. Nothing here commits: rows ride on the caller's transaction.

The seed (backend/seed/seed.py) calls the same builders with `at=` so the demo's
notifications look exactly like ones the API wrote.

Rules (also in docs/API.md):
- Nobody is notified about their own action.
- new_message collapses: while the recipient still has an unread new_message for
  a request, the next message updates that row (title counts the unread
  messages, body is the newest text, created_at moves to now) instead of adding
  another. Reading the chat (GET /requests/{id}/messages) or replying marks the
  reader's new_message rows for that request read.
- When the owner accepts or declines a request, their request_received for it is
  marked read (they've dealt with it).
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from .models import Listing, Message, Notification, Request, User, utcnow

TYPES = ("request_received", "request_accepted", "request_declined", "new_message", "badge_earned")
PREVIEW_MAX = 140


def notify(
    db: Session,
    user_id: int,
    type: str,
    title: str,
    body: str | None,
    request_id: int | None = None,
    listing_id: int | None = None,
    at: datetime | None = None,
) -> Notification:
    """Add one unread notification for `user_id` (no commit). `at` overrides created_at
    (the seed uses it); the API leaves it None for "now"."""
    assert type in TYPES, f"unknown notification type {type!r}"
    n = Notification(
        user_id=user_id, type=type, title=_clip(title, 160), body=_clip(body, 500),
        request_id=request_id, listing_id=listing_id, created_at=at or utcnow(),
    )
    db.add(n)
    return n


def mark_read(db: Session, user_id: int, request_id: int, types: tuple[str, ...],
              at: datetime | None = None) -> None:
    """Mark `user_id`'s unread notifications of `types` on `request_id` read (no commit)."""
    db.flush()  # a bulk UPDATE doesn't autoflush: rows still pending would be missed
    db.execute(
        update(Notification)
        .where(Notification.user_id == user_id, Notification.request_id == request_id,
               Notification.type.in_(types), Notification.read_at.is_(None))
        .values(read_at=at or utcnow())
        .execution_options(synchronize_session=False)
    )


# ---- Builders --------------------------------------------------------------------


def request_received(db: Session, req: Request, at: datetime | None = None) -> Notification | None:
    """The requester sent `req`: tell the owner."""
    listing = _listing(db, req)
    requester = db.get(User, req.requester_id)
    if listing.owner_id == req.requester_id:
        return None
    return notify(db, listing.owner_id, "request_received",
                  f"{first_name(requester)} requested your item", listing.title,
                  req.id, listing.id, at)


def request_accepted(db: Session, req: Request, at: datetime | None = None) -> Notification | None:
    """The owner accepted `req`: tell the requester; the owner's request_received is done."""
    listing = _listing(db, req)
    if listing.owner_id == req.requester_id:
        return None
    mark_read(db, listing.owner_id, req.id, ("request_received",), at)
    owner = db.get(User, listing.owner_id)
    return notify(db, req.requester_id, "request_accepted",
                  f"{first_name(owner)} accepted your request", listing.title,
                  req.id, listing.id, at)


def request_declined(db: Session, req: Request, auto: bool = False,
                     at: datetime | None = None) -> Notification | None:
    """`req` was declined (auto: the owner accepted someone else): tell the requester."""
    listing = _listing(db, req)
    if listing.owner_id == req.requester_id:
        return None
    mark_read(db, listing.owner_id, req.id, ("request_received",), at)
    owner = db.get(User, listing.owner_id)
    title = (f"{first_name(owner)} gave this one to someone else" if auto
             else f"{first_name(owner)} declined your request")
    return notify(db, req.requester_id, "request_declined", title, listing.title,
                  req.id, listing.id, at)


def new_message(db: Session, msg: Message, req: Request,
                at: datetime | None = None) -> Notification | None:
    """`msg` was sent on `req`: tell the other person, collapsing into their unread
    new_message for this request if there is one. Also marks the sender's own
    new_message rows for the request read (replying means they've seen the chat)."""
    listing = _listing(db, req)
    sender_id = msg.sender_id
    recipient_id = req.requester_id if sender_id == listing.owner_id else listing.owner_id
    if recipient_id == sender_id:
        return None
    mark_read(db, sender_id, req.id, ("new_message",), at)

    marker = req.requester_last_read_id if recipient_id == req.requester_id else req.owner_last_read_id
    unread = db.scalar(
        select(func.count()).select_from(Message).where(
            Message.request_id == req.id, Message.sender_id != recipient_id,
            Message.id > (marker or 0), Message.id <= msg.id,
        )
    ) or 1
    sender = db.get(User, sender_id)
    who = first_name(sender)
    title = f"{who} sent you a message" if unread == 1 else f"{who} sent you {unread} messages"
    body = _preview(msg.body)

    existing = db.scalar(
        select(Notification)
        .where(Notification.user_id == recipient_id, Notification.request_id == req.id,
               Notification.type == "new_message", Notification.read_at.is_(None))
        .order_by(Notification.id.desc())
        .limit(1)
    )
    if existing is not None:
        existing.title = _clip(title, 160)
        existing.body = _clip(body, 500)
        existing.created_at = at or utcnow()
        return existing
    return notify(db, recipient_id, "new_message", title, body, req.id, listing.id, at)


# ---- Helpers ---------------------------------------------------------------------


def first_name(user: User | None) -> str:
    name = ((user.name if user else None) or "").strip()
    return name.split()[0] if name else "Someone"


def _listing(db: Session, req: Request) -> Listing:
    return req.listing if req.listing is not None else db.get(Listing, req.listing_id)


def _preview(text: str) -> str:
    text = " ".join(text.split())
    return text if len(text) <= PREVIEW_MAX else text[: PREVIEW_MAX - 1].rstrip() + "…"


def _clip(text: str | None, n: int) -> str | None:
    if text is None:
        return None
    return text if len(text) <= n else text[: n - 1] + "…"
