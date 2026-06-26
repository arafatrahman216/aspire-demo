"""SQLite-backed lead repository. Internal operational store."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.integrations.sheets.base import LeadRepository
from app.models.lead import Lead
from app.schemas.lead import LeadResponse


class SqliteLeadRepository(LeadRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def save(self, lead: LeadResponse) -> LeadResponse:
        self._session.add(Lead(
            id=lead.id,
            full_name=lead.full_name,
            email=lead.email,
            company_name=lead.company_name,
            job_title=lead.job_title,
            phone=lead.phone,
            company_size=lead.company_size,
            budget_range=lead.budget_range,
            message=lead.message,
            lead_score=lead.lead_score,
            priority_tier=lead.priority_tier,
            intent_summary=lead.intent_summary,
            suggested_opener=lead.suggested_opener,
            red_flags=lead.red_flags or None,
            workflow_status=lead.workflow_status,
            error_message=lead.error_message,
            notification_sent=1 if lead.notification_sent else 0,
            received_at=lead.received_at,
            processed_at=lead.processed_at,
        ))
        await self._session.flush()
        return lead

    async def get_by_id(self, lead_id: str) -> LeadResponse | None:
        result = await self._session.execute(select(Lead).where(Lead.id == lead_id))
        model = result.scalar_one_or_none()
        return self._model_to_response(model) if model else None

    @staticmethod
    def _model_to_response(model: Lead) -> LeadResponse:
        return LeadResponse(
            id=str(model.id),
            full_name=str(model.full_name),
            email=str(model.email),
            company_name=str(model.company_name) if model.company_name else None,
            job_title=str(model.job_title) if model.job_title else None,
            phone=str(model.phone) if model.phone else None,
            company_size=str(model.company_size) if model.company_size else None,
            budget_range=str(model.budget_range) if model.budget_range else None,
            message=str(model.message) if model.message else None,
            lead_score=model.lead_score,
            priority_tier=model.priority_tier,
            intent_summary=model.intent_summary,
            suggested_opener=model.suggested_opener,
            red_flags=list(model.red_flags or []),
            workflow_status=str(model.workflow_status),
            error_message=model.error_message,
            notification_sent=bool(model.notification_sent),
            received_at=model.received_at or datetime.now(timezone.utc),
            processed_at=model.processed_at,
        )