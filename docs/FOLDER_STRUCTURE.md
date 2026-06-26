# Folder Structure

The project follows a Layered Architecture to enforce a clear separation of concerns, ensuring maintainability and ease of testing.

```text
lead_qualifier/
├── app/
│   ├── api/             # Presentation Layer: FastAPI routers, endpoints, and dependency injection.
│   │   ├── v1/          # API version 1 routers.
│   │   ├── deps.py      # Dependency injection providers.
│   │   └── errors.py    # Custom exception handlers for HTTP responses.
│   ├── core/            # Application-wide settings and core configurations.
│   │   ├── config.py    # Pydantic BaseSettings for environment variables.
│   │   ├── exceptions.py# Custom application exceptions.
│   │   └── logging.py   # Structured logging configuration.
│   ├── db/              # Database infrastructure (SQLAlchemy setup).
│   │   └── session.py   # DB session and engine creation.
│   ├── integrations/    # Infrastructure Layer: External APIs and services.
│   │   ├── ai/          # AI Provider integrations (Gemini, Fallbacks).
│   │   ├── notifications/ # Notification integrations (Brevo, Slack).
│   │   └── sheets/      # Persistence integrations (Google Sheets, SQLite).
│   ├── models/          # SQLAlchemy ORM models (Database representation).
│   │   └── lead.py      # Database table definition for Leads.
│   ├── schemas/         # Pydantic DTOs (Data Transfer Objects).
│   │   ├── lead.py      # Internal business logic schemas.
│   │   └── webhook.py   # API request/response schemas.
│   ├── services/        # Business Layer: Core application logic.
│   │   ├── filtering.py # Logic to identify spam or low-context leads.
│   │   ├── lead_qualifier.py # Main orchestration workflow for leads.
│   │   └── validation.py# Domain-specific validation logic.
│   └── main.py          # FastAPI application factory and entrypoint.
├── tests/               # Automated test suite (pytest).
│   ├── integration/     # End-to-end API and integration tests.
│   └── unit/            # Unit tests for isolated business logic.
├── docs/                # Project documentation and architectural decisions.
├── Makefile             # Automation shortcuts for setup, dev, and testing.
├── pyproject.toml       # Python dependencies and project metadata.
└── README.md            # Project overview and instructions.
```

## Responsibilities
- **Presentation Layer (`app/api`):** Handles HTTP requests, parses inputs, and formats responses. Depends on schemas and services.
- **Business Layer (`app/services`):** Contains the core business rules (lead qualification, orchestration). Operates entirely on DTOs (schemas).
- **Infrastructure Layer (`app/integrations`):** Implements interfaces to interact with the outside world (Gemini, Google Sheets, Slack, Database).
- **Schemas (`app/schemas`):** Defines strict data contracts passed between all layers, ensuring type safety and decoupling.
