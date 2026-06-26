#!/usr/bin/env bash
# =============================================================================
#  Lead Qualifier — Interactive Demo + Automated Test Suite
# =============================================================================
#  Spins up the FastAPI server (if not already running) and lets you hit each
#  endpoint interactively. Pick a number, see the curl request + JSON response.
#
#  Usage:
#    ./demo.sh              Interactive menu
#    ./demo.sh --test       Run automated test suite (smoke + edge cases + persistence)
#    ./demo.sh --test-only  Same as --test but skip the interactive demo intro
#    ./demo.sh --stop       Kill any demo server
# =============================================================================

set -u

# ── Config ───────────────────────────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="127.0.0.1"
PORT="8000"
BASE_URL="http://${HOST}:${PORT}"
PID_FILE="${PROJECT_DIR}/.demo_server.pid"
LOG_FILE="${PROJECT_DIR}/.demo_server.log"
DB_FILE="${PROJECT_DIR}/data/leads.db"
TEST_LOG="${PROJECT_DIR}/.test_results.log"
VENV_PY="${PROJECT_DIR}/.venv/bin/python"
VENV_UVICORN="${PROJECT_DIR}/.venv/bin/uvicorn"

# ── Test counters (used in --test mode) ──────────────────────────────────────
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
CURRENT_TEST=""

# ── Color helpers (auto-disabled if stdout is not a TTY) ─────────────────────
if [ -t 1 ]; then
    C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
    C_CYAN="\033[36m"; C_GREEN="\033[32m"; C_YELLOW="\033[33m"
    C_RED="\033[31m"; C_BLUE="\033[34m"; C_MAGENTA="\033[35m"
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""
    C_RED=""; C_BLUE=""; C_MAGENTA=""
fi

# ── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
    if [ -f "${PID_FILE}" ]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            echo
            echo -e "${C_DIM}Shutting down demo server (PID ${pid})…${C_RESET}"
            kill "${pid}" 2>/dev/null || true
            sleep 1
            kill -9 "${pid}" 2>/dev/null || true
        fi
        rm -f "${PID_FILE}"
    fi
}
trap cleanup EXIT INT TERM

# ── Utility: print section headers ───────────────────────────────────────────
banner() {
    local title="$1"
    echo
    echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}  ${title}${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
}

