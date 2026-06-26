"""
API v1 router.

Aggregates all v1 endpoints under /api/v1.
"""

from fastapi import APIRouter

from app.api.v1.webhook import router as webhook_router

router = APIRouter(prefix="/api/v1")
router.include_router(webhook_router)