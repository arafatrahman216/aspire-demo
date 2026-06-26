"""Lead ORM model. Stores inbound payload and AI-enriched analysis results."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import JSON, Column, DateTime, Integer, String, Text

from app.db.session import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Lead(Base):
    __tablename__ = "leads"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    full_name = Column(String(255), nullable=False)
    email = Column(String(255), nullable=False, index=True)
    company_name = Column(String(255), nullable=True)
    job_title = Column(String(255), nullable=True)
    phone = Column(String(50), nullable=True)
    company_size = Column(String(50), nullable=True)
    budget_range = Column(String(100), nullable=True)
    message = Column(Text, nullable=True)

    # AI-enriched fields
    lead_score = Column(Integer, nullable=True)
    priority_tier = Column(String(20), nullable=True, index=True)
    intent_summary = Column(Text, nullable=True)
    suggested_opener = Column(Text, nullable=True)
    red_flags = Column(JSON, nullable=True)

    # Processing metadata
    workflow_status = Column(String(20), nullable=False, default="received", index=True)
    ai_latency_ms = Column(Integer, nullable=True)
    error_message = Column(Text, nullable=True)
    notification_sent = Column(Integer, default=0)

    # Timestamps
    received_at = Column(DateTime, nullable=False, default=_utcnow)
    processed_at = Column(DateTime, nullable=True)
    synced_to_sheets_at = Column(DateTime, nullable=True)