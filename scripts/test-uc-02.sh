#!/usr/bin/env bash
# UC02 — Developer (code review + VS Code ACP)
#
# Tests HermesClaw then NemoClaw for the developer use case.
# Run after: ./scripts/test-setup.sh
#
# Usage:
#   bash scripts/test-uc-02.sh

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

# Sample code with intentional issues for review
SAMPLE_CODE='def divide(a, b):
    return a / b

def get_user(user_id):
    query = f"SELECT * FROM users WHERE id = {user_id}"
    return db.execute(query)

def process_items(items=[]):
    results = []
    for item in items:
        results.append(item * 2)
    return results'

echo ""
echo -e "${BOLD}UC02 — Developer (code review + VS Code ACP)${RESET}"
echo "=============================================="
echo ""

# ── HermesClaw ────────────────────────────────────────────────────────────────

echo -e "${BOLD}[HermesClaw]${RESET}"
echo ""

if ! docker compose -f "$REPO_DIR/docker-compose.yml" ps 2>/dev/null | grep -q "healthy\|running\|Up"; then
    fail "Stack not running — run: docker compose up -d"
    exit 1
fi
pass "Stack running"
update_result "UC02" "Code review via chat" "hermes" "🔲"

# Code review
info "Testing code review..."
REVIEW=$(docker exec hermesclaw hermes chat -q \
    "Review this Python code for bugs and security issues:

$SAMPLE_CODE

List specific issues found." 2>/dev/null || echo "")

if echo "$REVIEW" | grep -qi "division\|zero\|divide\|ZeroDivision"; then
    pass "Edge case flagged: division by zero"
    update_result "UC02" "Edge case flagged" "hermes" "✅"
else
    warn "Division-by-zero not flagged: '${REVIEW:0:100}'"
    update_result "UC02" "Edge case flagged" "hermes" "⚠️"
fi

if echo "$REVIEW" | grep -qi "injection\|sql\|f-string\|f\""; then
    pass "Security issue detected: SQL injection"
    update_result "UC02" "Security issue detected" "hermes" "✅"
else
    warn "SQL injection not flagged: '${REVIEW:0:100}'"
    update_result "UC02" "Security issue detected" "hermes" "⚠️"
fi

if [[ -n "$REVIEW" ]]; then
    pass "Code review via chat works"
    update_result "UC02" "Code review via chat" "hermes" "✅"
else
    fail "No code review response"
    update_result "UC02" "Code review via chat" "hermes" "❌"
fi

# ACP server
info "Testing ACP server startup..."
# Start ACP server in background inside container
docker exec -d hermesclaw hermes acp 2>/dev/null || true
sleep 2

# Check if ACP is listening
ACP_LISTENING=$(docker exec hermesclaw sh -c "ss -tlnp 2>/dev/null | grep ':' | grep acp || netstat -tlnp 2>/dev/null | grep acp || echo ''" 2>/dev/null | head -2 || echo "")
# Try a simpler check — does the process exist?
ACP_PID=$(docker exec hermesclaw pgrep -f "hermes acp" 2>/dev/null || echo "")
if [[ -n "$ACP_PID" ]]; then
    pass "ACP server process running (PID $ACP_PID)"
    update_result "UC02" "ACP server starts" "hermes" "✅"
else
    warn "ACP server process not confirmed — may need manual start"
    info "  docker exec -it hermesclaw hermes acp"
    update_result "UC02" "ACP server starts" "hermes" "⚠️"
fi

# VS Code — manual check
echo ""
warn "VS Code ACP connection: MANUAL CHECK REQUIRED"
info "1. Open VS Code"
info "2. Install the Hermes ACP extension (if not installed)"
info "3. Connect to your HermesClaw container's ACP endpoint"
info "4. Expected: extension shows 'Connected' status"
echo ""
read -rp "  Did VS Code ACP connect successfully? [y/n/skip]: " VSCODE_RESULT
case "$VSCODE_RESULT" in
    y) pass "VS Code connects"; update_result "UC02" "VS Code connects" "hermes" "✅" ;;
    n) fail "VS Code not connecting"; update_result "UC02" "VS Code connects" "hermes" "❌" ;;
    *) warn "VS Code test skipped"; update_result "UC02" "VS Code connects" "hermes" "⚠️" ;;
