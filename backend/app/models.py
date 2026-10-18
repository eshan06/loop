"""SQLAlchemy 2 ORM models, one per table in backend/migrations/*.sql.

Column names and types mirror the SQL exactly; the migrations stay the source of
truth for the schema (nothing here calls create_all).

Timestamps are naive DATETIMEs holding UTC. Python-side defaults fill them on
insert so the ORM object has them without a refresh; app.serializers.iso()
formats them for the API.

One-to-many relationships use passive_deletes=True so deletes leave cascading
(CASCADE / SET NULL) to MySQL's foreign keys instead of loading children.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import JSON, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.mysql import INTEGER, SMALLINT
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

UInt = INTEGER(unsigned=True)
USmallInt = SMALLINT(unsigned=True)


def utcnow() -> datetime:
    """Current UTC time as a naive datetime with whole seconds (what the DB stores)."""
    return datetime.now(UTC).replace(tzinfo=None, microsecond=0)


class Base(DeclarativeBase):
    pass


def _created_at() -> Mapped[datetime]:
    return mapped_column(DateTime, nullable=False, default=utcnow, server_default=func.now())


def _updated_at() -> Mapped[datetime]:
    return mapped_column(
        DateTime, nullable=False, default=utcnow, onupdate=utcnow, server_default=func.now()
    )


class Campus(Base):
    __tablename__ = "campuses"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email_domain: Mapped[str] = mapped_column(String(120), nullable=False, unique=True)
    created_at: Mapped[datetime] = _created_at()

    users: Mapped[list[User]] = relationship(back_populates="campus", passive_deletes=True)
    dorms: Mapped[list[Dorm]] = relationship(
        back_populates="campus", order_by="Dorm.name", passive_deletes=True
    )
    meetup_spots: Mapped[list[MeetupSpot]] = relationship(
        back_populates="campus", order_by="MeetupSpot.name", passive_deletes=True
    )


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    campus_id: Mapped[int] = mapped_column(UInt, ForeignKey("campuses.id"), nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    name: Mapped[str | None] = mapped_column(String(80))
    dorm: Mapped[str | None] = mapped_column(String(80))
    class_year: Mapped[int | None] = mapped_column(USmallInt)
    size_top: Mapped[str | None] = mapped_column(String(16))
    size_bottom: Mapped[str | None] = mapped_column(String(16))
    size_shoe: Mapped[str | None] = mapped_column(String(16))
    # No foreign key in the schema (see 001_schema.sql); the API checks ownership.
    avatar_photo_id: Mapped[int | None] = mapped_column(UInt)
    # Listings ever created, including deleted ones (Closet Cleanout badge, 004_*.sql).
    listings_created: Mapped[int] = mapped_column(
        UInt, nullable=False, default=0, server_default="0"
    )
    created_at: Mapped[datetime] = _created_at()

    campus: Mapped[Campus] = relationship(back_populates="users")
    avatar_photo: Mapped[Photo | None] = relationship(
        primaryjoin="foreign(User.avatar_photo_id) == Photo.id", viewonly=True
    )
    listings: Mapped[list[Listing]] = relationship(
        back_populates="owner", foreign_keys="Listing.owner_id", passive_deletes=True
    )
    sessions: Mapped[list[UserSession]] = relationship(back_populates="user", passive_deletes=True)


class UserSession(Base):
    """A bearer token. Named UserSession so it doesn't clash with sqlalchemy.orm.Session."""

    __tablename__ = "sessions"

    token: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = _created_at()

    user: Mapped[User] = relationship(back_populates="sessions")


