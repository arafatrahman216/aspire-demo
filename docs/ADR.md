# Architecture Decision Record (ADR)

## 1. Title
Lead Qualification & Response Automation Architecture

## 2. Status
Accepted

## 3. Context
We need to build an AI-powered Lead Qualification & Response Automation system that processes inbound leads via a webhook, validates and normalizes the data, filters out unusable leads, performs AI analysis using Gemini 2.5 Flash, stores the results, and sends notifications. The system must be highly resilient and handle external service failures gracefully.

## 4. Decisions

### 4.1 Runtime & Framework
**Decision:** Python 3.12+ with **FastAPI**
**Rationale:**
- **Performance:** FastAPI is asynchronous and highly performant, ideal for handling I/O bound tasks like external API calls (Gemini, Google Sheets, Brevo).
- **Simplicity & Maintainability:** Built-in Pydantic integration ensures strict data validation and OpenAPI schema generation out of the box.
- **Assessment Suitability:** It demonstrates modern Python backend practices and fulfills the requirement for a production-ready, maintainable system.

### 4.2 Architecture Pattern
**Decision:** **Layered Architecture** with Dependency Injection
**Rationale:**
- A layered architecture (Presentation -> Business -> Infrastructure) cleanly separates concerns without the over-engineering overhead of a strict Clean/Hexagonal architecture for a small-to-medium project.
- The Business layer orchestrates the workflow and delegates external concerns to abstract interfaces defined in the Infrastructure layer, allowing easy swapping of implementations (e.g., changing AI providers).

### 4.3 Database & Storage Strategy
**Decision:** **Persist locally (SQLite) and sync to Google Sheets (Reporting Layer)**
**Rationale:**
- Local persistence ensures that lead data is not lost if Google Sheets is rate-limited or temporarily unavailable.
- SQLite is chosen for deployment simplicity and assessment suitability (no complex database infrastructure required to run the project).
- Google Sheets acts purely as a reporting layer and sync target.

### 4.4 AI Provider
**Decision:** **Gemini 2.5 Flash** behind an `AIProvider` abstraction.
**Rationale:**
- Provides fast and efficient inference suitable for real-time lead qualification.
- Wrapped in an abstraction layer so the business logic is unaware of the specific SDK, making it easy to swap or upgrade providers in the future.

### 4.5 Notification Strategy
**Decision:** **Brevo** (transactional email) and **Slack** via abstract `NotificationService`.
**Rationale:**
- Allows for flexible notification delivery. The interface ensures that adding new channels (like SMS or Teams) requires no changes to the core business logic.

### 4.6 Error Handling & Resilience
**Decision:** Implement robust exception handling, retries, and fallback mechanisms.
**Rationale:**
- The system must never crash due to external service failures. If the AI fails after retries, a fallback deterministic score and response are generated.
- Unhandled exceptions at the API level are caught by custom exception handlers returning standard JSON error responses.

## 5. Consequences
- **Positive:** High resilience, clean separation of concerns, easy to test (due to dependency injection), and easy to extend.
- **Negative:** Dual storage (SQLite + Google Sheets) introduces slight sync complexity, but this is mitigated by treating local storage as the source of truth and failing gracefully on sync errors.
