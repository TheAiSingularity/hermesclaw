<p align="center">
  <img src="assets/banner.png" alt="HermesClaw" width="100%">
</p>

**Hermes Agent sandboxed by NVIDIA OpenShell.**

NVIDIA built OpenShell to hardware-enforce AI agent behavior — blocking network egress, filesystem writes, and dangerous syscalls at the kernel level. They demonstrated it with Claude Code, Codex, and Cursor. They used it to build NemoClaw (OpenClaw + OpenShell). **Nobody had done it for Hermes Agent — until now.**

HermesClaw puts Hermes inside OpenShell. The agent gets its full capability stack (40+ tools, persistent memory, self-improving skills, Telegram/Signal/Discord/Slack/WhatsApp/Email gateway) while the sandbox enforces hard limits: Hermes can only reach `inference.local` (your llama.cpp or any OpenAI-compatible API), can only write to `~/.hermes/` and `/sandbox/`, and cannot call `ptrace`, `mount`, or `kexec`. If a skill goes rogue, the OS stops it.

---

## Architecture

```
User (Telegram / Signal / Discord / Slack / WhatsApp / Email / CLI)
         │
         ▼
  ┌─────────────────────────────────────────────────────┐
  │         Hermes Agent (NousResearch)                  │
  │  40+ tools · memory · skills · gateway · voice       │
  │  ┌─────────────────────────────────────────────┐    │
  │  │        OpenShell Sandbox (NVIDIA)            │    │
  │  │  Network:  inference.local only (OPA proxy)  │    │
  │  │  FS:       ~/.hermes/ + /sandbox/ (Landlock) │    │
  │  │  Process:  non-root, Seccomp BPF             │    │
  │  │  Inference: credential stripping + injection │    │
  │  └─────────────────────────────────────────────┘    │
  └─────────────────────────────────────────────────────┘
         │  OpenShell privacy router intercepts
         │  inference.local calls and routes to:
         ▼
  llama.cpp (local, Metal/CUDA)  OR  NVIDIA API  OR  OpenAI  OR  Anthropic
```

OpenShell intercepts every call to `inference.local` inside the sandbox and routes it to the configured backend. Hermes never knows it's sandboxed.

---

## Quick Start

### Path 1 — Docker (no NVIDIA hardware required)

Full Hermes + llama.cpp in one command. No sandbox, but all Hermes features work.

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw

cp .env.example .env          # set MODEL_FILE and optionally bot tokens
# drop your .gguf model into models/

./scripts/setup.sh            # build image, create ~/.hermes/config.yaml

docker compose up             # start everything
docker compose --profile gpu up  # GPU variant (requires NVIDIA Container Toolkit)
```

Test Hermes inside the container:

```bash
docker exec -it hermesclaw hermes chat -q "hello"
docker exec -it hermesclaw hermes status
docker exec -it hermesclaw hermes skills list
```

---

### Path 2 — OpenShell Sandbox (full hardware enforcement)

```bash
# Install OpenShell (requires NVIDIA account)
curl -fsSL https://www.nvidia.com/openshell.sh | bash

git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw

./scripts/setup.sh            # build image, register policy + profile

# Start llama.cpp on the host
llama-server -m models/<model>.gguf --port 8080 -ngl 99

./scripts/start.sh            # or: hermesclaw start
```

Or use the `hermesclaw` CLI for everything:

```bash
./scripts/hermesclaw onboard       # check all prerequisites
./scripts/hermesclaw start         # start with default (strict) policy
./scripts/hermesclaw start --gpu --policy gateway  # GPU + messaging enabled
./scripts/hermesclaw status        # health + inference config + memory/skill counts
./scripts/hermesclaw chat "hello"  # one-shot message
./scripts/hermesclaw connect       # interactive shell inside sandbox
./scripts/hermesclaw logs          # stream logs
```

---

## Policy Presets

Switch security posture **without restarting** the sandbox:

```bash
./scripts/hermesclaw policy-list          # show all presets

