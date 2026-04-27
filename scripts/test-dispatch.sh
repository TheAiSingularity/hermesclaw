#!/usr/bin/env bash
set -euo pipefail

_tmpbase=$(mktemp -d)
export HERMESCLAW_HOME="$_tmpbase/hermesclaw-test"
mkdir -p "$HERMESCLAW_HOME"
export HOME="$_tmpbase/home-test"
mkdir -p "$HOME"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SCRIPT_DIR/hermesclaw"

# Stub openshell so _require_openshell doesn't exit
_fake_bin=$(mktemp -d)
printf '#!/bin/sh\necho "openshell stub $@"\n' > "$_fake_bin/openshell"
chmod +x "$_fake_bin/openshell"
export PATH="$_fake_bin:$PATH"

PASS=0; FAIL=0
check_contains() {
    local label="$1" expected="$2" output="$3"
    if echo "$output" | grep -qi "$expected"; then
        echo "  PASS: $label"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected to contain '$expected')"; FAIL=$((FAIL + 1))
    fi
}

echo "=== CLI Dispatch Tests ==="

echo "-- help command --"
out=$(bash "$CLI" help 2>&1)
check_contains "help shows USAGE" "USAGE" "$out"
check_contains "help shows GLOBAL" "GLOBAL COMMANDS" "$out"
check_contains "help shows LIFECYCLE" "LIFECYCLE COMMANDS" "$out"
check_contains "help shows snapshot" "snapshot" "$out"

echo "-- --help alias --"
out=$(bash "$CLI" --help 2>&1)
check_contains "--help shows USAGE" "USAGE" "$out"

echo "-- version command --"
out=$(bash "$CLI" version 2>&1)
check_contains "version shows 0.5.0" "0.5.0" "$out"

echo "-- --version alias --"
out=$(bash "$CLI" --version 2>&1)
check_contains "--version shows 0.5.0" "0.5.0" "$out"

echo "-- unknown command --"
out=$(bash "$CLI" foobar 2>&1 || true)
check_contains "unknown cmd shows error" "Unknown" "$out"

echo "-- list (empty registry) --"
out=$(bash "$CLI" list 2>&1)
check_contains "list shows header" "NAME" "$out"

echo "-- sandbox command without default errors --"
out=$(bash "$CLI" status 2>&1 || true)
check_contains "no default sandbox error" "No default sandbox" "$out"

echo "-- named sandbox start dispatch --"
out=$(bash "$CLI" testbot start 2>&1 || true)
check_contains "named start shows Starting" "Starting" "$out"

echo "-- list after start --"
out=$(bash "$CLI" list 2>&1)
check_contains "testbot in list" "testbot" "$out"

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"

rm -rf "$_tmpbase" "$_fake_bin"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
