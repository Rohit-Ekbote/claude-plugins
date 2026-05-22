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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
