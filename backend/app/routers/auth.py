"""POST /auth/login: log in or sign up with a .edu email."""

from __future__ import annotations

import re

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..auth import new_token
from ..campus import campus_domain, get_or_create_campus
from ..db import get_db
from ..errors import ApiError
from ..models import Campus, User, UserSession
from ..schemas import LoginIn, LoginOut
from ..serializers import user_out

router = APIRouter(tags=["auth"])

EDU_EMAIL = re.compile(r"^[^@\s]+@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+edu$")


def _find_or_create_user(db: Session, email: str, campus: Campus) -> tuple[User, bool]:
    user = db.scalar(select(User).where(User.email == email))
    if user:
        return user, False
    try:
        user = User(email=email, campus_id=campus.id)
        db.add(user)
        db.commit()
        return user, True
    except IntegrityError:
        db.rollback()
        return db.scalars(select(User).where(User.email == email)).one(), False


@router.post("/auth/login")
def login(body: LoginIn, db: Session = Depends(get_db)) -> LoginOut:
    email = body.email.strip().lower()
    if len(email) > 255 or not EDU_EMAIL.match(email):
        raise ApiError(400, "not_edu_email", "Use your college .edu email address.")

    campus = get_or_create_campus(db, campus_domain(email))
    user, is_new = _find_or_create_user(db, email, campus)

    token = new_token()
    db.add(UserSession(token=token, user_id=user.id))
    db.commit()
    return LoginOut(token=token, is_new=is_new, user=user_out(db, user))
