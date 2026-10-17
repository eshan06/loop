"""Bearer-token auth: the `current_user` dependency.

    @router.get("/me")
    def get_me(user: User = Depends(current_user), db: Session = Depends(get_db)): ...

Tokens live in the `sessions` table and never expire. A missing, malformed, or
unknown token answers 401 `unauthorized`.
"""

from __future__ import annotations

import secrets

from fastapi import Depends, Header
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import get_db
from .errors import ApiError
from .models import User, UserSession


def new_token() -> str:
    """32 hex characters, like the example in docs/API.md."""
    return secrets.token_hex(16)


def _bearer(authorization: str | None) -> str | None:
    if not authorization:
        return None
    scheme, _, token = authorization.strip().partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token or len(token) > 64:
        return None
    return token


def current_user(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User:
    token = _bearer(authorization)
    user = None
    if token:
        user = db.scalar(
            select(User).join(UserSession, UserSession.user_id == User.id).where(UserSession.token == token)
        )
    if user is None:
        raise ApiError(401, "unauthorized", "Please sign in again.")
    return user
