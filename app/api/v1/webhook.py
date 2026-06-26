"""
Webhook endpoint for inbound lead submissions.

POST /api/v1/webhook

Accepts a lead payload, runs the qualification pipeline,
and returns a synchronous result.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.deps import get_qualifier_service
from app.schemas.webhook import WebhookPayload, WebhookResponse
from app.services.lead_qualifier import LeadQualifierService

router = APIRouter()


@router.post(
    "/webhook",
    response_model=WebhookResponse,
    status_code=200,
    summary="Receive and qualify a new lead",
    description=(
        "Validates, filters, AI-analyzes, persists, and notifies "
        "for an inbound lead. Returns a synchronous response."
    ),
)
async def receive_lead(
    payload: WebhookPayload,
    qualifier: LeadQualifierService = Depends(get_qualifier_service),
) -> WebhookResponse:
    """Process an inbound lead through the full qualification pipeline."""
    return await qualifier.process_lead(payload)