<p align="center">
  <img src="assets/banner.png" alt="HermesClaw" width="100%">
</p>

<p align="center">
  <a href="https://github.com/TheAiSingularity/hermesclaw/actions/workflows/ci.yml"><img src="https://github.com/TheAiSingularity/hermesclaw/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/TheAiSingularity/hermesclaw/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/TheAiSingularity/hermesclaw/blob/main/CONTRIBUTING.md"><img src="https://img.shields.io/badge/contributions-welcome-brightgreen.svg" alt="Contributions welcome"></a>
  <a href="https://github.com/TheAiSingularity/hermesclaw/blob/main/CHANGELOG.md"><img src="https://img.shields.io/badge/version-0.2.0-orange.svg" alt="Version"></a>
</p>

**Hermes Agent (NousResearch) running inside NVIDIA OpenShell.**

NVIDIA built OpenShell to hardware-enforce AI agent behavior — blocking network egress, filesystem writes, and dangerous syscalls at the kernel level. NemoClaw (OpenClaw + OpenShell) is NVIDIA's reference implementation. HermesClaw is a community implementation applying the same runtime to Hermes Agent.

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

Full Hermes + llama.cpp. No sandbox, but all Hermes features work.

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw

cp .env.example .env          # set MODEL_FILE and optionally bot tokens
# drop your .gguf model into models/
# e.g. curl -L -o models/Qwen3-4B.gguf <huggingface-url>

./scripts/setup.sh            # build image, create ~/.hermes/config.yaml

# Start llama-server on your HOST machine first (Hermes connects to it via host.docker.internal)
# macOS:
brew install llama.cpp
llama-server -m models/your-model.gguf --port 8080 --ctx-size 32768 -ngl 99 --log-disable

# Linux (see https://github.com/ggerganov/llama.cpp#build for build instructions):
# llama-server -m models/your-model.gguf --port 8080 --ctx-size 32768 -ngl 99

# Then start the Hermes container:
docker compose up
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

## Use Cases

Seven end-to-end guides for real deployment scenarios — each with prerequisites, step-by-step setup, verification, and a NemoClaw comparison:

| Who you are | Stack | Guide |
|-------------|-------|-------|
| Researcher / writer | Docker + Telegram + weekly arXiv digest | [docs/use-cases/01-researcher/](docs/use-cases/01-researcher/) |
| Developer | Docker + VS Code ACP integration | [docs/use-cases/02-developer/](docs/use-cases/02-developer/) |
| Home automation | Docker + Home Assistant MCP + Telegram | [docs/use-cases/03-home-automation/](docs/use-cases/03-home-automation/) |
| Data analyst | Docker + Postgres MCP + anomaly alerts | [docs/use-cases/04-data-analyst/](docs/use-cases/04-data-analyst/) |
| Small business | Docker + Slack support bot | [docs/use-cases/05-small-business/](docs/use-cases/05-small-business/) |
| Privacy-regulated industry | OpenShell sandbox + strict policy | [docs/use-cases/06-privacy-regulated/](docs/use-cases/06-privacy-regulated/) |
| Trader / quant | Docker + Qwen-7B + Telegram alerts | [docs/use-cases/07-trader/](docs/use-cases/07-trader/) |

Full index and NemoClaw compatibility table: [docs/use-cases/README.md](docs/use-cases/)

---

## Skills Library

Pre-built Hermes skills that encode recurring workflows. Install one command and tell Hermes to run it:

```bash
./skills/install.sh research-digest     # weekly arXiv digest → Telegram
./skills/install.sh code-review         # local code review (CLI or VS Code ACP)
./skills/install.sh home-assistant      # natural language smart home control
./skills/install.sh anomaly-detection   # daily DB anomaly detection → Slack/Telegram
./skills/install.sh slack-support       # Slack support bot with knowledge base
./skills/install.sh market-alerts       # watchlist price alerts → Telegram
./skills/install.sh --all               # install everything
```

After installing, invoke from anywhere:
```bash
hermesclaw chat "run research-digest"
# or in Telegram/Slack: "run the anomaly-detection skill"
```

Skills index and usage: [skills/README.md](skills/)

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

## Use Cases

### Use case 1 — Personal research assistant with persistent memory

You are a researcher who regularly synthesises papers, market reports, and technical docs. You want an AI assistant that remembers your prior work and improves itself over time.

**With HermesClaw:**

```bash
# Start the assistant (strict policy — inference only, nothing leaves your machine)
hermesclaw start --policy strict

# Ask Hermes to research a topic
hermesclaw chat "summarise the last 6 months of transformer architecture improvements and save key findings to memory"
```

What happens inside the sandbox:
1. Hermes uses `web_search` and `web_extract` to gather papers
2. It writes a summary to `~/.hermes/memories/` — persists across sandbox restarts
3. After 5+ tool calls it auto-creates a skill (`research_synthesis`) with DSPy + GEPA optimisation
4. Next session: Hermes loads its memory and the new skill, and builds on prior research

