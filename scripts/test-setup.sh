#!/usr/bin/env bash
# HermesClaw + NemoClaw test environment setup.
#
# Verifies both stacks are ready to run sequential comparison tests.
# Run this once before executing the per-use-case test scripts.
#
# Usage:
#   ./scripts/test-setup.sh
#   ./scripts/test-setup.sh --model /path/to/model.gguf

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

echo ""
echo -e "${BOLD}HermesClaw × NemoClaw — Test Environment Setup${RESET}"
echo "=================================================="
echo ""

# ── Step 1: Docker ────────────────────────────────────────────────────────────

echo -e "${BOLD}[1/6] Docker${RESET}"
if ! command -v docker &>/dev/null; then
    fail "Docker not found. Install: https://docs.docker.com/get-docker/"
    exit 1
fi
if ! docker info &>/dev/null 2>&1; then
    fail "Docker daemon not running. Start Docker Desktop."
    exit 1
fi
pass "Docker running ($(docker --version | head -1))"

# ── Step 2: Model file ────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}[2/6] Model file${RESET}"
MODEL_PATH=""

# Check if --model flag provided
if [[ "${1:-}" == "--model" && -n "${2:-}" ]]; then
    MODEL_PATH="$2"
fi

# Check if models/ already has a gguf
EXISTING_MODEL=$(find "$REPO_DIR/models" -name "*.gguf" 2>/dev/null | head -1)
if [[ -n "$EXISTING_MODEL" ]]; then
    pass "Model already in models/: $(basename "$EXISTING_MODEL")"
elif [[ -n "$MODEL_PATH" && -f "$MODEL_PATH" ]]; then
    info "Copying model to models/..."
    cp "$MODEL_PATH" "$REPO_DIR/models/"
    pass "Model copied: $(basename "$MODEL_PATH")"
else
    warn "No model file found in models/"
    echo ""
    echo "  Please copy a GGUF model file into $REPO_DIR/models/"
    echo "  Then re-run: ./scripts/test-setup.sh"
    echo "  Or: ./scripts/test-setup.sh --model /path/to/model.gguf"
    echo ""
    echo "  Recommended models (download from HuggingFace):"
    echo "    Qwen3-4B-Q4_K_M.gguf   (~2.5 GB, fast)"
    echo "    Qwen3-7B-Q4_K_M.gguf   (~4 GB, better quality)"
    echo "    Qwen3-14B-Q4_K_M.gguf  (~8 GB, best quality)"
    exit 1
fi

# Set MODEL_FILE in .env if not already set
if [[ ! -f "$REPO_DIR/.env" ]]; then
    cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
    info "Created .env from .env.example"
fi

CURRENT_MODEL=$(find "$REPO_DIR/models" -name "*.gguf" 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "")
if [[ -n "$CURRENT_MODEL" ]]; then
    # Set MODEL_FILE in .env
    if grep -q "^MODEL_FILE=" "$REPO_DIR/.env"; then
        sed -i.bak "s|^MODEL_FILE=.*|MODEL_FILE=$CURRENT_MODEL|" "$REPO_DIR/.env" && rm -f "$REPO_DIR/.env.bak"
    else
        echo "MODEL_FILE=$CURRENT_MODEL" >> "$REPO_DIR/.env"
    fi
    pass "MODEL_FILE set to: $CURRENT_MODEL"
fi

# ── Step 3: Build + start HermesClaw ─────────────────────────────────────────

echo ""
echo -e "${BOLD}[3/6] HermesClaw stack${RESET}"
cd "$REPO_DIR"

info "Building HermesClaw image (this may take a few minutes on first run)..."
if docker compose build --quiet 2>/dev/null; then
    pass "Docker image built"
else
    fail "docker compose build failed — check Dockerfile"
    exit 1
fi

info "Starting HermesClaw stack..."
docker compose up -d 2>/dev/null

# Wait for health
MAX_WAIT=120
WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
    STATUS=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
for line in lines:
    if not line: continue
    try:
        d = json.loads(line)
        if d.get('Name','').startswith('hermesclaw') and 'hermes' in d.get('Name','').lower():
            print(d.get('Health', d.get('State', 'unknown')))
    except Exception:
        pass
" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" == "healthy" ]]; then
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done

if [[ "$STATUS" == "healthy" ]]; then
    pass "HermesClaw container: healthy"
else
    warn "HermesClaw container not yet healthy (status: $STATUS) — may need more time"
fi