esac

# code-review skill
info "Installing code-review skill..."
bash "$REPO_DIR/skills/install.sh" code-review 2>/dev/null || true

SKILL_RESPONSE=$(docker exec hermesclaw hermes chat -q \
    "Run the code-review skill on this code: def foo(x): return x/0" \
    2>/dev/null || echo "")
if echo "$SKILL_RESPONSE" | grep -qi "zero\|division\|error\|review\|issue"; then
    pass "code-review skill runs"
    update_result "UC02" "code-review skill runs" "hermes" "✅"
else
    warn "Skill response unclear: '${SKILL_RESPONSE:0:100}'"
    update_result "UC02" "code-review skill runs" "hermes" "⚠️"
fi

echo ""
echo -e "${BOLD}HermesClaw UC02 complete.${RESET}"

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
    for step in "Code review via chat" "Security issue detected" "Edge case flagged" "ACP server starts" "VS Code connects" "code-review skill runs"; do
        update_result "UC02" "$step" "nemo" "⚠️"
    done
    info "Install: curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
else
    # Code review
    info "Testing NemoClaw code review..."
    NC_REVIEW=$($OPENCLAW_CMD chat \
        "Review this Python code for bugs and security issues:

$SAMPLE_CODE

List specific issues found." 2>/dev/null || echo "")

    if [[ -n "$NC_REVIEW" ]]; then
        pass "Code review via chat works"
        update_result "UC02" "Code review via chat" "nemo" "✅"
    else
        fail "No response"
        update_result "UC02" "Code review via chat" "nemo" "❌"
    fi

    if echo "$NC_REVIEW" | grep -qi "injection\|sql\|f-string\|f\""; then
        pass "Security issue detected: SQL injection"
        update_result "UC02" "Security issue detected" "nemo" "✅"
    else
        warn "SQL injection not flagged"
        update_result "UC02" "Security issue detected" "nemo" "⚠️"
    fi

    if echo "$NC_REVIEW" | grep -qi "division\|zero\|divide\|ZeroDivision"; then
        pass "Edge case flagged: division by zero"
        update_result "UC02" "Edge case flagged" "nemo" "✅"
    else
        warn "Division-by-zero not flagged"
        update_result "UC02" "Edge case flagged" "nemo" "⚠️"
    fi

    # ACP — NemoClaw doesn't use HermesClaw's ACP protocol
    warn "NemoClaw uses its own IDE integration (not Hermes ACP)"
    info "OpenClaw has its own VS Code extension — test separately if needed"
    update_result "UC02" "ACP server starts" "nemo" "⚠️"
    update_result "UC02" "VS Code connects" "nemo" "⚠️"

    # code-review skill equivalent
    NC_SKILL=$($OPENCLAW_CMD chat \
        "Review this for bugs: def foo(x): return x/0" \
        2>/dev/null || echo "")
    if echo "$NC_SKILL" | grep -qi "zero\|division\|error\|bug\|issue"; then
        pass "Code review via NemoClaw works"
        update_result "UC02" "code-review skill runs" "nemo" "⚠️"
        info "Note: NemoClaw has no native code-review skill; direct chat used"
    else
        warn "Response unclear: '${NC_SKILL:0:80}'"
        update_result "UC02" "code-review skill runs" "nemo" "⚠️"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=============================================="
echo -e "${BOLD}UC02 complete. Results written to docs/test-results-uc.md${RESET}"
echo ""
info "Key findings:"
info "  HermesClaw: ACP protocol + VS Code integration"
info "  NemoClaw: uses own IDE integration (not ACP compatible)"
info ""
info "Next: bash scripts/test-uc-03.sh   # home automation (requires HA instance)"
info "  or: bash scripts/test-uc-04.sh   # data analyst (Docker Postgres used)"
echo ""
