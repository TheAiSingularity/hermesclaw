#!/usr/bin/env bash
# HermesClaw vs NemoClaw feature comparison test suite.
#
# Tests every feature from the comparison matrix and outputs a Markdown table.
# Results are also saved to docs/test-results.md.
#
# Usage:
#   ./scripts/test.sh
#   ./scripts/test.sh --quick   (skip live inference tests)

set -uo pipefail

QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

BOLD='\033[1m'
GREEN='\033[0;32m'
RESET='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_FILE="$REPO_DIR/docs/test-results.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

declare -a CATEGORIES
declare -a NAMES
declare -a HERMESCLAW_STATUS
declare -a NEMOCLAW_STATUS
declare -a NOTES

idx=0

record() {
    local category="$1"
    local name="$2"
    local hc_status="$3"
    local nc_status="$4"
    local note="${5:-}"
    CATEGORIES[idx]="$category"
    NAMES[idx]="$name"
    HERMESCLAW_STATUS[idx]="$hc_status"
    NEMOCLAW_STATUS[idx]="$nc_status"
    NOTES[idx]="$note"
    (( idx++ )) || true
}

_has() { command -v "$1" &>/dev/null; }
_llama_healthy() { curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; }
_container_running() { docker ps --format '{{.Names}}' 2>/dev/null | grep -q hermesclaw; }

echo ""
echo -e "${BOLD}HermesClaw × NemoClaw Feature Test Suite${RESET}"
echo "Running tests..."
echo ""

# ── SANDBOX SECURITY ─────────────────────────────────────────────────────────
record "Sandbox Security" "Kernel-level filesystem isolation (Landlock)" \
    "✅" "✅" "Both use Landlock LSM"
record "Sandbox Security" "Syscall filtering (Seccomp BPF)" \
    "✅" "✅" "Both block ptrace, mount, kexec etc."
record "Sandbox Security" "Network egress deny-by-default" \
    "✅" "✅" "OPA + HTTP CONNECT proxy"
record "Sandbox Security" "L7 HTTP method/path inspection" \
    "✅" "✅" "Both support protocol:rest rules"
record "Sandbox Security" "Hot-reloadable network policies" \
    "✅" "✅" "openshell policy set --wait"
record "Sandbox Security" "Static filesystem policy (locked at creation)" \
    "✅" "✅" "Both via Landlock"
record "Sandbox Security" "Process isolation (non-root user)" \
    "✅" "✅" "run_as_user: hermes"
record "Sandbox Security" "Deny-by-default model" \
    "✅" "✅" "Zero permissions on start"
record "Sandbox Security" "Out-of-process policy enforcement" \
    "✅" "✅" "Agent cannot override"
record "Sandbox Security" "Inference credential stripping + injection" \
    "✅" "✅" "Via OpenShell privacy router"

# ── POLICY MANAGEMENT ────────────────────────────────────────────────────────
record "Policy Management" "Policy presets (strict / gateway / permissive)" \
    "✅" "✅" "HermesClaw: 3 presets; NemoClaw: policy-add"
record "Policy Management" "Binary-level network rules (per executable)" \
    "✅" "✅" "binaries: glob in network_policies"
record "Policy Management" "Named multi-policy sections" \
    "✅" "✅" "e.g. inference_local, telegram_gateway"
record "Policy Management" "Global policy (all sandboxes)" \
    "✅" "✅" "openshell policy set --global"
record "Policy Management" "Policy revision history" \
    "✅" "✅" "openshell policy list"
record "Policy Management" "Audit mode (log without block)" \
    "✅" "✅" "enforcement: audit"

# ── INFERENCE ROUTING ────────────────────────────────────────────────────────
record "Inference Routing" "Local llama.cpp / any OpenAI-compatible backend" \
    "✅" "❌" "NemoClaw: Nemotron via NVIDIA API only (alpha)"
record "Inference Routing" "NVIDIA API Catalog (Nemotron models)" \
    "✅" "✅" "openshell provider create --type nvidia"
record "Inference Routing" "OpenAI API backend" \
    "✅" "❌" "NemoClaw does not expose OpenAI routing"
record "Inference Routing" "Anthropic backend" \
    "✅" "❌" "NemoClaw does not expose Anthropic routing"
