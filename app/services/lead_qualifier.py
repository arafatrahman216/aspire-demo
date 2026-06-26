"""Lead qualification orchestrator."""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from app.core.exceptions import ValidationError
from app.integrations.ai.base import AIProvider
from app.integrations.ai.fallback import fallback_analysis
from app.integrations.notifications.base import NotificationService
from app.integrations.sheets.base import LeadRepository, SheetAppender
from app.schemas.lead import LeadAnalysis, LeadResponse, LeadTableRow
from app.schemas.webhook import WebhookPayload, WebhookResponse
from app.services.filtering import detect_red_flags, is_low_context
from app.services.validation import (
    normalize_payload,
    validate_email_format,
    validate_required_fields,
)

logger = logging.getLogger(__name__)


@dataclass
class QualifierDependencies:
    repository: LeadRepository
    sheets_appender: SheetAppender | None
    ai_provider: AIProvider
    notification_service: NotificationService


class LeadQualifierService:
    def __init__(self, deps: QualifierDependencies) -> None:
        self._deps = deps

    async def process_lead(self, payload: WebhookPayload) -> WebhookResponse:
        lead_id = str(uuid.uuid4())
        received_at = datetime.now(timezone.utc)

        try:
            validate_required_fields(payload)
            normalized = normalize_payload(payload)
            validate_email_format(normalized.email)
        except ValidationError as exc:
            logger.info(
                "Lead rejected — validation failed",
                extra={"lead_id": lead_id, "error": str(exc)},
            )
            rejected = LeadResponse(
                id=lead_id,
                full_name=getattr(payload, "full_name", ""),
                email=getattr(payload, "email", ""),
                company_name=getattr(payload, "company_name", None),
                job_title=getattr(payload, "job_title", None),
                phone=getattr(payload, "phone", None),
                company_size=getattr(payload, "company_size", None),
                budget_range=getattr(payload, "budget_range", None),
                message=getattr(payload, "message", None),
                red_flags=[],
                workflow_status="rejected",
                error_message=str(exc),
                notification_sent=False,
                received_at=received_at,
                processed_at=None,
            )
            await self._persist_lead(rejected)
            await self._notify(rejected)
            return WebhookResponse(
                status="rejected",
                lead_id=lead_id,
                reason=str(exc),
                notification_sent=False,
            )

        if is_low_context(normalized):
            logger.info(
                "Lead filtered — low context",
                extra={"lead_id": lead_id, "email": normalized.email},
            )
            low_context = LeadResponse(
                id=lead_id,
                full_name=normalized.full_name,
                email=normalized.email,
                company_name=normalized.company_name,
                job_title=normalized.job_title,
                phone=normalized.phone,
                company_size=normalized.company_size,
                budget_range=normalized.budget_range,
                message=normalized.message,
                priority_tier="Cold",
                intent_summary="Low-context inquiry — insufficient detail for AI analysis",
                red_flags=detect_red_flags(normalized),
                workflow_status="low_context",
                notification_sent=False,
                received_at=received_at,
                processed_at=datetime.now(timezone.utc),
            )
            await self._persist_lead(low_context)
            await self._sync_to_sheets(low_context)
            notified = await self._notify(low_context)
            return WebhookResponse(
                status="low_context",
                lead_id=lead_id,
                priority_tier="Cold",
                reason="Message too short for AI analysis",
                notification_sent=notified,
            )

        ai_start = time.monotonic()
        try:
            analysis = await self._deps.ai_provider.analyze_lead(normalized.model_dump(exclude_none=True))
            ai_status = "ai_complete"
        except Exception:
            logger.exception("AI analysis failed after retries")
            analysis = fallback_analysis("AI analysis unavailable")
            ai_status = "ai_failed"
        logger.info("AI latency", extra={"latency_ms": int((time.monotonic() - ai_start) * 1000)})

        enriched = LeadResponse(
            id=lead_id,
            full_name=normalized.full_name,
            email=normalized.email,
            company_name=normalized.company_name,
            job_title=normalized.job_title,
            phone=normalized.phone,
            company_size=normalized.company_size,
            budget_range=normalized.budget_range,
            message=normalized.message,
            lead_score=analysis.lead_score,
            priority_tier=analysis.priority_tier,
            intent_summary=analysis.intent_summary,
            suggested_opener=analysis.suggested_opener,
            red_flags=list(dict.fromkeys(detect_red_flags(normalized) + analysis.red_flags)),
            workflow_status=ai_status,
            notification_sent=False,
            received_at=received_at,
            processed_at=datetime.now(timezone.utc),
        )

        await self._persist_lead(enriched)
        await self._sync_to_sheets(enriched)
        notified = await self._notify(enriched)

        return WebhookResponse(
            status="qualified_fallback" if ai_status == "ai_failed" else "qualified",
            lead_id=lead_id,
            lead_score=analysis.lead_score,
            priority_tier=analysis.priority_tier,
            intent_summary=analysis.intent_summary,
            suggested_opener=analysis.suggested_opener,
            red_flags=enriched.red_flags,
            notification_sent=notified,
        )

    async def _persist_lead(self, lead: LeadResponse) -> None:
        try:
            await self._deps.repository.save(lead)
            logger.info("Lead persisted", extra={"lead_id": lead.id, "status": lead.workflow_status})
        except Exception as exc:
            logger.error("Failed to persist lead", extra={"lead_id": lead.id, "error": str(exc)})

    async def _sync_to_sheets(self, lead: LeadResponse) -> None:
        if not self._deps.sheets_appender:
            return
        try:
            await self._deps.sheets_appender.append_row(LeadTableRow.from_orm_lead(lead))
        except Exception as exc:
            logger.error("Google Sheets sync failed", extra={"lead_id": lead.id, "error": str(exc)})

    async def _notify(self, lead: LeadResponse) -> bool:
        try:
            return await self._deps.notification_service.send_lead_notification(lead)
        except Exception as exc:
            logger.error("Notification failed", extra={"lead_id": lead.id, "error": str(exc)})
            return False