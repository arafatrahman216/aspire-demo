"""
Field validation and normalization for inbound lead payloads.

Every function is a pure function — no side effects, no I/O.
"""

from __future__ import annotations

import re

from app.core.exceptions import ValidationError
from app.schemas.webhook import WebhookPayload

REQUIRED_FIELDS = ["full_name", "email", "message"]

EMAIL_PATTERN = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")


def validate_required_fields(payload: WebhookPayload) -> None:
    """Check that required fields are present and non-empty after stripping."""
    missing: list[str] = []
    for field in REQUIRED_FIELDS:
        value = getattr(payload, field, None)
        if not value or not str(value).strip():
            missing.append(field)

    if missing:
        raise ValidationError(
            f"Missing required field(s): {', '.join(missing)}",
            field=", ".join(missing),
        )


def normalize_payload(payload: WebhookPayload) -> WebhookPayload:
    """Trim whitespace and lowercase the email."""
    normalized = payload.model_copy(deep=True)

    normalized.full_name = payload.full_name.strip()
    normalized.email = payload.email.strip().lower()
    if normalized.company_name:
        normalized.company_name = payload.company_name.strip()
    if normalized.job_title:
        normalized.job_title = payload.job_title.strip()
    if normalized.phone:
        normalized.phone = payload.phone.strip()
    if normalized.company_size:
        normalized.company_size = payload.company_size.strip()
    if normalized.budget_range:
        normalized.budget_range = payload.budget_range.strip()
    if normalized.message:
        normalized.message = payload.message.strip()

    return normalized


def validate_email_format(email: str) -> None:
    """Validate email format using a reasonably strict regex."""
    if not EMAIL_PATTERN.match(email):
        raise ValidationError(f"Invalid email format: {email}", field="email")