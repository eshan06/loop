"""Hooks for request events. The requests router calls these inside the same
transaction as the state change, before commit, so anything they add to `db`
(notifications, badges) commits or rolls back with it. They must not commit.

Today they do nothing. Later tasks fill them in:
- S-23 notifications: request_received (created), request_accepted (accepted),
  request_declined (declined, including every request an accept auto-declines).
  complete and cancel send none (docs/API.md).
- S-22 badges: check first_swap / giving_back on completed; closet_cleanout is
  about listings, not requests.

`actor` is the user who did the action. The request's listing is `req.listing`.
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from .models import Request, User


def on_request_created(db: Session, req: Request, actor: User) -> None:
    """The requester sent a request (status pending)."""


def on_request_accepted(db: Session, req: Request, actor: User) -> None:
    """The owner accepted `req`; the listing is now pending."""


def on_request_declined(db: Session, req: Request, actor: User, auto: bool = False) -> None:
    """`req` was declined: by the owner (auto=False), or because the owner accepted
    another request on the same listing (auto=True). Both send request_declined."""


def on_request_completed(db: Session, req: Request, actor: User) -> None:
    """Either side marked the exchange done; the listing is now completed."""


def on_request_cancelled(db: Session, req: Request, actor: User, was_accepted: bool) -> None:
    """The requester withdrew. If it was accepted, the listing went back to active."""
