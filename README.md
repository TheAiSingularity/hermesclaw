<p align="center">
  <img src="assets/banner.png" alt="HermesClaw" width="100%">
</p>

<p align="center">
  <a href="https://github.com/TheAiSingularity/hermesclaw/actions/workflows/ci.yml"><img src="https://github.com/TheAiSingularity/hermesclaw/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/TheAiSingularity/hermesclaw/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/TheAiSingularity/hermesclaw/blob/main/CONTRIBUTING.md"><img src="https://img.shields.io/badge/contributions-welcome-brightgreen.svg" alt="Contributions welcome"></a>
  <a href="https://github.com/TheAiSingularity/hermesclaw/blob/main/CHANGELOG.md"><img src="https://img.shields.io/badge/version-0.3.0-orange.svg" alt="Version"></a>
</p>

**Hermes Agent (NousResearch) running inside NVIDIA OpenShell.**

NVIDIA built OpenShell to hardware-enforce AI agent behavior — blocking network egress, filesystem writes, and dangerous syscalls at the kernel level. HermesClaw is a community implementation that puts Hermes Agent inside the same sandbox. The agent gets its full capability stack while the OS enforces hard limits. If a skill goes rogue, the kernel stops it.

---

## Table of Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
  - [Path 1 — Docker (no NVIDIA hardware)](#path-1--docker-no-nvidia-hardware-required)
  - [Path 2 — OpenShell Sandbox](#path-2--openshell-sandbox-full-hardware-enforcement)
- [What OpenShell Enforces](#what-openshell-enforces)
- [Policy Presets](#policy-presets)
- [Hermes Features](#hermes-features-inside-the-sandbox)
- [Skills Library](#skills-library)
- [Use Cases](#use-cases)
- [HermesClaw vs NemoClaw](#hermesclaw-vs-nemoclaw)
- [CLI Reference](#hermesclaw-cli)
- [Personalise Hermes](#personalise-hermes)
- [Project Structure](#project-structure)
- [Diagnostics & Testing](#diagnostics--testing)
- [Contributing](#contributing)
- [Related Projects](#related)

---

## Architecture

<p align="center">
  <img src="assets/architecture.png" alt="HermesClaw Architecture" width="780">
</p>

OpenShell intercepts every call to `inference.local` inside the sandbox and routes it to the configured backend. Hermes never knows it's sandboxed.

---

## Quick Start

### Path 1 — Docker (no NVIDIA hardware required)

All Hermes features work. No kernel-level sandbox enforcement — Docker isolation only.

**Step 1 — Clone and configure**
```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
```

Edit `.env` and set `MODEL_FILE` to your model filename. Download a model into `models/`:
```bash
# Example — Qwen3 4B (2.5 GB):
curl -L -o models/Qwen3-4B-Q4_K_M.gguf \
  https://huggingface.co/bartowski/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf
```

**Step 2 — Build the image**
```bash
./scripts/setup.sh
```

**Step 3 — Start llama-server on your host** (Hermes connects to it via `host.docker.internal`)

macOS:
```bash
brew install llama.cpp
llama-server -m models/your-model.gguf --port 8080 --ctx-size 32768 -ngl 99 --log-disable
```

Linux ([build instructions](https://github.com/ggerganov/llama.cpp#build)):
```bash
llama-server -m models/your-model.gguf --port 8080 --ctx-size 32768 -ngl 99
```

> **Note:** `--ctx-size 32768` is required. Hermes's system prompt alone is ~11k tokens — lower values cause context overflow on every query.

**Step 4 — Start Hermes**
```bash
docker compose up -d
docker exec -it hermesclaw hermes chat -q "hello"
```

---

### Path 2 — OpenShell Sandbox (full hardware enforcement)

Requires Linux + NVIDIA GPU + OpenShell installed.

```bash
# Install OpenShell (requires NVIDIA account)
curl -fsSL https://www.nvidia.com/openshell.sh | bash

git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw

# Build image + register OpenShell policy and profile
./scripts/setup.sh

# Start llama-server on the host
llama-server -m models/your-model.gguf --port 8080 --ctx-size 32768 -ngl 99

# Start Hermes inside the sandbox
./scripts/start.sh
```

Or use the `hermesclaw` CLI:
```bash
./scripts/hermesclaw onboard       # check all prerequisites
./scripts/hermesclaw start         # start with default (strict) policy
./scripts/hermesclaw start --gpu --policy gateway  # GPU + messaging enabled
./scripts/hermesclaw chat "hello"  # one-shot message
```

---

## What OpenShell Enforces

| Layer | Mechanism | Rule |
|-------|-----------|------|
| **Network** | OPA + HTTP CONNECT proxy | Egress to approved hosts only — all else blocked |
| **Filesystem** | Landlock LSM | `~/.hermes/` + `/sandbox/` + `/tmp/` only |
| **Process** | Seccomp BPF | `ptrace`, `mount`, `kexec_load`, `perf_event_open`, `process_vm_*` blocked |
| **Inference** | Privacy router | Credentials stripped from agent; backend credentials injected by OpenShell |

All four layers are enforced **out-of-process** — even a fully compromised Hermes instance cannot override them.

---

## Policy Presets

Switch security posture **without restarting** the sandbox:

```bash
./scripts/hermesclaw policy-set strict      # inference only (default)
./scripts/hermesclaw policy-set gateway     # + Telegram + Discord
./scripts/hermesclaw policy-set permissive  # + web search + GitHub skills
```

| Preset | Inference | Telegram / Discord | Web Search | GitHub Skills |
|--------|:---------:|:------------------:|:----------:|:-------------:|
| `strict` | ✅ | ❌ | ❌ | ❌ |
| `gateway` | ✅ | ✅ | ❌ | ❌ |
| `permissive` | ✅ | ✅ | ✅ | ✅ |

---

## Hermes Features Inside the Sandbox

| Feature | Status | Notes |
|---------|:------:|-------|
| `hermes chat` | ✅ | Routes via `inference.local` → llama.cpp |
| Persistent memory (MEMORY.md + USER.md) | ✅ | Volume-mounted on host, survives sandbox recreation |
| Self-improving skills | ✅ | DSPy + GEPA optimisation, stored in `~/.hermes/skills/` |
| 40+ built-in tools | ✅ | Terminal, file, vision, voice, browser, RL, image gen, etc. |
| Cron / scheduled tasks | ✅ | `hermes cron create` |
| Multi-agent delegation | ✅ | `hermes delegate_task` |
| MCP server integration | ✅ | `hermes mcp` |
| IDE integration (ACP) | ✅ | VS Code, JetBrains, Zed |
| Python SDK | ✅ | `from run_agent import AIAgent` |
| Telegram / Discord gateway | ✅ | Requires `gateway` or `permissive` policy |
| Signal / Slack / WhatsApp / Email | ✅ | Requires `permissive` policy |
| Voice notes (all platforms) | ✅ | Auto-transcribed before passing to model |
| Web search | ✅ | Requires `permissive` policy (DuckDuckGo) |

---

## Skills Library

Pre-built skills that encode recurring workflows. Install with one command, invoke via chat:

```bash
./skills/install.sh research-digest     # weekly arXiv digest → Telegram
./skills/install.sh code-review         # local code review (CLI or VS Code ACP)
./skills/install.sh anomaly-detection   # daily DB anomaly detection → Slack/Telegram
./skills/install.sh market-alerts       # watchlist price alerts → Telegram
./skills/install.sh slack-support       # Slack support bot with knowledge base
./skills/install.sh home-assistant      # natural language smart home control
./skills/install.sh --all               # install everything
```

After installing, invoke from chat or any connected messaging platform:
```bash
docker exec -it hermesclaw hermes chat -q "run research-digest"
# or in Telegram: "run the anomaly-detection skill"
```

Full index: [skills/README.md](skills/)

---

## Use Cases

Seven end-to-end guides covering real deployment scenarios — each with prerequisites, setup steps, automated tests, and a NemoClaw comparison:

| Who | Setup | Guide |
|-----|-------|-------|
| Researcher / writer | Docker + Telegram + weekly arXiv digest | [01-researcher](docs/use-cases/01-researcher/) |
| Developer | Docker + VS Code ACP | [02-developer](docs/use-cases/02-developer/) |
| Home automation | Docker + Home Assistant MCP + Telegram | [03-home-automation](docs/use-cases/03-home-automation/) |
| Data analyst | Docker + Postgres MCP + anomaly alerts | [04-data-analyst](docs/use-cases/04-data-analyst/) |
| Small business | Docker + Slack support bot + knowledge base | [05-small-business](docs/use-cases/05-small-business/) |
| Privacy-regulated | OpenShell sandbox + strict policy (HIPAA/legal) | [06-privacy-regulated](docs/use-cases/06-privacy-regulated/) |
| Trader / quant | Docker + local model + Telegram price alerts | [07-trader](docs/use-cases/07-trader/) |

Full index and NemoClaw compatibility table: [docs/use-cases/](docs/use-cases/)

---

## HermesClaw vs NemoClaw

Full comparison and test results: [docs/test-results.md](docs/test-results.md) · [docs/test-results-uc.md](docs/test-results-uc.md)

| | HermesClaw | NemoClaw |
|---|---|---|
| **Agent** | Hermes (NousResearch) | OpenClaw (wrapped by NemoClaw) |
| **Sandbox** | OpenShell (optional) | OpenShell |
| **Tools** | 40+ (web, browser, vision, voice, RL, …) | 25+ via OpenClaw |
| **Memory** | Persistent MEMORY.md + USER.md | Session only — no cross-session persistence |
| **Self-improving skills** | Yes (DSPy + GEPA) | No |
| **Messaging** | Telegram, Discord, Signal, Slack, WhatsApp, Email | Telegram, Discord, Slack, WhatsApp, Signal, Teams (via OpenClaw) |
| **MCP servers** | Yes | Unconfirmed |
| **IDE integration** | VS Code, JetBrains, Zed (ACP) | OpenClaw-native (not ACP) |
| **Inference providers** | llama.cpp, NVIDIA NIM, OpenAI, Anthropic, Ollama, vLLM | OpenAI, Anthropic, Gemini, NVIDIA NIM, local (Linux only) |
| **macOS local inference** | ✅ Works | ❌ Broken (DNS bug, issue #260) |
| **Without NVIDIA GPU** | ✅ CPU Docker mode | ✅ Cloud inference |
| **Status** | Community implementation | NVIDIA official (alpha) |

---

## hermesclaw CLI

```
hermesclaw onboard                    First-time setup and prerequisite check
hermesclaw start [--gpu] [--policy]   Start sandbox (OpenShell) or docker compose
hermesclaw stop                       Stop sandbox (memories + skills preserved)
hermesclaw status                     Show inference config + memory/skill counts
hermesclaw connect                    Open interactive shell inside sandbox
hermesclaw logs [--follow]            Stream sandbox logs
hermesclaw policy-list                List available policy presets
hermesclaw policy-set PRESET          Hot-swap policy without restart
hermesclaw doctor                     End-to-end diagnostic
hermesclaw chat "prompt"              One-shot message to Hermes
hermesclaw version                    Print version
hermesclaw uninstall                  Remove Docker image (data preserved)
```

---

## Personalise Hermes

```bash
cp configs/persona.yaml.example configs/persona.yaml
```

Edit `configs/persona.yaml` — set your name, role, expertise, ticker watchlist, and response style. Hermes loads this into every session. For deeper personalisation, edit `~/.hermes/SOUL.md` — this goes directly into the system prompt.

---

## Project Structure

```
hermesclaw/
├── Dockerfile                          # Hermes Agent on debian:bookworm-slim
├── docker-compose.yml                  # Hermes container (llama-server runs on host)
├── .env.example                        # MODEL_FILE, CTX_SIZE, bot tokens
├── openshell/
│   ├── hermesclaw-policy.yaml          # Default policy
│   ├── hermesclaw-profile.yaml         # Sandbox profile
│   ├── policy-strict.yaml             # Inference only
│   ├── policy-gateway.yaml            # Inference + Telegram + Discord
│   └── policy-permissive.yaml         # Everything
├── configs/
│   ├── hermes.yaml.example            # Full Hermes config
│   └── persona.yaml.example           # User persona
├── skills/
│   ├── install.sh                     # Skill installer
│   ├── anomaly-detection/             # DB anomaly detection (detect.py)
│   ├── market-alerts/                 # Price threshold alerts (monitor.py)
│   ├── code-review/                   # Code review prompts
│   ├── slack-support/                 # FAQ + escalation bot
│   ├── home-assistant/                # HA MCP control
│   └── research-digest/               # Weekly arXiv digest
├── scripts/
│   ├── hermesclaw                     # Main CLI
│   ├── setup.sh                       # One-time setup
│   ├── start.sh / stop.sh / status.sh
│   ├── doctor.sh                      # End-to-end diagnostic
│   ├── test.sh                        # Feature comparison test suite
│   ├── test-setup.sh                  # Use-case test environment setup
│   └── test-uc-01.sh … test-uc-07.sh  # Per-use-case automated tests
├── docs/
│   ├── use-cases/                     # 7 end-to-end use-case guides
│   ├── features.md                    # Full feature reference
│   ├── test-results.md                # Feature comparison table
│   └── test-results-uc.md             # Use-case test results (2026-03-31)
├── knowledge/                         # Drop documents here (RAG context, read-only mount)
└── models/                            # Drop .gguf model weights here
```

---

## Diagnostics & Testing

```bash
# Check your environment
./scripts/doctor.sh           # full diagnostic
./scripts/doctor.sh --quick   # skip slow checks

# Run the feature test suite
./scripts/test.sh             # generates docs/test-results.md
./scripts/test.sh --quick     # skip live inference tests

# Run use-case tests
bash scripts/test-setup.sh          # verify environment
bash scripts/test-uc-01.sh          # researcher
bash scripts/test-uc-04.sh          # data analyst (Postgres + anomaly detection)
bash scripts/test-uc-07.sh          # trader (latency measurement)
```

---

## Contributing

HermesClaw welcomes contributions — especially:

- **OpenShell policy corrections** — if you have access to a real OpenShell environment, correctness fixes are the highest-value contribution
- **New policy presets** — homeassistant, coding, research, etc.
- **New skills** — follow the `SKILL.md` format in any existing skill as a template
- **Real-world test reports** — if you've run HermesClaw on NVIDIA hardware, share your `./scripts/doctor.sh` output

**Quick contributor setup:**
```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
./scripts/doctor.sh --quick    # verify your environment
./scripts/test.sh --quick      # run the feature test suite
shellcheck scripts/hermesclaw  # lint before submitting
```

Full guide: [CONTRIBUTING.md](CONTRIBUTING.md) · [Code of Conduct](CODE_OF_CONDUCT.md) · [Changelog](CHANGELOG.md)

---

## Related

- [hermes-agent-nemoclaw-openclaw](https://github.com/TheAiSingularity/hermes-agent-nemoclaw-openclaw) — The parent repo: Hermes + NemoClaw + lightweight bots in one stack
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — NousResearch's agent (18k ⭐)
- [NemoClaw](https://github.com/NVIDIA/NemoClaw) — NVIDIA's OpenClaw + OpenShell reference implementation
- [OpenShell](https://docs.nvidia.com/openshell/latest/) — NVIDIA's hardware-enforced AI sandbox
