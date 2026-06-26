"""Async SQLAlchemy engine and session factory."""

from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import settings

IS_SQLITE = settings.database_url.startswith("sqlite")

# For SQLite, aiosqlite uses a background thread per connection; allow that.
connect_args: dict = {"check_same_thread": False} if IS_SQLITE else {}

engine = create_async_engine(
    settings.database_url,
    echo=False,
    connect_args=connect_args,
)


# Enable WAL mode + busy timeout for SQLite. Without WAL, concurrent writers
# serialize (or fail) on the database lock, breaking the concurrency guarantee.
if IS_SQLITE:
    @event.listens_for(engine.sync_engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, _):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.execute("PRAGMA busy_timeout=5000")
        cursor.close()


async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    """Declarative base for all ORM models."""


async def get_db_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency that yields an async database session."""
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def create_tables() -> None:
    """Create all tables defined in the ORM models (dev/testing only)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)