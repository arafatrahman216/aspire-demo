"""
FastAPI application factory.

Creates, configures, and returns the FastAPI app instance.
Call create_app() to bootstrap the application.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError

from app.api.errors import (
    request_validation_error_handler,
    unhandled_error_handler,
    validation_error_handler,
)
from app.api.v1.router import router as v1_router
from app.core.config import settings
from app.core.exceptions import ValidationError
from app.core.logging import setup_logging
from app.db.session import create_tables

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan — startup and shutdown logic."""
    setup_logging(settings.log_level)
    logger.info(
        "Starting Lead Qualifier",
        extra={"env": settings.app_env, "debug": settings.app_debug},
    )

    # SQLite + a single-table schema: create_all on startup is acceptable.
    # For Postgres, swap this for proper migrations before going live.
    await create_tables()
    logger.info("Database tables created/verified")

    yield

    logger.info("Shutting down Lead Qualifier")


def create_app() -> FastAPI:
    """Build and return a fully-configured FastAPI application."""
    app = FastAPI(
        title="Lead Qualifier API",
        description="AI-powered Lead Qualification & Response Automation",
        version="1.0.0",
        lifespan=lifespan,
    )

    # ── Routes ───────────────────────────────────────────
    app.include_router(v1_router)

    # ── Error handlers ───────────────────────────────────
    app.add_exception_handler(ValidationError, validation_error_handler)
    app.add_exception_handler(RequestValidationError, request_validation_error_handler)
    app.add_exception_handler(Exception, unhandled_error_handler)

    # ── Health check ─────────────────────────────────────
    @app.get("/health", status_code=200)
    async def health():
        return {"status": "ok"}

    return app


app = create_app()