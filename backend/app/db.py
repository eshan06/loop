"""SQLAlchemy engine and sessions.

Nothing here connects at import time: the engine is built on first use and
only opens a connection when a session runs a query. The API starts (and
/health answers) even when MySQL is unreachable.
"""

from __future__ import annotations

from collections.abc import Iterator
from functools import lru_cache

from sqlalchemy import URL, Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from .config import settings


def database_url() -> URL:
    return URL.create(
        "mysql+mysqlconnector",
        username=settings.db_user,
        password=settings.db_password,
        host=settings.db_host,
        port=settings.db_port,
        database=settings.db_name,
        query={"charset": "utf8mb4"},
    )


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    return create_engine(
        database_url(),
        pool_pre_ping=True,  # drop connections MySQL closed while idle
        pool_recycle=1800,  # and recycle before wait_timeout can bite
        pool_size=5,
        max_overflow=10,
        connect_args={"connection_timeout": 10},
    )


SessionLocal = sessionmaker(autoflush=False, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """FastAPI dependency: one session per request, always closed."""
    db = SessionLocal(bind=get_engine())
    try:
        yield db
    finally:
        db.close()