# Quick smoke test
RESPONSE=$(docker exec hermesclaw hermes chat -q "reply with: HERMESCLAW_OK" 2>/dev/null | tail -1 || echo "")
if echo "$RESPONSE" | grep -qi "HERMESCLAW_OK\|ok\|hello"; then
    pass "HermesClaw chat: responding"
else
    warn "HermesClaw chat response unexpected: '$RESPONSE' — model may still be loading"
fi

# ── Step 4: NemoClaw check ────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}[4/6] NemoClaw${RESET}"
if command -v openclaw &>/dev/null; then
    pass "openclaw CLI found: $(openclaw --version 2>/dev/null | head -1 || echo 'version unknown')"
    NEMOCLAW_READY=true
elif command -v nemoclaw &>/dev/null; then
    pass "nemoclaw CLI found: $(nemoclaw --version 2>/dev/null | head -1 || echo 'version unknown')"
    NEMOCLAW_READY=true
else
    warn "NemoClaw not installed"
    info "Install with: curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
    info "After install, re-run this script to verify."
    NEMOCLAW_READY=false
fi

if [[ "$NEMOCLAW_READY" == "true" ]]; then
    OPENCLAW_CMD="openclaw"
    command -v nemoclaw &>/dev/null && OPENCLAW_CMD="nemoclaw"
    NC_RESPONSE=$($OPENCLAW_CMD chat "reply with: NEMOCLAW_OK" 2>/dev/null | tail -1 || echo "")
    if echo "$NC_RESPONSE" | grep -qi "NEMOCLAW_OK\|ok\|hello"; then
        pass "NemoClaw chat: responding"
    else
        warn "NemoClaw chat: no response — check configuration"
    fi
fi

# ── Step 5: Port conflict check ───────────────────────────────────────────────

