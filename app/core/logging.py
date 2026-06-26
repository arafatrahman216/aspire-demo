"""
Structured JSON logging configuration.

Produces machine-parseable log lines suitable for production monitoring.
Every log entry includes: timestamp, level, logger, event name, trace_id,
and optional structured context.
"""

from __future__ import annotations

import json
import logging
import sys
import uuid
from datetime import datetime, timezone
from typing import Any


class JSONFormatter(logging.Formatter):
    """Formats log records as JSON lines."""

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        if hasattr(record, "trace_id"):
            entry["trace_id"] = record.trace_id
        if hasattr(record, "event"):
            entry["event"] = record.event
        if hasattr(record, "lead_id"):
            entry["lead_id"] = record.lead_id

        # Include extra contextual data from the 'extra' dict
        for key in ("error", "latency_ms", "status", "priority_tier"):
            if hasattr(record, key):
                entry[key] = getattr(record, key)

        if record.exc_info and record.exc_info[0]:
            entry["exception"] = self.formatException(record.exc_info)

        return json.dumps(entry, default=str)


def setup_logging(level: str = "INFO") -> None:
    """Configure root logger with JSON output to stdout."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())

    root = logging.getLogger()
    root.setLevel(getattr(logging, level.upper(), logging.INFO))
    # Remove default handlers to avoid duplicate output
    root.handlers.clear()
    root.addHandler(handler)

    # Quiet noisy 3rd-party loggers
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("gspread").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """Get a logger with the given dotted name."""
    return logging.getLogger(name)


def log_event(
    logger: logging.Logger,
    level: int,
    event: str,
    message: str = "",
    **extra: Any,
) -> None:
    """Log a structured event with extra context."""
    extra.setdefault("trace_id", str(uuid.uuid4())[:8])
    logger.log(level, message, extra={"event": event, **extra})