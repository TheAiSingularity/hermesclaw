#!/usr/bin/env bash
# HermesClaw setup — installs dependencies and configures the sandbox.
#
# Two paths:
#   OpenShell (NVIDIA) — full hardware-enforced sandbox (recommended)
#   Docker only        — no sandbox, but all Hermes features work
#
# Usage:
#   ./scripts/setup.sh

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}HermesClaw Setup${RESET}"
echo "=================================================="
echo ""

# ── Step 1: Docker ──────────────────────────────────────────────────────────
echo -e "${BOLD}[1/5] Checking Docker...${RESET}"
if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker is not installed.${RESET}"
    echo "  Install: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✓ Docker found: $(docker --version | head -1)${RESET}"

# ── Step 2: OpenShell (optional) ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/5] Checking OpenShell (optional — for full NVIDIA sandbox)...${RESET}"
OPENSHELL_AVAILABLE=false
if command -v openshell &>/dev/null; then
    OPENSHELL_AVAILABLE=true
    echo -e "${GREEN}✓ OpenShell found: $(openshell --version 2>&1 | head -1)${RESET}"
else
    echo -e "${YELLOW}⚠  OpenShell not found.${RESET}"
    echo "   Without OpenShell, HermesClaw runs in Docker-only mode (no hardware sandbox)."
    echo "   To install OpenShell:"
    echo -e "     ${CYAN}curl -fsSL https://www.nvidia.com/openshell.sh | bash${RESET}"
    echo "   (requires NVIDIA account)"
    echo ""
    echo "   Continuing with Docker-only mode..."
fi

# ── Step 3: Build the Hermes container image ─────────────────────────────────
echo ""
echo -e "${BOLD}[3/5] Building HermesClaw container image...${RESET}"
echo "   This installs Hermes Agent inside the container — takes 2-5 minutes on first run."
docker build -t hermesclaw:latest .
echo -e "${GREEN}✓ Image built: hermesclaw:latest${RESET}"

# ── Step 4: Apply OpenShell policy and profile (if available) ────────────────
echo ""
echo -e "${BOLD}[4/5] Registering OpenShell policy and profile...${RESET}"
if [ "$OPENSHELL_AVAILABLE" = true ]; then
    openshell policy apply openshell/hermesclaw-policy.yaml
    echo -e "${GREEN}✓ Policy applied: hermesclaw${RESET}"
    openshell profile register openshell/hermesclaw-profile.yaml
    echo -e "${GREEN}✓ Profile registered: hermesclaw${RESET}"
else
    echo "   Skipped (OpenShell not available)."
fi

# ── Step 5: Create Hermes config ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5/5] Setting up Hermes config...${RESET}"
mkdir -p ~/.hermes
if [ ! -f ~/.hermes/config.yaml ]; then
    cp configs/hermes.yaml.example ~/.hermes/config.yaml
    echo -e "${GREEN}✓ Created ~/.hermes/config.yaml${RESET}"
else
    echo "   ~/.hermes/config.yaml already exists — not overwriting."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=================================================="
echo -e "Setup complete!${RESET}"
echo ""
if [ "$OPENSHELL_AVAILABLE" = true ]; then
    echo -e "${GREEN}Mode: OpenShell sandbox (full security)${RESET}"
    echo ""
    echo "Next steps:"
    echo -e "  1. Download a model:  ${CYAN}curl -L -o models/Qwen3.5-4B-Q4_K_M.gguf <url>${RESET}"
    echo -e "  2. Configure messaging: ${CYAN}docker run --rm -it hermesclaw hermes gateway setup${RESET}"
    echo -e "  3. Start sandboxed:   ${CYAN}./scripts/start.sh${RESET}"
else
    echo -e "${YELLOW}Mode: Docker only (no hardware sandbox — OpenShell not installed)${RESET}"
    echo ""
    echo "Next steps:"
    echo -e "  1. Download a model:  ${CYAN}curl -L -o models/Qwen3.5-4B-Q4_K_M.gguf <url>${RESET}"
    echo -e "  2. Copy env file:     ${CYAN}cp .env.example .env${RESET}"
    echo -e "  3. Configure messaging: ${CYAN}docker compose run hermesclaw hermes gateway setup${RESET}"
    echo -e "  4. Start:             ${CYAN}docker compose up${RESET}"
fi
echo ""
