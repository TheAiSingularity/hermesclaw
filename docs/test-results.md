# HermesClaw × NemoClaw — Feature Comparison & Test Results

*Generated: 2026-03-31 10:59*
*Run `./scripts/test.sh` to refresh.*

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Supported / passed |
| ❌ | Not supported |
| ⚠️ | Partial / workaround available |
| ⏭ | Skipped |

## Results

### Sandbox Security

| Feature | HermesClaw | NemoClaw | Notes |
|---------|:----------:|:--------:|-------|
| Kernel-level filesystem isolation (Landlock) | ✅ | ✅ | Both use Landlock LSM |
| Syscall filtering (Seccomp BPF) | ✅ | ✅ | Both block ptrace, mount, kexec etc. |
| Network egress deny-by-default | ✅ | ✅ | OPA + HTTP CONNECT proxy |
| L7 HTTP method/path inspection | ✅ | ✅ | Both support protocol:rest rules |
| Hot-reloadable network policies | ✅ | ✅ | openshell policy set --wait |
| Static filesystem policy (locked at creation) | ✅ | ✅ | Both via Landlock |
| Process isolation (non-root user) | ✅ | ✅ | run_as_user: hermes |
| Deny-by-default model | ✅ | ✅ | Zero permissions on start |
| Out-of-process policy enforcement | ✅ | ✅ | Agent cannot override |
| Inference credential stripping + injection | ✅ | ✅ | Via OpenShell privacy router |

### Policy Management

| Feature | HermesClaw | NemoClaw | Notes |
|---------|:----------:|:--------:|-------|
| Policy presets (strict / gateway / permissive) | ✅ | ✅ | HermesClaw: 3 presets; NemoClaw: policy-add |
| Binary-level network rules (per executable) | ✅ | ✅ | binaries: glob in network_policies |
| Named multi-policy sections | ✅ | ✅ | e.g. inference_local, telegram_gateway |
| Global policy (all sandboxes) | ✅ | ✅ | openshell policy set --global |
| Policy revision history | ✅ | ✅ | openshell policy list |
| Audit mode (log without block) | ✅ | ✅ | enforcement: audit |

### Inference Routing

| Feature | HermesClaw | NemoClaw | Notes |
|---------|:----------:|:--------:|-------|
| Local llama.cpp backend | ✅ | ✅ | Via inference.local → host:8080 |
| NVIDIA API Catalog backend | ✅ | ✅ | openshell provider create --type nvidia |
| OpenAI-compatible backend | ✅ | ✅ | openshell provider create --type openai |
| Anthropic backend | ✅ | ✅ | openshell provider create --type anthropic |
| Ollama backend | ✅ | ✅ | host.openshell.internal:11434 |
| vLLM backend | ✅ | ✅ |  |
| Hot-swap provider without restart | ✅ | ✅ | openshell inference update |
| Privacy router (sensitivity-based routing) | ✅ | ✅ | NemoClaw: built-in; HermesClaw: via HERMES_PRIVACY_THRESHOLD env |
| GPU passthrough to sandbox | ✅ | ✅ | openshell sandbox create --gpu |

### Sandbox Lifecycle

| Feature | HermesClaw | NemoClaw | Notes |
|---------|:----------:|:--------:|-------|
| Create sandbox | ✅ | ✅ | hermesclaw start / openshell sandbox create |
| Stop sandbox | ✅ | ✅ | hermesclaw stop |
| Connect (interactive shell) | ✅ | ✅ | hermesclaw connect |
| View logs | ✅ | ✅ | hermesclaw logs / openshell logs |
| Live monitoring dashboard | ✅ | ✅ | openshell term |
| File upload to sandbox | ✅ | ✅ | openshell sandbox upload |
| File download from sandbox | ✅ | ✅ | openshell sandbox download |
| Port forwarding | ✅ | ✅ | openshell forward start |
| Remote deployment (SSH) | ✅ | ✅ | openshell gateway start --remote user@host |
| Remote GPU deployment | ⚠️ | ✅ | NemoClaw has nemoclaw deploy; HermesClaw: via openshell gateway start --remote |

### Agent Capabilities

