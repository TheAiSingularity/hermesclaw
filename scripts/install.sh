#!/usr/bin/env bash
# HermesClaw — one-command install.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/TheAiSingularity/hermesclaw/main/scripts/install.sh | bash
#
# What it does (idempotent, non-interactive):
#   1. Verifies bash, curl, docker, git are present and the Docker daemon is running.
#   2. Clones (or updates, if clean) the repo at $HERMESCLAW_HOME (default ~/.hermesclaw).
#   3. Pulls the prebuilt image from GHCR and tags it locally as hermesclaw:latest.
#   4. Bootstraps .env from .env.example.
#   5. Symlinks $HERMESCLAW_HOME/scripts/hermesclaw into $HERMESCLAW_BIN_DIR
#      (default /usr/local/bin) if writable, otherwise prints PATH instructions.
#   6. Prints the three remaining manual steps (model download, llama-server, docker compose).
#
# Overrides (env vars):
#   HERMESCLAW_HOME      — install location (default: ~/.hermesclaw)
#   HERMESCLAW_BIN_DIR   — where to symlink the CLI (default: /usr/local/bin)
#   HERMESCLAW_IMAGE     — override the pulled image (default: ghcr.io/theaisingularity/hermesclaw:latest)
#   HERMESCLAW_REF       — git ref to check out (default: main)
#
# Notes:
#   - This script is intentionally non-interactive so `| bash` works reliably.
#   - It does NOT download model weights or start llama-server — those are deliberate
#     manual steps, documented at the end.

set -euo pipefail

REPO_URL="${HERMESCLAW_REPO_URL:-https://github.com/TheAiSingularity/hermesclaw.git}"
REF="${HERMESCLAW_REF:-main}"
IMAGE="${HERMESCLAW_IMAGE:-ghcr.io/theaisingularity/hermesclaw:latest}"
INSTALL_DIR="${HERMESCLAW_HOME:-$HOME/.hermesclaw}"
BIN_DIR="${HERMESCLAW_BIN_DIR:-/usr/local/bin}"

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; DIM='\033[2m'; RESET='\033[0m'

say()     { printf "%b\n" "$*"; }
ok()      { say "  ${GREEN}✓${RESET} $*"; }
warn()    { say "  ${YELLOW}!${RESET} $*"; }
err()     { say "  ${RED}✗${RESET} $*" >&2; exit 1; }
heading() { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
heading "Checking prerequisites"
for cmd in bash curl docker git; do
    command -v "$cmd" >/dev/null 2>&1 || err "$cmd not found. Install it and retry."
done
if ! docker info >/dev/null 2>&1; then
    err "Docker daemon is not running. Start Docker Desktop (macOS/Windows) or 'sudo systemctl start docker' (Linux) and retry."
fi
ok "bash, curl, docker, git present; Docker daemon running"

# ── 2. Clone or update repo ───────────────────────────────────────────────────
heading "Fetching HermesClaw sources into $INSTALL_DIR"
if [ -d "$INSTALL_DIR/.git" ]; then
    # Existing checkout — only update if clean. Never blow away local changes.
    if ! git -C "$INSTALL_DIR" diff --quiet HEAD -- 2>/dev/null; then
        warn "Existing checkout at $INSTALL_DIR has local changes; skipping update."
        warn "Commit or stash and re-run, or set HERMESCLAW_HOME to a fresh path."
    else
        git -C "$INSTALL_DIR" fetch --tags --quiet origin
        git -C "$INSTALL_DIR" checkout --quiet "$REF"
        git -C "$INSTALL_DIR" pull --quiet --ff-only origin "$REF" || true
        ok "Updated existing install to $REF"
    fi
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --quiet --branch "$REF" --depth 1 "$REPO_URL" "$INSTALL_DIR"
    ok "Cloned $REPO_URL ($REF) to $INSTALL_DIR"
fi

# ── 3. Pull prebuilt image and tag locally ────────────────────────────────────
heading "Pulling container image"
# Retry pull once on transient GHCR hiccups.
if ! docker pull "$IMAGE" >/dev/null 2>&1; then
    warn "First pull failed; retrying once..."
    docker pull "$IMAGE" >/dev/null || err "Could not pull $IMAGE. Check network and try: docker pull $IMAGE"
fi
# Local-name tag so existing docker-compose.yml (image: hermesclaw:latest) works without rebuild.
docker tag "$IMAGE" hermesclaw:latest
ok "Pulled $IMAGE; tagged locally as hermesclaw:latest"

# ── 4. Bootstrap .env ─────────────────────────────────────────────────────────
if [ ! -f "$INSTALL_DIR/.env" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
    ok "Created $INSTALL_DIR/.env from .env.example"
fi

# ── 5. Install the CLI ────────────────────────────────────────────────────────
heading "Installing hermesclaw CLI"
CLI_SRC="$INSTALL_DIR/scripts/hermesclaw"
CLI_DST="$BIN_DIR/hermesclaw"
chmod +x "$CLI_SRC" 2>/dev/null || true
if [ -w "$BIN_DIR" ] || [ "${EUID:-$(id -u)}" = "0" ]; then
    ln -sf "$CLI_SRC" "$CLI_DST"
    ok "Symlinked $CLI_DST → $CLI_SRC"
elif command -v sudo >/dev/null 2>&1; then
    warn "$BIN_DIR is not writable; attempting sudo symlink (will prompt once)."
    if sudo ln -sf "$CLI_SRC" "$CLI_DST"; then
        ok "Symlinked (via sudo) $CLI_DST → $CLI_SRC"
    else
        warn "sudo symlink failed. Add this to your shell profile instead:"
        say "    export PATH=\"$INSTALL_DIR/scripts:\$PATH\""
    fi
else
    warn "$BIN_DIR is not writable and sudo is unavailable. Add to PATH manually:"
    say "    export PATH=\"$INSTALL_DIR/scripts:\$PATH\""
fi

# ── 6. Next steps ─────────────────────────────────────────────────────────────
heading "Done"
say ""
say "HermesClaw installed at ${CYAN}$INSTALL_DIR${RESET}."
say ""
say "${BOLD}Next (three manual steps):${RESET}"
say ""
say "  ${CYAN}1. Download a GGUF model${RESET}"
say "     ${DIM}# example (Qwen3 4B, ~2.5 GB):${RESET}"
say "     curl -L -o $INSTALL_DIR/models/Qwen3-4B-Q4_K_M.gguf \\"
say "       https://huggingface.co/bartowski/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf"
say ""
say "  ${CYAN}2. Start llama-server on the host${RESET}"
say "     ${DIM}# macOS:${RESET}"
say "     brew install llama.cpp && \\"
say "       llama-server -m $INSTALL_DIR/models/<your-model>.gguf --port 8080 --ctx-size 32768 -ngl 99"
say "     ${DIM}# Linux — build from https://github.com/ggerganov/llama.cpp#build${RESET}"
say ""
say "  ${CYAN}3. Start HermesClaw${RESET}"
say "     cd $INSTALL_DIR && docker compose up -d"
say "     hermesclaw chat \"hello\""
say ""
say "${DIM}Full diagnostic: hermesclaw doctor${RESET}"
say "${DIM}Policy presets:  hermesclaw policy-list${RESET}"
say ""
