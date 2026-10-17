"""Chat on a request: GET and POST /requests/{id}/messages.

Only the requester and the owner can read or send (same rules as GET
/requests/{id}: another campus is 404, anyone else on the campus is 403).
Reading works in any request status; sending only while it's `accepted`.

Read state is one marker per side on the request row (requester_last_read_id,
owner_last_read_id): unread_messages counts the other person's messages above
it. The app polls GET every 3 seconds, so GET is a few primary-key lookups plus
one range scan on ix_messages_request (request_id, id), and it only writes when
the marker actually moves.
"""

from __future__ import annotations

from fastapi import APIRouter, Body, Depends, Query
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from .. import events
from ..auth import current_user
from ..db import get_db
from ..errors import ApiError
from ..models import Message, Request, User, utcnow
from ..schemas import ItemsList, MessageIn, MessageOut
from ..serializers import message_out
from .requests import find_request

router = APIRouter(tags=["messages"])

BODY_MAX = 1000


def _read_marker(req: Request, user: User):
    """The caller's read-marker column on `req`."""
    return Request.requester_last_read_id if user.id == req.requester_id else Request.owner_last_read_id


@router.get("/requests/{request_id}/messages")
def get_messages(
    request_id: int,
    after_id: int | None = Query(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ItemsList[MessageOut]:
    req, _ = find_request(db, user, request_id)
    stmt = select(Message).where(Message.request_id == req.id)
    if after_id is not None:
        stmt = stmt.where(Message.id > after_id)
    msgs = db.scalars(stmt.order_by(Message.id)).all()

    if msgs:
        # Mark read up to the newest returned message. The WHERE keeps the marker
        # from moving backwards (an old after_id), and setting updated_at to itself
        # stops both the ORM onupdate and MySQL's ON UPDATE CURRENT_TIMESTAMP from
        # bumping it: reading shouldn't reorder the Requests inbox.
        marker = _read_marker(req, user)
        newest = msgs[-1].id
        db.execute(
            update(Request)
            .where(Request.id == req.id, marker < newest)
            .values({marker: newest, Request.updated_at: Request.updated_at})
            .execution_options(synchronize_session=False)
        )
        db.commit()
    return ItemsList[MessageOut](items=[message_out(m) for m in msgs])


@router.post("/requests/{request_id}/messages", status_code=201)
def send_message(
    request_id: int,
    body: MessageIn | None = Body(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> MessageOut:
    text = ((body.body if body else None) or "").strip()
    if not text:
        raise ApiError(400, "bad_request", "body: write a message first.")
    if len(text) > BODY_MAX:
        raise ApiError(400, "bad_request", f"body: must be at most {BODY_MAX} characters.")

    req, _ = find_request(db, user, request_id, lock=True)
    if req.status != "accepted":
        raise ApiError(409, "wrong_status", f"This request is {req.status}, so chat is closed.")

    msg = Message(request_id=req.id, sender_id=user.id, body=text)
    db.add(msg)
    db.flush()
    # The sender has seen everything up to their own message.
    if user.id == req.requester_id:
        req.requester_last_read_id = max(req.requester_last_read_id, msg.id)
    else:
        req.owner_last_read_id = max(req.owner_last_read_id, msg.id)
    # New chat activity moves the request to the top of GET /me/requests.
    req.updated_at = utcnow()
    events.on_message_sent(db, msg, req, user)
    db.commit()
    return message_out(msg)