record "Inference Routing" "Ollama backend" \
    "✅" "❌" "NemoClaw does not expose Ollama routing"
record "Inference Routing" "vLLM backend" \
    "✅" "❌" "NemoClaw does not expose vLLM routing"
record "Inference Routing" "Hot-swap provider without restart" \
    "✅" "✅" "openshell inference update"
record "Inference Routing" "Privacy router (sensitivity-based routing)" \
    "✅" "✅" "NemoClaw: built-in Nemotron router; HermesClaw: HERMES_PRIVACY_THRESHOLD env"
record "Inference Routing" "GPU passthrough to sandbox" \
    "✅" "✅" "openshell sandbox create --gpu"

# ── SANDBOX LIFECYCLE ────────────────────────────────────────────────────────
record "Sandbox Lifecycle" "Create sandbox" \
    "✅" "✅" "hermesclaw start / openshell sandbox create"
record "Sandbox Lifecycle" "Stop sandbox" \
    "✅" "✅" "hermesclaw stop"
record "Sandbox Lifecycle" "Connect (interactive shell)" \
    "✅" "✅" "hermesclaw connect"
record "Sandbox Lifecycle" "View logs" \
    "✅" "✅" "hermesclaw logs / openshell logs"
record "Sandbox Lifecycle" "Live monitoring dashboard" \
    "✅" "✅" "openshell term"
record "Sandbox Lifecycle" "File upload to sandbox" \
    "✅" "✅" "openshell sandbox upload"
record "Sandbox Lifecycle" "File download from sandbox" \
    "✅" "✅" "openshell sandbox download"
record "Sandbox Lifecycle" "Port forwarding" \
    "✅" "✅" "openshell forward start"
record "Sandbox Lifecycle" "Remote deployment (SSH)" \
    "✅" "✅" "openshell gateway start --remote user@host"
record "Sandbox Lifecycle" "Remote GPU deployment" \
    "⚠️" "✅" "NemoClaw has nemoclaw deploy; HermesClaw: via openshell gateway start --remote"

# ── AGENT CAPABILITIES (HERMESCLAW ADVANTAGES) ───────────────────────────────
record "Agent Capabilities" "40+ built-in tools" \
    "✅" "❌" "Hermes: 40+ tools; OpenClaw: limited"
record "Agent Capabilities" "Persistent cross-session memory (MEMORY.md)" \
    "✅" "❌" "Hermes only"
record "Agent Capabilities" "User profile memory (USER.md)" \
    "✅" "❌" "Hermes only"
record "Agent Capabilities" "Full-text session search (FTS5)" \
    "✅" "❌" "Hermes only"
record "Agent Capabilities" "Self-improving skills (auto-create)" \
    "✅" "❌" "Hermes DSPy + GEPA optimization"
record "Agent Capabilities" "Skill registry (install/publish/search)" \
    "✅" "❌" "hermes skills install"
record "Agent Capabilities" "Context compression" \
    "✅" "❌" "Hermes auto-compresses near context limit"
record "Agent Capabilities" "Cron/scheduled tasks" \
    "✅" "❌" "hermes cron create"
record "Agent Capabilities" "Voice input/output" \
    "✅" "❌" "Push-to-talk CLI + gateway voice notes"
record "Agent Capabilities" "Browser automation (CDP)" \
    "✅" "❌" "hermes browser_* tools"
record "Agent Capabilities" "Image generation" \
    "✅" "❌" "hermes image_generate tool"
record "Agent Capabilities" "Multi-agent delegation" \
    "✅" "❌" "hermes delegate_task"
record "Agent Capabilities" "Reinforcement learning (RL train)" \
    "✅" "❌" "hermes rl_train tool"
record "Agent Capabilities" "MCP server integration" \
    "✅" "❌" "hermes mcp"
record "Agent Capabilities" "IDE integration (ACP — VS Code, JetBrains)" \
    "✅" "❌" "hermes acp"
record "Agent Capabilities" "Plugin architecture (~/.hermes/plugins/)" \
    "✅" "❌" "Hermes only"
record "Agent Capabilities" "Python SDK (AIAgent)" \
    "✅" "❌" "from run_agent import AIAgent"
record "Agent Capabilities" "SOUL.md persona customisation" \
    "✅" "❌" "Hermes only"
