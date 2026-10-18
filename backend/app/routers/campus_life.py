"""GET /events and GET /donation-bins: the Swap Day tab and the campus map (S-27).

Both are read-only and scoped to the caller's campus. Rows come from the seed
(backend/seed/seed.py); there is no endpoint to create them.
"""

from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..models import DonationBin, Event, User, utcnow
from ..schemas import DonationBinOut, EventOut, ItemsList
from ..serializers import donation_bin_out, event_out

router = APIRouter(tags=["campus life"])

# By default an event stays listed for a day after it ends ("happened yesterday").
RECENT_GRACE = timedelta(days=1)

EVENT_KINDS = ("swap_day", "donation_drive", "repair_workshop")


@router.get("/events")
def get_events(
    include_past: bool = Query(False),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ItemsList[EventOut]:
    now = utcnow()
    q = select(Event).where(Event.campus_id == user.campus_id)
    if not include_past:
        q = q.where(Event.ends_at >= now - RECENT_GRACE)
    events = db.scalars(q.order_by(Event.starts_at, Event.id))
    return ItemsList[EventOut](items=[event_out(e, now) for e in events])


@router.get("/donation-bins")
def get_donation_bins(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> ItemsList[DonationBinOut]:
    bins = db.scalars(
        select(DonationBin)
        .where(DonationBin.campus_id == user.campus_id)
        .order_by(DonationBin.name, DonationBin.id)
    )
    return ItemsList[DonationBinOut](items=[donation_bin_out(b) for b in bins])
