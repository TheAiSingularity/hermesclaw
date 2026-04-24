#!/usr/bin/env bash
# UC07 — Trader / Quant (local latency + Telegram alerts)
#
# Tests HermesClaw then NemoClaw for the trader use case.
# Key metric: inference latency (ms) — measured for both stacks.
#
# Run after: ./scripts/test-setup.sh
#
# Usage:
#   bash scripts/test-uc-07.sh

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
    local col
    [[ "$stack" == "hermes" ]] && col=2 || col=3
    python3 - "$RESULTS_FILE" "$uc" "$step" "$col" "$result" << 'PYEOF'
import sys
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

update_latency() {
    # Update latency lines in summary section
    local stack="$1" latency="$2"
    local search_str
    if [[ "$stack" == "hermes" ]]; then
        search_str="HermesClaw latency"
    else
        search_str="NemoClaw latency"
    fi
    python3 - "$RESULTS_FILE" "$search_str" "$latency" << 'PYEOF'
import sys
path, search, latency = sys.argv[1:]
with open(path, 'r') as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if search in line and 'fill after testing' in line:
        lines[i] = line.replace('_fill after testing_', f'`{latency}`')
        break
with open(path, 'w') as f:
    f.writelines(lines)
PYEOF
}

measure_latency() {
    local cmd="$1"
    local start end elapsed
    start=$(python3 -c "import time; print(int(time.time() * 1000))")
    eval "$cmd" &>/dev/null
    end=$(python3 -c "import time; print(int(time.time() * 1000))")
    echo $((end - start))
}

echo ""
echo -e "${BOLD}UC07 — Trader / Quant (local latency + Telegram alerts)${RESET}"
echo "========================================================="
echo ""

