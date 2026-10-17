"""Impact: GET /impact/me and GET /impact/campus.

Impact counts when an exchange completes: every `completed` request, joined to
its listing, adds that listing's per-item estimate (app.impact) once.
"""

from __future__ import annotations

from collections import Counter
from datetime import timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..impact import impact_total
from ..models import Listing, Request, User, utcnow
from ..schemas import CampusImpactOut, MyImpactOut

router = APIRouter(tags=["impact"])

CAMPUS_WINDOW = timedelta(days=7)


@router.get("/impact/me")
def get_my_impact(user: User = Depends(current_user), db: Session = Depends(get_db)) -> MyImpactOut:
    """items_shared: my listings that completed; items_received: my requests that
    completed. The totals add up both sides' items."""
    rows = db.execute(
        select(Listing.owner_id, Request.requester_id, Listing.category)
        .select_from(Request)
        .join(Listing, Listing.id == Request.listing_id)
        .where(
            Request.status == "completed",
            (Listing.owner_id == user.id) | (Request.requester_id == user.id),
        )
    ).all()
    shared = sum(1 for owner, _, _ in rows if owner == user.id)
    received = sum(1 for _, requester, _ in rows if requester == user.id)
    return MyImpactOut(
        items_shared=shared, items_received=received, **impact_total(c for _, _, c in rows)
    )


@router.get("/impact/campus")
def get_campus_impact(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> CampusImpactOut:
    """Exchanges completed on my campus in the last 7 days. top_dorm is the owner
    dorm with the most of them (as the dorm leaderboard counts), ties by name."""
    since = utcnow() - CAMPUS_WINDOW
    rows = db.execute(
        select(Listing.category, User.dorm)
        .select_from(Request)
        .join(Listing, Listing.id == Request.listing_id)
        .join(User, User.id == Listing.owner_id)
        .where(
            Request.status == "completed",
            Request.completed_at >= since,
            Listing.campus_id == user.campus_id,
        )
    ).all()
    dorms = Counter(dorm for _, dorm in rows if dorm)
    top_dorm = min(dorms, key=lambda d: (-dorms[d], d)) if dorms else None
    return CampusImpactOut(
        items_rehomed=len(rows), top_dorm=top_dorm, **impact_total(c for c, _ in rows)
    )
