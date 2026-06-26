"""
API error handlers.

Translates domain exceptions and general errors into
consistent HTTP responses.
"""

from __future__ import annotations

import logging

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.core.exceptions import ValidationError

logger = logging.getLogger(__name__)


async def validation_error_handler(
    request: Request,
    exc: ValidationError,
) -> JSONResponse:
    """Handle domain ValidationError → 400."""
    return JSONResponse(
        status_code=400,
        content={
            "detail": [
                {
                    "loc": ["body", exc.field] if exc.field else ["body"],
                    "msg": str(exc),
                    "type": "value_error",
                }
            ]
        },
    )


async def request_validation_error_handler(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    """Handle Pydantic/FastAPI validation errors → 422."""
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors()},
    )


async def unhandled_error_handler(
    request: Request,
    exc: Exception,
) -> JSONResponse:
    """Catch-all for unexpected errors → 500."""
    logger.exception("Unhandled error processing request")
    return JSONResponse(
        status_code=500,
        content={
            "detail": [
                {
                    "loc": [],
                    "msg": "Internal server error",
                    "type": "server_error",
                }
            ]
        },
    )