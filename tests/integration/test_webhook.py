import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport

from app.main import app


@pytest_asyncio.fixture
async def client():
    """ASGI test client that triggers FastAPI's lifespan so tables get created."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Run the app's lifespan manually so startup hooks (table creation) fire.
        async with app.router.lifespan_context(app):
            yield ac


@pytest.mark.asyncio
async def test_webhook_happy_path(client: AsyncClient):
    payload = {
        "full_name": "Test User",
        "email": "test@test.com",
        "message": "We need help with automation for our sales team.",
    }
    response = await client.post("/api/v1/webhook", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ["qualified", "qualified_fallback"]
    assert "lead_id" in data


@pytest.mark.asyncio
async def test_webhook_missing_fields(client: AsyncClient):
    payload = {
        "email": "test@test.com"
    }
    response = await client.post("/api/v1/webhook", json=payload)
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_webhook_low_context(client: AsyncClient):
    payload = {
        "full_name": "Test User",
        "email": "test@test.com",
        "message": "hi",
    }
    response = await client.post("/api/v1/webhook", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "low_context"
    assert data["priority_tier"] == "Cold"