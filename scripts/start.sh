#!/usr/bin/env bash
# Start HermesClaw — sandboxed (OpenShell) or plain Docker.
#
# Usage:
#   ./scripts/start.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Pre-check: llama.cpp ─────────────────────────────────────────────────────
if ! curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠  llama.cpp is not running on port 8080.${RESET}"
    echo ""
    echo "Start it first:"
    echo -e "  ${CYAN}llama-server -m models/<model>.gguf --port 8080 -ngl 99${RESET}"
    echo ""
    echo "Or use docker compose (starts llama-server automatically):"
    echo -e "  ${CYAN}docker compose up${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ llama.cpp is running${RESET}"

# ── Choose mode ──────────────────────────────────────────────────────────────
if command -v openshell &>/dev/null; then
    echo ""
    echo -e "${BOLD}Starting HermesClaw inside OpenShell sandbox...${RESET}"
    openshell sandbox create --profile hermesclaw --name hermesclaw-1
    echo -e "${GREEN}✓ Sandbox started: hermesclaw-1${RESET}"
    echo ""
    echo "Check status:"
    echo -e "  ${CYAN}openshell sandbox status hermesclaw-1${RESET}"
    echo -e "  ${CYAN}./scripts/status.sh${RESET}"
else
    echo ""
    echo -e "${YELLOW}OpenShell not available — starting in Docker-only mode.${RESET}"
    docker compose up
fi
