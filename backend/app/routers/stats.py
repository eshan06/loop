"""Impact and the dorm leaderboard: GET /impact/me, GET /impact/campus,
GET /leaderboard/dorms.

Impact counts when an exchange completes: every `completed` request, joined to
its listing, adds that listing's per-item estimate (app.impact) once.
"""

from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..impact import impact_total
from ..models import Listing, Request, User, utcnow
from ..schemas import CampusImpactOut, DormRankOut, ItemsList, MyImpactOut

router = APIRouter(tags=["impact"])

CAMPUS_WINDOW = timedelta(days=7)


def dorm_board(db: Session, campus_id: int) -> list[DormRankOut]:
    """Exchanges completed on the campus in the last 7 days, counted by the
    listing owner's dorm (owners without a dorm are skipped). Most first, ties
    alphabetical and sharing a rank (1, 1, 3). The leaderboard and
    /impact/campus's top_dorm both come from here so they can't disagree."""
    rows = db.execute(
        select(User.dorm, func.count(Request.id))
        .select_from(Request)
        .join(Listing, Listing.id == Request.listing_id)
        .join(User, User.id == Listing.owner_id)
        .where(
            Request.status == "completed",
            Request.completed_at >= utcnow() - CAMPUS_WINDOW,
            Listing.campus_id == campus_id,
            User.dorm.is_not(None),
            User.dorm != "",
        )
        .group_by(User.dorm)
    ).all()
    rows = sorted(rows, key=lambda r: (-r[1], r[0].casefold(), r[0]))
    board: list[DormRankOut] = []
    for i, (dorm, count) in enumerate(rows):
        rank = board[-1].rank if board and board[-1].items_shared == count else i + 1
        board.append(DormRankOut(rank=rank, dorm=dorm, items_shared=count))
    return board


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
        select(Listing.category)
        .select_from(Request)
        .join(Listing, Listing.id == Request.listing_id)
        .where(
            Request.status == "completed",
            Request.completed_at >= since,
            Listing.campus_id == user.campus_id,
        )
    ).all()
    board = dorm_board(db, user.campus_id)
    return CampusImpactOut(
        items_rehomed=len(rows),
        top_dorm=board[0].dorm if board else None,
        **impact_total(c for (c,) in rows),
    )


@router.get("/leaderboard/dorms")
def get_dorm_leaderboard(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> ItemsList[DormRankOut]:
    return ItemsList[DormRankOut](items=dorm_board(db, user.campus_id))