echo ""
echo -e "${BOLD}[5/6] Port check${RESET}"
LLAMA_PORT=$(grep "^LLAMA_PORT=" "$REPO_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "8080")
LLAMA_PORT="${LLAMA_PORT:-8080}"

info "HermesClaw uses llama.cpp on port $LLAMA_PORT"
info "NemoClaw gateway uses port 8080 by default"
if [[ "$LLAMA_PORT" == "8080" ]]; then
    warn "Port conflict: both default to 8080. Run stacks sequentially (stop HermesClaw before NemoClaw tests)."
    info "Or set LLAMA_PORT=8081 in .env and restart: docker compose up -d"
else
    pass "No port conflict (HermesClaw on $LLAMA_PORT, NemoClaw on 8080)"
fi

# ── Step 6: Create results file ───────────────────────────────────────────────

echo ""
echo -e "${BOLD}[6/6] Results file${RESET}"
if [[ -f "$RESULTS_FILE" ]]; then
    warn "docs/test-results-uc.md already exists — appending new run"
fi

cat > "$RESULTS_FILE" << MARKDOWN
# Use Case Test Results

**Date**: $(date '+%Y-%m-%d %H:%M')
**Environment**: macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown'), Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
**HermesClaw model**: $CURRENT_MODEL
**NemoClaw inference**: OpenAI API (local inference broken on macOS, issue #260)

---

> Legend: ✅ Works as expected  ❌ Does not work  ⚠️ Partial/limited  🔲 Not tested

---

## UC01 — Researcher (memory + Telegram + weekly digest)

| Step | HermesClaw | NemoClaw | Notes |
|------|:----------:|:--------:|-------|
| Stack starts | 🔲 | 🔲 | |
| Basic chat | 🔲 | 🔲 | |
| Memory written to MEMORY.md | 🔲 | 🔲 | |
| Memory recalled in new session | 🔲 | 🔲 | |
| Telegram bot responds | 🔲 | 🔲 | |
| Cron created | 🔲 | 🔲 | |
| research-digest skill runs | 🔲 | 🔲 | |

**HermesClaw notes**: _fill after testing_
**NemoClaw notes**: _fill after testing_

---

## UC02 — Developer (code review + VS Code ACP)

| Step | HermesClaw | NemoClaw | Notes |
|------|:----------:|:--------:|-------|
| Code review via chat | 🔲 | 🔲 | |
| Security issue detected | 🔲 | 🔲 | |
| Edge case flagged | 🔲 | 🔲 | |
| ACP server starts | 🔲 | 🔲 | |
| VS Code connects | 🔲 | 🔲 | |
| code-review skill runs | 🔲 | 🔲 | |

**HermesClaw notes**: _fill after testing_
**NemoClaw notes**: _fill after testing_

---

## UC03 — Home Automation (HA MCP + Telegram)

| Step | HermesClaw | NemoClaw | Notes |
|------|:----------:|:--------:|-------|
| HA MCP server connects | 🔲 | 🔲 | Requires HA instance |
| Natural language command executed | 🔲 | 🔲 | |
| Routine created and saved | 🔲 | 🔲 | |
| home-assistant skill runs | 🔲 | 🔲 | |

**Status**: Requires a running Home Assistant instance — skipped if unavailable
**HermesClaw notes**: _fill after testing_
**NemoClaw notes**: _fill after testing_

---

## UC04 — Data Analyst (Postgres MCP + anomaly detection)

| Step | HermesClaw | NemoClaw | Notes |
|------|:----------:|:--------:|-------|
| Postgres MCP connects | 🔲 | 🔲 | Using Docker test-postgres |
| SQL query executed | 🔲 | 🔲 | |
| Table list returned | 🔲 | 🔲 | |
| anomaly-detection skill runs | 🔲 | 🔲 | |
| detect.py z-score output | 🔲 | 🔲 | |
| Alert sent | 🔲 | 🔲 | |

**HermesClaw notes**: _fill after testing_
**NemoClaw notes**: _fill after testing_

---

## UC05 — Small Business (Slack support bot)

| Step | HermesClaw | NemoClaw | Notes |
|------|:----------:|:--------:|-------|
| Slack bot connects | 🔲 | 🔲 | Requires Slack app |
| FAQ question answered | 🔲 | 🔲 | |
| Escalation triggered | 🔲 | 🔲 | |
| Knowledge base loaded | 🔲 | 🔲 | |
| slack-support skill runs | 🔲 | 🔲 | |

**HermesClaw notes**: _fill after testing_
**NemoClaw notes**: _fill after testing_

---

## UC06 — Privacy-regulated (sandbox enforcement)

| Step | HermesClaw | NemoClaw | Notes |
|------|:----------:|:--------:|-------|
| Stack starts with strict policy | 🔲 | 🔲 | |
| Document in knowledge/ summarized | 🔲 | 🔲 | |
| Outbound request blocked | 🔲 | 🔲 | Full enforcement Linux-only |
| Local inference only (no cloud) | 🔲 | 🔲 | NemoClaw needs cloud on macOS |

**Status**: Full OpenShell enforcement (Landlock/Seccomp) requires Linux kernel — partial test only on macOS
**HermesClaw notes**: _fill after testing_
**NemoClaw notes**: _fill after testing_

---

## UC07 — Trader (local latency + Telegram alerts)

| Step | HermesClaw | NemoClaw | Notes |
|------|:----------:|:--------:|-------|
| Stack starts | 🔲 | 🔲 | |
| Watchlist + thresholds saved to memory | 🔲 | 🔲 | |
| Threshold check returns correct result | 🔲 | 🔲 | |
| market-alerts skill runs | 🔲 | 🔲 | |
| monitor.py output correct | 🔲 | 🔲 | |
| Telegram alert sent | 🔲 | 🔲 | |
| Inference latency (ms) | 🔲 | 🔲 | Record actual times |

**HermesClaw latency**: _fill after testing_
**NemoClaw latency**: _fill after testing_ (cloud API)

---

## Summary

| Use case | HermesClaw | NemoClaw | Winner |
|----------|:----------:|:--------:|--------|
| Researcher | 🔲 | 🔲 | _TBD_ |
| Developer | 🔲 | 🔲 | _TBD_ |
| Home automation | 🔲 | 🔲 | _TBD_ |
| Data analyst | 🔲 | 🔲 | _TBD_ |
| Small business | 🔲 | 🔲 | _TBD_ |
| Privacy-regulated | 🔲 | 🔲 | _TBD_ |
| Trader | 🔲 | 🔲 | _TBD_ |
MARKDOWN

pass "docs/test-results-uc.md created"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo ""
if [[ "$NEMOCLAW_READY" == "true" ]]; then
    echo -e "${GREEN}${BOLD}Both stacks ready. Run tests:${RESET}"
else
    echo -e "${YELLOW}${BOLD}HermesClaw ready. Install NemoClaw, then run tests:${RESET}"
    echo ""
    echo "  curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
    echo ""
fi
echo "  bash scripts/test-uc-01.sh   # researcher"
echo "  bash scripts/test-uc-02.sh   # developer"
echo "  bash scripts/test-uc-04.sh   # data analyst"
echo "  bash scripts/test-uc-05.sh   # small business"
echo "  bash scripts/test-uc-06.sh   # privacy-regulated"
echo "  bash scripts/test-uc-07.sh   # trader"
echo ""
echo "  Results: docs/test-results-uc.md"
echo ""