info()    { echo -e "${C_DIM}▸${C_RESET} $*"; }
ok()      { echo -e "${C_GREEN}✓${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }
err()     { echo -e "${C_RED}✗${C_RESET} $*"; }
request()  { echo -e "${C_BLUE}▶ REQUEST${C_RESET}  $*"; }
response() { echo -e "${C_MAGENTA}◀ RESPONSE${C_RESET} $*"; }
test_pass() { echo -e "  ${C_GREEN}✓${C_RESET} $*"; }
test_fail() { echo -e "  ${C_RED}✗${C_RESET} $*"; }
section()  { echo -e "\n${C_BOLD}${C_MAGENTA}── $* ──${C_RESET}"; }

# ── Check / start the server ─────────────────────────────────────────────────
ensure_server() {
    if curl -sf --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
        ok "Server already responding at ${BASE_URL}"
        return 0
    fi

    if [ -f "${PID_FILE}" ]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            err "PID ${pid} is alive but server is not responding. Killing it."
            kill "${pid}" 2>/dev/null || true
            sleep 1
        fi
        rm -f "${PID_FILE}"
    fi

    if [ ! -x "${VENV_UVICORN}" ]; then
        err "uvicorn not found at ${VENV_UVICORN}. Run: make setup"
        return 1
    fi

    info "Starting FastAPI server on ${BASE_URL} (logs → ${LOG_FILE})"
    cd "${PROJECT_DIR}"
    : > "${LOG_FILE}"
    nohup "${VENV_UVICORN}" app.main:app --host "${HOST}" --port "${PORT}" \
        > "${LOG_FILE}" 2>&1 &
    echo $! > "${PID_FILE}"

    local i
    for i in $(seq 1 30); do
        if curl -sf --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
            ok "Server is up (PID $(cat "${PID_FILE}"))"
            return 0
        fi
        sleep 0.5
    done

    err "Server failed to start within 15s. Last log lines:"
    tail -20 "${LOG_FILE}" 2>/dev/null || true
    return 1
}

# ── HTTP helpers ─────────────────────────────────────────────────────────────

# post_webhook <payload> -> writes status to stdout, body to $1 (file path)
post_webhook() {
    local outfile="$1"
    local payload="$2"
    curl -sS --max-time 30 -o "${outfile}" -w "%{http_code}" \
        -X POST "${BASE_URL}/api/v1/webhook" \
        -H "Content-Type: application/json" \
        --data "${payload}"
}

# ── Test framework ───────────────────────────────────────────────────────────
record_result() {
    local name="$1"
    local passed="$2"
    local detail="${3:-}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "${passed}" = "1" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        test_pass "${name}${detail:+ — ${detail}}"
        echo "PASS  ${name}  ${detail}" >> "${TEST_LOG}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        test_fail "${name}${detail:+ — ${detail}}"
        echo "FAIL  ${name}  ${detail}" >> "${TEST_LOG}"
    fi
}

assert_eq() {
    # assert_eq <test_name> <expected> <actual> [detail]
    local name="$1" expected="$2" actual="$3" detail="${4:-}"
    if [ "${expected}" = "${actual}" ]; then
        record_result "${name}" 1 "${detail} (=${actual})"
    else
        record_result "${name}" 0 "${detail} (expected=${expected}, got=${actual})"
    fi
}

assert_contains() {
    # assert_contains <test_name> <substring> <haystack> [detail]
    local name="$1" needle="$2" haystack="$3" detail="${4:-}"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        record_result "${name}" 1 "${detail}"
    else
        record_result "${name}" 0 "${detail} (substring '${needle}' not found)"
    fi
}

assert_jq() {
    # assert_jq <test_name> <jq_expr> <expected> <json_file> [detail]
    local name="$1" expr="$2" expected="$3" file="$4" detail="${5:-}"
    local actual
    actual=$(jq -r "${expr}" "${file}" 2>/dev/null || echo "<jq-error>")
    if [ "${actual}" = "${expected}" ]; then
        record_result "${name}" 1 "${detail}"
    else
        record_result "${name}" 0 "${detail} (expected '${expected}', got '${actual}')"
    fi
}

# ── Reset database before test run ───────────────────────────────────────────
reset_database() {
    info "Resetting SQLite database at ${DB_FILE}"
    rm -f "${DB_FILE}"
    # Trigger fresh table creation by hitting a request after server starts
}

# Verify a lead was persisted with the expected workflow_status
assert_lead_persisted() {
    local lead_id="$1" expected_status="$2"
    if [ ! -f "${DB_FILE}" ]; then
        record_result "Persistence: ${lead_id}" 0 "DB file not found"
        return
    fi
    local status
    status=$("${VENV_PY}" -c "
import sqlite3, sys
conn = sqlite3.connect('${DB_FILE}')
row = conn.execute('SELECT workflow_status FROM leads WHERE id = ?', ('${lead_id}',)).fetchone()
print(row[0] if row else 'NOT_FOUND')
" 2>/dev/null)
    if [ "${status}" = "${expected_status}" ]; then
        record_result "Persistence: ${lead_id}" 1 "workflow_status=${status}"
    else
        record_result "Persistence: ${lead_id}" 0 "expected=${expected_status}, got=${status}"
    fi
}

# ── Test payloads ───────────────────────────────────────────────────────────
PAYLOAD_HOT='{"full_name":"Sarah Chen","email":"sarah.chen@bigtech.com","company_name":"BigTech Industries","job_title":"VP of Engineering","phone":"555-2024","company_size":"500+","budget_range":"$50k+","message":"We urgently need to replace our broken lead routing system within 30 days. Budget approved, demo this week."}'

PAYLOAD_QUALIFIED='{"full_name":"Jordan Ellis","email":"jordan.ellis@examplecorp.com","company_name":"Example Corp","job_title":"Operations Manager","phone":"555-0199","company_size":"11-50","budget_range":"$5k-$15k/mo","message":"We are looking to automate our onboarding workflow and need help integrating with Salesforce."}'

PAYLOAD_LOW_CONTEXT='{"full_name":"Bob","email":"bob@test.com","message":"hi"}'

PAYLOAD_SPAM='{"full_name":"Spammer","email":"spam@spam.com","message":"Click here for free money!!! Limited offer, act now!"}'

PAYLOAD_MISSING_FIELDS='{"email":"test@test.com"}'

PAYLOAD_INVALID_EMAIL='{"full_name":"Bad","email":"not-an-email","message":"Hello there"}'

PAYLOAD_EMPTY_MESSAGE='{"full_name":"Alice","email":"alice@test.com","message":""}'

PAYLOAD_WHITESPACE_MESSAGE='{"full_name":"Alice","email":"alice@test.com","message":"          "}'

PAYLOAD_NORMALIZE_EMAIL='{"full_name":"Casey","email":"  CASEY@UPPERCASE.COM  ","message":"I want to know about pricing for the enterprise tier and what onboarding looks like."}'

# ── Test suite: webhook response codes & statuses ───────────────────────────
test_webhook_paths() {
    section "Webhook Response Codes & Workflow Statuses"
    local body

    body=$(mktemp)
    local code
    code=$(post_webhook "${body}" "${PAYLOAD_HOT}")
    assert_eq "Hot lead returns 200" "200" "${code}" "POST /webhook"
    assert_jq "Hot lead → qualified or qualified_fallback" \
        '.status | test("^qualified")' "true" "${body}"
    assert_jq "Hot lead has lead_id (UUID)" \
        '(.lead_id | length) > 30' "true" "${body}"
    HOT_LEAD_ID=$(jq -r '.lead_id' "${body}")
    rm -f "${body}"

    body=$(mktemp)
    code=$(post_webhook "${body}" "${PAYLOAD_QUALIFIED}")
    assert_eq "Warm qualified lead returns 200" "200" "${code}" "POST /webhook"
    assert_jq "Warm lead → qualified or qualified_fallback" \
        '.status | test("^qualified")' "true" "${body}"
    QUALIFIED_LEAD_ID=$(jq -r '.lead_id' "${body}")
    rm -f "${body}"

    body=$(mktemp)
    code=$(post_webhook "${body}" "${PAYLOAD_LOW_CONTEXT}")
    assert_eq "Low-context lead returns 200" "200" "${code}" "POST /webhook"
    assert_jq "Low-context → status=low_context" '.status' "low_context" "${body}"
    assert_jq "Low-context → priority_tier=Cold" '.priority_tier' "Cold" "${body}"
    LOW_CTX_LEAD_ID=$(jq -r '.lead_id' "${body}")
    rm -f "${body}"

    body=$(mktemp)
    code=$(post_webhook "${body}" "${PAYLOAD_SPAM}")
    assert_eq "Spam lead returns 200" "200" "${code}" "POST /webhook"
    assert_jq "Spam red flag detected" \
        '(.red_flags | tostring | contains("looks_like_spam"))' "true" "${body}"
    SPAM_LEAD_ID=$(jq -r '.lead_id' "${body}")
    rm -f "${body}"
}

# ── Test suite: validation & edge cases ─────────────────────────────────────
test_validation_edges() {
    section "Validation & Edge Cases"

    local body
    body=$(mktemp)
    local code

    # Schema-level rejection (Pydantic): missing required fields → 422
    code=$(post_webhook "${body}" "${PAYLOAD_MISSING_FIELDS}")
    assert_eq "Missing required fields → 422" "422" "${code}" "POST /webhook"
    rm -f "${body}"

    # Business-level rejection: malformed email caught by validate_email_format
    # → 200 with status=rejected (NOT 422 — it's domain validation, not schema)
    body=$(mktemp)
    code=$(post_webhook "${body}" "${PAYLOAD_INVALID_EMAIL}")
    assert_eq "Invalid email format → 200 (rejected by business layer)" "200" "${code}" "POST /webhook"
    assert_jq "Invalid email → status=rejected" '.status' "rejected" "${body}"
    assert_jq "Invalid email → reason mentions email" \
        '(.reason // "") | test("email"; "i")' "true" "${body}"
    rm -f "${body}"

    # Empty message: required-field check fires first → status=rejected
    body=$(mktemp)
    code=$(post_webhook "${body}" "${PAYLOAD_EMPTY_MESSAGE}")
    assert_eq "Empty message → 200 (rejected)" "200" "${code}" "POST /webhook"
    assert_jq "Empty message → status=rejected" '.status' "rejected" "${body}"
    rm -f "${body}"

    # Whitespace-only message: same path (after strip, msg is empty)
    body=$(mktemp)
    code=$(post_webhook "${body}" "${PAYLOAD_WHITESPACE_MESSAGE}")
    assert_eq "Whitespace-only message → 200 (rejected)" "200" "${code}" "POST /webhook"
    assert_jq "Whitespace msg → status=rejected" '.status' "rejected" "${body}"
    rm -f "${body}"

    # Email normalization: trim + lowercase before persistence
    body=$(mktemp)
    code=$(post_webhook "${body}" "${PAYLOAD_NORMALIZE_EMAIL}")
    assert_eq "Whitespace email → 200" "200" "${code}" "POST /webhook"
    sleep 0.3  # let the async session flush
    local normalized
    normalized=$("${VENV_PY}" -c "
import sqlite3
conn = sqlite3.connect('${DB_FILE}')
row = conn.execute('SELECT email FROM leads ORDER BY received_at DESC LIMIT 1').fetchone()
print(row[0] if row else '')
" 2>/dev/null)
    assert_eq "Email normalized (trimmed + lowercased)" \
        "casey@uppercase.com" "${normalized}" "DB row email"
    rm -f "${body}"

    # Method-not-allowed sanity check
    code=$(curl -sS --max-time 5 -o /dev/null -w "%{http_code}" \
        -X GET "${BASE_URL}/api/v1/webhook")
    assert_eq "GET /webhook → 405" "405" "${code}" "wrong HTTP method"
}

# ── Test suite: persistence (SQLite) ─────────────────────────────────────────
test_persistence() {
    section "Persistence (SQLite)"

    if [ -z "${HOT_LEAD_ID:-}" ] || [ -z "${LOW_CTX_LEAD_ID:-}" ] || [ -z "${SPAM_LEAD_ID:-}" ]; then
        warn "Lead IDs from earlier tests missing — re-running webhook calls"
        local body
        body=$(mktemp)
        post_webhook "${body}" "${PAYLOAD_HOT}" >/dev/null
        HOT_LEAD_ID=$(jq -r '.lead_id' "${body}")
        rm -f "${body}"

        body=$(mktemp)
        post_webhook "${body}" "${PAYLOAD_LOW_CONTEXT}" >/dev/null
        LOW_CTX_LEAD_ID=$(jq -r '.lead_id' "${body}")
        rm -f "${body}"

        body=$(mktemp)
        post_webhook "${body}" "${PAYLOAD_SPAM}" >/dev/null
        SPAM_LEAD_ID=$(jq -r '.lead_id' "${body}")
        rm -f "${body}"
    fi

    assert_lead_persisted "${HOT_LEAD_ID}" "ai_complete"
    assert_lead_persisted "${LOW_CTX_LEAD_ID}" "low_context"

    # Verify the spam lead's red_flags JSON column contains our flag
    local red_flags
    red_flags=$("${VENV_PY}" -c "
import sqlite3, json
conn = sqlite3.connect('${DB_FILE}')
row = conn.execute('SELECT red_flags FROM leads WHERE id = ?', ('${SPAM_LEAD_ID}',)).fetchone()
print(json.dumps(row[0]) if row else 'NOT_FOUND')
" 2>/dev/null)
    if [[ "${red_flags}" == *"looks_like_spam"* ]]; then
        record_result "Spam red flag persisted in JSON column" 1 "${red_flags}"
    else
        record_result "Spam red flag persisted in JSON column" 0 "${red_flags}"
    fi

    # Verify total lead count is what we expect
    local count
    count=$("${VENV_PY}" -c "
import sqlite3
print(sqlite3.connect('${DB_FILE}').execute('SELECT COUNT(*) FROM leads').fetchone()[0])
" 2>/dev/null)
    if [ "${count}" -ge 4 ]; then
        record_result "Lead count ≥ 4" 1 "count=${count}"
    else
        record_result "Lead count ≥ 4" 0 "count=${count}"
    fi
}

# ── Test suite: notification attempts ────────────────────────────────────────
test_notification_attempts() {
    section "Notification Attempts (logged in server log)"

    if [ ! -f "${LOG_FILE}" ]; then
        record_result "Server log exists" 0 "${LOG_FILE} missing"
        return
    fi

    # Send a fresh hot lead and check the log for Brevo/Slack attempts
    local body
    body=$(mktemp)
    post_webhook "${body}" "${PAYLOAD_HOT}" >/dev/null
    rm -f "${body}"

    sleep 1  # let log writes flush

    # At least one of: Brevo skipped (no key) or Brevo send attempted
    if grep -q "Brevo not configured" "${LOG_FILE}" \
       || grep -q "Brevo notification sent" "${LOG_FILE}" \
       || grep -q "Brevo notification failed" "${LOG_FILE}"; then
        record_result "Brevo channel exercised" 1 "logged"
    else
        record_result "Brevo channel exercised" 0 "no Brevo log entries"
    fi

    # Slack similarly
    if grep -q "Slack webhook not configured" "${LOG_FILE}" \
       || grep -q "Slack notification sent" "${LOG_FILE}" \
       || grep -q "Slack notification failed" "${LOG_FILE}"; then
        record_result "Slack channel exercised" 1 "logged"
    else
        record_result "Slack channel exercised" 0 "no Slack log entries"
    fi
}

# ── Test suite: Google Sheets sync attempts ──────────────────────────────────
test_sheets_sync_attempts() {
    section "Google Sheets Sync Attempts (logged in server log)"

    if [ ! -f "${LOG_FILE}" ]; then
        record_result "Server log exists" 0 "${LOG_FILE} missing"
        return
    fi

    # With dummy creds in .env, the GoogleSheetsAppender is NOT constructed
    # (deps.py skips it). So we just verify the orchestrator handled this gracefully:
    # the webhook returned 200 without crashing.
    local body
    body=$(mktemp)
    local code
    code=$(post_webhook "${body}" "${PAYLOAD_HOT}")
    if [ "${code}" = "200" ]; then
        record_result "Sheets sync absent → webhook still 200" 1 "graceful skip"
    else
        record_result "Sheets sync absent → webhook still 200" 0 "got HTTP ${code}"
    fi
    rm -f "${body}"
}

# ── Test suite: AI fallback ─────────────────────────────────────────────────
test_ai_fallback() {
    section "AI Fallback (when GEMINI_API_KEY missing or model returns junk)"

    # If Gemini key is missing, every webhook call should yield qualified_fallback
    local has_key
    has_key=$(grep -E '^GEMINI_API_KEY=.+' "${PROJECT_DIR}/.env" 2>/dev/null \
              | grep -v '^GEMINI_API_KEY=$' | wc -l)

    if [ "${has_key}" -eq 0 ]; then
        info "No GEMINI_API_KEY set → expecting qualified_fallback"
        local body
        body=$(mktemp)
        post_webhook "${body}" "${PAYLOAD_QUALIFIED}" >/dev/null
        assert_jq "No Gemini key → qualified_fallback" \
            '.status' "qualified_fallback" "${body}"
        assert_jq "Fallback includes AI_ERROR red flag" \
            '(.red_flags | tostring | contains("AI_ERROR"))' "true" "${body}"
        assert_jq "Fallback uses Manual Review tier" \
            '.priority_tier' "Manual Review" "${body}"
        rm -f "${body}"
    else
        info "Gemini key present → AI may succeed or fail. Checking both are handled."
        local body
        body=$(mktemp)
        post_webhook "${body}" "${PAYLOAD_QUALIFIED}" >/dev/null
        assert_jq "AI response status is qualified*" \
            '.status | test("^qualified")' "true" "${body}"
        rm -f "${body}"
    fi
}

# ── Test suite: webhook concurrency / no-crash ──────────────────────────────
test_concurrency() {
    section "Concurrency & No-Crash Guarantee"

    # Fire 5 concurrent webhook calls. We use a *short* message so requests hit
    # the low_context path (no AI calls) — keeps the test fast and avoids
    # hitting Gemini rate limits.
    local CONCURRENCY=5
    info "Firing ${CONCURRENCY} parallel webhook calls (low-context payloads)..."
    local pids=()
    local results_dir
    results_dir=$(mktemp -d)

    local LOW_CTX_PAYLOAD='{"full_name":"Load Test","email":"load@test.com","message":"hi"}'

    for i in $(seq 1 "${CONCURRENCY}"); do
        (
            curl -sS --max-time 15 -o "${results_dir}/r${i}.json" -w "%{http_code}" \
                -X POST "${BASE_URL}/api/v1/webhook" \
                -H "Content-Type: application/json" \
                --data "${LOW_CTX_PAYLOAD}" > "${results_dir}/s${i}"
        ) &
        pids+=($!)
    done

    local failed=0
    for pid in "${pids[@]}"; do
        wait "${pid}" || failed=$((failed + 1))
    done

    local non200=0
    for i in $(seq 1 "${CONCURRENCY}"); do
        local s
        s=$(cat "${results_dir}/s${i}" 2>/dev/null)
        if [ "${s}" != "200" ]; then
            non200=$((non200 + 1))
        fi
    done

    if [ "${failed}" -eq 0 ] && [ "${non200}" -eq 0 ]; then
        record_result "${CONCURRENCY} parallel webhook calls all return 200" 1 "no crashes"
    else
        record_result "${CONCURRENCY} parallel webhook calls all return 200" 0 \
            "failures=${failed} non200=${non200}"
    fi

    # Verify all ${CONCURRENCY} leads got persisted
    # Wait for async sessions to commit; SQLite WAL can lag briefly.
    sleep 1
    local count
    count=$("${VENV_PY}" -c "
import sqlite3
print(sqlite3.connect('${DB_FILE}').execute(\"SELECT COUNT(*) FROM leads WHERE email='load@test.com'\").fetchone()[0])
" 2>/dev/null)
    if [ "${count}" = "${CONCURRENCY}" ]; then
        record_result "${CONCURRENCY} concurrent leads persisted" 1 "count=${count}"
    else
        record_result "${CONCURRENCY} concurrent leads persisted" 0 "expected=${CONCURRENCY} got=${count}"
    fi

    rm -rf "${results_dir}"
}

# ── Test suite runner ───────────────────────────────────────────────────────
run_test_suite() {
    banner "AUTOMATED TEST SUITE"
    info "Server: ${BASE_URL}"
    info "DB:     ${DB_FILE}"
    info "Log:    ${LOG_FILE}"
    info "Results:${TEST_LOG}"

    : > "${TEST_LOG}"

    reset_database
    ensure_server || { err "Cannot start server"; return 1; }

    test_webhook_paths
    test_validation_edges
    test_persistence
    test_notification_attempts
    test_sheets_sync_attempts
    test_ai_fallback
    test_concurrency

    # ── Summary ──
    banner "TEST SUMMARY"
    echo -e "  Total:  ${C_BOLD}${TESTS_TOTAL}${C_RESET}"
    echo -e "  Passed: ${C_GREEN}${TESTS_PASSED}${C_RESET}"
    echo -e "  Failed: ${C_RED}${TESTS_FAILED}${C_RESET}"
    echo
    if [ "${TESTS_FAILED}" -eq 0 ]; then
        echo -e "  ${C_BOLD}${C_GREEN}✓ ALL TESTS PASSED${C_RESET}"
        echo
        info "Detailed results: ${TEST_LOG}"
        return 0
    else
        echo -e "  ${C_BOLD}${C_RED}✗ ${TESTS_FAILED} TEST(S) FAILED${C_RESET}"
        echo
        info "Detailed results: ${TEST_LOG}"
        return 1
    fi
}

# ── Show menu ────────────────────────────────────────────────────────────────
show_menu() {
    echo
    echo -e "${C_BOLD}┌────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}│        LEAD QUALIFIER — INTERACTIVE API DEMO               │${C_RESET}"
    echo -e "${C_BOLD}│        Server: ${C_CYAN}${BASE_URL}${C_BOLD}                             │${C_RESET}"
    echo -e "${C_BOLD}├────────────────────────────────────────────────────────────┤${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[1]${C_RESET} GET  /health                                  ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[2]${C_RESET} GET  /openapi.json  (API schema)             ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[3]${C_RESET} GET  /docs        (Swagger UI link)        ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[4]${C_RESET} POST /api/v1/webhook  (qualified lead)      ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[5]${C_RESET} POST /api/v1/webhook  (hot / decision-maker) ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[6]${C_RESET} POST /api/v1/webhook  (cold / low-context)   ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[7]${C_RESET} POST /api/v1/webhook  (spam detection)       ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[8]${C_RESET} POST /api/v1/webhook  (missing fields → 422) ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[9]${C_RESET} POST /api/v1/webhook  (invalid email → 422)  ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[a]${C_RESET} POST /api/v1/webhook  (custom JSON payload)   ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[b]${C_RESET} POST /api/v1/webhook  (run ALL examples)      ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_YELLOW}[t]${C_RESET} Run AUTOMATED TEST SUITE (~30s)             ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_DIM}[s]${C_RESET} Show server status & last log lines          ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_RED}[q]${C_RESET} Quit                                          ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}└────────────────────────────────────────────────────────────┘${C_RESET}"
}

# ── Endpoint runners ─────────────────────────────────────────────────────────

run_health() {
    banner "GET /health"
    request "GET ${BASE_URL}/health"
    response "↓"
    echo
    curl -sS -i --max-time 5 "${BASE_URL}/health" | head -20
    echo
}

run_openapi() {
    banner "GET /openapi.json (truncated)"
    request "GET ${BASE_URL}/openapi.json"
    response "↓"
    echo
    curl -sS --max-time 5 "${BASE_URL}/openapi.json" \
        | jq '{openapi, info, paths: (.paths | keys)}'
}

run_docs() {
    banner "GET /docs (Swagger UI)"
    info "Interactive docs are served at: ${BASE_URL}/docs"
    request "GET ${BASE_URL}/docs (HEAD only)"
    response "↓"
    echo
    curl -sS -I --max-time 5 "${BASE_URL}/docs" | head -10
    echo
    info "Open this URL in a browser to explore the API visually."
}

run_webhook_qualified() {
    banner "POST /api/v1/webhook — QUALIFIED LEAD (warm B2B inquiry)"
    run_webhook "${PAYLOAD_QUALIFIED}"
}

run_webhook_hot() {
    banner "POST /api/v1/webhook — HOT LEAD (urgent decision-maker)"
    run_webhook "${PAYLOAD_HOT}"
}

run_webhook_low_context() {
    banner "POST /api/v1/webhook — LOW CONTEXT LEAD (rejected by filter)"
    run_webhook "${PAYLOAD_LOW_CONTEXT}"
}

run_webhook_spam() {
    banner "POST /api/v1/webhook — SPAM DETECTION"
    run_webhook "${PAYLOAD_SPAM}"
}

run_webhook_missing_fields() {
    banner "POST /api/v1/webhook — MISSING REQUIRED FIELDS (→ 422)"
    run_webhook "${PAYLOAD_MISSING_FIELDS}"
}

run_webhook_invalid_email() {
    banner "POST /api/v1/webhook — INVALID EMAIL FORMAT (→ 422 from Pydantic)"
    run_webhook "${PAYLOAD_INVALID_EMAIL}"
}

run_webhook_custom() {
    banner "POST /api/v1/webhook — CUSTOM PAYLOAD"
    echo -e "${C_DIM}Paste a JSON payload, then press Enter on an empty line:${C_RESET}"
    echo
    local payload=""
    while IFS= read -r line; do
        [ -z "$line" ] && break
        payload+="${line}"$'\n'
    done
    if [ -z "${payload}" ]; then
        warn "No payload entered — using the qualified-lead default."
        run_webhook_qualified
        return
    fi
    run_webhook "${payload}"
}

run_webhook_all() {
    run_webhook_qualified
    press_enter
    run_webhook_hot
    press_enter
    run_webhook_low_context
    press_enter
    run_webhook_spam
    press_enter
    run_webhook_missing_fields
    press_enter
    run_webhook_invalid_email
}

# ── Core: fire a webhook request and pretty-print the response ───────────────
run_webhook() {
    local payload="$1"
    request "POST ${BASE_URL}/api/v1/webhook"
    echo -e "${C_DIM}  Payload:${C_RESET}"
    echo "${payload}" | jq . 2>/dev/null | sed 's/^/    /'
    echo
    response "↓"
    echo

    local tmpfile
    tmpfile=$(mktemp)

    local http_status
    http_status=$(curl -sS --max-time 30 -o "${tmpfile}" -w "%{http_code}" \
        -X POST "${BASE_URL}/api/v1/webhook" \
        -H "Content-Type: application/json" \
        --data "${payload}")

    echo -e "${C_BOLD}  HTTP ${http_status}${C_RESET}"
    echo
    if jq . "${tmpfile}" >/dev/null 2>&1; then
        jq . "${tmpfile}" | sed 's/^/    /'
    else
        cat "${tmpfile}" | sed 's/^/    /'
    fi
    rm -f "${tmpfile}"
    echo
}

press_enter() {
    echo
    echo -e "${C_DIM}───────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -en "${C_DIM}Press Enter to continue…${C_RESET}"
    read -r _
}

show_status() {
    banner "SERVER STATUS"
    if curl -sf --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
        ok "Server is responding at ${BASE_URL}"
    else
        warn "Server is NOT responding at ${BASE_URL}"
    fi
    if [ -f "${PID_FILE}" ]; then
        info "PID file: $(cat "${PID_FILE}")"
    fi
    if [ -f "${LOG_FILE}" ]; then
        echo
        info "Last 15 log lines:"
        tail -15 "${LOG_FILE}" 2>/dev/null | sed 's/^/    /'
    fi
    if [ -f "${TEST_LOG}" ]; then
        echo
        info "Last test run results:"
        tail -20 "${TEST_LOG}" 2>/dev/null | sed 's/^/    /'
    fi
}

# ── CLI flag handling ────────────────────────────────────────────────────────
case "${1:-}" in
    --stop)
        if [ -f "${PID_FILE}" ]; then
            pid=$(cat "${PID_FILE}")
            if kill -0 "${pid}" 2>/dev/null; then
                kill "${pid}"
                ok "Stopped server (PID ${pid})"
            fi
            rm -f "${PID_FILE}"
        else
            info "No demo server is running."
        fi
        exit 0
        ;;
    --test|--test-only)
        run_test_suite
        exit $?
        ;;
esac

# ── Main loop ────────────────────────────────────────────────────────────────
ensure_server || exit 1

banner "WELCOME"
echo -e "  Project:  ${C_BOLD}Lead Qualifier API${C_RESET}"
echo -e "  Server:   ${C_CYAN}${BASE_URL}${C_RESET}"
echo -e "  Endpoints under ${C_BOLD}/api/v1${C_RESET}"
echo -e "  Logs:     ${C_DIM}${LOG_FILE}${C_RESET}"
echo
echo -e "  ${C_DIM}Tip: this script keeps the server running in the background.${C_RESET}"
echo -e "  ${C_DIM}It will be stopped automatically when you quit (or run: ./demo.sh --stop).${C_RESET}"
echo -e "  ${C_DIM}For automated testing, run: ./demo.sh --test${C_RESET}"

while true; do
    show_menu
    echo
    echo -en "${C_BOLD}Pick an option [1-9, a, b, t, s, q]:${C_RESET} "
    read -r choice

    case "${choice}" in
        1) run_health ;;
        2) run_openapi ;;
        3) run_docs ;;
        4) run_webhook_qualified ;;
        5) run_webhook_hot ;;
        6) run_webhook_low_context ;;
        7) run_webhook_spam ;;
        8) run_webhook_missing_fields ;;
        9) run_webhook_invalid_email ;;
        a|A) run_webhook_custom ;;
        b|B) run_webhook_all ;;
        t|T)
            run_test_suite
            ;;
        s|S) show_status ;;
        q|Q)
            echo
            ok "Bye!"
            exit 0
            ;;
        *)
            err "Unknown option: '${choice}'. Pick 1-9, a, b, t, s, or q."
            ;;
    esac

    press_enter
done
