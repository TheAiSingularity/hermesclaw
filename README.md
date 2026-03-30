<p align="center">
  <img src="assets/banner.png" alt="HermesClaw" width="100%">
</p>

**The world's first Hermes Agent sandboxed by NVIDIA OpenShell.**

NVIDIA built OpenShell to hardware-enforce AI agent behavior — blocking network egress, filesystem writes, and dangerous syscalls at the kernel level. They demonstrated it with Claude Code, Codex, and Cursor. They used it to build NemoClaw (OpenClaw + OpenShell). **Nobody had done it for Hermes Agent — until now.**

HermesClaw puts Hermes inside OpenShell. The agent gets its full capability stack (40+ tools, persistent memory, self-improving skills, Telegram/Signal/Discord gateway) while the sandbox enforces hard limits: Hermes can only reach `inference.local` (your llama.cpp), can only write to `~/.hermes/` and `/sandbox/`, and cannot call `ptrace`, `mount`, or `kexec`. If a skill goes rogue, the OS stops it.

---

## Architecture

```
User (Telegram / Signal / Discord / CLI)
         │
         ▼
  ┌─────────────────────────────────────┐
  │        Hermes Agent                 │
  │  memory · skills · 40+ tools        │
  │  ┌───────────────────────────────┐  │
  │  │    OpenShell Sandbox          │  │
  │  │  Network:  inference.local    │  │
  │  │            (all else BLOCKED) │  │
  │  │  FS:       ~/.hermes/ only    │  │
  │  │  Syscalls: ptrace/mount/kexec │  │
  │  │            BLOCKED            │  │
  │  └───────────────────────────────┘  │
  └─────────────────────────────────────┘
         │  OpenShell intercepts
         │  and routes to host
         ▼
  llama.cpp  (port 8080, Metal / CUDA)
  ─── or ───
  Any OpenAI-compatible API
```

OpenShell intercepts every call to `inference.local` inside the sandbox and routes it to the configured endpoint — your local llama.cpp, vLLM, or any cloud API. Hermes never knows it's sandboxed.

---

## Quick Start

### Path 1 — Docker (no NVIDIA hardware required)

Run Hermes + llama.cpp together with a single command. No sandbox, but all Hermes features work.

**Prerequisites:** Docker, a `.gguf` model file

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw

# Copy env file and point it at your model
cp .env.example .env
# Edit .env: set MODEL_FILE and N_GPU_LAYERS

# Drop your model into models/
# (example: models/Qwen3-4B-Q4_K_M.gguf)

# Set up Hermes config
./scripts/setup.sh

# Start everything
docker compose up
```

Verify Hermes is alive inside the container:

```bash
docker exec -it hermesclaw hermes chat -q "hello"
docker exec -it hermesclaw ls /root/.hermes/memories/
```

---

### Path 2 — OpenShell Sandbox (full hardware enforcement)

**Prerequisites:** Docker, NVIDIA GPU, OpenShell CLI, a `.gguf` model

```bash
# Install OpenShell (requires NVIDIA account)
curl -fsSL https://www.nvidia.com/openshell.sh | bash

git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw

# Build image + register policy and profile
./scripts/setup.sh

# Start llama.cpp on the host
llama-server -m models/<model>.gguf --port 8080 -ngl 99

