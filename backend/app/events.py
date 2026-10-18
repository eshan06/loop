"""Hooks for listing, request and message events. The routers call these inside the same
transaction as the state change, before commit, so anything they add to `db`
(notifications, badges) commits or rolls back with it. They must not commit.

- S-23 notifications (app/notifications.py): request_received (created),
  request_accepted (accepted), request_declined (declined, including every request
  an accept auto-declines), new_message (message sent, to the other person,
  collapsed into their unread one). complete and cancel send none (docs/API.md).
- S-22 badges (app/badges.py): check_badges for the owner when a listing is created
  (closet_cleanout) and for both sides when a request completes (first_swap,
  giving_back). New badges write a badge_earned notification.

`actor` is the user who did the action. The request's listing is `req.listing`.
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from . import badges, notifications
from .models import Listing, Message, Request, User


def on_listing_created(db: Session, listing: Listing, actor: User) -> None:
    """`actor` posted `listing` (POST /listings, after flush)."""
    badges.check_badges(db, actor)


def on_request_created(db: Session, req: Request, actor: User) -> None:
    """The requester sent a request (status pending)."""
    notifications.request_received(db, req)


def on_request_accepted(db: Session, req: Request, actor: User) -> None:
    """The owner accepted `req`; the listing is now pending."""
    notifications.request_accepted(db, req)


def on_request_declined(db: Session, req: Request, actor: User, auto: bool = False) -> None:
    """`req` was declined: by the owner (auto=False), or because the owner accepted
    another request on the same listing (auto=True). Both send request_declined."""
    notifications.request_declined(db, req, auto=auto)


def on_request_completed(db: Session, req: Request, actor: User) -> None:
    """Either side marked the exchange done; the listing is now completed."""
    listing = req.listing if req.listing is not None else db.get(Listing, req.listing_id)
    for uid in (listing.owner_id, req.requester_id):
        user = actor if uid == actor.id else db.get(User, uid)
        badges.check_badges(db, user)


def on_request_cancelled(db: Session, req: Request, actor: User, was_accepted: bool) -> None:
    """The requester withdrew. If it was accepted, the listing went back to active."""


def on_message_sent(db: Session, msg: Message, req: Request, actor: User) -> None:
    """`actor` sent `msg` on the accepted request `req` (the messages router calls
    this after flush, so msg.id is set). The other person is req.requester_id or
    req.listing.owner_id, whichever isn't actor.id."""
    notifications.new_message(db, msg, req)