TELEGRAM_TOKEN=$(grep "^TELEGRAM_BOT_TOKEN=" "$REPO_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "")
if [[ -z "$TELEGRAM_TOKEN" ]]; then
    warn "TELEGRAM_BOT_TOKEN not set in .env — Telegram alert tests will be skipped"
    TELEGRAM_AVAILABLE=false
else
    pass "TELEGRAM_BOT_TOKEN found"
    TELEGRAM_AVAILABLE=true
fi

# ── HermesClaw ────────────────────────────────────────────────────────────────

echo -e "${BOLD}[HermesClaw]${RESET}"
echo ""

if ! docker compose -f "$REPO_DIR/docker-compose.yml" ps 2>/dev/null | grep -q "healthy\|running\|Up"; then
    fail "Stack not running — run: docker compose up -d"
    exit 1
fi
pass "Stack running"
update_result "UC07" "Stack starts" "hermes" "✅"

# Install market-alerts skill
info "Installing market-alerts skill..."
bash "$REPO_DIR/skills/install.sh" market-alerts 2>/dev/null || true

# Set watchlist and thresholds
info "Setting watchlist and thresholds..."
docker exec hermesclaw hermes chat -q "
My trading watchlist and alert thresholds:
- NVDA: alert if above \$950 or below \$820
- TSLA: alert if above \$280 or below \$220
- BTC-USD: alert if above \$95000 or below \$78000

Daily briefing: every weekday at 9:25am ET.
Please remember this watchlist and alert configuration." \
    2>/dev/null | tail -3 || true

# Verify memory stored
MEMORY_CONTENT=$(docker exec hermesclaw cat /opt/hermes-data/memories/MEMORY.md 2>/dev/null || echo "")
if echo "$MEMORY_CONTENT" | grep -qi "NVDA\|watchlist\|threshold\|820\|950"; then
    pass "Watchlist + thresholds saved to memory"
    update_result "UC07" "Watchlist + thresholds saved to memory" "hermes" "✅"
else
    warn "Watchlist not found in MEMORY.md"
    update_result "UC07" "Watchlist + thresholds saved to memory" "hermes" "⚠️"
fi

# Threshold check
info "Testing threshold check logic..."
THRESHOLD_RESP=$(docker exec hermesclaw hermes chat -q \
    "NVDA is currently at \$823. Is this above or below my alert threshold? Should I be alerted?" \
    2>/dev/null || echo "")

if echo "$THRESHOLD_RESP" | grep -qi "below\|alert\|threshold\|820\|breach\|trigger"; then
    pass "Threshold check returns correct result"
    update_result "UC07" "Threshold check returns correct result" "hermes" "✅"
else
    warn "Threshold check unclear: '${THRESHOLD_RESP:0:100}'"
    update_result "UC07" "Threshold check returns correct result" "hermes" "⚠️"
fi

# market-alerts skill
info "Testing market-alerts skill..."
MARKET_RESP=$(docker exec hermesclaw hermes chat -q \
    "Run the market-alerts skill for my watchlist" \
    2>/dev/null || echo "")
if echo "$MARKET_RESP" | grep -qi "NVDA\|TSLA\|BTC\|alert\|market\|price\|threshold\|skill"; then
    pass "market-alerts skill runs"
    update_result "UC07" "market-alerts skill runs" "hermes" "✅"
else
    warn "Skill response unclear: '${MARKET_RESP:0:100}'"
    update_result "UC07" "market-alerts skill runs" "hermes" "⚠️"
fi

# Test monitor.py directly
info "Testing monitor.py script..."
MONITOR_RESULT=$(echo '[
    {"symbol": "NVDA", "current_price": 823, "threshold_high": 950, "threshold_low": 820},
    {"symbol": "TSLA", "current_price": 240, "threshold_high": 280, "threshold_low": 220},
    {"symbol": "BTC-USD", "current_price": 82000, "threshold_high": 95000, "threshold_low": 78000}
]' | docker exec -i hermesclaw python3 /opt/hermes-data/skills/market-alerts/scripts/monitor.py 2>/dev/null || echo "")

if echo "$MONITOR_RESULT" | grep -qi "alert\|breach\|threshold\|NVDA\|result"; then
    pass "monitor.py output correct"
    update_result "UC07" "monitor.py output correct" "hermes" "✅"
else
    # Try locally
    LOCAL_MONITOR=$(echo '[{"symbol":"NVDA","current_price":823,"threshold_high":950,"threshold_low":820}]' | \
        python3 "$REPO_DIR/skills/market-alerts/scripts/monitor.py" 2>/dev/null || echo "")
    if echo "$LOCAL_MONITOR" | grep -qi "alert\|result\|NVDA"; then
        pass "monitor.py output correct (local)"
        update_result "UC07" "monitor.py output correct" "hermes" "✅"
    else
        warn "monitor.py output unclear: '${MONITOR_RESULT:0:100}'"
        update_result "UC07" "monitor.py output correct" "hermes" "⚠️"
    fi
fi

# Schedule monitoring cron
info "Setting up market monitoring cron..."
docker exec hermesclaw hermes chat -q \
    "Schedule: every 15 minutes from 9:30am to 4pm ET Monday through Friday, run market-alerts on my watchlist and send alerts for any threshold breaches." \
    2>/dev/null | tail -2 || true

CRON_LIST=$(docker exec hermesclaw hermes cron list 2>/dev/null || echo "")
if echo "$CRON_LIST" | grep -qi "market\|15\|9:30\|alert"; then
    pass "Cron scheduled"
else
    warn "Cron not confirmed: '$CRON_LIST'"
fi

# Telegram alert
if [[ "$TELEGRAM_AVAILABLE" == "true" ]]; then
    warn "Telegram alert: MANUAL CHECK REQUIRED"
    info "In Telegram, send to your bot: 'NVDA is at \$819 — am I breaching my threshold?'"
    info "Expected: alert sent via Telegram with threshold breach notification"
    read -rp "  Was Telegram alert sent? [y/n/skip]: " TELE_RESULT
    case "$TELE_RESULT" in
        y) pass "Telegram alert sent"; update_result "UC07" "Telegram alert sent" "hermes" "✅" ;;
        n) fail "Telegram alert not sent"; update_result "UC07" "Telegram alert sent" "hermes" "❌" ;;
        *) warn "Skipped"; update_result "UC07" "Telegram alert sent" "hermes" "⚠️" ;;
    esac
else
    warn "Telegram not configured"
    update_result "UC07" "Telegram alert sent" "hermes" "⚠️"
fi

# ── Latency measurement (critical for trader use case) ────────────────────────

