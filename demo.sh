#!/usr/bin/env bash
# =============================================================================
#  Lead Qualifier — Interactive API Demo
# =============================================================================
#  Spins up the FastAPI server (if not already running) and lets you hit each
#  endpoint interactively. Pick a number, see the curl request + JSON response.
#
#  Usage:   ./demo.sh          (interactive menu)
#           ./demo.sh --stop   (kill the demo server)
# =============================================================================

set -u

# ── Config ───────────────────────────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="127.0.0.1"
PORT="8000"
BASE_URL="http://${HOST}:${PORT}"
PID_FILE="${PROJECT_DIR}/.demo_server.pid"
LOG_FILE="${PROJECT_DIR}/.demo_server.log"
VENV_PY="${PROJECT_DIR}/.venv/bin/python"
VENV_UVICORN="${PROJECT_DIR}/.venv/bin/uvicorn"

# Color helpers (auto-disabled if stdout is not a TTY)
if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_CYAN="\033[36m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_RED="\033[31m"
    C_BLUE="\033[34m"
    C_MAGENTA="\033[35m"
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_MAGENTA=""
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

# ── Pretty-print JSON (uses jq if available, otherwise cat) ──────────────────
pretty_json() {
    if command -v jq >/dev/null 2>&1; then
        jq .
    else
        cat
    fi
}

# ── Check / start the server ─────────────────────────────────────────────────
ensure_server() {
    # Already running?
    if curl -sf --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
        ok "Server already responding at ${BASE_URL}"
        return 0
    fi

    # PID file says it should be running?
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

    # Start it
    if [ ! -x "${VENV_UVICORN}" ]; then
        err "uvicorn not found at ${VENV_UVICORN}. Run: make setup"
        return 1
    fi

    info "Starting FastAPI server on ${BASE_URL} (logs → ${LOG_FILE})"
    cd "${PROJECT_DIR}"
    nohup "${VENV_UVICORN}" app.main:app --host "${HOST}" --port "${PORT}" \
        > "${LOG_FILE}" 2>&1 &
    echo $! > "${PID_FILE}"

    # Wait until /health responds (max 15s)
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
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[9]${C_RESET} POST /api/v1/webhook  (invalid email → 400)  ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[a]${C_RESET} POST /api/v1/webhook  (custom JSON payload)   ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}│${C_RESET}  ${C_GREEN}[b]${C_RESET} POST /api/v1/webhook  (run ALL examples)      ${C_BOLD}│${C_RESET}"
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
    local payload='{
  "full_name": "Jordan Ellis",
  "email": "jordan.ellis@examplecorp.com",
  "company_name": "Example Corp",
  "job_title": "Operations Manager",
  "phone": "555-0199",
  "company_size": "11-50",
  "budget_range": "$5k-$15k/mo",
  "message": "We are looking to automate our onboarding workflow and need help integrating with Salesforce."
}'
    run_webhook "$payload"
}

run_webhook_hot() {
    banner "POST /api/v1/webhook — HOT LEAD (urgent decision-maker)"
    local payload='{
  "full_name": "Sarah Chen",
  "email": "sarah.chen@bigtech.com",
  "company_name": "BigTech Industries",
  "job_title": "VP of Engineering",
  "phone": "555-2024",
  "company_size": "500+",
  "budget_range": "$50k+",
  "message": "We urgently need to replace our broken lead routing system within 30 days. We have budget approved and need to schedule a demo this week."
}'
    run_webhook "$payload"
}

run_webhook_low_context() {
    banner "POST /api/v1/webhook — LOW CONTEXT LEAD (rejected by filter)"
    local payload='{
  "full_name": "Bob",
  "email": "bob@test.com",
  "message": "hi"
}'
    run_webhook "$payload"
}

run_webhook_spam() {
    banner "POST /api/v1/webhook — SPAM DETECTION"
    local payload='{
  "full_name": "Spammer",
  "email": "spam@spam.com",
  "message": "Click here for free money!!! Limited offer, act now!"
}'
    run_webhook "$payload"
}

run_webhook_missing_fields() {
    banner "POST /api/v1/webhook — MISSING REQUIRED FIELDS (→ 422)"
    local payload='{
  "email": "test@test.com"
}'
    run_webhook "$payload"
}

run_webhook_invalid_email() {
    banner "POST /api/v1/webhook — INVALID EMAIL FORMAT (→ 422 from Pydantic)"
    local payload='{
  "full_name": "Bad Email",
  "email": "not-an-email",
  "message": "I would like to learn more about your services."
}'
    run_webhook "$payload"
}

run_webhook_custom() {
    banner "POST /api/v1/webhook — CUSTOM PAYLOAD"
    echo -e "${C_DIM}Paste a JSON payload, then press Ctrl-D (or Enter on empty line):${C_RESET}"
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

    local http_status
    local body
    local tmpfile
    tmpfile=$(mktemp)

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
}

# ── Handle --stop flag ───────────────────────────────────────────────────────
if [ "${1:-}" = "--stop" ]; then
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
fi

# ── Main loop ────────────────────────────────────────────────────────────────
ensure_server || exit 1

# Print summary on first launch
banner "WELCOME"
echo -e "  Project:  ${C_BOLD}Lead Qualifier API${C_RESET}"
echo -e "  Server:   ${C_CYAN}${BASE_URL}${C_RESET}"
echo -e "  Endpoints under ${C_BOLD}/api/v1${C_RESET}"
echo -e "  Logs:     ${C_DIM}${LOG_FILE}${C_RESET}"
echo
echo -e "  ${C_DIM}Tip: this script keeps the server running in the background.${C_RESET}"
echo -e "  ${C_DIM}It will be stopped automatically when you quit (or run: ./demo.sh --stop).${C_RESET}"

while true; do
    show_menu
    echo
    echo -en "${C_BOLD}Pick an option [1-9, a, b, s, q]:${C_RESET} "
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
        s|S) show_status ;;
        q|Q)
            echo
            ok "Bye!"
            exit 0
            ;;
        *)
            err "Unknown option: '${choice}'. Pick 1-9, a, b, s, or q."
            ;;
    esac

    press_enter
done
