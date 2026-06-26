import pytest
from app.schemas.webhook import WebhookPayload


@pytest.fixture
def valid_payload():
    return WebhookPayload(
        full_name="Jordan Ellis",
        email="jordan.ellis@examplecorp.com",
        company_name="Example Corp",
        job_title="Operations Manager",
        phone="555-0199",
        company_size="11-50",
        budget_range="$5k-$15k/mo",
        message="We are looking to automate our onboarding workflow.",
    )


@pytest.fixture
def low_context_payload():
    return WebhookPayload(
        full_name="Bob",
        email="bob@test.com",
        message="hi",
    )


@pytest.fixture
def spam_payload():
    return WebhookPayload(
        full_name="Spammer",
        email="spam@spam.com",
        message="Click here for free money!!!",
    )