./scripts/hermesclaw policy-set strict    # inference only (default)
./scripts/hermesclaw policy-set gateway   # + Telegram + Discord
./scripts/hermesclaw policy-set permissive  # + web search + GitHub skills
```

| Preset | Inference | Telegram/Discord | Web Search | GitHub Skills |
|--------|:---------:|:----------------:|:----------:|:-------------:|
| `strict` | ✅ | ❌ | ❌ | ❌ |
| `gateway` | ✅ | ✅ | ❌ | ❌ |
| `permissive` | ✅ | ✅ | ✅ | ✅ |

---

## What OpenShell Enforces

| Layer | Mechanism | Rule |
|-------|-----------|------|
| **Network** | OPA + HTTP CONNECT proxy | Egress to approved hosts only; all else blocked |
| **Filesystem** | Landlock LSM | `~/.hermes/` + `/sandbox/` + `/tmp/` only |
| **Process** | Seccomp BPF | `ptrace`, `mount`, `kexec_load`, `perf_event_open`, `process_vm_*` blocked |
| **Inference** | Privacy router | Credentials stripped from agent; backend credentials injected by OpenShell |

All four layers are enforced **out-of-process** — even a fully compromised Hermes instance cannot override them.

---

## Hermes Features Inside the Sandbox

Everything that doesn't need unrestricted internet access works out of the box:

| Feature | Status | Notes |
|---------|:------:|-------|
| `hermes chat` | ✅ | Routes via `inference.local` → llama.cpp |
| Persistent memory (MEMORY.md + USER.md) | ✅ | Volume-mounted on host, survives sandbox recreation |
| Self-improving skills (auto-create) | ✅ | DSPy + GEPA optimization, stored in `~/.hermes/skills/` |
| 40+ built-in tools | ✅ | Terminal, file, vision, voice, image gen, browser, RL, etc. |
| Cron / scheduled tasks | ✅ | `hermes cron create` |
| Multi-agent delegation | ✅ | `hermes delegate_task` |
| MCP server integration | ✅ | `hermes mcp` |
| IDE integration (ACP) | ✅ | VS Code, JetBrains, Zed |
| Python SDK | ✅ | `from run_agent import AIAgent` |
| Plugin architecture | ✅ | Drop `.py` into `~/.hermes/plugins/` |
| Telegram gateway | ✅ | With `gateway` or `permissive` policy |
| Discord gateway | ✅ | With `gateway` or `permissive` policy |
| Signal gateway | ✅ | With `gateway` policy + signal-cli bridge |
| Slack / WhatsApp / Email | ✅ | With `permissive` policy |
| Voice notes (all platforms) | ✅ | Auto-transcribed before passing to agent |
| Web search tools | ✅ | With `permissive` policy (DuckDuckGo) |
| Skills download (GitHub) | ✅ | With `permissive` policy |

---

## hermesclaw CLI

```
hermesclaw onboard              First-time setup and prerequisite check
hermesclaw start [--gpu] [--policy PRESET]
                                Start sandbox (OpenShell) or docker compose