| Feature | HermesClaw | NemoClaw | Notes |
|---------|:----------:|:--------:|-------|
| 40+ built-in tools | ✅ | ❌ | Hermes: 40+ tools; OpenClaw: limited |
| Persistent cross-session memory (MEMORY.md) | ✅ | ❌ | Hermes only |
| User profile memory (USER.md) | ✅ | ❌ | Hermes only |
| Full-text session search (FTS5) | ✅ | ❌ | Hermes only |
| Self-improving skills (auto-create) | ✅ | ❌ | Hermes DSPy + GEPA optimization |
| Skill registry (install/publish/search) | ✅ | ❌ | hermes skills install |
| Context compression | ✅ | ❌ | Hermes auto-compresses near context limit |
| Cron/scheduled tasks | ✅ | ❌ | hermes cron create |
| Voice input/output | ✅ | ❌ | Push-to-talk CLI + gateway voice notes |
| Browser automation (CDP) | ✅ | ❌ | hermes browser_* tools |
| Image generation | ✅ | ❌ | hermes image_generate tool |
| Multi-agent delegation | ✅ | ❌ | hermes delegate_task |
| Reinforcement learning (RL train) | ✅ | ❌ | hermes rl_train tool |
| MCP server integration | ✅ | ❌ | hermes mcp |
| IDE integration (ACP — VS Code, JetBrains) | ✅ | ❌ | hermes acp |
| Plugin architecture (~/.hermes/plugins/) | ✅ | ❌ | Hermes only |
| Python SDK (AIAgent) | ✅ | ❌ | from run_agent import AIAgent |
| SOUL.md persona customisation | ✅ | ❌ | Hermes only |
| Concurrent tool execution | ✅ | ❌ | Hermes v0.3.0+ |
| Streaming responses (all platforms) | ✅ | ❌ | Hermes v0.3.0+ |

### Messaging Gateway

| Feature | HermesClaw | NemoClaw | Notes |
|---------|:----------:|:--------:|-------|
| Telegram integration | ✅ | ❌ | hermes gateway (policy-gateway.yaml) |
| Discord integration | ✅ | ❌ | hermes gateway |
| Signal integration | ✅ | ❌ | hermes gateway (requires signal-cli) |
| Slack integration | ✅ | ❌ | hermes gateway |
| WhatsApp integration | ✅ | ❌ | hermes whatsapp |
| Email (IMAP/SMTP) | ✅ | ❌ | hermes gateway |
| Voice note transcription | ✅ | ❌ | All gateway platforms, auto-transcribe |
| Multi-user auth + DM pairing | ✅ | ❌ | hermes pairing |

### Docker / Deployment

| Feature | HermesClaw | NemoClaw | Notes |
|---------|:----------:|:--------:|-------|
| Docker Compose stack (no NVIDIA HW) | ✅ | ⚠️ | HermesClaw: native; NemoClaw: Linux server required |
| GPU-accelerated compose profile | ✅ | ✅ | docker compose --profile gpu up |
| Persistent memory volume | ✅ | ✅ | hermesclaw-memories volume |
| Persistent skills volume | ✅ | ❌ | hermesclaw-skills volume (NemoClaw agent has no skills) |
| Works on macOS | ✅ | ❌ | NemoClaw requires Linux; HermesClaw: Mac Docker mode |
| Works without NVIDIA GPU | ✅ | ❌ | HermesClaw Docker mode: CPU inference |
| Multiple inference providers in one stack | ✅ | ✅ | openshell provider create |

## Live Test Results

| Test | Status |
|------|--------|
| llama.cpp health check | ⏭ skipped (--quick) |
| hermes chat (container) | ⏭ skipped (--quick) |
| hermes memory (container) | ⏭ skipped (--quick) |
| hermes skills (container) | ⏭ skipped (--quick) |

## Summary

### Where HermesClaw matches NemoClaw
- Full OpenShell kernel-level sandbox (Landlock + Seccomp + OPA proxy)
- All policy management features (presets, hot-reload, global, audit mode)
- All inference routing features (local, NVIDIA, OpenAI, Anthropic, Ollama, vLLM)
- Full sandbox lifecycle (create/stop/connect/logs/monitor/remote)

### Where HermesClaw goes further
- **40+ tools** — web search, browser, vision, image gen, voice, RL training (OpenClaw has ~10)
- **Persistent memory** — MEMORY.md + USER.md survive across sandbox recreations
- **Self-improving skills** — auto-created, optimised with DSPy+GEPA, shareable
- **6 messaging platforms** — Telegram, Discord, Signal, Slack, WhatsApp, Email (OpenClaw: none)
- **Voice** — push-to-talk CLI + voice note transcription on all gateway platforms
- **Python SDK** — embed Hermes in any application (`from run_agent import AIAgent`)
- **MCP integration** — connect to any external tool server
- **IDE integration** — VS Code, JetBrains, Zed via ACP server
- **Plugin architecture** — extend without forking (`~/.hermes/plugins/`)
- **Works on macOS** — Docker mode with CPU or Apple Metal inference
- **Works without NVIDIA GPU** — NemoClaw requires Linux + NVIDIA hardware

### Where NemoClaw has an edge
- **Purpose-built CLI** — `nemoclaw onboard`, `nemoclaw deploy` for DGX Spark
- **Nemotron model integration** — native NVIDIA model catalog access
- **Privacy sensitivity router** — automatic local/cloud routing by query sensitivity (HermesClaw has manual threshold config)
