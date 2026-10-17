"""The bell: GET /notifications and POST /notifications/read.

Rows are written by app/notifications.py (from the app/events.py hooks). Everything
here is scoped to the caller's own notifications.
"""

from __future__ import annotations

from fastapi import APIRouter, Body, Depends, Response
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..errors import ApiError
from ..models import Notification, User, utcnow
from ..paging import Paging, paged, paging_params
from ..schemas import NotificationPage, NotificationsReadIn
from ..serializers import notification_out

router = APIRouter(tags=["notifications"])

IDS_MAX = 500


def unread_count(db: Session, user_id: int) -> int:
    return db.scalar(
        select(func.count()).select_from(Notification)
        .where(Notification.user_id == user_id, Notification.read_at.is_(None))
    ) or 0


@router.get("/notifications")
def get_notifications(
    paging: Paging = Depends(paging_params),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> NotificationPage:
    stmt = (
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
    )
    rows, total = paged(db, stmt, paging)
    return NotificationPage(
        items=[notification_out(n) for n in rows],
        total=total,
        next_offset=paging.next_offset(len(rows), total),
        unread=unread_count(db, user.id),
    )


@router.post("/notifications/read", status_code=204)
def mark_notifications_read(
    body: NotificationsReadIn | None = Body(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Response:
    stmt = update(Notification).where(
        Notification.user_id == user.id, Notification.read_at.is_(None)
    )
    if body is not None and body.all is True:
        pass
    elif body is not None and body.ids is not None:
        if len(body.ids) > IDS_MAX:
            raise ApiError(400, "bad_request", f"ids: at most {IDS_MAX} at a time.")
        if not body.ids:
            return Response(status_code=204)
        stmt = stmt.where(Notification.id.in_(set(body.ids)))
    else:
        raise ApiError(400, "bad_request", 'Send {"ids": [...]} or {"all": true}.')
    db.execute(stmt.values(read_at=utcnow()).execution_options(synchronize_session=False))
    db.commit()
    return Response(status_code=204)
