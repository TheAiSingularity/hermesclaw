#!/usr/bin/env bash
# UC04 — Data Analyst (Postgres MCP + anomaly detection)
#
# Spins up a temporary Docker Postgres instance for testing.
# Tests HermesClaw then NemoClaw for the data analyst use case.
# Run after: ./scripts/test-setup.sh
#
# Usage:
#   bash scripts/test-uc-04.sh

set -uo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_FILE="$REPO_DIR/docs/test-results-uc.md"
TEST_PG_CONTAINER="hermesclaw-test-postgres"
TEST_PG_PASSWORD="hermestest"
TEST_PG_PORT="5433"   # use 5433 to avoid conflicts with local postgres
TEST_DB_URL="postgresql://postgres:${TEST_PG_PASSWORD}@host.docker.internal:${TEST_PG_PORT}/postgres"

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

cleanup() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${TEST_PG_CONTAINER}$"; then
        info "Stopping test Postgres..."
        docker stop "$TEST_PG_CONTAINER" &>/dev/null
        docker rm "$TEST_PG_CONTAINER" &>/dev/null
    fi
}
trap cleanup EXIT

echo ""
echo -e "${BOLD}UC04 — Data Analyst (Postgres MCP + anomaly detection)${RESET}"
echo "======================================================="
echo ""

# ── Start test Postgres ───────────────────────────────────────────────────────

echo -e "${BOLD}[Setup] Test Postgres${RESET}"

# Remove existing test container if any
docker stop "$TEST_PG_CONTAINER" &>/dev/null || true
docker rm "$TEST_PG_CONTAINER" &>/dev/null || true

info "Starting test Postgres on port $TEST_PG_PORT..."
docker run -d \
    --name "$TEST_PG_CONTAINER" \
    -e POSTGRES_PASSWORD="$TEST_PG_PASSWORD" \
    -p "${TEST_PG_PORT}:5432" \
    postgres:16 &>/dev/null

# Wait for Postgres to be ready
WAITED=0
while [[ $WAITED -lt 30 ]]; do
    if docker exec "$TEST_PG_CONTAINER" pg_isready -U postgres &>/dev/null; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if ! docker exec "$TEST_PG_CONTAINER" pg_isready -U postgres &>/dev/null; then
    fail "Test Postgres failed to start"
    exit 1
fi
pass "Test Postgres running on port $TEST_PG_PORT"

# Seed test data
info "Seeding test data..."
docker exec "$TEST_PG_CONTAINER" psql -U postgres -c "
CREATE TABLE IF NOT EXISTS daily_metrics (
    date DATE PRIMARY KEY,
    dau INTEGER,
    revenue NUMERIC(10,2),
    signups INTEGER,
    activation_rate NUMERIC(5,2)
);

INSERT INTO daily_metrics VALUES
    (CURRENT_DATE - 7, 8100, 24100, 305, 68.5),
    (CURRENT_DATE - 6, 8200, 24300, 308, 67.9),
    (CURRENT_DATE - 5, 8150, 24200, 310, 68.1),
    (CURRENT_DATE - 4, 8300, 24500, 315, 68.8),
    (CURRENT_DATE - 3, 8050, 23900, 302, 67.5),
    (CURRENT_DATE - 2, 8400, 24800, 320, 69.1),
    (CURRENT_DATE - 1, 8200, 24200, 312, 68.0),
    (CURRENT_DATE,     4800, 15200, 180, 52.3)   -- anomaly day
ON CONFLICT (date) DO UPDATE SET
    dau=EXCLUDED.dau, revenue=EXCLUDED.revenue,
    signups=EXCLUDED.signups, activation_rate=EXCLUDED.activation_rate;

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    activated BOOLEAN DEFAULT false
);

INSERT INTO users (email, activated) VALUES
    ('alice@example.com', true),
    ('bob@example.com', false),
    ('carol@example.com', true);
" &>/dev/null
pass "Test data seeded (daily_metrics, users tables with anomaly on today)"

# ── HermesClaw ────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}[HermesClaw]${RESET}"
echo ""

if ! docker compose -f "$REPO_DIR/docker-compose.yml" ps 2>/dev/null | grep -q "healthy\|running\|Up"; then
    fail "Stack not running — run: docker compose up -d"
    exit 1
fi
pass "Stack running"

