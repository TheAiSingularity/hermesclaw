FROM debian:bookworm-slim

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

# Install Hermes Agent. The install script runs an interactive setup wizard at the
# end that tries to open /dev/tty (not available in Docker build). The binary and
# skills are fully installed before the wizard runs, so we ignore the wizard failure.
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash || true \
    && test -f /root/.local/bin/hermes || test -f /root/.hermes/bin/hermes \
    || (echo "Hermes binary not found after install" && exit 1)

ENV PATH="/root/.local/bin:$PATH"

# Configure Hermes to use local llama.cpp server (via host.docker.internal on macOS).
# provider: "custom" (NOT alias "llamacpp") is required — runtime_provider.py only
# activates config base_url for the literal string "custom", not aliases.
RUN sed -i \
    -e 's|^  default: .*|  default: "local"|' \
    -e 's|^  provider: .*|  provider: "custom"|' \
    -e 's|^  base_url: .*|  base_url: "http://host.docker.internal:8080/v1"|' \
    /root/.hermes/config.yaml \
    && sed -i '/^  base_url: "http:\/\/host.docker.internal/a\\  api_key: "local"' /root/.hermes/config.yaml \
    && echo "Hermes configured for local llamacpp at host.docker.internal:8080"

# Working directory — maps to the sandboxed filesystem
WORKDIR /sandbox

# Persistent volumes:
#   /root/.hermes  — Hermes memories, skills, config (persists across restarts)
#   /sandbox       — Agent working directory
VOLUME ["/root/.hermes", "/sandbox"]

# Default: start the Hermes gateway (handles Telegram, Signal, Discord, etc.)
# Override with: docker compose run hermesclaw hermes chat -q "hello"
CMD ["hermes", "gateway"]
