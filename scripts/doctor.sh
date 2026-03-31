#!/usr/bin/env bash
# HermesClaw end-to-end diagnostic.
#
# Checks every component of the stack and prints a status table.
#
# Usage:
#   ./scripts/doctor.sh
#   ./scripts/doctor.sh --quick   (skip slow checks)

set -uo pipefail

QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
RESET='\033[0m'

RESULTS=()
FAILURES=0
WARNINGS=0

# ── Helpers ───────────────────────────────────────────────────────────────────
_has() { command -v "$1" &>/dev/null; }

record() {
    local status="$1"
    local name="$2"
    local detail="${3:-}"
    RESULTS+=("$status|$name|$detail")
    if [[ "$status" == "FAIL" ]]; then (( FAILURES++ )); fi
    if [[ "$status" == "WARN" ]]; then (( WARNINGS++ )); fi
}

print_results() {
    echo ""
    echo -e "${BOLD}HermesClaw Diagnostic Report${RESET}"
    echo "================================================================"
    printf "  %-8s  %-35s  %s\n" "STATUS" "CHECK" "DETAIL"
    echo "  --------  -----------------------------------  ---------------"
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r status name detail <<< "$row"
        local color=""
        case "$status" in
            PASS) color=$GREEN ;;
            FAIL) color=$RED ;;
            WARN) color=$YELLOW ;;
            SKIP) color=$DIM ;;
        esac
        printf "  ${color}%-8s${RESET}  %-35s  %s\n" "$status" "$name" "$detail"
    done
    echo "================================================================"
    echo ""
    if [[ $FAILURES -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}All checks passed.${RESET}"
    elif [[ $FAILURES -eq 0 ]]; then
        echo -e "${YELLOW}$WARNINGS warning(s) — see above.${RESET}"
    else
        echo -e "${RED}$FAILURES failure(s), $WARNINGS warning(s) — see above.${RESET}"
    fi
    echo ""
}

# ── Checks ────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Running HermesClaw diagnostics...${RESET}"
echo ""

# 1. Docker
if _has docker; then
    VER=$(docker --version 2>&1 | head -1)
    record "PASS" "docker installed" "$VER"
else
    record "FAIL" "docker installed" "not found — https://docs.docker.com/get-docker/"
fi

# 2. Docker daemon
if docker info &>/dev/null; then
    record "PASS" "docker daemon running" ""
else
    record "FAIL" "docker daemon running" "run: docker desktop or dockerd"
fi

# 3. OpenShell
if _has openshell; then
    VER=$(openshell --version 2>&1 | head -1)
    record "PASS" "openshell installed" "$VER"
else
    record "WARN" "openshell installed" "not found — Docker mode only"
fi

# 4. OpenShell gateway
if _has openshell; then
    if openshell status &>/dev/null; then
        record "PASS" "openshell gateway running" ""
    else
        record "WARN" "openshell gateway running" "run: openshell gateway start"
    fi
else
    record "SKIP" "openshell gateway running" "OpenShell not installed"
fi

# 5. llama.cpp health
if curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
    record "PASS" "llama.cpp on :8080" "responding"
else
    record "WARN" "llama.cpp on :8080" "not responding — start before sandboxing"
fi

