"""Bearer-token lookup dependency. Implemented in S-8 (POST /auth/login)."""

from fastapi import Header

from .errors import ApiError


def current_user(authorization: str | None = Header(default=None)):
    """Placeholder until S-8: every authenticated route answers 401."""
    raise ApiError(401, "unauthorized", "Please sign in again.")
