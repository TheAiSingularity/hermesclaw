#!/bin/sh
# Sourced at login via /etc/profile.d/ — sets up Hermes environment and
# seeds config into the user-writable HERMES_HOME directory.

export HERMES_HOME="/sandbox/.hermes"
export HERMES_WEB_DIST="/opt/hermes/hermes_cli/web_dist"
export PATH="/opt/hermes/.venv/bin:$PATH"
export TZ="${TZ:-$(cat /etc/timezone 2>/dev/null || echo UTC)}"

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

# Configure git to trust the OpenShell TLS proxy CA and authenticate via
# GITLAB_TOKEN so that `git clone/push` work without manual intervention.
OPENSHELL_CA="/etc/openshell-tls/openshell-ca.pem"
if [ -f "$OPENSHELL_CA" ]; then
  git config --global http.sslCAInfo "$OPENSHELL_CA"
fi
[ -f "$DEFAULTS/mcp-urls.env" ] && . "$DEFAULTS/mcp-urls.env"
if [ -n "${GITLAB_TOKEN:-}" ] && [ -n "${GITLAB_URL:-}" ]; then
  git config --global credential.helper \
    "!f() { echo username=oauth2; echo password=\$GITLAB_TOKEN; }; f"
fi

# API timeouts for local large-model inference (Nemotron 120B, 262K context).
# Hermes reads .env as config but does not export to the process environment,
# so sub-agents spawned by delegate_task inherit the default 300s timeout.
# Exporting here ensures all child processes use the extended timeouts.
export HERMES_API_TIMEOUT="${HERMES_API_TIMEOUT:-1800}"
export HERMES_API_CALL_STALE_TIMEOUT="${HERMES_API_CALL_STALE_TIMEOUT:-900}"
