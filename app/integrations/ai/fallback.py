"""
Fallback response generation when AI analysis is unavailable.

The fallback analysis is the safety net — always produces a valid
LeadAnalysis so the workflow never crashes. The provider class wraps
it so the dependency container can use it the same way as a real
provider.
"""

from app.integrations.ai.base import AIProvider
from app.schemas.lead import LeadAnalysis


def fallback_analysis(reason: str = "AI analysis unavailable") -> LeadAnalysis:
    """Return a safe default analysis when AI fails."""
    return LeadAnalysis(
        lead_score=50,
        priority_tier="Manual Review",
        intent_summary=reason,
        suggested_opener="Manual review required",
        red_flags=["AI_ERROR"],
    )


class FallbackAIProvider(AIProvider):
    """Stand-in provider used when no real AI is configured."""

    async def analyze_lead(self, lead_data: dict) -> LeadAnalysis:
        return fallback_analysis("Gemini API key not configured")
