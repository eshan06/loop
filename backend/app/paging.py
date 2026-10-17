"""Paging for list endpoints (docs/API.md "Paging"): limit (default 20, max 50)
and offset (default 0), answered as {"items", "total", "next_offset"}.

    def get_things(paging: Paging = Depends(paging_params), ...):
        rows, total = paged(db, select(Thing).where(...).order_by(...), paging)
        return Page[ThingOut](items=[...], total=total, next_offset=paging.next_offset(len(rows), total))
"""

from __future__ import annotations

from dataclasses import dataclass

from fastapi import Query
from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from .errors import ApiError

DEFAULT_LIMIT = 20
MAX_LIMIT = 50


@dataclass(frozen=True)
class Paging:
    limit: int
    offset: int

    def next_offset(self, returned: int, total: int) -> int | None:
        nxt = self.offset + returned
        return nxt if returned and nxt < total else None


def paging_params(limit: int = Query(DEFAULT_LIMIT), offset: int = Query(0)) -> Paging:
    """FastAPI dependency. A limit over 50 is treated as 50."""
    if limit < 1:
        raise ApiError(400, "bad_request", "limit: must be at least 1.")
    if offset < 0:
        raise ApiError(400, "bad_request", "offset: must be 0 or more.")
    return Paging(limit=min(limit, MAX_LIMIT), offset=offset)


def paged(db: Session, stmt: Select, paging: Paging) -> tuple[list, int]:
    """(this page's rows, total matching rows) for an ORM select like select(Listing)."""
    total = db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0
    rows = list(db.scalars(stmt.limit(paging.limit).offset(paging.offset)))
    return rows, total
