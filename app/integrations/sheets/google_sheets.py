"""Google Sheets sync target. Appends one row per qualified lead."""

from __future__ import annotations

import logging

import gspread
from google.oauth2.service_account import Credentials

from app.core.config import settings
from app.core.exceptions import SheetsError
from app.integrations.sheets.base import SheetAppender
from app.schemas.lead import LeadTableRow

logger = logging.getLogger(__name__)

HEADERS = [
    "lead_id",
    "full_name",
    "email",
    "company_name",
    "job_title",
    "phone",
    "company_size",
    "budget_range",
    "message",
    "lead_score",
    "priority_tier",
    "intent_summary",
    "suggested_opener",
    "red_flags",
    "received_at",
    "processed_at",
]


class GoogleSheetsAppender(SheetAppender):
    def __init__(self) -> None:
        self._sheet: gspread.Worksheet | None = None

    async def append_row(self, row: LeadTableRow) -> None:
        try:
            sheet = await self._get_or_create_sheet()
            values = [getattr(row, h.replace(" ", "_"), "") for h in HEADERS]
            sheet.append_row(values, value_input_option="USER_ENTERED")
            logger.info("Row appended to Google Sheets", extra={"lead_id": row.lead_id})
        except Exception as exc:
            logger.error(
                "Google Sheets append failed",
                extra={"error": str(exc), "lead_id": row.lead_id},
            )
            raise SheetsError(f"Failed to append row to sheet: {exc}", original_error=exc) from exc

    async def _get_or_create_sheet(self) -> gspread.Worksheet:
        if self._sheet is not None:
            return self._sheet

        creds_dict = settings.google_sheets_credentials_dict
        if not creds_dict:
            raise SheetsError("Google Sheets credentials not configured")

        scopes = [
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive",
        ]
        creds = Credentials.from_service_account_info(creds_dict, scopes=scopes)
        client = gspread.authorize(creds)

        spreadsheet = client.open_by_key(settings.google_sheets_spreadsheet_id)
        try:
            self._sheet = spreadsheet.worksheet(settings.google_sheets_sheet_name)
        except gspread.WorksheetNotFound:
            self._sheet = spreadsheet.add_worksheet(
                title=settings.google_sheets_sheet_name,
                rows=1000,
                cols=len(HEADERS),
            )
            self._sheet.append_row(HEADERS)

        return self._sheet