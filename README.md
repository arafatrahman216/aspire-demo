# Lead Qualifier & Automation

AI-powered Lead Qualification & Response Automation system.
Built for the AI Automation Engineer Technical Assessment.

## Architecture

This project implements a Layered Architecture with Dependency Inversion at boundaries.

- **Presentation**: FastAPI endpoints
- **Business**: `LeadQualifierService` checking context, validating, orchestrating.
- **Infrastructure**: AI (Gemini), Database (SQLite), Integrations (Google Sheets, Brevo, Slack).

### Design Decisions
1. **Fallback Resiliency**: The webhook is synchronous but never crashes. If AI/Sheets/Brevo goes offline, errors are logged and safe fallbacks are used.
2. **Local Persistence**: We use SQLite as an internal operational store. Google Sheets acts as an external sync layer, protecting us from their rate-limits.
3. **Pydantic DTOs**: Strict contracts between HTTP, business logic, and infrastructure.

## Setup

1. Copy env example:
   ```bash
   cp .env.example .env
   ```
2. Setup environment and install dependencies:
   ```bash
   make setup
   ```
3. Run the development server:
   ```bash
   make dev
   ```

## Testing

```bash
make test
```

## Bonus Extension implemented
**Synchronous Webhook Response**: The system returns the AI tier and generated opener in real-time to the caller.