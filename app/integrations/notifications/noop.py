"""
No-op notification service.

Used when no real channels are configured — the orchestrator still
gets a service to call, and the result is a clean "nothing happened"
rather than a NoneType error.
"""

from app.integrations.notifications.base import NotificationService
from app.schemas.lead import LeadResponse


class NoopNotification(NotificationService):
    async def send_lead_notification(self, lead: LeadResponse) -> bool:
        return False