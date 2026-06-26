"""
Slack webhook notification service.

Sends richly formatted Slack messages. Hot leads are posted to a
separate urgent channel with @here mention.
"""

from __future__ import annotations

import json
import logging

import httpx

from app.core.config import settings
from app.integrations.notifications.base import NotificationService
from app.schemas.lead import LeadResponse

logger = logging.getLogger(__name__)


class SlackNotification(NotificationService):
    """Sends lead notifications via Slack webhook."""

    def __init__(self) -> None:
        self._webhook_url = settings.slack_webhook_url

    async def send_lead_notification(self, lead: LeadResponse) -> bool:
        if not self._webhook_url:
            logger.debug("Slack webhook not configured — skipping")
            return False

        is_hot = lead.priority_tier == "Hot"
        channel = (
            settings.slack_hot_channel if is_hot else settings.slack_default_channel
        )

        blocks = self._build_blocks(lead, is_hot)

        payload = {
            "channel": channel,
            "username": "Lead Qualifier",
            "icon_emoji": ":zap:",
            "text": f"{'🚨 HOT LEAD' if is_hot else 'New Lead'}: {lead.full_name}",
            "blocks": blocks,
        }

        try:
            async with httpx.AsyncClient(timeout=15) as client:
                response = await client.post(
                    self._webhook_url,
                    json=payload,
                )
            if response.is_success:
                logger.info(
                    "Slack notification sent",
                    extra={
                        "lead_id": lead.id,
                        "channel": channel,
                        "priority_tier": lead.priority_tier,
                    },
                )
                return True

            logger.warning(
                "Slack returned error",
                extra={
                    "lead_id": lead.id,
                    "status_code": response.status_code,
                    "body": response.text,
                },
            )
            return False

        except Exception as exc:
            logger.error(
                "Slack notification failed",
                extra={"error": str(exc), "lead_id": lead.id},
            )
            return False

    def _build_blocks(self, lead: LeadResponse, is_hot: bool) -> list[dict]:
        blocks = []

        if is_hot:
            blocks.append(
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*🚨 HOT LEAD — Immediate attention required*",
                    },
                }
            )

        blocks.append(
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Name:*\n{lead.full_name}"},
                    {
                        "type": "mrkdwn",
                        "text": f"*Company:*\n{lead.company_name or 'N/A'}",
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Score:*\n{lead.lead_score or 'N/A'}/100",
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Tier:*\n{lead.priority_tier or 'N/A'}",
                    },
                ],
            }
        )

        if lead.intent_summary:
            blocks.append(
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Intent:*\n{lead.intent_summary}",
                    },
                }
            )

        if lead.suggested_opener:
            blocks.append(
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Suggested Opener:*\n{lead.suggested_opener}",
                    },
                }
            )

        if lead.red_flags:
            flags_text = "\n".join(f"• {f}" for f in lead.red_flags)
            blocks.append(
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Red Flags:*\n{flags_text}",
                    },
                }
            )

        blocks.append(
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"Lead ID: {lead.id} | Received: {lead.received_at.isoformat() if lead.received_at else 'N/A'}",
                    }
                ],
            }
        )

        return blocks