"""FastAPI dependency injection container."""

from __future__ import annotations

from collections.abc import AsyncGenerator

from app.core.config import settings
from app.db.session import get_db_session
from app.integrations.ai.base import AIProvider
from app.integrations.ai.fallback import FallbackAIProvider
from app.integrations.ai.gemini import GeminiProvider
from app.integrations.notifications.base import (
    CompositeNotificationService,
    NotificationService,
)
from app.integrations.notifications.brevo import BrevoNotification
from app.integrations.notifications.noop import NoopNotification
from app.integrations.notifications.slack import SlackNotification
from app.integrations.sheets.base import SheetAppender
from app.integrations.sheets.google_sheets import GoogleSheetsAppender
from app.integrations.sheets.sqlite_repo import SqliteLeadRepository
from app.services.lead_qualifier import LeadQualifierService, QualifierDependencies

_ai_provider: AIProvider | None = None
_sheets_appender: SheetAppender | None = None


def get_ai_provider() -> AIProvider:
    global _ai_provider
    if _ai_provider is None:
        _ai_provider = GeminiProvider() if settings.gemini_api_key else FallbackAIProvider()
    return _ai_provider


def get_notification_service() -> NotificationService:
    services: list[NotificationService] = []
    if settings.brevo_enabled:
        services.append(BrevoNotification())
    if settings.slack_enabled:
        services.append(SlackNotification())
    if not services:
        services.append(NoopNotification())
    return CompositeNotificationService(services)


def get_sheets_appender() -> SheetAppender | None:
    global _sheets_appender
    if _sheets_appender is None and settings.google_sheets_credentials_json:
        _sheets_appender = GoogleSheetsAppender()
    return _sheets_appender


async def get_qualifier_service() -> AsyncGenerator[LeadQualifierService, None]:
    async for session in get_db_session():
        deps = QualifierDependencies(
            repository=SqliteLeadRepository(session),
            sheets_appender=get_sheets_appender(),
            ai_provider=get_ai_provider(),
            notification_service=get_notification_service(),
        )
        yield LeadQualifierService(deps)