"""Pydantic request and response models. They must match docs/API.md.

Nullable fields are declared `X | None` with no default so they are always
present in the JSON (as null), never left out.
"""

from __future__ import annotations

from typing import Generic, TypeVar

from pydantic import BaseModel, StrictInt, StrictStr

T = TypeVar("T")


class Health(BaseModel):
    status: str


class ItemsList(BaseModel, Generic[T]):
    """Unpaged list: {"items": [...]}."""

    items: list[T]


# ---- User ------------------------------------------------------------------

class CampusOut(BaseModel):
    id: int
    name: str


class Sizes(BaseModel):
    top: str | None
    bottom: str | None
    shoe: str | None


class UserOut(BaseModel):
    id: int
    name: str | None
    email: str
    campus: CampusOut
    dorm: str | None
    class_year: int | None
    sizes: Sizes
    avatar_url: str | None
    items_shared: int
    created_at: str


class OwnerOut(BaseModel):
    id: int
    name: str | None
    dorm: str | None
    avatar_url: str | None
    items_shared: int


class PhotoOut(BaseModel):
    id: int
    url: str
    kind: str


# ---- Auth and profile ------------------------------------------------------

class LoginIn(BaseModel):
    email: StrictStr


class LoginOut(BaseModel):
    token: str
    is_new: bool
    user: UserOut


class SizesIn(BaseModel):
    top: StrictStr | None = None
    bottom: StrictStr | None = None
    shoe: StrictStr | None = None


class MePatch(BaseModel):
    """Every field optional; `model_fields_set` tells which ones were sent."""

    name: StrictStr | None = None
    dorm: StrictStr | None = None
    class_year: StrictInt | None = None
    sizes: SizesIn | None = None
    avatar_photo_id: StrictInt | None = None


class UnreadOut(BaseModel):
    notifications: int
    messages: int
    incoming_requests: int