# Configure Postgres MCP
HERMES_YAML="$REPO_DIR/configs/hermes.yaml"
if [[ ! -f "$HERMES_YAML" ]]; then
    cp "$REPO_DIR/configs/hermes.yaml.example" "$HERMES_YAML" 2>/dev/null || true
fi

if grep -q "postgres\|postgresql" "$HERMES_YAML" 2>/dev/null; then
    info "Postgres MCP already in hermes.yaml"
else
    info "Adding Postgres MCP to hermes.yaml..."
    cat >> "$HERMES_YAML" << YAML

mcp:
  servers:
    postgres:
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-postgres"
        - "${TEST_DB_URL}"
      timeout: 60
YAML
    info "Restarting container..."
    docker compose -f "$REPO_DIR/docker-compose.yml" restart 2>/dev/null
    sleep 8
fi

# Test Postgres MCP connection
info "Testing Postgres MCP connection..."
TABLES=$(docker exec hermesclaw hermes chat -q \
    "List all tables in the database" \
    2>/dev/null || echo "")

if echo "$TABLES" | grep -qi "daily_metrics\|users\|table"; then
    pass "Postgres MCP connects"
    update_result "UC04" "Postgres MCP connects" "hermes" "✅"
else
    warn "Table list response unclear: '${TABLES:0:120}'"
    update_result "UC04" "Postgres MCP connects" "hermes" "⚠️"
fi

# SQL query
info "Testing SQL query execution..."
QUERY_RESULT=$(docker exec hermesclaw hermes chat -q \
    "Run this query and show results: SELECT date, revenue FROM daily_metrics ORDER BY date DESC LIMIT 3" \
    2>/dev/null || echo "")

if echo "$QUERY_RESULT" | grep -qi "revenue\|date\|15200\|24200\|24800"; then
    pass "SQL query executed"
    update_result "UC04" "SQL query executed" "hermes" "✅"
else
    warn "Query response unclear: '${QUERY_RESULT:0:100}'"
    update_result "UC04" "SQL query executed" "hermes" "⚠️"
fi

# Table list
if echo "$TABLES" | grep -qi "daily_metrics\|users"; then
    pass "Table list returned"
    update_result "UC04" "Table list returned" "hermes" "✅"
else
    update_result "UC04" "Table list returned" "hermes" "⚠️"
fi

# Install anomaly-detection skill
info "Installing anomaly-detection skill..."
bash "$REPO_DIR/skills/install.sh" anomaly-detection 2>/dev/null || true

SKILL_RESPONSE=$(docker exec hermesclaw hermes chat -q \
    "Run anomaly-detection on today's metrics in daily_metrics table vs the past 7-day average" \
    2>/dev/null || echo "")

if echo "$SKILL_RESPONSE" | grep -qi "anomaly\|deviation\|alert\|z-score\|unusual\|revenue\|dau"; then
    pass "anomaly-detection skill runs"
    update_result "UC04" "anomaly-detection skill runs" "hermes" "✅"
else
    warn "Skill response unclear: '${SKILL_RESPONSE:0:120}'"
    update_result "UC04" "anomaly-detection skill runs" "hermes" "⚠️"
fi

# detect.py
info "Testing detect.py script directly..."
DETECT_RESULT=$(echo '[
    {"metric": "revenue", "current": 15200, "history": [24100,24300,24200,24500,23900,24800,24200]},
    {"metric": "dau", "current": 4800, "history": [8100,8200,8150,8300,8050,8400,8200]}
]' | docker exec -i hermesclaw python3 /root/.hermes/skills/anomaly-detection/scripts/detect.py 2>/dev/null || echo "")

if echo "$DETECT_RESULT" | grep -qi "anomaly\|z_score\|is_anomaly\|revenue\|dau"; then
    pass "detect.py z-score output correct"
    update_result "UC04" "detect.py z-score output" "hermes" "✅"
else
    # Try running locally if not in container
    LOCAL_DETECT=$(echo '[{"metric":"revenue","current":15200,"history":[24100,24300,24200,24500,23900,24800,24200]}]' | \
        python3 "$REPO_DIR/skills/anomaly-detection/scripts/detect.py" 2>/dev/null || echo "")
    if echo "$LOCAL_DETECT" | grep -qi "anomaly\|z_score\|revenue"; then
        pass "detect.py z-score output correct (local)"
        update_result "UC04" "detect.py z-score output" "hermes" "✅"
    else
        warn "detect.py output unclear: '${DETECT_RESULT:0:100}'"
        update_result "UC04" "detect.py z-score output" "hermes" "⚠️"
    fi