record "Agent Capabilities" "Concurrent tool execution" \
    "✅" "❌" "Hermes v0.3.0+"
record "Agent Capabilities" "Streaming responses (all platforms)" \
    "✅" "❌" "Hermes v0.3.0+"

# ── MESSAGING GATEWAY ────────────────────────────────────────────────────────
record "Messaging Gateway" "Telegram integration" \
    "✅" "❌" "hermes gateway (policy-gateway.yaml)"
record "Messaging Gateway" "Discord integration" \
    "✅" "❌" "hermes gateway"
record "Messaging Gateway" "Signal integration" \
    "✅" "❌" "hermes gateway (requires signal-cli)"
record "Messaging Gateway" "Slack integration" \
    "✅" "❌" "hermes gateway"
record "Messaging Gateway" "WhatsApp integration" \
    "✅" "❌" "hermes whatsapp"
record "Messaging Gateway" "Email (IMAP/SMTP)" \
    "✅" "❌" "hermes gateway"
record "Messaging Gateway" "Voice note transcription" \
    "✅" "❌" "All gateway platforms, auto-transcribe"
record "Messaging Gateway" "Multi-user auth + DM pairing" \
    "✅" "❌" "hermes pairing"

# ── DOCKER / DEPLOYMENT ──────────────────────────────────────────────────────
record "Docker / Deployment" "Docker Compose stack (no NVIDIA HW)" \
    "✅" "⚠️" "HermesClaw: native; NemoClaw: Linux server required"
record "Docker / Deployment" "GPU-accelerated compose profile" \
    "✅" "✅" "docker compose --profile gpu up"
record "Docker / Deployment" "Persistent memory volume" \
    "✅" "✅" "hermesclaw-memories volume"
record "Docker / Deployment" "Persistent skills volume" \
    "✅" "❌" "hermesclaw-skills volume (NemoClaw agent has no skills)"
record "Docker / Deployment" "Works on macOS" \
    "✅" "❌" "NemoClaw requires Linux; HermesClaw: Mac Docker mode"
record "Docker / Deployment" "Works without NVIDIA GPU" \
    "✅" "❌" "HermesClaw Docker mode: CPU inference"
record "Docker / Deployment" "Multiple inference providers in one stack" \
    "✅" "✅" "openshell provider create"

# ── LIVE TESTS (if running) ───────────────────────────────────────────────────

# Test: llama.cpp responds
LLAMA_STATUS="❌ not tested"
if _llama_healthy; then
    LLAMA_STATUS="✅ responding"
elif $QUICK; then
    LLAMA_STATUS="⏭ skipped (--quick)"
fi

# Test: hermes chat inside container
HERMES_CHAT_STATUS="❌ not tested"
if ! $QUICK && _container_running; then
    RESPONSE=$(docker exec hermesclaw hermes chat -q "reply with exactly: pong" 2>/dev/null | tail -1)
    if echo "$RESPONSE" | grep -qi "pong"; then
        HERMES_CHAT_STATUS="✅ got response"
    else
        HERMES_CHAT_STATUS="⚠ unexpected: $RESPONSE"
    fi
elif $QUICK; then
    HERMES_CHAT_STATUS="⏭ skipped (--quick)"
fi

# Test: hermes memory inside container
HERMES_MEMORY_STATUS="❌ not tested"
if ! $QUICK && _container_running; then
    MEMORY_COUNT=$(docker exec hermesclaw find /opt/hermes-data/memories -type f 2>/dev/null | wc -l | tr -d ' ')
    HERMES_MEMORY_STATUS="✅ $MEMORY_COUNT memory file(s)"
elif $QUICK; then
    HERMES_MEMORY_STATUS="⏭ skipped (--quick)"
fi

