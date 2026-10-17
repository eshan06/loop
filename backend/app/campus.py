"""Campuses: find-or-create from an email domain, and default meetup spots.

A campus is created the first time someone from its domain logs in. It gets
DEFAULT_MEETUP_SPOTS right away so the listing form always has a spot to pick.
Campuses that somehow have none (older rows) get the defaults the first time
their spots are read, via ensure_meetup_spots.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .models import Campus, MeetupSpot

DEFAULT_MEETUP_SPOTS: tuple[str, ...] = (
    "Main Library entrance",
    "Student Union",
    "Main Dining Hall",
    "Campus Center",
)


def campus_domain(email: str) -> str:
    """Last two labels of the domain: jordan@alumni.vanderbilt.edu -> vanderbilt.edu."""
    return ".".join(email.rsplit("@", 1)[1].split(".")[-2:])


def campus_name(domain: str) -> str:
    """tufts.edu -> Tufts, cal-poly.edu -> Cal Poly."""
    return domain.split(".")[0].replace("-", " ").title()


def get_or_create_campus(db: Session, domain: str) -> Campus:
    """The campus for this email domain, created (with default spots) if new."""
    campus = db.scalar(select(Campus).where(Campus.email_domain == domain))
    if campus:
        return campus
    try:
        campus = Campus(name=campus_name(domain), email_domain=domain)
        campus.meetup_spots = [MeetupSpot(name=n) for n in DEFAULT_MEETUP_SPOTS]
        db.add(campus)
        db.commit()
        return campus
    except IntegrityError:  # another login created it first
        db.rollback()
        return db.scalars(select(Campus).where(Campus.email_domain == domain)).one()


def campus_meetup_spots(db: Session, campus_id: int) -> list[MeetupSpot]:
    return list(
        db.scalars(
            select(MeetupSpot)
            .where(MeetupSpot.campus_id == campus_id)
            .order_by(MeetupSpot.name, MeetupSpot.id)
        )
    )


def ensure_meetup_spots(db: Session, campus_id: int) -> list[MeetupSpot]:
    """The campus's spots sorted by name, inserting the defaults first if it has none."""
    spots = campus_meetup_spots(db, campus_id)
    if spots:
        return spots
    try:
        db.add_all(MeetupSpot(campus_id=campus_id, name=n) for n in DEFAULT_MEETUP_SPOTS)
        db.commit()
    except IntegrityError:  # a concurrent request inserted them first
        db.rollback()
    return campus_meetup_spots(db, campus_id)
