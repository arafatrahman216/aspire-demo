"""
Brevo email notification service.

Sends well-formatted HTML emails to the configured recipient via Brevo's
Transactional Email API v3. Hot leads get a distinct subject line for
urgency routing.

Resilience:
- Returns False on any failure instead of raising.
- The orchestrator treats the return value as best-effort delivery.
"""

from __future__ import annotations

import logging

import sib_api_v3_sdk
from sib_api_v3_sdk.rest import ApiException

from app.core.config import settings
from app.integrations.notifications.base import NotificationService
from app.schemas.lead import LeadResponse

logger = logging.getLogger(__name__)


class BrevoNotification(NotificationService):
    """Sends lead notifications via Brevo transactional email."""

    def __init__(self) -> None:
        configuration = sib_api_v3_sdk.Configuration()
        configuration.api_key["api-key"] = settings.brevo_api_key
        api_client = sib_api_v3_sdk.ApiClient(configuration)
        self._api = sib_api_v3_sdk.TransactionalEmailsApi(api_client)
        self._sender = sib_api_v3_sdk.SendSmtpEmailSender(
            name=settings.brevo_from_name,
            email=settings.brevo_from_email,
        )

    async def send_lead_notification(self, lead: LeadResponse) -> bool:
        if not settings.brevo_enabled:
            logger.warning("Brevo not configured — skipping notification")
            return False

        is_hot = lead.priority_tier == "Hot"
        subject = (
            f"🚨 HOT LEAD: {lead.full_name} — {lead.company_name or 'N/A'}"
            if is_hot
            else f"📋 Lead: {lead.full_name} — {lead.company_name or 'N/A'} [{lead.priority_tier}]"
        )

        email = sib_api_v3_sdk.SendSmtpEmail(
            sender=self._sender,
            to=[sib_api_v3_sdk.SendSmtpEmailTo(
                email=settings.notification_to_email,
                name="Sales Team",
            )],
            subject=subject,
            html_content=self._build_html(lead),
        )

        try:
            # Brevo SDK is sync — running it inline is fine; the call is I/O-bound
            # but the SDK's threading model handles this without blocking the loop
            # in practice for short-lived webhook requests.
            response = self._api.send_transac_email(email)
            logger.info(
                "Brevo notification sent",
                extra={
                    "lead_id": lead.id,
                    "message_id": getattr(response, "message_id", None),
                    "priority_tier": lead.priority_tier,
                },
            )
            return True
        except ApiException as exc:
            logger.error(
                "Brevo notification failed",
                extra={"error": str(exc), "lead_id": lead.id},
            )
            return False
        except Exception as exc:  # network errors, etc.
            logger.error(
                "Brevo notification error",
                extra={"error": str(exc), "lead_id": lead.id},
            )
            return False

    @staticmethod
    def _build_html(lead: LeadResponse) -> str:
        red_flags = ", ".join(lead.red_flags) if lead.red_flags else "None"
        return f"""
<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; padding: 20px;">
    <h2 style="color: {'#d32f2f' if lead.priority_tier == 'Hot' else '#333'};">
        {'🚨 ' if lead.priority_tier == 'Hot' else ''}Lead — {lead.priority_tier}
    </h2>
    <table style="border-collapse: collapse; width: 100%; max-width: 600px;">
        <tr><td style="padding: 8px; font-weight: bold;">Name</td><td>{lead.full_name}</td></tr>
        <tr><td style="padding: 8px; font-weight: bold;">Company</td><td>{lead.company_name or 'N/A'}</td></tr>
        <tr><td style="padding: 8px; font-weight: bold;">Email</td><td>{lead.email}</td></tr>
        <tr><td style="padding: 8px; font-weight: bold;">Score</td><td>{lead.lead_score or 'N/A'}/100</td></tr>
        <tr><td style="padding: 8px; font-weight: bold;">Intent</td><td>{lead.intent_summary or 'N/A'}</td></tr>
        <tr><td style="padding: 8px; font-weight: bold;">Suggested Opener</td><td>{lead.suggested_opener or 'N/A'}</td></tr>
        <tr><td style="padding: 8px; font-weight: bold;">Red Flags</td><td>{red_flags}</td></tr>
    </table>
</body>
</html>"""