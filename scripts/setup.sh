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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo -e "${BOLD}HermesClaw Setup${RESET}"
echo "=================================================="
echo ""

# ── Step 1: Docker ──────────────────────────────────────────────────────────
echo -e "${BOLD}[1/6] Checking Docker...${RESET}"
if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker is not installed.${RESET}"
    echo "  Install: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✓ Docker found: $(docker --version | head -1)${RESET}"

# ── Step 2: OpenShell (optional) ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/6] Checking OpenShell (optional — for full NVIDIA sandbox)...${RESET}"
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
echo -e "${BOLD}[3/6] Building HermesClaw container image...${RESET}"
echo "   This installs Hermes Agent inside the container — takes 2-5 minutes on first run."
docker build -t hermesclaw:latest .
echo -e "${GREEN}✓ Image built: hermesclaw:latest${RESET}"

# ── Step 4: Register OpenShell inference provider + route ────────────────────
# This mirrors NVIDIA/NemoClaw's own setup.sh: an inference provider must be
# registered with the OpenShell gateway *before* a sandbox is created, so that
# calls to `http://inference.local` inside the sandbox are routed to a real
# backend (host llama.cpp by default).
#
# We skip this silently if OpenShell is not installed — Docker mode bypasses
# OpenShell entirely and hits llama.cpp directly via host.docker.internal.
echo ""
echo -e "${BOLD}[4/6] Registering OpenShell inference provider + route...${RESET}"
if [ "$OPENSHELL_AVAILABLE" = true ]; then
    # Require a running OpenShell gateway before we try to talk to it.
    if ! openshell status &>/dev/null; then
        echo -e "${YELLOW}⚠  OpenShell gateway is not running.${RESET}"
        echo -e "   Start it first: ${CYAN}openshell gateway start${RESET}"
        echo "   Then re-run this script."
        exit 1
    fi

    # Provider: a 'generic' OpenAI-compatible provider pointing at the host
    # llama.cpp server. Inside an OpenShell sandbox the host is reachable via
    # 'host.openshell.internal' (OpenShell's own magic hostname).
    #
    # We use a fixed dummy credential because llama.cpp doesn't require auth.
    # Use --from-existing semantics by always re-creating to keep this idempotent.
    if openshell provider get local-llama &>/dev/null; then
        echo "   Provider 'local-llama' already exists — skipping creation."
    else
        openshell provider create \
            --name local-llama \
            --type generic \
            --config base_url=http://host.openshell.internal:8080/v1 \
            --credential API_KEY=not-needed \
            >/dev/null
        echo -e "${GREEN}✓ Provider 'local-llama' created${RESET}"
    fi

    # Inference route: tell the gateway which provider + model to use when the
    # sandbox calls inference.local. --no-verify skips the endpoint liveness
    # check so `setup.sh` can complete before llama-server is running.
    openshell inference set \
        --no-verify \
        --provider local-llama \
        --model local \
        >/dev/null
    echo -e "${GREEN}✓ Inference route set: local-llama / local${RESET}"
    echo "   (override later with: openshell inference set --provider <name> --model <id>)"
else
    echo "   Skipped (OpenShell not installed — Docker mode will hit llama.cpp directly)."
fi

# ── Step 5: Create Hermes config ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5/6] Setting up Hermes config...${RESET}"
mkdir -p ~/.hermes
if [ ! -f ~/.hermes/config.yaml ]; then
    cp configs/hermes.yaml.example ~/.hermes/config.yaml
    echo -e "${GREEN}✓ Created ~/.hermes/config.yaml${RESET}"
else
    echo "   ~/.hermes/config.yaml already exists — not overwriting."
fi

# ── Step 6: .env bootstrap ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[6/6] Bootstrapping .env...${RESET}"
if [ ! -f "$REPO_DIR/.env" ]; then
    cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
    echo -e "${GREEN}✓ Created .env from .env.example${RESET}"
    echo "   Edit .env to set MODEL_FILE and any messaging bot tokens."
else
    echo "   .env already exists — not overwriting."
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
    echo -e "  1. Download a model:  ${CYAN}curl -L -o models/<model>.gguf <url>${RESET}"
    echo -e "  2. Start llama-server: ${CYAN}llama-server -m models/<model>.gguf --port 8080 --ctx-size 32768 -ngl 99${RESET}"
    echo -e "  3. Start sandboxed:   ${CYAN}./scripts/hermesclaw start --policy strict${RESET}"
    echo -e "  4. Chat:              ${CYAN}./scripts/hermesclaw chat \"hello\"${RESET}"
else
    echo -e "${YELLOW}Mode: Docker only (no hardware sandbox — OpenShell not installed)${RESET}"
    echo ""
    echo "Next steps:"
    echo -e "  1. Download a model:  ${CYAN}curl -L -o models/<model>.gguf <url>${RESET}"
    echo -e "  2. Edit .env:         ${CYAN}MODEL_FILE=<your-model>.gguf${RESET}"
    echo -e "  3. Start llama-server on host: ${CYAN}llama-server -m models/<model>.gguf --port 8080 --ctx-size 32768 -ngl 99${RESET}"
    echo -e "  4. Start container:   ${CYAN}docker compose up -d${RESET}"
    echo -e "  5. Chat:              ${CYAN}docker exec -it hermesclaw hermes chat -q \"hello\"${RESET}"
fi
echo ""
