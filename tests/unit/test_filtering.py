from app.services.filtering import is_low_context, looks_like_spam, detect_red_flags
from tests.fixtures.leads import valid_payload, low_context_payload, spam_payload

def test_is_low_context(valid_payload, low_context_payload):
    assert not is_low_context(valid_payload)
    assert is_low_context(low_context_payload)

def test_looks_like_spam(valid_payload, spam_payload):
    assert not looks_like_spam(valid_payload)
    assert looks_like_spam(spam_payload)

def test_detect_red_flags(spam_payload):
    flags = detect_red_flags(spam_payload)
    assert "looks_like_spam" in flags