**Not possible with NemoClaw / OpenClaw:** OpenClaw does not have Hermes-style persistent MEMORY.md / USER.md or self-improving skills via DSPy + GEPA. NemoClaw supports multiple inference providers (OpenAI, Anthropic, NVIDIA NIM), but cross-session memory that builds a user model over months is specific to Hermes.

---

### Use case 2 — Local AI gateway on your own hardware

You want an AI assistant accessible from your phone (Telegram) and laptop (Discord), running on your home server, with all inference staying on-device. No data leaves your network.

```bash
# Configure messaging (one-time)
docker compose run --rm hermesclaw hermes gateway setup   # add bot tokens interactively

# Start with gateway policy (inference + Telegram + Discord allowed, everything else blocked)
hermesclaw start --policy gateway
```

What happens:
- Hermes runs inside OpenShell — the kernel blocks all outbound traffic except `inference.local` (LLM) and `api.telegram.org` / `discord.com`
- Your Telegram bot and Discord bot share one Hermes session with shared memory
- Voice notes you send are auto-transcribed before reaching the model
- The OpenShell sandbox guarantees: even if a skill or plugin goes rogue, it cannot exfiltrate data or access outside-policy hosts

```bash
# Hot-swap to permissive for a web-search session, then back to gateway
hermesclaw policy-set permissive   # unlocks DuckDuckGo + GitHub skills
hermesclaw policy-set gateway      # locks back down — no restart required
```

**Where HermesClaw wins here:** NemoClaw (via OpenClaw) does support Telegram and Discord, but routes inference to cloud APIs on macOS — your voice notes and messages pass through an external provider. HermesClaw keeps all inference local: the model runs on your hardware, nothing leaves your network.

---

## HermesClaw vs NemoClaw

Full comparison table and test results: [docs/test-results.md](docs/test-results.md)

**TL;DR:**

| | HermesClaw | NemoClaw |
|---|---|---|
| **Agent** | Hermes (NousResearch) | OpenClaw (wrapped by NemoClaw) |
| **Sandbox** | OpenShell (optional) | OpenShell |
| **Tools** | 40+ (web, browser, vision, voice, RL, …) | 25+ via OpenClaw (browser, shell, voice, camera, Live Canvas) |
| **Memory** | Persistent MEMORY.md + USER.md | Session memory only — no cross-session persistence |
| **Self-improving skills** | Yes (DSPy + GEPA) | No |
| **Messaging gateway** | Telegram, Discord, Signal, Slack, WhatsApp, Email | Telegram, Discord, Slack, WhatsApp, Signal, Google Chat, Teams (via OpenClaw) |
| **Voice** | Push-to-talk + voice notes on all platforms | Yes — wake words + continuous voice (via OpenClaw) |
| **Python SDK** | Yes (`from run_agent import AIAgent`) | No |
| **MCP servers** | Yes | No (unconfirmed) |
| **IDE integration** | VS Code, JetBrains, Zed (ACP) | OpenClaw-native integration (not ACP standard) |
| **Inference providers** | Local llama.cpp, NVIDIA NIM, OpenAI, Anthropic, Ollama, vLLM | OpenAI, Anthropic, Google Gemini, NVIDIA NIM, local Nemotron (Linux only — broken on macOS, issue #260) |
| **macOS support** | Yes — Docker mode + local inference | Yes — sandbox + cloud inference (local model broken, issue #260) |
| **Without NVIDIA GPU** | Yes (CPU Docker mode) | Yes — with cloud inference (OpenAI/Anthropic/NVIDIA NIM) |
| **Status** | Community implementation | NVIDIA official (alpha) |

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

## Contributing

HermesClaw is open to contributions from the community — especially:

- **OpenShell policy corrections** — if you have access to a real OpenShell environment, correctness fixes are the highest-value contribution
- **New policy presets** — homeassistant, coding, research, etc.
- **New gateway platform policies** — Slack, WhatsApp, Signal network rules
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

## For the NVIDIA and Hermes Teams

This is the first public implementation of Hermes Agent running inside OpenShell. The policy and profile format is based on the official OpenShell schema (`version: 1`, `filesystem_policy`, `landlock`, `process`, `network_policies`). If anything needs correction, pull requests are very welcome.

If NVIDIA or NousResearch want to make this official or collaborate, we'd love to hear from you.

---

## Related

- [hermes-agent-nemoclaw-openclaw](https://github.com/TheAiSingularity/hermes-agent-nemoclaw-openclaw) — The parent repo: Hermes + NemoClaw + lightweight bots in one stack
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — NousResearch's agent (18k ⭐)
- [NemoClaw](https://github.com/NVIDIA/NemoClaw) — NVIDIA's OpenClaw + OpenShell
- [OpenShell](https://docs.nvidia.com/openshell/latest/) — NVIDIA's hardware-enforced AI sandbox
