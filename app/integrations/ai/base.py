"""AI provider contract. Business code never imports a concrete SDK."""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas.lead import LeadAnalysis


class AIProvider(ABC):
    @abstractmethod
    async def analyze_lead(self, lead_data: dict) -> LeadAnalysis: ...
