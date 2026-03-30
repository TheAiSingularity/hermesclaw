#!/usr/bin/env bash
# Show HermesClaw status.
#
# Usage:
#   ./scripts/status.sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}HermesClaw Status${RESET}"
echo "================================"

# llama.cpp
if curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
    echo -e "llama.cpp    ${GREEN}running${RESET} (port 8080)"
else
    echo -e "llama.cpp    ${RED}not running${RESET}"
fi

# Sandbox / Docker
if command -v openshell &>/dev/null; then
    echo ""
    echo "OpenShell sandbox:"
    openshell sandbox status hermesclaw-1 2>/dev/null || echo -e "  ${YELLOW}hermesclaw-1 not running${RESET}"
else
    echo ""
    echo "Docker services:"
    docker compose ps 2>/dev/null || echo -e "  ${YELLOW}docker compose not running${RESET}"
fi

# Hermes memories
MEMORY_DIR=~/.hermes/memories
if [ -d "$MEMORY_DIR" ]; then
    COUNT=$(find "$MEMORY_DIR" -type f | wc -l | tr -d ' ')
    echo ""
    echo -e "Hermes memories: ${GREEN}${COUNT} files${RESET} in $MEMORY_DIR"
else
    echo ""
    echo -e "Hermes memories: ${YELLOW}none yet${RESET} (created after first session)"
fi

echo ""
