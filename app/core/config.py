"""
Application configuration via environment variables.

Uses Pydantic BaseSettings to load, validate, and freeze all settings
at startup. Never call os.getenv() directly in application code.
"""

from __future__ import annotations

import json
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        frozen=True,
        extra="ignore",  # tolerate leftover keys (e.g. MAILGUN_API_KEY from prior experiments)
    )

    # ── FastAPI ──────────────────────────────────────────
    app_env: Literal["development", "production", "testing"] = "development"
    app_debug: bool = True
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    log_level: str = "INFO"

    # ── Database ─────────────────────────────────────────
    database_url: str = Field(
        default="sqlite+aiosqlite:///./data/leads.db",
        description="SQLite or PostgreSQL connection string",
    )

    # ── Gemini AI ────────────────────────────────────────
    gemini_api_key: str = Field(default="", alias="GEMINI_API_KEY")
    gemini_model: str = "gemini-2.5-flash"
    gemini_timeout_seconds: int = 30
    gemini_max_retries: int = 2

    # ── Google Sheets ────────────────────────────────────
    google_sheets_credentials_json: str = Field(
        default="", alias="GOOGLE_SHEETS_CREDENTIALS_JSON"
    )
    google_sheets_spreadsheet_id: str = ""
    google_sheets_sheet_name: str = "Leads"

    @property
    def google_sheets_credentials_dict(self) -> dict[str, str] | None:
        if not self.google_sheets_credentials_json:
            return None
        return json.loads(self.google_sheets_credentials_json)

    # ── Brevo ────────────────────────────────────────────
    brevo_api_key: str = Field(default="", alias="BREVO_API_KEY")
    brevo_from_email: str = Field(default="", alias="BREVO_FROM_EMAIL")
    brevo_from_name: str = "Lead Qualifier"
    notification_to_email: str = ""

    # ── Slack (optional) ─────────────────────────────────
    slack_webhook_url: str = ""
    slack_hot_channel: str = "urgent-leads"
    slack_default_channel: str = "general"

    # ── Webhook Security ─────────────────────────────────
    webhook_secret: str = ""

    # ── Derived ──────────────────────────────────────────
    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def slack_enabled(self) -> bool:
        return bool(self.slack_webhook_url)

    @property
    def brevo_enabled(self) -> bool:
        return bool(self.brevo_api_key and self.brevo_from_email)

    @field_validator("gemini_api_key")
    @classmethod
    def _warn_missing_gemini_key(cls, v: str) -> str:
        if not v:
            import warnings

            warnings.warn(
                "GEMINI_API_KEY is not set. AI analysis will always fall back.",
                stacklevel=1,
            )
        return v


settings = Settings()  # singleton — importable across the app