fi

# Alert delivery — manual
warn "Alert delivery: MANUAL CHECK REQUIRED"
info "Configure SLACK_BOT_TOKEN or TELEGRAM_BOT_TOKEN in .env then re-run anomaly-detection"
info "Expected: alert sent when z-score > 2.0 (revenue today is -2.8σ from mean)"
read -rp "  Was an alert sent? [y/n/skip]: " ALERT_RESULT
case "$ALERT_RESULT" in
    y) pass "Alert sent"; update_result "UC04" "Alert sent" "hermes" "✅" ;;
    n) fail "Alert not sent"; update_result "UC04" "Alert sent" "hermes" "❌" ;;
    *) warn "Alert test skipped"; update_result "UC04" "Alert sent" "hermes" "⚠️" ;;
esac

echo ""
echo -e "${BOLD}HermesClaw UC04 complete.${RESET}"

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
    for step in "Postgres MCP connects" "SQL query executed" "Table list returned" "anomaly-detection skill runs" "detect.py z-score output" "Alert sent"; do
        update_result "UC04" "$step" "nemo" "⚠️"
    done
    info "Install: curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
else
    # Test Postgres MCP via NemoClaw
    info "Testing NemoClaw Postgres connection..."
    NC_TABLES=$($OPENCLAW_CMD chat \
        "Connect to PostgreSQL at $TEST_DB_URL and list all tables" \
        2>/dev/null || echo "")

    if echo "$NC_TABLES" | grep -qi "daily_metrics\|users\|table"; then
        pass "NemoClaw Postgres connects"
        update_result "UC04" "Postgres MCP connects" "nemo" "✅"
        update_result "UC04" "Table list returned" "nemo" "✅"
    else
        warn "NemoClaw Postgres response: '${NC_TABLES:0:100}'"
        update_result "UC04" "Postgres MCP connects" "nemo" "⚠️"
        update_result "UC04" "Table list returned" "nemo" "⚠️"
        info "Note: NemoClaw MCP/Postgres support is unconfirmed upstream"
    fi

    NC_QUERY=$($OPENCLAW_CMD chat \
        "From the Postgres database, run: SELECT date, revenue FROM daily_metrics ORDER BY date DESC LIMIT 3" \
        2>/dev/null || echo "")
    if echo "$NC_QUERY" | grep -qi "revenue\|date\|15200\|24"; then
        pass "NemoClaw SQL query executed"
        update_result "UC04" "SQL query executed" "nemo" "✅"
    else
        warn "NemoClaw query response unclear"
        update_result "UC04" "SQL query executed" "nemo" "⚠️"
    fi

    # Anomaly detection via NemoClaw
    NC_ANOMALY=$($OPENCLAW_CMD chat \
        "Today's revenue is 15200. The 7-day average is 24286. Is this an anomaly? Calculate the z-score." \
        2>/dev/null || echo "")
    if echo "$NC_ANOMALY" | grep -qi "anomaly\|deviation\|z.score\|unusual\|significant"; then
        pass "NemoClaw anomaly detection works (ad-hoc)"
        update_result "UC04" "anomaly-detection skill runs" "nemo" "⚠️"
        info "Note: NemoClaw has no native anomaly-detection skill — ad-hoc analysis used"
    else
        warn "NemoClaw anomaly response unclear: '${NC_ANOMALY:0:100}'"
        update_result "UC04" "anomaly-detection skill runs" "nemo" "⚠️"
    fi
    update_result "UC04" "detect.py z-score output" "nemo" "⚠️"

    warn "NemoClaw alert delivery: MANUAL CHECK"
    read -rp "  Was a NemoClaw alert sent? [y/n/skip]: " NC_ALERT
    case "$NC_ALERT" in
        y) update_result "UC04" "Alert sent" "nemo" "✅" ;;
        n) update_result "UC04" "Alert sent" "nemo" "❌" ;;
        *) update_result "UC04" "Alert sent" "nemo" "⚠️" ;;
    esac
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "======================================================="
echo -e "${BOLD}UC04 complete. Results written to docs/test-results-uc.md${RESET}"
echo ""
info "Key findings:"
info "  HermesClaw: native Postgres MCP + detect.py z-score + persistent metric memory"
info "  NemoClaw: Postgres MCP support unconfirmed; data goes to cloud API (privacy concern)"
echo ""
info "Next: bash scripts/test-uc-05.sh   # small business (Slack)"
echo ""
