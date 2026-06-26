"""
Lead filtering logic — low-context detection and spam heuristics.

Runs *before* AI to avoid wasting tokens on unusable leads.
"""

from __future__ import annotations

from app.schemas.webhook import WebhookPayload

# Leads with fewer than this many characters in 'message' skip AI
LOW_CONTEXT_THRESHOLD = 10

# Simple spam indicators (case-insensitive substring match)
SPAM_INDICATORS: list[str] = [
    "buy now",
    "click here",
    "free money",
    "act now",
    "limited offer",
    "congratulations you won",
]


def is_low_context(payload: WebhookPayload) -> bool:
    """Return True if the message is too short to analyze meaningfully."""
    if not payload.message:
        return True
    return len(payload.message.strip()) < LOW_CONTEXT_THRESHOLD


def looks_like_spam(payload: WebhookPayload) -> bool:
    """Simple heuristic spam check on message text."""
    if not payload.message:
        return False
    message_lower = payload.message.lower()
    return any(indicator in message_lower for indicator in SPAM_INDICATORS)


def detect_red_flags(payload: WebhookPayload) -> list[str]:
    """Return a list of automatically-detectable red flags."""
    flags: list[str] = []

    if not payload.message:
        flags.append("empty_message")
    if is_low_context(payload):
        flags.append("low_context")
    if looks_like_spam(payload):
        flags.append("looks_like_spam")
    if payload.company_name and len(payload.company_name.strip()) < 2:
        flags.append("suspicious_company_name")

    return flags