# Launch Hermes inside the sandbox
./scripts/start.sh
```

Check status:

```bash
./scripts/status.sh
openshell sandbox status hermesclaw-1
```

---

## What OpenShell Enforces

| Layer | Rule | Why it matters |
|-------|------|----------------|
| Network | Egress only to `inference.local` (80/443) | Hermes tools can't exfiltrate data or phone home |
| Network | All other outbound traffic blocked | Rogue skills can't download payloads |
| Filesystem | Read/write: `~/.hermes/`, `/sandbox/`, `/tmp` | Memories are contained; host filesystem untouched |
| Filesystem | All other paths: deny | Skills can't read `/etc/passwd`, SSH keys, etc. |
| Syscalls | `ptrace`, `mount`, `umount2`, `kexec_load`, `perf_event_open`, `process_vm_readv/writev` blocked | Container escape vectors closed |

The policy is in [`openshell/hermesclaw-policy.yaml`](openshell/hermesclaw-policy.yaml). The profile (inference routing, resource limits, mounts) is in [`openshell/hermesclaw-profile.yaml`](openshell/hermesclaw-profile.yaml).

---

## Hermes Features Inside the Sandbox

Everything in Hermes that doesn't need unrestricted internet access works:

| Feature | Status | Notes |
|---------|--------|-------|
| `hermes chat` | Works | Routes through `inference.local` → llama.cpp |
| `hermes gateway` (Telegram) | Works | Outbound to Telegram is allowed if you add it to policy |
| `hermes gateway` (Signal) | Works | Same — add signal-cli endpoint |
| Persistent memory | Works | Stored in `/root/.hermes/memories/` (volume-mounted) |
| Self-improving skills | Works | Skills written to `/root/.hermes/skills/` |
| 40+ built-in tools | Mostly works | Tools that need external APIs require policy egress rules |
| Web search tools | Blocked by default | Uncomment `api.duckduckgo.com` in policy to allow |

To enable web search, uncomment the `duckduckgo.com` line in `openshell/hermesclaw-policy.yaml` and re-apply the policy:

```yaml
network:
  egress:
    - host: api.duckduckgo.com
      port: 443
      protocol: tcp
```

```bash
openshell policy apply openshell/hermesclaw-policy.yaml
```

---

## Personalise Hermes

Copy the example persona config and fill it in:

```bash
cp configs/persona.yaml.example configs/persona.yaml
```

Edit `configs/persona.yaml` — your name, role, expertise, ticker watchlist, preferred response style, and context. Hermes uses this to personalise all responses.

---

## Comparison

| | HermesClaw | NemoClaw | Plain Hermes |
|---|---|---|---|
| Agent | Hermes (NousResearch) | OpenClaw (NVIDIA) | Hermes (NousResearch) |
| Sandbox | OpenShell | OpenShell | None |
| Inference | llama.cpp / any OpenAI API | llama.cpp / any OpenAI API | Any |
| Memory | Persistent (`~/.hermes/memories/`) | N/A | Persistent |
| Tools | 40+ | OpenClaw tools | 40+ |
| Gateway | Telegram, Signal, Discord | N/A | Telegram, Signal, Discord |
| First implementation | **This repo** | NVIDIA official | N/A |

NemoClaw = OpenClaw + OpenShell. HermesClaw = Hermes + OpenShell. They use the same underlying sandbox runtime; the agents are different.

---

## Project Structure

```
hermesclaw/
├── Dockerfile                    # Hermes Agent inside debian:bookworm-slim
├── docker-compose.yml            # llama-server + hermesclaw (Docker path)
├── .env.example                  # MODEL_FILE, N_GPU_LAYERS
├── openshell/
│   ├── hermesclaw-policy.yaml    # Network / filesystem / syscall rules
│   └── hermesclaw-profile.yaml  # Inference routing, mounts, resource limits
├── configs/
│   ├── hermes.yaml.example       # Hermes config (inference.local endpoint)
│   └── persona.yaml.example      # User persona for personalised responses
├── scripts/
│   ├── setup.sh                  # One-time setup (Docker + OpenShell)
│   ├── start.sh                  # Start sandbox or docker compose
│   └── status.sh                 # Health check
├── models/                       # Drop .gguf files here
└── knowledge/                    # Drop documents here (mounted read-only)
```

---

## For the NVIDIA and Hermes Teams

This is the first public implementation of Hermes Agent running inside OpenShell. We've made a best-effort at the policy and profile format based on public NemoClaw examples — if the format needs corrections, pull requests are very welcome.

If NVIDIA or NousResearch want to make this official, we'd be happy to transfer the repo or collaborate. The goal is simple: give Hermes users a sandbox story as strong as what OpenClaw users already have.

Issues, corrections, and contributions welcome.

---

## Related

- [hermes-agent-nemoclaw-openclaw](https://github.com/TheAiSingularity/hermes-agent-nemoclaw-openclaw) — The parent repo: Hermes + NemoClaw + lightweight bots in one stack
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — NousResearch's agent (18k stars)
- [NemoClaw](https://github.com/NVIDIA/NemoClaw) — NVIDIA's OpenClaw + OpenShell implementation
- [OpenShell](https://www.nvidia.com/openshell) — NVIDIA's hardware-enforced AI agent sandbox
