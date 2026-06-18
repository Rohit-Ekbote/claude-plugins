#!/usr/bin/env bash
# test-catalog-lint.sh - Unit tests for lib/catalog-lint.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
LINT="$PLUGIN_DIR/lib/catalog-lint.sh"
DATA="$PLUGIN_DIR/data"

PASS=0; FAIL=0
assert_rc() {
    if [ "$1" = "$2" ]; then printf "  PASS: %s\n" "$3"; PASS=$((PASS+1));
    else printf "  FAIL: %s (rc=%s, expected=%s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1)); fi
}

echo "== catalog-lint: real catalog is clean =="
bash "$LINT" "$DATA/knob-catalog.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "0" "shipped catalog passes lint"

echo "== catalog-lint: missing known-issue ref fails =="
bash "$LINT" "$SCRIPT_DIR/fixtures/catalog-bad-missing-ref.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "1" "missing id reference is rejected"

echo "== catalog-lint: inline secret in emits fails =="
bash "$LINT" "$SCRIPT_DIR/fixtures/catalog-bad-inline-secret.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "1" "inline secret in emits is rejected"

echo ""
echo "catalog-lint: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
