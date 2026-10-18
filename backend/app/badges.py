"""Badges (docs/API.md "GET /me/badges"): one rules table, progress computed from the DB.

- first_swap       First Swap: one completed exchange, on either side.
- giving_back      Giving Back: five of my `donate` listings completed.
- closet_cleanout  Closet Cleanout: ten listings created, counting ones since deleted
                   or completed (users.listings_created, since DELETE removes the row).

`check_badges(db, user)` is called inside the API's transaction (app/events.py:
listing created -> owner, request completed -> both sides). It inserts a
`user_badges` row for each badge whose goal is newly reached and writes one
`badge_earned` notification per new badge. Idempotent: a badge already earned is
never inserted or notified again (primary key user_id + badge_id). It never commits.

The seed calls it with `backdate=True`: each new badge's earned_at (and its
notification's created_at) is the moment the history shows the goal was reached.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from . import notifications
from .models import Listing, Request, User, UserBadge, utcnow


def _exchanges(user: User):
    """Completed requests where `user` is the owner or the requester."""
    return (
        select(Request.completed_at)
        .join(Listing, Listing.id == Request.listing_id)
        .where(Request.status == "completed",
               or_(Request.requester_id == user.id, Listing.owner_id == user.id))
    )


def _donations(user: User):
    """Completed requests on `user`'s donate listings (each listing completes once)."""
    return (
        select(Request.completed_at)
        .join(Listing, Listing.id == Request.listing_id)
        .where(Request.status == "completed", Listing.owner_id == user.id,
               Listing.share_type == "donate", Listing.status == "completed")
    )


def _count(db: Session, stmt) -> int:
    return len(db.scalars(stmt).all())


def _nth_time(db: Session, stmt, n: int) -> datetime | None:
    """When the n-th event happened (oldest first), or None if there aren't n."""
    times = sorted(t for t in db.scalars(stmt).all() if t is not None)
    return times[n - 1] if len(times) >= n else None


def _listings_made(db: Session, user: User) -> int:
    existing = _count(db, select(Listing.id).where(Listing.owner_id == user.id))
    return max(user.listings_created or 0, existing)


def _nth_listing_at(db: Session, user: User, n: int) -> datetime | None:
    times = sorted(db.scalars(select(Listing.created_at).where(Listing.owner_id == user.id)))
    return times[n - 1] if len(times) >= n else None


@dataclass(frozen=True)
class Rule:
    id: str
    name: str
    description: str
    goal: int
    progress: Callable[[Session, User], int]
    # When the history shows the goal was reached (seed backdating); None if unknown.
    reached_at: Callable[[Session, User, int], datetime | None]


# In GET /me/badges order.
RULES: tuple[Rule, ...] = (
    Rule("first_swap", "First Swap", "Complete your first exchange", 1,
         lambda db, u: _count(db, _exchanges(u)),
         lambda db, u, n: _nth_time(db, _exchanges(u), n)),
    Rule("giving_back", "Giving Back", "Donate five items", 5,
         lambda db, u: _count(db, _donations(u)),
         lambda db, u, n: _nth_time(db, _donations(u), n)),
    Rule("closet_cleanout", "Closet Cleanout", "List ten items", 10,
         _listings_made, _nth_listing_at),
)
BADGE_IDS = tuple(r.id for r in RULES)


def earned(db: Session, user: User) -> dict[str, datetime]:
    """badge id -> earned_at for `user`'s earned badges."""
    rows = db.scalars(select(UserBadge).where(UserBadge.user_id == user.id)).all()
    return {b.badge_id: b.earned_at for b in rows}


def check_badges(db: Session, user: User, at: datetime | None = None,
                 backdate: bool = False) -> list[str]:
    """Award every badge `user` has newly reached (no commit). Returns the new badge ids.
    `at` is the earned time (default now); with `backdate`, the time comes from the
    history instead (falling back to `at`)."""
    db.flush()  # the caller's pending changes (status, new listing) must count
    have = earned(db, user)
    new: list[str] = []
    for rule in RULES:
        if rule.id in have or rule.progress(db, user) < rule.goal:
            continue
        when = (rule.reached_at(db, user, rule.goal) if backdate else None) or at or utcnow()
        when = when.replace(microsecond=0)
        db.add(UserBadge(user_id=user.id, badge_id=rule.id, earned_at=when, created_at=when))
        notifications.notify(db, user.id, "badge_earned", f"You earned {rule.name}",
                             rule.description, at=when)
        new.append(rule.id)
    if new:
        db.flush()
    return new


def badges_for(db: Session, user: User) -> list[dict]:
    """Every badge in RULES order: id, name, description, earned_at, progress, goal.
    `progress` stops at `goal`, and an earned badge shows the goal reached."""
    have = earned(db, user)
    out = []
    for rule in RULES:
        got = have.get(rule.id)
        progress = rule.goal if got else min(rule.progress(db, user), rule.goal)
        out.append({"id": rule.id, "name": rule.name, "description": rule.description,
                    "earned_at": got, "progress": progress, "goal": rule.goal})
    return out
