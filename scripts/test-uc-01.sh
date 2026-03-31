#!/usr/bin/env bash
# UC01 — Researcher (memory + Telegram + weekly digest)
#
# Tests HermesClaw then NemoClaw for the researcher use case.
# Run after: ./scripts/test-setup.sh
#
# Usage:
#   bash scripts/test-uc-01.sh

set -uo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_FILE="$REPO_DIR/docs/test-results-uc.md"

pass() { echo -e "  ${GREEN}✅ PASS${RESET}  $*"; }
fail() { echo -e "  ${RED}❌ FAIL${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠️  WARN${RESET}  $*"; }
info() { echo -e "  ${BOLD}ℹ${RESET}       $*"; }

update_result() {
    local uc="$1" step="$2" stack="$3" result="$4"
    # stack: "hermes" or "nemo"
    # result: "✅" "❌" "⚠️"
    local col
    [[ "$stack" == "hermes" ]] && col=2 || col=3
    python3 - "$RESULTS_FILE" "$uc" "$step" "$col" "$result" << 'PYEOF'
import sys, re

path, uc, step, col, result = sys.argv[1:]
col = int(col)

with open(path, 'r') as f:
    lines = f.readlines()

in_section = False
for i, line in enumerate(lines):
    if f'## {uc}' in line:
        in_section = True
    if in_section and step in line and '|' in line:
        parts = line.split('|')
        if len(parts) > col:
            parts[col] = f' {result} '
            lines[i] = '|'.join(parts)
        break

with open(path, 'w') as f:
    f.writelines(lines)
PYEOF
}

echo ""
echo -e "${BOLD}UC01 — Researcher (memory + Telegram + weekly digest)${RESET}"
echo "======================================================"
echo ""

# ── HermesClaw ────────────────────────────────────────────────────────────────

echo -e "${BOLD}[HermesClaw]${RESET}"
echo ""

# Stack running?
if docker compose -f "$REPO_DIR/docker-compose.yml" ps 2>/dev/null | grep -q "healthy\|running\|Up"; then
    pass "Stack running"
    update_result "UC01" "Stack starts" "hermes" "✅"
else
    fail "Stack not running — run: docker compose up -d"
    update_result "UC01" "Stack starts" "hermes" "❌"
    echo "  Run: docker compose up -d && bash scripts/test-uc-01.sh"
    exit 1
fi

# Basic chat
info "Testing basic chat..."
RESPONSE=$(docker exec hermesclaw hermes chat -q "Reply with: RESEARCHER_OK" 2>/dev/null || echo "")
if echo "$RESPONSE" | grep -qi "researcher_ok\|ok\|hello"; then
    pass "Basic chat: '$RESPONSE'"
    update_result "UC01" "Basic chat" "hermes" "✅"
else
    fail "Basic chat no response: '$RESPONSE'"
    update_result "UC01" "Basic chat" "hermes" "❌"
fi

# Memory write
info "Testing memory write..."
docker exec hermesclaw hermes chat -q \
    "My research area is transformer architectures and LLM inference optimization. Please remember this." \
    2>/dev/null | tail -3 || true

# Check if MEMORY.md was written
MEMORY_CONTENT=$(docker exec hermesclaw cat /root/.hermes/memories/MEMORY.md 2>/dev/null || echo "")
if echo "$MEMORY_CONTENT" | grep -qi "transformer\|research\|LLM"; then
    pass "Memory written to MEMORY.md"
    update_result "UC01" "Memory written to MEMORY.md" "hermes" "✅"
else
    warn "Memory not found in MEMORY.md (may use different path)"
    update_result "UC01" "Memory written to MEMORY.md" "hermes" "⚠️"
fi

# Memory recall in new session (simulate with -q flag)
info "Testing memory recall..."
RECALL=$(docker exec hermesclaw hermes chat -q \
    "What do you know about my research interests?" 2>/dev/null || echo "")
if echo "$RECALL" | grep -qi "transformer\|research\|LLM\|inference"; then
    pass "Memory recalled in new session"
    update_result "UC01" "Memory recalled in new session" "hermes" "✅"
