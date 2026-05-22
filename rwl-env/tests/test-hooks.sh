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

echo "== Kubectl validation (helm-dev) =="
use_fixture helm-dev

# Reads allowed
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev get pods -n runwhen" "kubectl get pods allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev logs my-pod -n runwhen" "kubectl logs allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev describe deploy/papi -n runwhen" "kubectl describe allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev get events -n runwhen --sort-by=.lastTimestamp" "kubectl get events allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev rollout status deploy/papi -n runwhen" "kubectl rollout status allowed"

# Writes always blocked (even when not readOnly)
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev apply -f x.yaml -n runwhen" "kubectl apply blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev delete pod my-pod -n runwhen" "kubectl delete blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev patch deploy/papi --patch='{}' -n runwhen" "kubectl patch blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev edit deploy/papi -n runwhen" "kubectl edit blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev scale deploy/papi --replicas=3 -n runwhen" "kubectl scale blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev rollout restart deploy/papi -n runwhen" "kubectl rollout restart blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev set image deploy/papi papi=newtag -n runwhen" "kubectl set image blocked"

# Exec and port-forward allowed (reads from rwl-env perspective)
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec my-pod -n runwhen -- ls" "kubectl exec interactive allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev port-forward svc/papi 8080:8080 -n runwhen" "kubectl port-forward allowed"

# Flag mismatches
assert_block "kubectl --kubeconfig=/tmp/wrong --context=k3d-rwl-dev get pods -n runwhen" "wrong kubeconfig blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=wrong get pods -n runwhen" "wrong context blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev get pods -n elsewhere" "wrong namespace blocked"

echo "== psql validation =="
use_fixture helm-dev

assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'SELECT 1'" "exec + psql SELECT allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'EXPLAIN SELECT 1'" "exec + psql EXPLAIN allowed"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'INSERT INTO t VALUES (1)'" "exec + psql INSERT blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'DROP TABLE x'" "exec + psql DROP blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'TRUNCATE x'" "exec + psql TRUNCATE blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -f /tmp/file.sql" "psql -f file form blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core" "psql with no -c blocked (would start interactive)"

# Multi-statement
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'SELECT 1; DROP TABLE x'" "multi-stmt with DDL blocked"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
