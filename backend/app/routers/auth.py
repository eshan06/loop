"""POST /auth/login: log in or sign up with a .edu email."""

from __future__ import annotations

import re

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..auth import new_token
from ..db import get_db
from ..errors import ApiError
from ..models import Campus, User, UserSession
from ..schemas import LoginIn, LoginOut
from ..serializers import user_out

router = APIRouter(tags=["auth"])

EDU_EMAIL = re.compile(r"^[^@\s]+@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+edu$")


def campus_domain(email: str) -> str:
    """Last two labels of the domain: jordan@alumni.vanderbilt.edu -> vanderbilt.edu."""
    return ".".join(email.rsplit("@", 1)[1].split(".")[-2:])


def campus_name(domain: str) -> str:
    """tufts.edu -> Tufts, cal-poly.edu -> Cal Poly."""
    return domain.split(".")[0].replace("-", " ").title()


def _find_or_create_campus(db: Session, domain: str) -> Campus:
    campus = db.scalar(select(Campus).where(Campus.email_domain == domain))
    if campus:
        return campus
    try:
        campus = Campus(name=campus_name(domain), email_domain=domain)
        db.add(campus)
        db.commit()
        return campus
    except IntegrityError:  # another login created it first
        db.rollback()
        return db.scalars(select(Campus).where(Campus.email_domain == domain)).one()


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

    campus = _find_or_create_campus(db, campus_domain(email))
    user, is_new = _find_or_create_user(db, email, campus)

    token = new_token()
    db.add(UserSession(token=token, user_id=user.id))
    db.commit()
    return LoginOut(token=token, is_new=is_new, user=user_out(db, user))