# 6. llama.cpp /v1/models
if ! $QUICK; then
    MODELS_JSON=$(curl -sf http://127.0.0.1:8080/v1/models 2>/dev/null || true)
    if [ -n "$MODELS_JSON" ]; then
        # Parse JSON: prefer jq (fast), fall back to python3, fall back to grep
        if _has jq; then
            MODELS=$(echo "$MODELS_JSON" | jq -r '[.data[].id] | .[0:3] | join(", ")' 2>/dev/null || echo "")
        elif _has python3; then
            MODELS=$(echo "$MODELS_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ids = [m['id'] for m in d.get('data', [])]
    print(', '.join(ids[:3]))
except Exception:
    print('')
" 2>/dev/null || echo "")
        else
            # Fallback: crude grep for id fields
            MODELS=$(echo "$MODELS_JSON" | grep -o '"id":"[^"]*"' | head -3 | cut -d'"' -f4 | tr '\n' ',' | sed 's/,$//' || echo "")
        fi
        if [ -n "$MODELS" ]; then
            record "PASS" "llama.cpp models endpoint" "$MODELS"
        else
            record "WARN" "llama.cpp models endpoint" "responded but no models listed"
        fi
    else
        record "WARN" "llama.cpp models endpoint" "no response (llama.cpp not running?)"
    fi
fi

# 7. Hermes (local install)
if _has hermes; then
    VER=$(hermes version 2>&1 | head -1)
    record "PASS" "hermes installed (local)" "$VER"
else
    record "SKIP" "hermes installed (local)" "runs inside container"
fi

# 8. Docker image
if docker image inspect hermesclaw:latest &>/dev/null 2>&1; then
    CREATED=$(docker image inspect hermesclaw:latest --format '{{.Created}}' 2>/dev/null | cut -c1-10)
    record "PASS" "docker image hermesclaw:latest" "built $CREATED"
else
    record "WARN" "docker image hermesclaw:latest" "not built — run: ./scripts/setup.sh"
fi

# 9. Hermes chat (inside container)
if ! $QUICK && docker image inspect hermesclaw:latest &>/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -q hermesclaw; then
    RESPONSE=$(docker exec hermesclaw hermes chat -q "reply with exactly: ok" 2>/dev/null | tail -1)
    if echo "$RESPONSE" | grep -qi "ok"; then
        record "PASS" "hermes chat (in container)" "got response"
    else
        record "WARN" "hermes chat (in container)" "unexpected response: $RESPONSE"
    fi
elif $QUICK; then
    record "SKIP" "hermes chat (in container)" "--quick mode"
else
    record "SKIP" "hermes chat (in container)" "container not running"
fi

# 10. Hermes config
if [ -f "$HOME/.hermes/config.yaml" ]; then
    record "PASS" "$HOME/.hermes/config.yaml" "present"
else
    record "WARN" "$HOME/.hermes/config.yaml" "missing — run: ./scripts/setup.sh"
fi

# 11. Model files
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_COUNT=$(find "$REPO_DIR/models" -name "*.gguf" 2>/dev/null | wc -l | tr -d ' ')
if [ "$MODEL_COUNT" -gt 0 ]; then
    record "PASS" "model files in models/" "$MODEL_COUNT .gguf file(s)"
else
    record "WARN" "model files in models/" "none — drop .gguf files in models/"
fi

# 12. Hermes memories
MEMORY_COUNT=$(find ~/.hermes/memories -type f 2>/dev/null | wc -l | tr -d ' ')
record "PASS" "hermes memories dir" "$MEMORY_COUNT file(s) in $HOME/.hermes/memories/"

# 13. Hermes skills
SKILL_COUNT=$(find ~/.hermes/skills -type d -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
record "PASS" "hermes skills dir" "$SKILL_COUNT skill(s) in ~/.hermes/skills/"

# 14. Policy files
for policy in hermesclaw-policy policy-strict policy-gateway policy-permissive; do
    if [ -f "$REPO_DIR/openshell/${policy}.yaml" ]; then
        record "PASS" "policy: $policy" ""
    else
        record "FAIL" "policy: $policy" "missing: openshell/${policy}.yaml"
    fi
done

# 15. OpenShell sandbox (if applicable)
if _has openshell; then
    SANDBOX_NAME="${HERMESCLAW_SANDBOX:-hermesclaw-1}"
    if openshell sandbox list 2>/dev/null | grep -q "$SANDBOX_NAME"; then
        record "PASS" "sandbox $SANDBOX_NAME" "running"
    else
        record "WARN" "sandbox $SANDBOX_NAME" "not running — run: hermesclaw start"
    fi
fi

# 16. Inference inside sandbox
if ! $QUICK && _has openshell && openshell sandbox list 2>/dev/null | grep -q "${HERMESCLAW_SANDBOX:-hermesclaw-1}"; then
    SANDBOX_NAME="${HERMESCLAW_SANDBOX:-hermesclaw-1}"
    INFERENCE=$(openshell inference get 2>/dev/null | head -1)
    if [ -n "$INFERENCE" ]; then
        record "PASS" "openshell inference config" "$INFERENCE"
    else
        record "WARN" "openshell inference config" "not configured"
    fi
elif $QUICK; then
    record "SKIP" "openshell inference config" "--quick mode"
else
    record "SKIP" "openshell inference config" "sandbox not running"
fi

# ── Print results ─────────────────────────────────────────────────────────────
print_results
