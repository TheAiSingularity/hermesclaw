FROM debian:bookworm-slim

# Install system dependencies needed by the Hermes install script
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bash \
    git \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Hermes Agent via official install script
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

ENV PATH="/root/.local/bin:$PATH"

# Working directory — maps to the sandboxed filesystem
WORKDIR /sandbox

# Persistent volumes:
#   /root/.hermes  — Hermes memories, skills, config (persists across restarts)
#   /sandbox       — Agent working directory
VOLUME ["/root/.hermes", "/sandbox"]

# Default: start the Hermes gateway (handles Telegram, Signal, Discord, etc.)
# Override with: docker compose run hermesclaw hermes chat -q "hello"
CMD ["hermes", "gateway"]