hermesclaw stop                 Stop sandbox (memories + skills preserved)
hermesclaw status               Show inference config + memory/skill counts
hermesclaw connect              Open interactive shell inside sandbox
hermesclaw logs [--follow]      Stream sandbox logs
hermesclaw policy-list          List available policy presets
hermesclaw policy-set PRESET    Hot-swap policy without restart
hermesclaw doctor               End-to-end diagnostic
hermesclaw chat "prompt"        One-shot message to Hermes
hermesclaw version              Print version
hermesclaw uninstall            Remove Docker image (data preserved)
```

---

## HermesClaw vs NemoClaw

Full comparison table and test results: [docs/test-results.md](docs/test-results.md)

**TL;DR:**

| | HermesClaw | NemoClaw |
|---|---|---|
| **Agent** | Hermes (NousResearch, 18k ⭐) | OpenClaw (NVIDIA) |
| **Sandbox** | OpenShell | OpenShell |
| **Tools** | 40+ (web, browser, vision, voice, RL, …) | ~10 |
| **Memory** | Persistent MEMORY.md + USER.md | None |
| **Self-improving skills** | Yes (DSPy + GEPA) | No |
| **Messaging gateway** | Telegram, Discord, Signal, Slack, WhatsApp, Email | None |
| **Voice** | Push-to-talk + voice notes on all platforms | No |
| **Python SDK** | Yes (`from run_agent import AIAgent`) | No |
| **MCP servers** | Yes | No |
| **IDE integration** | VS Code, JetBrains, Zed (ACP) | No |
| **Inference providers** | Local, NVIDIA, OpenAI, Anthropic, Ollama, vLLM | Same |
| **macOS support** | Yes (Docker mode) | No (Linux required) |
| **Without NVIDIA GPU** | Yes (CPU Docker mode) | No |
| **First implementation** | **This repo** | NVIDIA official |

---

## Personalise Hermes

```bash
cp configs/persona.yaml.example configs/persona.yaml
```

Edit `configs/persona.yaml` — your name, role, expertise, ticker watchlist, response style. Hermes loads this into every session.

For deeper personalisation, edit `~/.hermes/SOUL.md` — this is the identity file that goes directly into Hermes's system prompt.

---

## Diagnostics

```bash
./scripts/doctor.sh           # full diagnostic report
./scripts/doctor.sh --quick   # skip slow checks

./scripts/test.sh             # run feature comparison test suite
./scripts/test.sh --quick     # skip live inference tests
```

---

## Project Structure

```
hermesclaw/
├── Dockerfile                         # Hermes Agent on debian:bookworm-slim
├── docker-compose.yml                 # llama-server + hermesclaw (CPU + GPU profiles)
├── .env.example                       # MODEL_FILE, N_GPU_LAYERS, bot tokens
├── openshell/
│   ├── hermesclaw-policy.yaml         # Default policy (inference only + commented extras)
│   ├── hermesclaw-profile.yaml        # Sandbox profile reference (image, mounts, inference)
│   ├── policy-strict.yaml             # Strict preset: inference only
│   ├── policy-gateway.yaml            # Gateway preset: inference + Telegram + Discord
│   └── policy-permissive.yaml         # Permissive preset: everything
├── configs/
│   ├── hermes.yaml.example            # Full Hermes config (memory, skills, gateway, tools)
│   └── persona.yaml.example           # User persona for personalised responses
├── scripts/
│   ├── hermesclaw                     # Main CLI (start/stop/status/connect/policy-set/doctor)
│   ├── setup.sh                       # One-time setup
│   ├── start.sh                       # Start (OpenShell or Docker)
│   ├── status.sh                      # Quick status check
│   ├── doctor.sh                      # End-to-end diagnostic
│   └── test.sh                        # Feature comparison test suite
├── docs/
│   ├── features.md                    # Full feature reference
│   └── test-results.md                # Generated comparison table (./scripts/test.sh)
├── models/                            # Drop .gguf model weights here
└── knowledge/                         # Drop documents here (mounted read-only as RAG context)
```

---

## For the NVIDIA and Hermes Teams

This is the first public implementation of Hermes Agent running inside OpenShell. The policy and profile format is based on the official OpenShell schema (`version: 1`, `filesystem_policy`, `landlock`, `process`, `network_policies`). If anything needs correction, pull requests are very welcome.

If NVIDIA or NousResearch want to make this official or collaborate, we'd love to hear from you.

---

## Related

- [hermes-agent-nemoclaw-openclaw](https://github.com/TheAiSingularity/hermes-agent-nemoclaw-openclaw) — The parent repo: Hermes + NemoClaw + lightweight bots in one stack
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — NousResearch's agent (18k ⭐)
- [NemoClaw](https://github.com/NVIDIA/NemoClaw) — NVIDIA's OpenClaw + OpenShell
- [OpenShell](https://docs.nvidia.com/openshell/latest/) — NVIDIA's hardware-enforced AI sandbox
