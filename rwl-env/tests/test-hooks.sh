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

echo "== Helm validation (helm-dev, read-write) =="
use_fixture helm-dev

# Allowed reads
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev get values rwl -n runwhen" "helm get values allowed"
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev history rwl -n runwhen" "helm history allowed"
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev status rwl -n runwhen" "helm status allowed"

# Allowed writes (read-write env)
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev upgrade rwl oci://registry.example.com/charts/runwhen-platform --reuse-values -n runwhen" "helm upgrade allowed when not readOnly"
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev rollback rwl 7 -n runwhen" "helm rollback allowed when not readOnly"

# Forbidden operations
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev install rwl chart -n runwhen" "helm install forbidden (out of scope)"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev uninstall rwl -n runwhen" "helm uninstall forbidden"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev delete rwl -n runwhen" "helm delete forbidden"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev repo add foo https://example.com -n runwhen" "helm repo add forbidden"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev repo remove foo -n runwhen" "helm repo remove forbidden"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev dependency build -n runwhen" "helm dependency forbidden"

# Flag mismatches
assert_block "helm --kubeconfig=/tmp/wrong --kube-context=k3d-rwl-dev get values rwl -n runwhen" "wrong kubeconfig blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=wrong-ctx get values rwl -n runwhen" "wrong context blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev get values rwl -n other-ns" "wrong namespace blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev upgrade other-release chart --reuse-values -n runwhen" "wrong release name blocked"

# Missing required flags
assert_block "helm get values rwl -n runwhen" "missing --kubeconfig and --kube-context blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig get values rwl -n runwhen" "missing --kube-context blocked"

echo "== Helm validation (helm-staging, read-only) =="
use_fixture helm-staging
assert_allow "helm --kubeconfig=/tmp/staging-kubeconfig --kube-context=staging-ctx get values rwl -n runwhen" "read on readOnly env allowed"
assert_block "helm --kubeconfig=/tmp/staging-kubeconfig --kube-context=staging-ctx upgrade rwl chart --reuse-values -n runwhen" "helm upgrade on readOnly blocked"
assert_block "helm --kubeconfig=/tmp/staging-kubeconfig --kube-context=staging-ctx rollback rwl 7 -n runwhen" "helm rollback on readOnly blocked"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
