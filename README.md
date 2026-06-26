# Lead Qualifier

Webhook → AI scoring → SQLite + Google Sheets → email/Slack alert. Built for the AI Automation Engineer assessment.

## Run it

```bash
make setup        # create venv, install deps
cp .env.example .env  # add your keys
make dev          # uvicorn on :8000
```

`/health` returns 200 once it's up. The single endpoint is `POST /api/v1/webhook`. There's a `demo.sh` that lets you fire example payloads interactively or run the full automated test suite (`./demo.sh --test`).

## Architecture, in one paragraph

FastAPI on top, business logic in `app/services/lead_qualifier.py`, integrations hidden behind four one-method ABCs (`AIProvider`, `LeadRepository`, `SheetAppender`, `NotificationService`). The orchestrator depends on those interfaces and never on an SDK. SQLite is the source of truth; Google Sheets is a downstream sync target. External services never crash the webhook — AI returns a deterministic fallback on failure, Sheets/Brevo/Slack errors are logged and the response still goes out.

The full ADR is in [`docs/ADR.md`](docs/ADR.md). If you only have two minutes, read that file.

## Key design decisions

**Layered architecture, not hexagonal.** The codebase is small. A port/adapter split would be ceremony for its own sake. Layers are enforced by import direction (presentation → business → integrations), not by abstract base classes everywhere. The integrations *do* have ABCs because that's where swapping matters.

**SQLite as the source of truth, Sheets as reporting.** This was the call I'm most comfortable defending. If Sheets rate-limits us or our service account breaks, we don't lose leads. The cost is dual-write complexity, which I mitigated by making Sheets a fire-and-forget append with logged failures.

**The webhook is synchronous.** The bonus extension asks for a synchronous response and I took it. The AI call is the bottleneck — 1–3 seconds typical, 30s timeout, two retries with exponential backoff. Means the caller's HTTP client has to be patient. Trade-off I accepted: slower response, but the caller walks away with a tier and a suggested opener, no follow-up call needed.

**Resilience via fallbacks, not retries-everywhere.** I tried retries on Sheets and Brevo and removed them. If those fail, retrying immediately makes things worse. The right move is: log it, fail that step, return 200. The fallback AI response (score=50, priority="Manual Review", red_flags=["AI_ERROR"]) is what makes the system safe to operate without a human on call.

## The AI prompt

In [`app/integrations/ai/prompts/lead_scoring.py`](app/integrations/ai/prompts/lead_scoring.py). System prompt only — no few-shot examples, no chain-of-thought. I tried few-shot first and the scores got *less* consistent because Gemini started pattern-matching on the examples rather than the rubric. The prompt defines a strict JSON schema, gives scoring bands (Hot=75-100, Warm=40-74, Cold=1-39), and tells the model to return only JSON with no markdown fencing.

Temperature is 0.1 — low enough to be deterministic, high enough that you don't get the same suggested opener verbatim for two similar leads. `max_output_tokens=1024` is overkill; the actual response is ~150 tokens.

Two things I'd change about the prompt:
- The "Hot/Warm/Cold" tier labels are arbitrary. I'd align them with the company's existing CRM vocabulary.
- The red_flags enum isn't fixed. Right now Gemini can invent flag strings ("Spam message", "Irrelevant content") that don't match anything in our spam heuristic. I'd constrain it to a closed set.

## Known limitations

**SQLite is single-writer.** I enabled WAL mode in `app/db/session.py` so concurrent readers don't block writers, but two simultaneous writes still serialize. For an assessment-scale system this is fine. For a real inbound flow doing 50+ req/sec, swap to Postgres — the SQLAlchemy code is portable, only `DATABASE_URL` changes.

**The Brevo and Slack integrations are not unit-tested.** I test the orchestrator with a `NoopNotification`. The SDK call paths have manual coverage via `demo.sh` but no mocked test for, say, "Brevo returns 429 and we log it." That's a gap.

**No webhook signature verification.** The `WEBHOOK_SECRET` env var exists but isn't enforced. If I were deploying this, I'd add HMAC verification on the `X-Signature` header before doing anything else.

**The AI timeout is 30s.** That's long. In practice the response is 2-3s, but if Gemini ever has a brownout, every webhook hangs for 30s before falling back. I'd lower this to 10s and rely on the retry policy.

**No idempotency.** If the caller's network drops the response, they retry, we create a second lead row. Production would need an idempotency key header and a unique constraint.

**No structured logging of the lead payload itself.** We log lead_id, status, scores, latencies — but not the actual message text. Good for privacy, bad for debugging a specific lead. I'd add a `payload_hash` field so you can grep all logs for a specific message without logging PII.

**No request rate limiting.** The webhook will accept as many calls as the kernel will let it make TCP connections. FastAPI has no built-in throttling.

## What I'd do with more time

1. **Postgres migration.** The current SQLite setup is a deliberate tradeoff, not a permanent choice. Port the schema, swap the engine URL, add a one-time data migration script.

2. **Background job queue for Sheets/Brevo.** Right now the webhook waits for those calls to complete (or fail). Move them to a worker (RQ, Celery, or just asyncio.create_task with proper retry). Webhook response time drops from ~3s to ~500ms.

3. **Real webhook auth.** HMAC verification on inbound, plus a per-tenant API key for outgoing Sheets/Brevo credentials.

4. **Lead deduplication.** Check email + company on inbound; if a lead exists, append the new message to the existing record instead of creating a new row.

5. **Prompt evaluation suite.** A `tests/prompts/` folder with 20-30 hand-labeled example leads, asserting that Gemini's scoring matches expectations within a tolerance. Run on every prompt change.

6. **OpenTelemetry traces.** Spans across the orchestrator steps so you can see exactly where a slow webhook is spending its time.

7. **A second AI provider behind the same `AIProvider` ABC.** OpenAI for cost comparison, or a local Llama for PII-sensitive leads. The interface is there; nobody has built it yet.

8. **Better filtering logic.** Right now `is_low_context` is just a length threshold (10 chars). I'd add basic NLP — does the message contain a question? a product name? a budget number? — before deciding to skip the AI call.

## Testing

```bash
make test             # pytest unit + integration
./demo.sh --test      # 30+ end-to-end tests including persistence, notifications, concurrency
```

The bash test suite is what I'd run before a deploy. It actually hits the webhook, checks the SQLite DB, greps the server log for notification attempts, and fires concurrent requests to verify no-crash behavior. It catches things pytest can't — like the WAL-mode bug I shipped in the first version.

## Repo layout

```
app/
  api/            # FastAPI routers, error handlers, DI container
  core/           # config, logging, exceptions
  db/             # SQLAlchemy engine + session
  integrations/   # AI, Sheets, Notifications — one folder per concern
  models/         # ORM models
  schemas/        # Pydantic DTOs (the contracts between layers)
  services/       # orchestrator + validation + filtering
  main.py         # app factory
docs/             # ADR, schema, API contract, sequence diagram
tests/            # pytest
demo.sh           # interactive demo + automated E2E test runner
```

See [`docs/FOLDER_STRUCTURE.md`](docs/FOLDER_STRUCTURE.md) for the reasoning.