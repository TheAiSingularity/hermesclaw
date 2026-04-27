#!/usr/bin/env bash
# hermesclaw helper library — registry, credentials, validation, snapshots
# Color variables (BOLD, GREEN, RED, YELLOW, CYAN, DIM, RESET) are provided
# by the sourcing script (scripts/hermesclaw).
# shellcheck disable=SC2154

HERMESCLAW_HOME="${HERMESCLAW_HOME:-$HOME/.hermesclaw}"
REGISTRY_FILE="$HERMESCLAW_HOME/sandboxes.json"

# ── Registry ──────────────────────────────────────────────────────────────────

_ensure_registry() {
    mkdir -p "$HERMESCLAW_HOME"
    [ -f "$REGISTRY_FILE" ] || echo '{"default":"","sandboxes":{}}' > "$REGISTRY_FILE"
}

_registry_get() {
    _ensure_registry
    python3 -c "
import json, sys
with open('$REGISTRY_FILE') as f: reg = json.load(f)
sb = reg['sandboxes'].get('$1')
if not sb: sys.exit(1)
if len(sys.argv) > 1: print(sb.get(sys.argv[1].lstrip('.'), ''))
else: print(json.dumps(sb))
" "${2:-}" 2>/dev/null
}

_registry_add() {
    _ensure_registry
    local name="$1" policy="$2"
    python3 -c "
import json
from datetime import datetime, timezone
with open('$REGISTRY_FILE') as f: reg = json.load(f)
reg['sandboxes']['$name'] = {
    'created': datetime.now(timezone.utc).isoformat(),
    'policy': '$policy',
    'profile': '$name'
}
if not reg['default']: reg['default'] = '$name'
with open('$REGISTRY_FILE', 'w') as f: json.dump(reg, f, indent=2)
"
}

_registry_remove() {
    _ensure_registry
    python3 -c "
import json
with open('$REGISTRY_FILE') as f: reg = json.load(f)
reg['sandboxes'].pop('$1', None)
if reg['default'] == '$1':
    names = list(reg['sandboxes'].keys())
    reg['default'] = names[0] if names else ''
with open('$REGISTRY_FILE', 'w') as f: json.dump(reg, f, indent=2)
"
}

_registry_default() {
    _ensure_registry
    if [ -n "${1:-}" ]; then
        python3 -c "
import json
with open('$REGISTRY_FILE') as f: reg = json.load(f)
reg['default'] = '$1'
with open('$REGISTRY_FILE', 'w') as f: json.dump(reg, f, indent=2)
"
    else
        python3 -c "
import json
with open('$REGISTRY_FILE') as f: reg = json.load(f)
d = reg.get('default', '')
if not d: exit(1)
print(d)
" || { echo -e "${RED}No default sandbox. Run: hermesclaw <name> start${RESET}" >&2; exit 1; }
    fi
}

_registry_list() {
    _ensure_registry
    python3 -c "
import json
with open('$REGISTRY_FILE') as f: reg = json.load(f)
for name in sorted(reg['sandboxes'].keys()): print(name)
"
}

# ── Name Validation ───────────────────────────────────────────────────────────

_validate_name() {
    local name="$1"
    local reserved="help|version|onboard|list|backup-all|doctor|uninstall"
    name="${name,,}"
    if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        echo -e "${RED}Invalid name '$name'. Use lowercase alphanumeric and hyphens, start/end with alphanumeric.${RESET}" >&2
        exit 1
    fi
    if [[ "$name" =~ ^($reserved)$ ]]; then
        echo -e "${RED}Name '$name' is reserved. Choose a different name.${RESET}" >&2
        exit 1
    fi
    echo "$name"
}

# ── Credential Leak Detection ─────────────────────────────────────────────────

_warn_credentials() {
    local zipfile="$1"
    local tmpdir
    tmpdir=$(mktemp -d)
    unzip -q "$zipfile" -d "$tmpdir"

    local found=false
    local patterns="sk-or-v1-|nvapi-|sk-ant-|sk-proj-|AIza|ghp_|gho_|glpat-"

    while IFS= read -r -d '' file; do
        if grep -qE "$patterns" "$file" 2>/dev/null; then
            local relpath="${file#$tmpdir/}"
            echo -e "${YELLOW}⚠ Possible API key found in backup: $relpath${RESET}" >&2
            found=true
        fi
    done < <(find "$tmpdir" -type f -print0)

    rm -rf "$tmpdir"

    if $found; then
        echo -e "${YELLOW}⚠ Your sandbox may contain real credentials that should be proxied via OpenShell.${RESET}" >&2
        echo -e "${YELLOW}  Review your inference config: openshell inference get${RESET}" >&2
        echo -e "${YELLOW}  Backup saved but may contain sensitive data.${RESET}" >&2
    fi
}

# ── Snapshot Resolution ───────────────────────────────────────────────────────

_resolve_snapshot() {
    local snap_dir="$1"
    local prefix="${2:-}"
    local matches count
    if [ -z "$prefix" ]; then
        find "$snap_dir" -maxdepth 1 -name 'hermesclaw-snap-*.zip' 2>/dev/null | sort | tail -1
    else
        matches=$(find "$snap_dir" -maxdepth 1 -name "hermesclaw-snap-${prefix}*.zip" 2>/dev/null)
        count=$(echo "$matches" | grep -c '.' || true)
        if [ "$count" -eq 0 ]; then
            echo -e "${RED}No snapshot matching '$prefix'${RESET}" >&2; exit 1
        elif [ "$count" -gt 1 ]; then
            echo -e "${RED}Ambiguous prefix '$prefix' matches $count snapshots${RESET}" >&2; exit 1
        fi
        echo "$matches"
    fi
}

_sandbox_running_by_name() {
    openshell sandbox list 2>/dev/null | grep -q "$1"
}
