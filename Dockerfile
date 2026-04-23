FROM debian:bookworm-slim

# Hermes Agent version to install. Pinned to a released tag for reproducible
# builds; bump after validating a new upstream release locally.
# See docs/compatibility.md for the tested-against matrix.
ARG HERMES_VERSION=v2026.4.16

# Install system dependencies needed by the Hermes install script
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bash \
    git \
    python3 \
    python3-pip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Hermes Agent at the pinned tag. The install script runs an interactive
# setup wizard at the end that tries to open /dev/tty (not available in Docker
# build). The binary and skills are fully installed before the wizard runs, so
# we ignore the wizard failure. The install script accepts `--branch <tag>`
# which it passes through to `git clone --branch`, so any release tag works.
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash -s -- --branch "${HERMES_VERSION}" || true \
    && ( test -f /root/.local/bin/hermes || test -f /root/.hermes/bin/hermes ) \
    || (echo "Hermes binary not found after install" && exit 1) \
    && echo "${HERMES_VERSION}" > /etc/hermes-version

# Relocate hermes out of /root/ so OpenShell's non-root sandbox user can reach it.
# Without this, `openshell sandbox connect` sessions hit `Permission denied` on
# /root/.local/bin/hermes. See issues #3 and #4.
#
# The binary moves to /usr/local/bin/hermes (already on default PATH) and the
# venv to /opt/hermes-venv, with the binary's shebang rewritten to point at the
# relocated venv's python3. `chmod -R a+rX` uses capital X so only already-
# executable files (i.e. the python interpreter, hermes entry point, etc.)
# keep execute perms; data files do not gain spurious exec.
#
# Hermes data (config, memories, skills, sessions) moves from /root/.hermes to
# /opt/hermes-data so the sandbox user can access it without `chmod 755 /root`,
# which would expose all of /root/ including credentials. See issue #4.
RUN if [ -d /root/.hermes/hermes-agent/venv ]; then \
        cp -a /root/.hermes/hermes-agent/venv /opt/hermes-venv \
        && chmod -R a+rX /opt/hermes-venv ; \
    fi \
    && if [ -f /root/.local/bin/hermes ]; then \
        cp /root/.local/bin/hermes /usr/local/bin/hermes ; \
    elif [ -f /root/.hermes/bin/hermes ]; then \
        cp /root/.hermes/bin/hermes /usr/local/bin/hermes ; \
    fi \
    && chmod a+rx /usr/local/bin/hermes \
    && if [ -d /opt/hermes-venv ]; then \
        sed -i "1s|.*|#!/opt/hermes-venv/bin/python3|" /usr/local/bin/hermes ; \
    fi

# Move Hermes data out of /root/ so the sandbox user can reach config, memories,
# and skills without opening /root (which contains credentials). See issue #4.
RUN cp -a /root/.hermes /opt/hermes-data \
    && chmod -R a+rX /opt/hermes-data \
    && mkdir -p /opt/hermes-data/memories /opt/hermes-data/sessions \
               /opt/hermes-data/skills /opt/hermes-data/cron \
               /opt/hermes-data/hooks /opt/hermes-data/logs \
    && chmod -R a+rwX /opt/hermes-data/memories \
                      /opt/hermes-data/sessions \
                      /opt/hermes-data/skills \
                      /opt/hermes-data/cron \
                      /opt/hermes-data/hooks \
                      /opt/hermes-data/logs

ENV HERMES_HOME="/opt/hermes-data"
ENV PATH="/usr/local/bin:$PATH"

# Configure Hermes to use local llama.cpp server (via host.docker.internal on macOS).
# provider: "custom" (NOT alias "llamacpp") is required — runtime_provider.py only
# activates config base_url for the literal string "custom", not aliases.
RUN sed -i \
    -e 's|^  default: .*|  default: "local"|' \
    -e 's|^  provider: .*|  provider: "custom"|' \
    -e 's|^  base_url: .*|  base_url: "http://host.docker.internal:8080/v1"|' \
    /opt/hermes-data/config.yaml \
    && sed -i '/^  base_url: "http:\/\/host.docker.internal/a\\  api_key: "local"' /opt/hermes-data/config.yaml \
    && echo "Hermes configured for local llamacpp at host.docker.internal:8080"

# Working directory — maps to the sandboxed filesystem
WORKDIR /sandbox

# Persistent volumes:
#   /opt/hermes-data — Hermes memories, skills, config (persists across restarts)
#   /sandbox         — Agent working directory
VOLUME ["/opt/hermes-data", "/sandbox"]

# Default: start the Hermes gateway (handles Telegram, Signal, Discord, etc.)
# Override with: docker compose run hermesclaw hermes chat -q "hello"
CMD ["hermes", "gateway"]
