#!/usr/bin/env bash
# test-hooks.sh - Decision-matrix tests for transform-commands.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$PLUGIN_DIR/hooks/transform-commands.sh"

PASS=0; FAIL=0

# Set up a temp project dir with a fixture .claude/rwl-env-env
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/.claude"
trap "rm -rf $TMPDIR_TEST" EXIT

use_fixture() {
    cp "$SCRIPT_DIR/fixtures/rwl-env-env-$1" "$TMPDIR_TEST/.claude/rwl-env-env"
}
clear_fixture() {
    rm -f "$TMPDIR_TEST/.claude/rwl-env-env"
}

# Run hook with a given Bash command. Returns "<rc>|<stdout>".
run_hook() {
    local cmd="$1"
    local input
    input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
    local out rc
    out=$(cd "$TMPDIR_TEST" && echo "$input" | bash "$HOOK" 2>/dev/null) && rc=$? || rc=$?
    printf "%d|%s" "$rc" "$out"
}

assert_allow() {
    local cmd="$1" desc="$2"
    local result; result=$(run_hook "$cmd")
    local rc="${result%%|*}" out="${result#*|}"
    if [[ "$rc" == "0" ]] && echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, out=%s)\n" "$desc" "$rc" "$out"
        FAIL=$((FAIL+1))
    fi
}

assert_block() {
    local cmd="$1" desc="$2"
    local result; result=$(run_hook "$cmd")
    local rc="${result%%|*}"
    if [[ "$rc" == "2" ]]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, expected 2)\n" "$desc" "$rc"
        FAIL=$((FAIL+1))
    fi
}

# --- Engagement tests ---

echo "== No rwl-env-env: pass through =="
clear_fixture
assert_allow "echo hello" "echo passes through without env file"
assert_allow "kubectl get pods" "kubectl passes through without env file (no opinion)"

echo "== Non-managed binaries with env file =="
use_fixture helm-dev
assert_allow "ls -la" "ls always allowed"
assert_allow "git status" "git always allowed"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
