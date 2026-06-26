"""Storage contracts. The orchestrator depends on these, never on SQLite or Sheets."""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas.lead import LeadResponse, LeadTableRow


class LeadRepository(ABC):
    """Internal store. SQLite is the only implementation today."""

    @abstractmethod
    async def save(self, lead: LeadResponse) -> LeadResponse: ...

    @abstractmethod
    async def get_by_id(self, lead_id: str) -> LeadResponse | None: ...


class SheetAppender(ABC):
    """External sync target. Google Sheets is the only implementation today."""

    @abstractmethod
    async def append_row(self, row: LeadTableRow) -> None: ...