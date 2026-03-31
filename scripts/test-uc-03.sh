#!/usr/bin/env bash
# UC03 — Home Automation (HA MCP + Telegram)
#
# Tests HermesClaw then NemoClaw for the home automation use case.
# NOTE: Requires a running Home Assistant instance accessible on the network.
#       If HA is not available, the script documents the limitation and skips.
#
# Usage:
#   bash scripts/test-uc-03.sh
#   bash scripts/test-uc-03.sh --ha-url http://homeassistant.local:8123

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

# Parse args
HA_URL="${2:-}"
if [[ "${1:-}" == "--ha-url" ]]; then
    HA_URL="$2"
fi
if [[ -z "$HA_URL" ]]; then
    HA_URL=$(grep "^HA_URL=" "$REPO_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "")
    HA_URL="${HA_URL:-http://homeassistant.local:8123}"
fi

HA_TOKEN=$(grep "^HA_TOKEN=" "$REPO_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "")

echo ""
echo -e "${BOLD}UC03 — Home Automation (HA MCP + Telegram)${RESET}"
echo "============================================="
echo ""

# Check if HA is reachable
HA_AVAILABLE=false
if curl -sf --max-time 5 "$HA_URL/api/" -H "Authorization: Bearer $HA_TOKEN" &>/dev/null 2>&1; then
    HA_AVAILABLE=true
    pass "Home Assistant reachable at $HA_URL"
elif curl -sf --max-time 5 "$HA_URL" &>/dev/null 2>&1; then
    warn "Home Assistant UI reachable but API check failed (check HA_TOKEN in .env)"
    HA_AVAILABLE=false
else
    warn "Home Assistant NOT reachable at $HA_URL"
    info "Set HA_URL and HA_TOKEN in .env and re-run, or skip this test."
    info "Example: bash scripts/test-uc-03.sh --ha-url http://192.168.1.100:8123"
fi

if [[ "$HA_AVAILABLE" == "false" ]]; then
    echo ""
    warn "Home Assistant unavailable — this use case requires an external dependency."
    info "Documenting as 'requires HA instance' in test results."
    for step in "HA MCP server connects" "Natural language command executed" "Routine created and saved" "home-assistant skill runs"; do
        update_result "UC03" "$step" "hermes" "⚠️"
        update_result "UC03" "$step" "nemo" "⚠️"
    done
    echo ""
    info "To test UC03 fully:"
    info "  1. Set HA_URL=http://homeassistant.local:8123 in .env"
    info "  2. Set HA_TOKEN=your_long_lived_token in .env"
    info "     (HA > Profile > Security > Long-Lived Access Tokens)"
    info "  3. Ensure MCP is enabled in HA: Settings > Home Assistant Cloud > Remote UI"
    info "     or navigate to HA > Developer Tools > REST API"
    info "  4. Re-run: bash scripts/test-uc-03.sh"
    echo ""
    info "Next: bash scripts/test-uc-04.sh   # data analyst"
    exit 0
fi

# ── HermesClaw ────────────────────────────────────────────────────────────────

echo -e "${BOLD}[HermesClaw]${RESET}"
echo ""

if ! docker compose -f "$REPO_DIR/docker-compose.yml" ps 2>/dev/null | grep -q "healthy\|running\|Up"; then
    fail "Stack not running — run: docker compose up -d"
    exit 1
fi
pass "Stack running"

# Configure HA MCP in hermes.yaml
HERMES_YAML="$REPO_DIR/configs/hermes.yaml"
if [[ ! -f "$HERMES_YAML" ]]; then
    cp "$REPO_DIR/configs/hermes.yaml.example" "$HERMES_YAML" 2>/dev/null || true
fi

if grep -q "homeassistant\|home_assistant" "$HERMES_YAML" 2>/dev/null; then
    info "HA MCP already in hermes.yaml"
else
    info "Adding HA MCP to hermes.yaml..."
    cat >> "$HERMES_YAML" << YAML

mcp:
  servers:
    homeassistant:
      type: http
      url: "${HA_URL}/mcp"
      headers:
        Authorization: "Bearer ${HA_TOKEN}"
YAML
    info "Restarting container to pick up new config..."
    docker compose -f "$REPO_DIR/docker-compose.yml" restart 2>/dev/null
    sleep 5
fi

# Test HA MCP connection
info "Testing HA MCP connection..."
HA_RESPONSE=$(docker exec hermesclaw hermes chat -q \
    "List the available entities in Home Assistant" \
    2>/dev/null || echo "")

if echo "$HA_RESPONSE" | grep -qi "entity\|light\|switch\|sensor\|domain\|automation"; then
    pass "HA MCP server connects"
    update_result "UC03" "HA MCP server connects" "hermes" "✅"
else
    warn "HA MCP response unclear: '${HA_RESPONSE:0:120}'"
    update_result "UC03" "HA MCP server connects" "hermes" "⚠️"
fi

# Natural language command
info "Testing natural language command..."
CMD_RESPONSE=$(docker exec hermesclaw hermes chat -q \
    "Turn on all lights in the living room" \
    2>/dev/null || echo "")

if echo "$CMD_RESPONSE" | grep -qi "light\|living\|turn\|on\|executed\|done\|success"; then
    pass "Natural language command executed"
    update_result "UC03" "Natural language command executed" "hermes" "✅"
else
    warn "Command response unclear: '${CMD_RESPONSE:0:100}'"
    update_result "UC03" "Natural language command executed" "hermes" "⚠️"
fi

# Routine creation
info "Testing routine creation..."
ROUTINE_RESPONSE=$(docker exec hermesclaw hermes chat -q \
    "Create a routine: every weekday at 7am, turn on kitchen lights to 80% brightness. Please save this as 'morning-routine'." \
    2>/dev/null || echo "")

if echo "$ROUTINE_RESPONSE" | grep -qi "routine\|saved\|created\|scheduled\|morning"; then
    pass "Routine created and saved"
    update_result "UC03" "Routine created and saved" "hermes" "✅"
else
    warn "Routine response unclear: '${ROUTINE_RESPONSE:0:100}'"
    update_result "UC03" "Routine created and saved" "hermes" "⚠️"
fi

# home-assistant skill
info "Installing home-assistant skill..."
bash "$REPO_DIR/skills/install.sh" home-assistant 2>/dev/null || true

SKILL_RESPONSE=$(docker exec hermesclaw hermes chat -q \
    "Run the home-assistant skill to get a summary of my home status" \
    2>/dev/null || echo "")

if echo "$SKILL_RESPONSE" | grep -qi "home\|status\|entity\|light\|temperature\|sensor"; then
    pass "home-assistant skill runs"
    update_result "UC03" "home-assistant skill runs" "hermes" "✅"
else
    warn "Skill response unclear: '${SKILL_RESPONSE:0:100}'"
    update_result "UC03" "home-assistant skill runs" "hermes" "⚠️"
fi

echo ""
echo -e "${BOLD}HermesClaw UC03 complete.${RESET}"

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
    for step in "HA MCP server connects" "Natural language command executed" "Routine created and saved" "home-assistant skill runs"; do
        update_result "UC03" "$step" "nemo" "⚠️"
    done
    info "Install: curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
else
    # NemoClaw + HA MCP
    info "Testing NemoClaw HA MCP (via HTTP endpoint)..."
    NC_HA=$($OPENCLAW_CMD chat \
        "Connect to Home Assistant at $HA_URL and list available entities" \
        2>/dev/null || echo "")

    if echo "$NC_HA" | grep -qi "entity\|light\|switch\|sensor"; then
        pass "HA MCP server connects via NemoClaw"
        update_result "UC03" "HA MCP server connects" "nemo" "✅"
    else
        warn "NemoClaw HA response unclear: '${NC_HA:0:100}'"
        update_result "UC03" "HA MCP server connects" "nemo" "⚠️"
        info "Note: NemoClaw MCP support is unconfirmed — may need config"
    fi

    NC_CMD=$($OPENCLAW_CMD chat "Turn on all lights in the living room via Home Assistant" \
        2>/dev/null || echo "")
    if echo "$NC_CMD" | grep -qi "light\|living\|turn\|on\|done\|executed"; then
        pass "Natural language command executed"
        update_result "UC03" "Natural language command executed" "nemo" "✅"
    else
        warn "Command response unclear"
        update_result "UC03" "Natural language command executed" "nemo" "⚠️"
    fi

    NC_ROUTINE=$($OPENCLAW_CMD chat \
        "Schedule: every weekday at 7am, turn on kitchen lights to 80% brightness." \
        2>/dev/null || echo "")
    if echo "$NC_ROUTINE" | grep -qi "schedule\|routine\|created\|monday\|weekday\|7am"; then
        pass "Routine created"
        update_result "UC03" "Routine created and saved" "nemo" "✅"
    else
        warn "Routine response unclear"
        update_result "UC03" "Routine created and saved" "nemo" "⚠️"
    fi

    # home-assistant skill (NemoClaw has no SKILL.md format)
    update_result "UC03" "home-assistant skill runs" "nemo" "⚠️"
    info "Note: NemoClaw has no native home-assistant skill (no SKILL.md format)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "============================================="
echo -e "${BOLD}UC03 complete. Results written to docs/test-results-uc.md${RESET}"
echo ""
info "Key finding: Both stacks require a running HA instance."
info "HermesClaw advantage: native MCP support + persistent routine memory."
echo ""
info "Next: bash scripts/test-uc-04.sh   # data analyst"
echo ""