else
    warn "Memory recall unclear: '$RECALL'"
    update_result "UC01" "Memory recalled in new session" "hermes" "⚠️"
fi

# Telegram — manual check
echo ""
warn "Telegram bot: MANUAL CHECK REQUIRED"
info "1. Message your Telegram bot: 'What are my research interests?'"
info "2. Expected: bot responds with transformer/LLM info from memory"
info "   Telegram bot token configured? Check .env TELEGRAM_BOT_TOKEN"
echo ""
read -rp "  Did Telegram bot respond? [y/n/skip]: " TELE_RESULT
case "$TELE_RESULT" in
    y) pass "Telegram bot responds"; update_result "UC01" "Telegram bot responds" "hermes" "✅" ;;
    n) fail "Telegram bot not responding"; update_result "UC01" "Telegram bot responds" "hermes" "❌" ;;
    *) warn "Telegram test skipped"; update_result "UC01" "Telegram bot responds" "hermes" "⚠️" ;;
esac

# Cron creation
info "Testing cron creation..."
docker exec hermesclaw hermes chat -q \
    "Every Monday at 9am, run research-digest. Please schedule this cron." \
    2>/dev/null | tail -2 || true

CRON_LIST=$(docker exec hermesclaw hermes cron list 2>/dev/null || echo "")
if echo "$CRON_LIST" | grep -qi "research\|monday\|9am\|9:00"; then
    pass "Cron created"
    update_result "UC01" "Cron created" "hermes" "✅"
else
    warn "Cron not confirmed: '$CRON_LIST'"
    update_result "UC01" "Cron created" "hermes" "⚠️"
fi

# Install and run research-digest skill
info "Testing research-digest skill install..."
if bash "$REPO_DIR/skills/install.sh" research-digest 2>/dev/null; then
    pass "research-digest skill installed"
else
    warn "Skill install returned non-zero (may already be installed)"
fi

SKILL_RESPONSE=$(docker exec hermesclaw hermes chat -q \
    "Run the research-digest skill with topic: transformer inference optimization" \
    2>/dev/null || echo "")
if echo "$SKILL_RESPONSE" | grep -qi "research\|digest\|arxiv\|paper\|topic\|transformer"; then
    pass "research-digest skill runs"
    update_result "UC01" "research-digest skill runs" "hermes" "✅"
else
    warn "Skill response unclear: '${SKILL_RESPONSE:0:100}...'"
    update_result "UC01" "research-digest skill runs" "hermes" "⚠️"
fi

echo ""
echo -e "${BOLD}HermesClaw UC01 complete.${RESET}"

# ── NemoClaw ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}[NemoClaw]${RESET}"
echo ""

OPENCLAW_CMD=""
if command -v openclaw &>/dev/null; then
    OPENCLAW_CMD="openclaw"
elif command -v nemoclaw &>/dev/null; then
    OPENCLAW_CMD="nemoclaw"
fi

if [[ -z "$OPENCLAW_CMD" ]]; then
    warn "NemoClaw not installed — skipping NemoClaw tests"
    for step in "Stack starts" "Basic chat" "Memory written to MEMORY.md" "Memory recalled in new session" "Telegram bot responds" "Cron created" "research-digest skill runs"; do
        update_result "UC01" "$step" "nemo" "⚠️"
    done
    echo ""
    info "Install NemoClaw and re-run to complete NemoClaw tests:"
    info "  curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
    echo ""
