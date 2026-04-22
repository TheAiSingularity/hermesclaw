# HermesClaw — Feature Reference

Complete reference for all features, capabilities, and CLI commands.

---

## Table of Contents

1. [Sandbox Security](#sandbox-security)
2. [Policy Management](#policy-management)
3. [Inference Routing](#inference-routing)
4. [Sandbox Lifecycle](#sandbox-lifecycle)
5. [Hermes Agent Capabilities](#hermes-agent-capabilities)
6. [Messaging Gateway](#messaging-gateway)
7. [Memory System](#memory-system)
8. [Skills System](#skills-system)
9. [hermesclaw CLI Reference](#hermesclaw-cli-reference)
10. [Python SDK](#python-sdk)
11. [Docker / Deployment](#docker--deployment)

---

## Sandbox Security

OpenShell enforces security at the kernel level — **below the application layer**. Even a fully compromised Hermes process cannot override these limits.

### Four enforcement layers

| Layer | Mechanism | Locked at creation? |
|-------|-----------|:-------------------:|
| Filesystem | Landlock LSM | Yes |
| Process | Seccomp BPF + unprivileged user | Yes |
| Network | OPA + HTTP CONNECT proxy | No (hot-reloadable) |
| Inference | Privacy router (credential injection) | No (hot-reloadable) |

### What is blocked by default

- **Network**: all outbound traffic except `inference.local` (configured per policy)
- **Filesystem**: everything except `~/.hermes/`, `/sandbox/`, `/tmp/`, and system read-only paths
- **Syscalls**: `ptrace`, `mount`, `umount2`, `kexec_load`, `perf_event_open`, `process_vm_readv`, `process_vm_writev`
- **Privilege escalation**: agent runs as non-root user `hermes:hermes`

---

## Policy Management

### Policy presets

| Preset | File | Description |
|--------|------|-------------|
| `default` | `openshell/hermesclaw-policy.yaml` | Base policy — inference only, all extras commented out |
| `strict` | `openshell/policy-strict.yaml` | Inference only, most secure |
| `gateway` | `openshell/policy-gateway.yaml` | Inference + Telegram + Discord |
| `permissive` | `openshell/policy-permissive.yaml` | Inference + all gateways + web search + GitHub skills |

### Apply a policy

```bash
# Apply to a running sandbox (hot-reload, no restart):
hermesclaw policy-set gateway
# or directly:
openshell policy set hermesclaw-1 --policy openshell/policy-gateway.yaml --wait

# Apply globally to all sandboxes:
openshell policy set --global --policy openshell/policy-strict.yaml

# Check current policy:
openshell policy get hermesclaw-1 --full

# View policy history:
openshell policy list hermesclaw-1
```

### Policy YAML schema

```yaml
version: 1

filesystem_policy:
  include_workdir: true     # auto-include agent working dir
  read_only:
    - /usr
    - /etc/ssl
  read_write:
    - /root/.hermes
    - /sandbox
    - /tmp

landlock:
  compatibility: best_effort   # or hard_requirement

process:
  run_as_user: hermes          # cannot be "root"
  run_as_group: hermes

network_policies:
  policy_name:
    endpoints:
      - host: "api.example.com"
        port: 443
        enforcement: enforce   # or audit
        access: full           # or read-only, read-write
        rules:
          - method: "POST"
            path: "/v1/chat/completions"
    binaries:
      - path: "/usr/local/bin/hermes*"   # glob supported
```

---

## Inference Routing

OpenShell's privacy router intercepts every call to `https://inference.local` inside the sandbox, strips the agent's credentials, and forwards to the configured backend.

### Configure providers

```bash
# Local llama.cpp
openshell provider create --name local-llama --type openai \
  --credential OPENAI_API_KEY=not-needed \
  --config OPENAI_BASE_URL=http://127.0.0.1:8080/v1

# NVIDIA API Catalog
openshell provider create --name nvidia-prod --type nvidia --from-existing

# OpenAI
openshell provider create --name openai-prod --type openai --from-existing

# Anthropic
openshell provider create --name anthropic-prod --type anthropic --from-existing

# Ollama (local)
openshell provider create --name local-ollama --type openai \
  --credential OPENAI_API_KEY=dummy \
  --config OPENAI_BASE_URL=http://host.openshell.internal:11434/v1
```

### Switch inference backend (hot-reload, no restart)

```bash
openshell inference set --provider local-llama --model qwen3-4b
openshell inference set --provider nvidia-prod --model nemotron-4-340b-instruct
openshell inference set --provider anthropic-prod --model claude-sonnet-4-6
openshell inference get   # verify
```

---

## Sandbox Lifecycle

### Full command reference

```bash
# Start
hermesclaw start                         # OpenShell or Docker depending on availability
hermesclaw start --gpu                   # Pass NVIDIA GPU to sandbox
hermesclaw start --policy permissive     # Use permissive policy preset

# Connect and inspect
hermesclaw connect                       # Interactive shell inside sandbox
hermesclaw logs                          # View logs
hermesclaw logs --follow                 # Stream logs
openshell term                           # Live monitoring dashboard (TUI)

# File transfer
openshell sandbox upload hermesclaw-1 ./local-file.txt /sandbox/file.txt
openshell sandbox download hermesclaw-1 /root/.hermes/MEMORY.md ./memory-backup.md

# Port forwarding
openshell forward start hermesclaw-1 --local 9090 --remote 9090

# Remote deployment
openshell gateway start --remote user@gpu-server
openshell gateway select my-remote-gateway
hermesclaw start   # now creates sandbox on remote machine

# Stop / cleanup
hermesclaw stop                          # Stop sandbox (memories preserved)
hermesclaw uninstall                     # Remove image (memories preserved)
```

---

## Hermes Agent Capabilities

HermesClaw runs the full Hermes Agent stack inside the sandbox. All 40+ tools are available (subject to the active network policy).

### Tool categories

| Category | Tools | Network policy needed |
|----------|-------|----------------------|
| Web | `web_search`, `web_extract`, `browser_*` | `web_search` policy |
| Terminal | `terminal`, `process`, `execute_code` | None |
| Files | `read_file`, `patch`, `file_search`, `file_grep` | None |
| Memory | `memory`, `session_search`, `honcho` | None |
| Vision | `vision_analyze`, `image_crop`, `browser_vision` | None (local model) |
| Voice | `text_to_speech` | None (local) |
| Image gen | `image_generate` | Optional API |
| Messaging | `send_message`, `background_notify` | Gateway policy |
| Skills | `skill_manage` (`create`, `patch`, `edit`, `delete`) | Optional GitHub |
| Planning | `todo`, `clarify`, `delegate_task` | None |
| Scheduling | `cronjob` | None |
| AI | `moa`, `rl_train` | Inference only |
| MCP | `mcp_tool` | Per-MCP-server policy |

### In-session commands

```
/model         Switch provider/model mid-session
/tools         Manage active tools
/skills browse Browse available skills
/personality   Switch persona (focused, researcher, etc.)
/reasoning     Set reasoning level (low/medium/high)
/voice on      Enable voice mode
/plan          Generate implementation plan
/rollback      Rollback to previous checkpoint
/stop          Stop active agent run
/background    Run task in background
```

---

## Messaging Gateway

Run `hermes gateway` inside the sandbox to handle messages from all platforms.

**Required network policy: `gateway`** — apply with `hermesclaw policy-set gateway`

### Setup

```bash
# Interactive setup (run inside sandbox)
hermesclaw connect
hermes gateway

# Or configure manually in ~/.hermes/config.yaml
# Tokens in ~/.hermes/.env
```

### Supported platforms

| Platform | Bot creation | Voice notes | Threading | Groups |
|----------|-------------|:-----------:|:---------:|:------:|
| Telegram | @BotFather | ✅ | ✅ | ✅ |
| Discord | Developer Portal | ✅ | ✅ | ✅ |
| Signal | signal-cli bridge | ✅ | - | ✅ |
| Slack | Workspace app | - | ✅ | ✅ |
| WhatsApp | QR pairing | ✅ | - | ✅ |
| Email | IMAP/SMTP | - | - | - |

### User authorization

```bash
# Generate pairing code (users send this in DM)
hermes pairing

# Allow all users on a platform (not recommended for public bots)
# Set allow_all: true in gateway config
```

---

## Memory System

Hermes maintains two memory files, loaded into every session:

| File | Size | Contents |
|------|------|----------|
| `~/.hermes/memories/MEMORY.md` | ~800 tokens | Environment facts, conventions, lessons learned |
| `~/.hermes/memories/USER.md` | ~500 tokens | Your profile, preferences, communication style |

Memory is **persisted on the host** via the volume mount — survives sandbox recreation.

### Session search

All past sessions are stored in SQLite with FTS5 full-text search:

```bash
hermes sessions search "how to configure Telegram"
hermes sessions list
hermes sessions browse
```

---

## Skills System

Skills are reusable procedures Hermes creates, stores, and improves over time.

```
~/.hermes/skills/
  skill-name/
    SKILL.md          # Description + procedure
    references/       # Reference docs
    scripts/          # Helper scripts
    templates/        # File templates
```

### Auto-creation

Hermes creates skills automatically after complex tasks (5+ tool calls). Skills improve via **DSPy + GEPA** (Genetic-Pareto Prompt Evolution) — no GPU required, costs $2–10/run.

```bash
# Manage skills
hermes skills list
hermes skills search "deployment"
hermes skills install skill-name
hermes skills browse
hermes skills publish my-skill

# Audit installed skills
hermes skills audit
```

---

## hermesclaw CLI Reference

```
hermesclaw help                      Display this help
hermesclaw onboard                   First-time setup and status check
hermesclaw start [--gpu] [--policy]  Start sandbox (OpenShell) or docker compose
hermesclaw stop                      Stop sandbox (memories preserved)
hermesclaw status                    Show inference config + memory/skill counts
hermesclaw connect                   Open interactive shell in sandbox
hermesclaw logs [--follow]           Stream sandbox logs
hermesclaw policy-list               List policy presets
hermesclaw policy-set PRESET         Hot-swap policy on running sandbox
hermesclaw doctor                    Run end-to-end diagnostics
hermesclaw chat "prompt"             One-shot message to Hermes
hermesclaw version                   Print version info
hermesclaw uninstall                 Remove Docker image (memories preserved)
```

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMESCLAW_SANDBOX` | `hermesclaw-1` | Sandbox name |

---

## Python SDK

Use Hermes programmatically in any Python application:

```python
from run_agent import AIAgent

agent = AIAgent(
    model="local",                         # or "anthropic/claude-opus-4-6"
    enabled_toolsets=["web", "terminal", "memory", "skills"],
    ephemeral_system_prompt="You are a helpful assistant.",
    max_iterations=90,
    skip_memory=False,                     # load MEMORY.md + USER.md
)

# Single-turn
response = agent.chat("Summarise the files in /sandbox")
print(response)

# Multi-turn
history = []
result = agent.run_conversation("Research this topic", conversation_history=history)
history = result["history"]
result2 = agent.run_conversation("Now write a report", conversation_history=history)
```

---

## Docker / Deployment

### Quick start

```bash
cp .env.example .env         # fill in MODEL_FILE and optional tokens
docker compose up            # CPU inference
docker compose --profile gpu up  # NVIDIA GPU inference
```

### GPU mode

Requires NVIDIA Container Toolkit. Uses `llama.cpp:server-cuda` image.

```bash
# In .env:
N_GPU_LAYERS=99
```

### Volumes

| Volume | Contents | Persists |
|--------|----------|:--------:|
| `hermesclaw-memories` | Hermes memories | ✅ |
| `hermesclaw-skills` | Hermes skills | ✅ |
| `./knowledge` | User docs (read-only mount) | On host |
| `./models` | Model weights (read-only mount) | On host |

### Environment variables (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `MODEL_FILE` | `Qwen3-4B-Q4_K_M.gguf` | Model filename in `models/` |
| `N_GPU_LAYERS` | `0` | GPU layers (0 = CPU, 99 = all GPU) |
| `CTX_SIZE` | `8192` | Context window size |
| `LLAMA_PORT` | `8080` | llama.cpp port |
| `HERMESCLAW_PORT` | `8090` | HermesClaw gateway webhook port |
| `TELEGRAM_BOT_TOKEN` | — | Telegram bot token |
| `DISCORD_BOT_TOKEN` | — | Discord bot token |
| `SLACK_BOT_TOKEN` | — | Slack bot token |
| `HERMES_PRIVACY_THRESHOLD` | `0.0` | 0=local only, 1=cloud only, 0.7=auto |
| `HERMES_APPROVAL_MODE` | `smart` | `manual`, `smart`, or `off` |
