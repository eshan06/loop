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


class MeetupSpotOut(BaseModel):
    id: int
    name: str


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


# ---- Paging ----------------------------------------------------------------

class Page(BaseModel, Generic[T]):
    """Paged list: {"items": [...], "total": 87, "next_offset": 20 | null}."""

    items: list[T]
    total: int
    next_offset: int | None


# ---- Listings --------------------------------------------------------------

class ImpactOut(BaseModel):
    textile_kg: float
    water_l: float
    co2_kg: float


class ListingOut(BaseModel):
    id: int
    title: str
    category: str
    size: str | None
    color: str | None
    brand: str | None
    condition: str
    description: str | None
    tags: list[str]
    share_type: str
    status: str
    photos: list[PhotoOut]
    meetup_spot: MeetupSpotOut | None
    owner: OwnerOut
    impact: ImpactOut
    is_mine: bool
    saved_by_me: bool
    my_request_status: str | None
    my_request_id: int | None
    pending_request_count: int
    accepted_request_id: int | None
    created_at: str


class ListingIn(BaseModel):
    """Body of POST and PATCH /listings. Every field optional here; the router
    checks required fields (POST) and limits, so messages name the field.
    `model_fields_set` tells PATCH which fields were sent."""

    title: StrictStr | None = None
    category: StrictStr | None = None
    size: StrictStr | None = None
    color: StrictStr | None = None
    brand: StrictStr | None = None
    condition: StrictStr | None = None
    description: StrictStr | None = None
    tags: list[StrictStr] | None = None
    share_type: StrictStr | None = None
    meetup_spot_id: StrictInt | None = None
    photo_ids: list[StrictInt] | None = None


class ScanDraftOut(BaseModel):
    title: str | None
    category: str | None
    size: str | None
    color: str | None
    brand: str | None
    condition: str | None
    description: str | None
    tags: list[str]


class ScanOut(BaseModel):
    photos: list[PhotoOut]
    draft: ScanDraftOut
    source: str


# ---- Requests --------------------------------------------------------------

class RequestIn(BaseModel):
    """Body of POST /listings/{id}/requests. The body can be {} or missing."""

    note: StrictStr | None = None


class RequestListingOut(BaseModel):
    """The short listing summary inside a Request."""

    id: int
    title: str
    photo_url: str | None
    share_type: str
    status: str


class RequestOut(BaseModel):
    id: int
    listing: RequestListingOut
    requester: OwnerOut
    owner: OwnerOut
    note: str | None
    status: str
    unread_messages: int
    created_at: str
    updated_at: str


# ---- Messages --------------------------------------------------------------

class MessageIn(BaseModel):
    """Body of POST /requests/{id}/messages. The router trims and checks length."""

    body: StrictStr | None = None


class MessageOut(BaseModel):
    id: int
    request_id: int
    sender_id: int
    body: str
    created_at: str
