#!/usr/bin/env bash
set -euo pipefail

_tmpbase=$(mktemp -d)
export HERMESCLAW_HOME="$_tmpbase/hc"
mkdir -p "$HERMESCLAW_HOME"

BOLD="" GREEN="" RED="" YELLOW="" CYAN="" DIM="" RESET=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hermesclaw-helpers.sh"

PASS=0; FAIL=0

echo "=== Credential Leak Detection Tests ==="

# Helper to create a test zip (uses python since zip may not be available)
make_test_zip() {
    local zipfile="$1"
    shift
    python3 -c "
import zipfile, sys, os
zf = zipfile.ZipFile('$zipfile', 'w')
for pair in sys.argv[1:]:
    name, content = pair.split('=', 1)
    zf.writestr(name, content + '\n')
zf.close()
" "$@"
}

echo "-- clean backup (no credentials) --"
zipfile="$_tmpbase/clean.zip"
make_test_zip "$zipfile" \
    "config.yaml=model: hermes-3" \
    "MEMORY.md=User likes coffee"
output=$(_warn_credentials "$zipfile" 2>&1 || true)
if [ -z "$output" ]; then
    echo "  PASS: no warning for clean backup"; PASS=$((PASS + 1))
else
    echo "  FAIL: unexpected warning: $output"; FAIL=$((FAIL + 1))
fi

echo "-- backup with OpenRouter key (sk-or-v1-) --"
zipfile="$_tmpbase/openrouter.zip"
make_test_zip "$zipfile" \
    "config.yaml=api_key: sk-or-v1-abc123def456"
output=$(_warn_credentials "$zipfile" 2>&1 || true)
if echo "$output" | grep -q "Possible API key"; then
    echo "  PASS: detected OpenRouter key"; PASS=$((PASS + 1))
else
    echo "  FAIL: missed OpenRouter key"; FAIL=$((FAIL + 1))
fi

echo "-- backup with NVIDIA NIM key (nvapi-) --"
zipfile="$_tmpbase/nvidia.zip"
make_test_zip "$zipfile" \
    "settings.json=key: nvapi-1234567890"
output=$(_warn_credentials "$zipfile" 2>&1 || true)
if echo "$output" | grep -q "Possible API key"; then
    echo "  PASS: detected NVIDIA NIM key"; PASS=$((PASS + 1))
else
    echo "  FAIL: missed NVIDIA NIM key"; FAIL=$((FAIL + 1))
fi

echo "-- backup with Anthropic key (sk-ant-) --"
zipfile="$_tmpbase/anthropic.zip"
make_test_zip "$zipfile" \
    "deep/nested/file.txt=token: sk-ant-api03-xyzabc"
output=$(_warn_credentials "$zipfile" 2>&1 || true)
if echo "$output" | grep -q "deep/nested/file.txt"; then
    echo "  PASS: detected Anthropic key with correct path"; PASS=$((PASS + 1))
else
    echo "  FAIL: missed Anthropic key or wrong path"; FAIL=$((FAIL + 1))
fi

echo "-- backup with GitHub token (ghp_) --"
zipfile="$_tmpbase/github.zip"
make_test_zip "$zipfile" \
    ".env=GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx"
output=$(_warn_credentials "$zipfile" 2>&1 || true)
if echo "$output" | grep -q "Possible API key"; then
    echo "  PASS: detected GitHub token"; PASS=$((PASS + 1))
else
    echo "  FAIL: missed GitHub token"; FAIL=$((FAIL + 1))
fi

echo "-- backup with multiple keys --"
zipfile="$_tmpbase/multi.zip"
make_test_zip "$zipfile" \
    "a.txt=key: sk-proj-abc123" \
    "b.txt=key: glpat-xyz789" \
    "c.txt=just normal text"
output=$(_warn_credentials "$zipfile" 2>&1 || true)
a_found=$(echo "$output" | grep -c "a.txt" || true)
b_found=$(echo "$output" | grep -c "b.txt" || true)
c_found=$(echo "$output" | grep -c "c.txt" || true)
if [ "$a_found" -ge 1 ] && [ "$b_found" -ge 1 ] && [ "$c_found" -eq 0 ]; then
    echo "  PASS: detected both keys, skipped clean file"; PASS=$((PASS + 1))
else
    echo "  FAIL: detection mismatch (a=$a_found b=$b_found c=$c_found)"; FAIL=$((FAIL + 1))
fi

echo "-- proxy warning message shown --"
zipfile="$_tmpbase/openrouter.zip"
output=$(_warn_credentials "$zipfile" 2>&1 || true)
if echo "$output" | grep -q "proxied via OpenShell"; then
    echo "  PASS: shows OpenShell proxy warning"; PASS=$((PASS + 1))
else
    echo "  FAIL: missing proxy warning"; FAIL=$((FAIL + 1))
fi

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"

rm -rf "$_tmpbase"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
