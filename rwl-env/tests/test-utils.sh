#!/usr/bin/env bash
# test-utils.sh - Unit tests for rwlenv-utils.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Point at fixtures
export RWLENV_CONFIG_DIR="$SCRIPT_DIR/fixtures"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/lib/rwlenv-utils.sh"

PASS=0; FAIL=0

assert_eq() {
    local actual="$1" expected="$2" desc="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s\n    expected=%q\n    actual=%q\n" "$desc" "$expected" "$actual"
        FAIL=$((FAIL+1))
    fi
}

assert_rc() {
    local rc="$1" expected="$2" desc="$3"
    if [[ "$rc" == "$expected" ]]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, expected=%s)\n" "$desc" "$rc" "$expected"
        FAIL=$((FAIL+1))
    fi
}

# --- Tests ---

echo "== get_config_dir =="
assert_eq "$(get_config_dir)" "$SCRIPT_DIR/fixtures" "respects RWLENV_CONFIG_DIR"

echo "== load_envs =="
assert_eq "$(load_envs | jq -r '.version')" "1.0" "loads envs.json version"
assert_eq "$(load_envs | jq -r '.rwlenvs | keys | length')" "2" "loads 2 rwlenvs"

echo "== get_rwlenv_by_name =="
assert_eq "$(get_rwlenv_by_name helm-dev | jq -r '.namespace')" "runwhen" "fetches helm-dev"
set +e; out=$(get_rwlenv_by_name nonexistent 2>/dev/null); assert_rc $? 1 "missing rwlenv returns rc=1"; set -e

echo "== list_rwlenv_names =="
got=$(list_rwlenv_names | sort | tr '\n' ',' | sed 's/,$//')
assert_eq "$got" "helm-dev,helm-staging" "lists all names"

echo "== is_readonly =="
set +e; is_readonly helm-dev; assert_rc $? 1 "helm-dev is not readOnly (rc=1)"
is_readonly helm-staging; assert_rc $? 0 "helm-staging is readOnly (rc=0)"; set -e

echo "== list_contexts_in_file =="
got=$(list_contexts_in_file "$SCRIPT_DIR/fixtures/kube-a.yaml" | sort | tr '\n' ',' | sed 's/,$//')
assert_eq "$got" "ctx-only-a,ctx-shared" "kube-a.yaml lists ctx-only-a + ctx-shared"

echo "== find_context_across_files =="
# Searches under a temporary KUBE_SEARCH_ROOT (env var, override of ~/.kube/)
export KUBE_SEARCH_ROOT="$SCRIPT_DIR/fixtures"
got=$(find_context_across_files ctx-only-a | tr '\n' '|' | sed 's/|$//')
# Format: "<file>\t<context>"
assert_eq "$got" "$SCRIPT_DIR/fixtures/kube-a.yaml	ctx-only-a" "ctx-only-a found in kube-a.yaml only"

got_count=$(find_context_across_files ctx-shared | wc -l | tr -d ' ')
assert_eq "$got_count" "2" "ctx-shared found in both files"

got=$(find_context_across_files ctx-missing | wc -l | tr -d ' ')
assert_eq "$got" "0" "ctx-missing returns no matches"
unset KUBE_SEARCH_ROOT

echo "== is_helm_write_operation =="
is_helm_write_operation "upgrade"; assert_rc $? 0 "upgrade is a write"
is_helm_write_operation "rollback"; assert_rc $? 0 "rollback is a write"
is_helm_write_operation "install"; assert_rc $? 0 "install is a write (forbidden by allowlist later)"
is_helm_write_operation "uninstall"; assert_rc $? 0 "uninstall is a write"
set +e
is_helm_write_operation "get values"; assert_rc $? 1 "get values is not a write"
is_helm_write_operation "history"; assert_rc $? 1 "history is not a write"
set -e

echo "== is_helm_forbidden_operation =="
is_helm_forbidden_operation "install"; assert_rc $? 0 "install is forbidden"
is_helm_forbidden_operation "uninstall"; assert_rc $? 0 "uninstall is forbidden"
is_helm_forbidden_operation "delete"; assert_rc $? 0 "delete is forbidden"
set +e
is_helm_forbidden_operation "upgrade"; assert_rc $? 1 "upgrade is not forbidden"
is_helm_forbidden_operation "rollback"; assert_rc $? 1 "rollback is not forbidden"
set -e

echo "== is_kubectl_write_operation =="
is_kubectl_write_operation "apply"; assert_rc $? 0 "apply is a write"
is_kubectl_write_operation "delete"; assert_rc $? 0 "delete is a write"
is_kubectl_write_operation "patch"; assert_rc $? 0 "patch is a write"
is_kubectl_write_operation "scale"; assert_rc $? 0 "scale is a write"
is_kubectl_write_operation "set image"; assert_rc $? 0 "set image is a write"
set +e
is_kubectl_write_operation "get"; assert_rc $? 1 "get is not a write"
is_kubectl_write_operation "logs"; assert_rc $? 1 "logs is not a write"
set -e
# rollout subcommands
is_kubectl_write_operation "rollout restart"; assert_rc $? 0 "rollout restart is a write"
is_kubectl_write_operation "rollout pause";   assert_rc $? 0 "rollout pause is a write"
is_kubectl_write_operation "rollout resume";  assert_rc $? 0 "rollout resume is a write"
is_kubectl_write_operation "rollout undo";    assert_rc $? 0 "rollout undo is a write"
set +e
is_kubectl_write_operation "rollout status";  assert_rc $? 1 "rollout status is not a write"
is_kubectl_write_operation "rollout history"; assert_rc $? 1 "rollout history is not a write"
set -e

echo "== validate_psql_query =="
validate_psql_query "SELECT * FROM users"; assert_rc $? 0 "SELECT allowed"
validate_psql_query "EXPLAIN SELECT 1"; assert_rc $? 0 "EXPLAIN allowed"
set +e
validate_psql_query "INSERT INTO t VALUES (1)" 2>/dev/null; assert_rc $? 1 "INSERT blocked"
validate_psql_query "UPDATE t SET x=1" 2>/dev/null; assert_rc $? 1 "UPDATE blocked"
validate_psql_query "DELETE FROM t" 2>/dev/null; assert_rc $? 1 "DELETE blocked"
validate_psql_query "CREATE TABLE x (a int)" 2>/dev/null; assert_rc $? 1 "CREATE blocked"
validate_psql_query "DROP TABLE x" 2>/dev/null; assert_rc $? 1 "DROP blocked"
validate_psql_query "TRUNCATE x" 2>/dev/null; assert_rc $? 1 "TRUNCATE blocked"
validate_psql_query "COPY x TO '/tmp/f'" 2>/dev/null; assert_rc $? 1 "COPY TO blocked"
validate_psql_query "SELECT 1; DROP TABLE x" 2>/dev/null; assert_rc $? 1 "multi-stmt with DDL blocked"
set -e

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