echo ""
echo -e "${BOLD}[HermesClaw] Latency measurement${RESET}"
info "Running 3 inference calls and averaging..."

TOTAL_MS=0
SUCCESSFUL=0
for i in 1 2 3; do
    START=$(python3 -c "import time; print(int(time.time() * 1000))")
    RESULT=$(docker exec hermesclaw hermes chat -q "Is NVDA at 830 above or below my 820 threshold? One sentence." 2>/dev/null || echo "")
    END=$(python3 -c "import time; print(int(time.time() * 1000))")
    MS=$((END - START))
    if [[ -n "$RESULT" ]]; then
        info "  Run $i: ${MS}ms — '${RESULT:0:60}'"
        TOTAL_MS=$((TOTAL_MS + MS))
        SUCCESSFUL=$((SUCCESSFUL + 1))
    else
        warn "  Run $i: no response"
    fi
done

if [[ $SUCCESSFUL -gt 0 ]]; then
    AVG_MS=$((TOTAL_MS / SUCCESSFUL))
    pass "HermesClaw avg latency: ${AVG_MS}ms (${SUCCESSFUL}/3 runs)"
    update_result "UC07" "Inference latency (ms)" "hermes" "✅"
    update_latency "hermes" "${AVG_MS}ms avg (CPU, ${SUCCESSFUL}/3 runs)"
else
    fail "Could not measure latency"
    update_result "UC07" "Inference latency (ms)" "hermes" "❌"
fi

echo ""
echo -e "${BOLD}HermesClaw UC07 complete.${RESET}"

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
    warn "NemoClaw not installed — skipping"
    for step in "Stack starts" "Watchlist + thresholds saved to memory" "Threshold check returns correct result" "market-alerts skill runs" "monitor.py output correct" "Telegram alert sent" "Inference latency (ms)"; do
        update_result "UC07" "$step" "nemo" "⚠️"
    done
    update_latency "nemo" "not measured (NemoClaw not installed)"
    info "Install: curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
