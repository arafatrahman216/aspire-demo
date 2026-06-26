import pytest
from app.core.exceptions import ValidationError
from app.services.validation import validate_required_fields, normalize_payload
from tests.fixtures.leads import valid_payload

def test_validate_required_fields(valid_payload):
    # Should not raise
    validate_required_fields(valid_payload)
    
    valid_payload.message = "   "
    with pytest.raises(ValidationError):
        validate_required_fields(valid_payload)

def test_normalize_payload(valid_payload):
    valid_payload.email = " JORDAN@EXAMPLE.COM "
    normalized = normalize_payload(valid_payload)
    assert normalized.email == "jordan@example.com"
