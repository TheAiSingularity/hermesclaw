#!/usr/bin/env bash
set -euo pipefail

_tmpbase=$(mktemp -d)
export HERMESCLAW_HOME="$_tmpbase/hermesclaw-test"
mkdir -p "$HERMESCLAW_HOME"
export HOME="$_tmpbase/home-test"
mkdir -p "$HOME"

BOLD="" GREEN="" RED="" YELLOW="" CYAN="" DIM="" RESET=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hermesclaw-helpers.sh"

PASS=0; FAIL=0
check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (expected='$expected', got='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Registry Tests ==="

echo "-- _ensure_registry --"
_ensure_registry
check "registry file created" "true" "$([ -f "$REGISTRY_FILE" ] && echo true || echo false)"

echo "-- _registry_add --"
_registry_add "mybot" "strict"
_registry_add "devbot" "gateway"
count=$(python3 -c "import json; r=json.load(open('$REGISTRY_FILE')); print(len(r['sandboxes']))")
check "two sandboxes added" "2" "$count"

echo "-- _registry_default (auto-set) --"
result=$(_registry_default)
check "default auto-set to first" "mybot" "$result"

echo "-- _registry_get --"
policy=$(_registry_get "devbot" .policy)
check "devbot policy" "gateway" "$policy"
profile=$(_registry_get "mybot" .profile)
check "mybot profile" "mybot" "$profile"

echo "-- _registry_list --"
list=$(_registry_list | tr '\n' ',')
check "list contains devbot" "true" "$(echo "$list" | grep -q devbot && echo true || echo false)"
check "list contains mybot" "true" "$(echo "$list" | grep -q mybot && echo true || echo false)"

echo "-- _registry_remove --"
_registry_remove "mybot"
check "mybot removed" "false" "$(echo "$(_registry_list)" | grep -q mybot && echo true || echo false)"

echo "-- default cascades --"
result=$(_registry_default)
check "default cascaded to devbot" "devbot" "$result"

echo "-- explicit default --"
_registry_add "thirdbot" "permissive"
_registry_default "thirdbot"
result=$(_registry_default)
check "explicit default set" "thirdbot" "$result"

echo ""
echo "=== Name Validation Tests ==="

echo "-- valid names --"
check "simple name" "mybot" "$(_validate_name "mybot")"
check "with hyphen" "my-bot" "$(_validate_name "my-bot")"
check "uppercase normalized" "mybot" "$(_validate_name "MyBot")"
check "with numbers" "bot42" "$(_validate_name "bot42")"

echo "-- invalid names (run in subshells since _validate_name exits) --"
expect_reject() {
    local label="$1" input="$2"
    if (source "$SCRIPT_DIR/lib/hermesclaw-helpers.sh"; _validate_name "$input") &>/dev/null; then
        echo "  FAIL: $label accepted"; FAIL=$((FAIL + 1))
    else
        echo "  PASS: $label rejected"; PASS=$((PASS + 1))
    fi
}
expect_reject "leading hyphen" "-bad"
expect_reject "trailing hyphen" "bad-"
expect_reject "spaces" "has spaces"
expect_reject "underscore" "has_underscore"

echo "-- reserved names --"
expect_reject "reserved 'help'" "help"
expect_reject "reserved 'version'" "version"
expect_reject "reserved 'list'" "list"
expect_reject "reserved 'backup-all'" "backup-all"

# Cleanup
rm -rf "$HERMESCLAW_HOME"

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
