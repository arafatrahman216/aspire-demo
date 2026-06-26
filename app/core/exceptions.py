


class LeadQualifierError(Exception):
    """Base exception for all domain-level errors."""


class ValidationError(LeadQualifierError):
    """Raised when lead payload fails field validation."""

    def __init__(self, message: str, field: str | None = None) -> None:
        self.field = field
        super().__init__(message)


class AIServiceError(LeadQualifierError):
    """Raised when the AI provider fails (timeout, rate-limit, malformed response)."""

    def __init__(self, message: str, original_error: Exception | None = None) -> None:
        self.original_error = original_error
        super().__init__(message)


class SheetsError(LeadQualifierError):
    """Raised when Google Sheets API call fails."""

    def __init__(self, message: str, original_error: Exception | None = None) -> None:
        self.original_error = original_error
        super().__init__(message)


class NotificationError(LeadQualifierError):
    """Raised when notification delivery fails."""

    def __init__(self, message: str, channel: str | None = None) -> None:
        self.channel = channel
        super().__init__(message)