class MeetupSpot(Base):
    __tablename__ = "meetup_spots"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    campus_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("campuses.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    created_at: Mapped[datetime] = _created_at()

    campus: Mapped[Campus] = relationship(back_populates="meetup_spots")


class Listing(Base):
    __tablename__ = "listings"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    campus_id: Mapped[int] = mapped_column(UInt, ForeignKey("campuses.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    category: Mapped[str] = mapped_column(String(20), nullable=False)
    size: Mapped[str | None] = mapped_column(String(20))
    color: Mapped[str | None] = mapped_column(String(60))
    brand: Mapped[str | None] = mapped_column(String(80))
    # `condition` is a MySQL reserved word; quote it explicitly.
    condition: Mapped[str] = mapped_column("condition", String(20), nullable=False, quote=True)
    description: Mapped[str | None] = mapped_column(Text)
    tags: Mapped[list | None] = mapped_column(JSON)
    share_type: Mapped[str] = mapped_column(String(10), nullable=False)
    status: Mapped[str] = mapped_column(
        String(12), nullable=False, default="active", server_default="active"
    )
    meetup_spot_id: Mapped[int | None] = mapped_column(
        UInt, ForeignKey("meetup_spots.id", ondelete="SET NULL")
    )
    style_ideas: Mapped[list | dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = _created_at()
    updated_at: Mapped[datetime] = _updated_at()

    owner: Mapped[User] = relationship(back_populates="listings", foreign_keys=[owner_id])
    campus: Mapped[Campus] = relationship()
    meetup_spot: Mapped[MeetupSpot | None] = relationship()
    photos: Mapped[list[Photo]] = relationship(
        back_populates="listing",
        order_by=lambda: [Photo.position, Photo.id],
        passive_deletes=True,
    )
    requests: Mapped[list[Request]] = relationship(
        back_populates="listing", order_by="Request.id", passive_deletes=True
    )


class Photo(Base):
    __tablename__ = "photos"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    listing_id: Mapped[int | None] = mapped_column(
        UInt, ForeignKey("listings.id", ondelete="SET NULL")
    )
    # Order within the listing (0 = first, the feed card photo); NULL while unattached.
    position: Mapped[int | None] = mapped_column(USmallInt)
    kind: Mapped[str] = mapped_column(String(10), nullable=False)
    # Relative to MEDIA_DIR, e.g. "71.jpg"; settings.media_url(path) makes the URL.
    path: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = _created_at()

    owner: Mapped[User] = relationship(foreign_keys=[owner_id])
    listing: Mapped[Listing | None] = relationship(back_populates="photos")


class Request(Base):
    __tablename__ = "requests"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    listing_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("listings.id", ondelete="CASCADE"), nullable=False
    )
    requester_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    note: Mapped[str | None] = mapped_column(String(280))
    status: Mapped[str] = mapped_column(
        String(12), nullable=False, default="pending", server_default="pending"
    )
    created_at: Mapped[datetime] = _created_at()
    updated_at: Mapped[datetime] = _updated_at()
    completed_at: Mapped[datetime | None] = mapped_column(DateTime)
    owner_last_read_id: Mapped[int] = mapped_column(
        UInt, nullable=False, default=0, server_default="0"
    )
    requester_last_read_id: Mapped[int] = mapped_column(
        UInt, nullable=False, default=0, server_default="0"
    )

    listing: Mapped[Listing] = relationship(back_populates="requests")
    requester: Mapped[User] = relationship(foreign_keys=[requester_id])
    messages: Mapped[list[Message]] = relationship(
        back_populates="request", order_by="Message.id", passive_deletes=True
    )


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    request_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("requests.id", ondelete="CASCADE"), nullable=False
    )
    sender_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    body: Mapped[str] = mapped_column(String(1000), nullable=False)
    created_at: Mapped[datetime] = _created_at()

    request: Mapped[Request] = relationship(back_populates="messages")
    sender: Mapped[User] = relationship()


class Save(Base):
    __tablename__ = "saves"

    user_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    listing_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("listings.id", ondelete="CASCADE"), primary_key=True
    )
    created_at: Mapped[datetime] = _created_at()

    user: Mapped[User] = relationship()
    listing: Mapped[Listing] = relationship()


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    listing_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("listings.id", ondelete="CASCADE"), nullable=False
    )
    reporter_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    reason: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = _created_at()

    listing: Mapped[Listing] = relationship()
    reporter: Mapped[User] = relationship()


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    type: Mapped[str] = mapped_column(String(30), nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    body: Mapped[str | None] = mapped_column(String(500))
    request_id: Mapped[int | None] = mapped_column(
        UInt, ForeignKey("requests.id", ondelete="SET NULL")
    )
    listing_id: Mapped[int | None] = mapped_column(
        UInt, ForeignKey("listings.id", ondelete="SET NULL")
    )
    read_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = _created_at()

    user: Mapped[User] = relationship()


class UserBadge(Base):
    __tablename__ = "user_badges"

    user_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    badge_id: Mapped[str] = mapped_column(String(40), primary_key=True)
    earned_at: Mapped[datetime] = _created_at()
    created_at: Mapped[datetime] = _created_at()

    user: Mapped[User] = relationship()


class Dorm(Base):
    __tablename__ = "dorms"

    id: Mapped[int] = mapped_column(UInt, primary_key=True, autoincrement=True)
    campus_id: Mapped[int] = mapped_column(
        UInt, ForeignKey("campuses.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    created_at: Mapped[datetime] = _created_at()

    campus: Mapped[Campus] = relationship(back_populates="dorms")
