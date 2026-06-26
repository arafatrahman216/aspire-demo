"""
Pydantic DTOs for lead data.

These schemas define the contract between layers. No raw dictionaries
are passed across service boundaries.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, EmailStr, Field


class LeadCreate(BaseModel):
    """Raw inbound lead payload."""

    full_name: str = Field(..., min_length=1, max_length=255)
    email: EmailStr
    company_name: str | None = Field(None, max_length=255)
    job_title: str | None = Field(None, max_length=255)
    phone: str | None = Field(None, max_length=50)
    company_size: str | None = Field(None, max_length=50)
    budget_range: str | None = Field(None, max_length=100)
    message: str | None = Field(None, max_length=5000)


class LeadAnalysis(BaseModel):
    """AI-generated analysis stuck onto a qualified lead."""

    lead_score: int = Field(..., ge=1, le=100)
    priority_tier: str = Field(..., pattern=r"^(Hot|Warm|Cold|Manual Review)$")
    intent_summary: str = Field(..., max_length=500)
    suggested_opener: str = Field(..., max_length=1000)
    red_flags: list[str] = Field(default_factory=list)


class LeadResponse(BaseModel):
    """Full lead record returned to the caller."""

    id: str
    full_name: str
    email: str
    company_name: str | None
    job_title: str | None
    phone: str | None
    company_size: str | None
    budget_range: str | None
    message: str | None
    lead_score: int | None = None
    priority_tier: str | None = None
    intent_summary: str | None = None
    suggested_opener: str | None = None
    red_flags: list[str]
    workflow_status: str
    error_message: str | None = None
    notification_sent: bool
    received_at: datetime
    processed_at: datetime | None

    model_config = {"from_attributes": True}


class LeadTableRow(BaseModel):
    """Flat dict representation for Google Sheets row append."""

    lead_id: str
    full_name: str
    email: str
    company_name: str
    job_title: str
    phone: str
    company_size: str
    budget_range: str
    message: str
    lead_score: str
    priority_tier: str
    intent_summary: str
    suggested_opener: str
    red_flags: str
    received_at: str
    processed_at: str

    @classmethod
    def from_orm_lead(cls, lead: Any) -> "LeadTableRow":
        red_flags = lead.red_flags or []
        return cls(
            lead_id=str(lead.id),
            full_name=str(lead.full_name or ""),
            email=str(lead.email or ""),
            company_name=str(lead.company_name or ""),
            job_title=str(lead.job_title or ""),
            phone=str(lead.phone or ""),
            company_size=str(lead.company_size or ""),
            budget_range=str(lead.budget_range or ""),
            message=str(lead.message or ""),
            lead_score=str(lead.lead_score or ""),
            priority_tier=str(lead.priority_tier or ""),
            intent_summary=str(lead.intent_summary or ""),
            suggested_opener=str(lead.suggested_opener or ""),
            red_flags=",".join(red_flags) if isinstance(red_flags, list) else str(red_flags or ""),
            received_at=str(lead.received_at or ""),
            processed_at=str(lead.processed_at or ""),
        )