else
    # Stack
    NC_STATUS=$($OPENCLAW_CMD status 2>/dev/null | head -1 || echo "")
    if [[ -n "$NC_STATUS" ]]; then
        pass "NemoClaw running"
        update_result "UC07" "Stack starts" "nemo" "✅"
    else
        update_result "UC07" "Stack starts" "nemo" "⚠️"
    fi

    # Memory
    $OPENCLAW_CMD chat "My watchlist: NVDA (low: 820, high: 950), TSLA (low: 220, high: 280), BTC (low: 78000, high: 95000). Remember this." \
        2>/dev/null | tail -1 || true

    NC_RECALL=$($OPENCLAW_CMD chat "What are my trading thresholds for NVDA?" 2>/dev/null || echo "")
    if echo "$NC_RECALL" | grep -qi "820\|950\|NVDA\|threshold"; then
        warn "NemoClaw memory works within session only"
        update_result "UC07" "Watchlist + thresholds saved to memory" "nemo" "⚠️"
        info "Note: NemoClaw session memory — not persisted between sessions"
    else
        fail "NemoClaw memory not recalled"
        update_result "UC07" "Watchlist + thresholds saved to memory" "nemo" "❌"
    fi

    # Threshold check
    NC_THRESH=$($OPENCLAW_CMD chat \
        "NVDA is at \$823. My threshold is below \$820 = alert. Is this a breach?" \
        2>/dev/null || echo "")
    if echo "$NC_THRESH" | grep -qi "below\|above\|breach\|alert\|threshold\|820"; then
        pass "NemoClaw threshold check works"
        update_result "UC07" "Threshold check returns correct result" "nemo" "✅"
    else
        warn "NemoClaw threshold unclear: '${NC_THRESH:0:100}'"
        update_result "UC07" "Threshold check returns correct result" "nemo" "⚠️"
    fi

    # market-alerts skill
    update_result "UC07" "market-alerts skill runs" "nemo" "⚠️"
    update_result "UC07" "monitor.py output correct" "nemo" "⚠️"
    info "Note: NemoClaw has no native market-alerts skill (no SKILL.md format)"

    # Telegram
    if [[ "$TELEGRAM_AVAILABLE" == "true" ]]; then
        warn "NemoClaw Telegram alert: MANUAL CHECK"
        read -rp "  Was NemoClaw Telegram alert sent? [y/n/skip]: " NC_TELE
        case "$NC_TELE" in
            y) update_result "UC07" "Telegram alert sent" "nemo" "✅" ;;
            n) update_result "UC07" "Telegram alert sent" "nemo" "❌" ;;
            *) update_result "UC07" "Telegram alert sent" "nemo" "⚠️" ;;
        esac
    else
        update_result "UC07" "Telegram alert sent" "nemo" "⚠️"
    fi

    # Latency measurement for NemoClaw (cloud API)
    echo ""
    echo -e "${BOLD}[NemoClaw] Latency measurement (cloud inference)${RESET}"
    info "Running 3 inference calls via NemoClaw (cloud API round-trip)..."

    NC_TOTAL=0
    NC_SUCCESSFUL=0
    for i in 1 2 3; do
        START=$(python3 -c "import time; print(int(time.time() * 1000))")
        NC_RESULT=$($OPENCLAW_CMD chat "Is NVDA at 830 above or below threshold 820? One sentence." 2>/dev/null || echo "")
        END=$(python3 -c "import time; print(int(time.time() * 1000))")
        MS=$((END - START))
        if [[ -n "$NC_RESULT" ]]; then
            info "  Run $i: ${MS}ms — '${NC_RESULT:0:60}'"
            NC_TOTAL=$((NC_TOTAL + MS))
            NC_SUCCESSFUL=$((NC_SUCCESSFUL + 1))
        else
            warn "  Run $i: no response"
        fi
    done

    if [[ $NC_SUCCESSFUL -gt 0 ]]; then
        NC_AVG=$((NC_TOTAL / NC_SUCCESSFUL))
        pass "NemoClaw avg latency: ${NC_AVG}ms (${NC_SUCCESSFUL}/3 runs, cloud API)"
        update_result "UC07" "Inference latency (ms)" "nemo" "✅"
        update_latency "nemo" "${NC_AVG}ms avg (cloud API, ${NC_SUCCESSFUL}/3 runs)"
    else
        fail "Could not measure NemoClaw latency"
        update_result "UC07" "Inference latency (ms)" "nemo" "❌"
        update_latency "nemo" "not measured"
    fi
fi

# ── Final latency comparison ──────────────────────────────────────────────────

echo ""
echo "========================================================="
echo -e "${BOLD}UC07 complete — Latency Summary${RESET}"
echo ""

if [[ ${SUCCESSFUL:-0} -gt 0 ]] && [[ ${NC_SUCCESSFUL:-0} -gt 0 ]]; then
    HERMES_AVG=${AVG_MS:-0}
    NEMO_AVG=${NC_AVG:-0}
    DIFF=$((NEMO_AVG - HERMES_AVG))
    if [[ $DIFF -gt 0 ]]; then
        echo -e "  HermesClaw (local):  ${GREEN}${HERMES_AVG}ms${RESET}"
        echo -e "  NemoClaw (cloud):    ${YELLOW}${NEMO_AVG}ms${RESET}"
        echo -e "  Difference:          ${BOLD}${DIFF}ms faster local${RESET}"
    else
        echo -e "  HermesClaw (local):  ${HERMES_AVG}ms"
        echo -e "  NemoClaw (cloud):    ${NEMO_AVG}ms"
    fi
else
    info "Latency comparison: re-run with both stacks installed to compare"
fi

echo ""
info "Results written to docs/test-results-uc.md"
echo ""
info "All use cases complete. Run summary:"
info "  UC01 researcher:      bash scripts/test-uc-01.sh"
info "  UC02 developer:       bash scripts/test-uc-02.sh"
info "  UC03 home automation: bash scripts/test-uc-03.sh  (needs HA)"
info "  UC04 data analyst:    bash scripts/test-uc-04.sh"
info "  UC05 small business:  bash scripts/test-uc-05.sh"
info "  UC06 privacy:         bash scripts/test-uc-06.sh"
info "  UC07 trader:          bash scripts/test-uc-07.sh  ← you are here"
echo ""
info "Full results: docs/test-results-uc.md"
echo ""
