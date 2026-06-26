"""Notification channel contract. Brevo, Slack, or any future provider implements it."""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas.lead import LeadResponse


class NotificationService(ABC):
    @abstractmethod
    async def send_lead_notification(self, lead: LeadResponse) -> bool: ...


class CompositeNotificationService(NotificationService):
    """Fan out to multiple channels; treat success as any-channel-succeeded."""

    def __init__(self, services: list[NotificationService]) -> None:
        self._services = services

    async def send_lead_notification(self, lead: LeadResponse) -> bool:
        results: list[bool] = []
        for svc in self._services:
            try:
                results.append(await svc.send_lead_notification(lead))
            except Exception:
                results.append(False)
        return any(results)
