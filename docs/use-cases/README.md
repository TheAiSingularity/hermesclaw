# HermesClaw — Use Case Guides

Seven end-to-end guides for deploying HermesClaw in real scenarios. Each guide covers prerequisites, step-by-step setup, verification, and a NemoClaw comparison.

---

## Which guide is for you?

| Who you are | Stack | Guide |
|-------------|-------|-------|
| Researcher / writer | Docker + Telegram + arXiv digest | [01-researcher](01-researcher/) |
| Developer | Docker + VS Code ACP integration | [02-developer](02-developer/) |
| Home automation | Docker + Home Assistant MCP + Telegram | [03-home-automation](03-home-automation/) |
| Data analyst | Docker + Postgres MCP + anomaly alerts | [04-data-analyst](04-data-analyst/) |
| Small business | Docker + Slack support bot | [05-small-business](05-small-business/) |
| Privacy-regulated industry | OpenShell sandbox + strict policy | [06-privacy-regulated](06-privacy-regulated/) |
| Trader / quant | Docker + Qwen-7B + Telegram alerts | [07-trader](07-trader/) |

---

## HermesClaw vs NemoClaw — Use-Case Compatibility

NemoClaw (alpha, March 2026) is NVIDIA's reference stack for OpenClaw agents. It provides the OpenShell sandbox, 25+ tools, messaging gateways (Telegram, Discord, Slack, WhatsApp, and more via OpenClaw), and supports multiple inference providers (OpenAI, Anthropic, Google Gemini, NVIDIA NIM). **Local model inference is broken on macOS** (DNS bug, issue #260) — cloud APIs required on macOS.

| Use case | HermesClaw | NemoClaw | Key difference |
|----------|:----------:|:--------:|----------------|
| Researcher (cross-session memory + digest) | ✅ | ⚠️ | NemoClaw: Telegram ✅, but no persistent MEMORY.md/USER.md across sessions |
| Developer (VS Code ACP) | ✅ | ⚠️ | NemoClaw: no ACP — OpenClaw has its own IDE integration |
| Home automation (HA MCP + Telegram) | ✅ | ⚠️ | NemoClaw: Telegram ✅, but no MCP server support (unconfirmed) |
| Data analyst (Postgres MCP + alerts) | ✅ | ⚠️ | NemoClaw: Slack/Telegram alerts ✅, but no Postgres MCP (unconfirmed), no persistent memory |
| Small business (Slack bot) | ✅ | ✅ | Both support Slack natively — difference is local vs cloud inference |
| Privacy-regulated (air-gapped, local inference) | ✅ | ⚠️ | NemoClaw: sandbox ✅, but local inference broken on macOS — cloud API required (data leaves network) |
| Trader (local latency + Telegram) | ✅ | ⚠️ | NemoClaw: Telegram ✅, but local inference broken on macOS — cloud API adds 200–500ms latency |

**Summary**: NemoClaw has more capabilities than previously documented — messaging gateways, voice, and multi-provider inference. The remaining HermesClaw advantages are: **persistent cross-session memory** (MEMORY.md/USER.md), **self-improving skills** (DSPy + GEPA), **MCP server support**, and **local inference that works on macOS**. For privacy-sensitive and low-latency use cases, local inference is the decisive factor.

---

## Skills library

Each use case has a corresponding installable Hermes skill. Skills are instruction files that Hermes reads to execute recurring workflows (weekly digests, anomaly detection, market alerts).

```bash
# Install from the repo root
./skills/install.sh research-digest      # Researcher
./skills/install.sh code-review          # Developer
./skills/install.sh home-assistant       # Home automation
./skills/install.sh anomaly-detection    # Data analyst
./skills/install.sh slack-support        # Small business
./skills/install.sh market-alerts        # Trader
```

Full documentation: [skills/README.md](../../skills/README.md)

---

## Common prerequisites

All Docker-mode guides share these baseline requirements:

- **Docker Desktop** (or Docker Engine + Compose) — [install](https://docs.docker.com/get-docker/)
- **A GGUF model file** in `models/` — recommended: `Qwen3-4B-Q4_K_M.gguf` (~2.5 GB)
- **Git** to clone the repo

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
# Drop your .gguf model into models/
```

OpenShell-mode (guide 06) additionally requires:
- Linux host (Ubuntu 22.04+) or macOS Apple Silicon with Colima
- NVIDIA OpenShell runtime — [install](https://docs.nvidia.com/openshell/latest/)
