"""
Webhook request/response DTOs.

Defines the public API contract for the inbound lead endpoint.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class WebhookPayload(BaseModel):
    """Expected shape of the incoming webhook JSON body."""

    full_name: str = Field(..., min_length=1, examples=["Jordan Ellis"])
    email: str = Field(..., examples=["jordan.ellis@examplecorp.com"])
    company_name: str | None = Field(None, examples=["Example Corp"])
    job_title: str | None = Field(None, examples=["Operations Manager"])
    phone: str | None = Field(None, examples=[""])
    company_size: str | None = Field(None, examples=["11-50"])
    budget_range: str | None = Field(None, examples=["$5k-$15k/mo"])
    message: str | None = Field(None, examples=["We need automation..."])


class WebhookResponse(BaseModel):
    """Synchronous response returned to the webhook caller."""

    status: str = Field(
        ...,
        description="One of: qualified, qualified_fallback, rejected, low_context",
    )
    lead_id: str
    lead_score: int | None = None
    priority_tier: str | None = None
    intent_summary: str | None = None
    suggested_opener: str | None = None
    red_flags: list[str] = Field(default_factory=list)
    reason: str | None = None
    notification_sent: bool = False