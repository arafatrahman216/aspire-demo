# Implementation Plan

This document outlines the step-by-step roadmap followed to build the Lead Qualification System.

## Phase 1: Architecture & Design
- Review the prompt requirements.
- Select the tech stack (FastAPI, Python 3.12, SQLite, Gemini, Google Sheets).
- Design the Layered Architecture.
- Generate Phase 1 Deliverables: ADR, Folder Structure, DB Schema, API Contract, Sequence Diagram, and this Implementation Plan.

## Phase 2: Implementation

### Milestone 1: Project Bootstrap
- Initialize the Python project using `pyproject.toml`.
- Configure `app/core/config.py` for environment variables.
- Set up structured logging in `app/core/logging.py`.
- Define custom application exceptions (`app/core/exceptions.py`).
- Create the basic FastAPI application factory (`app/main.py`).

### Milestone 2: Webhook Endpoint & Validation
- Define Pydantic DTO schemas for requests and responses (`app/schemas/webhook.py`).
- Implement the webhook endpoint (`app/api/v1/webhook.py`).
- Implement dependency injection for services (`app/api/deps.py`).
- Create the `validation.py` and `filtering.py` services to handle data normalization, required fields, and low-context lead rejection.

### Milestone 3: AI Integration
- Create the `AIProvider` base class (`app/integrations/ai/base.py`).
- Implement the `GeminiProvider` using the new `google-genai` SDK (`app/integrations/ai/gemini.py`).
- Implement retry logic with exponential backoff and timeout handling.
- Separate AI prompts into `app/integrations/ai/prompts`.
- Implement `fallback_analysis` to handle complete AI failure gracefully.

### Milestone 4: Persistence Layer
- Set up SQLAlchemy and SQLite database connection (`app/db/session.py`).
- Define the ORM model (`app/models/lead.py`).
- Bootstrap the schema on startup via `Base.metadata.create_all()` (no Alembic — overkill for a single-table SQLite store).
- Implement `SQLiteRepository` (`app/integrations/sheets/sqlite_repo.py`).
- Implement `GoogleSheetsRepository` using `gspread` (`app/integrations/sheets/google_sheets.py`).

### Milestone 5: Notification Systems
- Create the `NotificationService` base class (`app/integrations/notifications/base.py`).
- Implement `BrevoNotification` to send transactional emails based on the AI response.
- Implement `SlackNotificationService` for internal team alerts.

### Milestone 6: Orchestration
- Create `LeadQualifierService` (`app/services/lead_qualifier.py`) to tie all components together.
- Connect validation -> filtering -> AI analysis -> DB save -> Sheets sync -> Notifications.
- Ensure failure in optional steps (Sheets, Notifications) does not fail the webhook response.

### Milestone 7: Testing & Refinement
- Write unit tests for validation and filtering.
- Write integration tests for the webhook endpoint using `httpx`.
- Verify the system functions via `make test`.
- Refine error handling and ensure the system never crashes due to external services.