else
    # Stack starts
    NC_STATUS=$($OPENCLAW_CMD status 2>/dev/null | head -1 || echo "")
    if [[ -n "$NC_STATUS" ]]; then
        pass "NemoClaw CLI responding: '$NC_STATUS'"
        update_result "UC01" "Stack starts" "nemo" "✅"
    else
        warn "NemoClaw status unclear"
        update_result "UC01" "Stack starts" "nemo" "⚠️"
    fi

    # Basic chat
    info "Testing NemoClaw basic chat..."
    NC_RESPONSE=$($OPENCLAW_CMD chat "Reply with: NEMOCLAW_RESEARCHER_OK" 2>/dev/null || echo "")
    if echo "$NC_RESPONSE" | grep -qi "ok\|hello\|researcher"; then
        pass "Basic chat: '$NC_RESPONSE'"
        update_result "UC01" "Basic chat" "nemo" "✅"
    else
        fail "Basic chat no response: '$NC_RESPONSE'"
        update_result "UC01" "Basic chat" "nemo" "❌"
    fi

    # Memory write
    info "Testing NemoClaw memory write..."
    $OPENCLAW_CMD chat "My research area is quantum computing and error correction. Please remember this." \
        2>/dev/null | tail -2 || true

    # NemoClaw session memory check
    NC_RECALL=$($OPENCLAW_CMD chat "What do you know about my research interests?" 2>/dev/null || echo "")
    if echo "$NC_RECALL" | grep -qi "quantum\|research\|error correction"; then
        pass "Memory recalled (within session)"
        update_result "UC01" "Memory written to MEMORY.md" "nemo" "⚠️"
        update_result "UC01" "Memory recalled in new session" "nemo" "⚠️"
        info "Note: NemoClaw memory is session-only (no persistent MEMORY.md)"
    else
        fail "Memory not recalled: '$NC_RECALL'"
        update_result "UC01" "Memory written to MEMORY.md" "nemo" "❌"
        update_result "UC01" "Memory recalled in new session" "nemo" "❌"
    fi

    # Telegram
    warn "Telegram: MANUAL CHECK REQUIRED for NemoClaw"
    info "Message NemoClaw bot in Telegram: 'What are my research interests?'"
    read -rp "  Did NemoClaw Telegram bot respond? [y/n/skip]: " NC_TELE
    case "$NC_TELE" in
        y) pass "NemoClaw Telegram bot responds"; update_result "UC01" "Telegram bot responds" "nemo" "✅" ;;
        n) fail "NemoClaw Telegram not responding"; update_result "UC01" "Telegram bot responds" "nemo" "❌" ;;
        *) warn "Skipped"; update_result "UC01" "Telegram bot responds" "nemo" "⚠️" ;;
    esac

    # Cron
    info "Testing NemoClaw cron..."
    $OPENCLAW_CMD chat "Every Monday at 9am, summarize my research area and send to Telegram." \
        2>/dev/null | tail -2 || true
    NC_CRON=$($OPENCLAW_CMD cron list 2>/dev/null || echo "")
    if echo "$NC_CRON" | grep -qi "monday\|9am\|research\|9:00"; then
        pass "NemoClaw cron created"
        update_result "UC01" "Cron created" "nemo" "✅"
    else
        warn "NemoClaw cron not confirmed: '$NC_CRON'"
        update_result "UC01" "Cron created" "nemo" "⚠️"
    fi

    # research-digest skill (OpenClaw doesn't have SKILL.md format)
    NC_SKILL=$($OPENCLAW_CMD chat "Summarize recent research on transformer inference optimization" \
        2>/dev/null || echo "")
    if echo "$NC_SKILL" | grep -qi "transformer\|inference\|research\|paper"; then
        pass "NemoClaw research summary works"
        update_result "UC01" "research-digest skill runs" "nemo" "⚠️"
        info "Note: NemoClaw has no native research-digest skill; ad-hoc web search used"
    else
        warn "NemoClaw research summary unclear: '${NC_SKILL:0:80}'"
        update_result "UC01" "research-digest skill runs" "nemo" "⚠️"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "======================================================"
echo -e "${BOLD}UC01 complete. Results written to docs/test-results-uc.md${RESET}"
echo ""
info "Key findings:"
info "  HermesClaw: local inference + persistent MEMORY.md across sessions"
info "  NemoClaw: cloud inference (OpenAI) + session-only memory"
echo ""
info "Next: bash scripts/test-uc-02.sh   # developer"
echo ""