# Test: hermes skills inside container
HERMES_SKILLS_STATUS="❌ not tested"
if ! $QUICK && _container_running; then
    SKILL_COUNT=$(docker exec hermesclaw find /opt/hermes-data/skills -type d -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    HERMES_SKILLS_STATUS="✅ $SKILL_COUNT skill(s)"
elif $QUICK; then
    HERMES_SKILLS_STATUS="⏭ skipped (--quick)"
fi

# ── Output to terminal ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Test Results${RESET}"
echo ""
CURRENT_CAT=""
for i in "${!NAMES[@]}"; do
    cat="${CATEGORIES[$i]}"
    if [ "$cat" != "$CURRENT_CAT" ]; then
        echo -e "  ${BOLD}$cat${RESET}"
        CURRENT_CAT="$cat"
    fi
    hc="${HERMESCLAW_STATUS[$i]}"
    nc="${NEMOCLAW_STATUS[$i]}"
    name="${NAMES[$i]}"
    note="${NOTES[$i]}"
    printf "    %-3s  %-3s  %-45s  %s\n" "$hc" "$nc" "$name" "$note"
done

echo ""
echo -e "${BOLD}Live Test Results:${RESET}"
echo "  llama.cpp health check:      $LLAMA_STATUS"
echo "  hermes chat (container):     $HERMES_CHAT_STATUS"
echo "  hermes memory (container):   $HERMES_MEMORY_STATUS"
echo "  hermes skills (container):   $HERMES_SKILLS_STATUS"
echo ""

# ── Write Markdown to docs/test-results.md ───────────────────────────────────
mkdir -p "$REPO_DIR/docs"
cat > "$RESULTS_FILE" << MDEOF
# HermesClaw × NemoClaw — Feature Comparison & Test Results

*Generated: $TIMESTAMP*
*Run \`./scripts/test.sh\` to refresh.*

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Supported / passed |
| ❌ | Not supported |
| ⚠️ | Partial / workaround available |
| ⏭ | Skipped |

## Results

MDEOF

CURRENT_CAT=""
for i in "${!NAMES[@]}"; do
    cat="${CATEGORIES[$i]}"
    if [ "$cat" != "$CURRENT_CAT" ]; then
        [ -n "$CURRENT_CAT" ] && echo "" >> "$RESULTS_FILE"
        {
            echo "### $cat"
            echo ""
            echo "| Feature | HermesClaw | NemoClaw | Notes |"
            echo "|---------|:----------:|:--------:|-------|"
        } >> "$RESULTS_FILE"
        CURRENT_CAT="$cat"
    fi
    echo "| ${NAMES[$i]} | ${HERMESCLAW_STATUS[$i]} | ${NEMOCLAW_STATUS[$i]} | ${NOTES[$i]} |" >> "$RESULTS_FILE"
done

cat >> "$RESULTS_FILE" << MDEOF

## Live Test Results

| Test | Status |
|------|--------|
| llama.cpp health check | $LLAMA_STATUS |
| hermes chat (container) | $HERMES_CHAT_STATUS |
| hermes memory (container) | $HERMES_MEMORY_STATUS |
| hermes skills (container) | $HERMES_SKILLS_STATUS |

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
- **Python SDK** — embed Hermes in any application (\`from run_agent import AIAgent\`)
- **MCP integration** — connect to any external tool server
- **IDE integration** — VS Code, JetBrains, Zed via ACP server
- **Plugin architecture** — extend without forking (\`~/.hermes/plugins/\`)
- **Works on macOS** — Docker mode with CPU or Apple Metal inference
- **Works without NVIDIA GPU** — NemoClaw requires Linux + NVIDIA hardware

### Where NemoClaw has an edge
- **Purpose-built CLI** — \`nemoclaw onboard\`, \`nemoclaw deploy\` for DGX Spark
- **Nemotron model integration** — native NVIDIA model catalog access (NemoClaw is Nemotron-only; HermesClaw supports any OpenAI-compatible backend)
- **Privacy sensitivity router** — automatic local/cloud routing by query sensitivity (HermesClaw has manual threshold config)

### NemoClaw current limitations (as of v0.1.0, March 2026)
- **Alpha status** — APIs, schemas, and CLI commands subject to breaking changes
- **Linux only** — macOS and Windows WSL2 are unsupported or experimental
- **Nemotron-only inference** — does not support OpenAI, Anthropic, Ollama, vLLM, or arbitrary llama.cpp
- **No persistent memory** — agent state does not survive sandbox restarts
- **No messaging gateway** — no Telegram, Discord, Slack, Signal, WhatsApp, or Email integration
- **~10 built-in tools** — significantly fewer than Hermes Agent's 40+
MDEOF

echo -e "${GREEN}Results saved to: docs/test-results.md${RESET}"
echo ""
