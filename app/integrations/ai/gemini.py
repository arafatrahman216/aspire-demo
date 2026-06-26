"""Gemini 2.5 Flash provider. Wraps the sync google-genai SDK via asyncio.to_thread."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any

from google.genai.types import GenerateContentResponse

from app.core.config import settings
from app.core.exceptions import AIServiceError
from app.integrations.ai.base import AIProvider
from app.integrations.ai.fallback import fallback_analysis
from app.integrations.ai.prompts.lead_scoring import build_lead_scoring_prompt
from app.schemas.lead import LeadAnalysis

logger = logging.getLogger(__name__)


class GeminiProvider(AIProvider):
    def __init__(self) -> None:
        if not settings.gemini_api_key:
            logger.warning("Gemini API key not set — AI calls will fall back")
        # Import lazily so config errors surface here, not at import time.
        from google import genai

        self._client = genai.Client(api_key=settings.gemini_api_key or "unset")
        self._model = settings.gemini_model
        self._max_retries = settings.gemini_max_retries

    async def analyze_lead(self, lead_data: dict) -> LeadAnalysis:
        if not settings.gemini_api_key:
            return fallback_analysis("Gemini API key not configured")

        messages = build_lead_scoring_prompt(lead_data)
        last_error: Exception | None = None

        for attempt in range(1, self._max_retries + 2):
            try:
                start = time.monotonic()
                response = await self._call_gemini(messages)
                elapsed_ms = int((time.monotonic() - start) * 1000)

                analysis = self._parse_response(response)
                logger.info(
                    "AI analysis succeeded",
                    extra={"latency_ms": elapsed_ms, "attempt": attempt, "score": analysis.lead_score},
                )
                return analysis
            except Exception as exc:
                last_error = exc
                logger.warning(
                    "AI call failed",
                    extra={"attempt": attempt, "error": str(exc), "max_retries": self._max_retries},
                )
                if attempt <= self._max_retries:
                    await asyncio.sleep(2**attempt)

        logger.error("All AI attempts exhausted", extra={"error": str(last_error)})
        return fallback_analysis(f"AI unavailable after {self._max_retries + 1} attempts")

    async def _call_gemini(self, messages: list[dict]) -> GenerateContentResponse:
        contents = "\n\n".join(m["content"] for m in messages if m["content"])
        return await asyncio.to_thread(
            self._client.models.generate_content,
            model=self._model,
            contents=contents,
            config={"temperature": 0.1, "max_output_tokens": 1024},
        )

    def _parse_response(self, response: GenerateContentResponse) -> LeadAnalysis:
        text = (response.text or "").strip()
        if not text:
            raise AIServiceError("Empty response from Gemini")

        # Strip markdown code fences if present.
        cleaned = text
        if cleaned.startswith("```json"):
            cleaned = cleaned[7:]
        if cleaned.startswith("```"):
            cleaned = cleaned.split("\n", 1)[-1]
        if cleaned.endswith("```"):
            cleaned = cleaned.rsplit("```", 1)[0]
        cleaned = cleaned.strip()

        try:
            data: dict[str, Any] = json.loads(cleaned)
        except json.JSONDecodeError as exc:
            raise AIServiceError(f"Malformed JSON response: {exc}", original_error=exc) from exc

        try:
            return LeadAnalysis(
                lead_score=int(data.get("lead_score", 50)),
                priority_tier=str(data.get("priority_tier", "Manual Review")),
                intent_summary=str(data.get("intent_summary", "AI analysis unavailable")),
                suggested_opener=str(data.get("suggested_opener", "Manual review required")),
                red_flags=list(data.get("red_flags", [])),
            )
        except (ValueError, TypeError) as exc:
            raise AIServiceError(f"Invalid analysis schema: {exc}", original_error=exc) from exc