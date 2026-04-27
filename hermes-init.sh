#!/bin/sh
# Sourced at login via /etc/profile.d/ — sets up Hermes environment and
# seeds config into the user-writable HERMES_HOME directory.

export HERMES_HOME="/sandbox/.hermes"
export HERMES_WEB_DIST="/opt/hermes/hermes_cli/web_dist"
export PATH="/opt/hermes/.venv/bin:$PATH"

export NVM_DIR="/opt/nvm"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://inference.local/v1}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-not-needed}"

mkdir -p "$HERMES_HOME"

# Seed defaults from the image stash. These are copied directly from
# /opt/hermes/ source files at build time (bypassing the /opt/data VOLUME)
# and have inference config already applied.
DEFAULTS="/usr/local/share/hermes-defaults"
for f in config.yaml .env SOUL.md; do
  [ ! -f "$HERMES_HOME/$f" ] && [ -f "$DEFAULTS/$f" ] && \
    cp "$DEFAULTS/$f" "$HERMES_HOME/$f"
done

# Append MCP server blocks based on runtime credentials + baked-in URLs
[ -x /usr/local/bin/configure-mcp.sh ] && /usr/local/bin/configure-mcp.sh
