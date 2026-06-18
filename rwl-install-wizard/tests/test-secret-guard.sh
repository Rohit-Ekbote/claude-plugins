#!/usr/bin/env bash
# test-secret-guard.sh - Unit tests for lib/secret-guard.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
GUARD="$PLUGIN_DIR/lib/secret-guard.sh"

PASS=0; FAIL=0
assert_rc() {
    if [ "$1" = "$2" ]; then
        printf "  PASS: %s\n" "$3"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, expected=%s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1))
    fi
}

echo "== secret-guard: clean dir passes =="
bash "$GUARD" "$SCRIPT_DIR/fixtures/secret-clean" >/dev/null 2>&1
assert_rc "$?" "0" "clean fixture dir exits 0"

echo "== secret-guard: dirty dir is flagged =="
bash "$GUARD" "$SCRIPT_DIR/fixtures/secret-dirty" >/dev/null 2>&1
assert_rc "$?" "2" "dirty fixture dir exits 2"

echo "== secret-guard: dirty output names the offending file =="
out="$(bash "$GUARD" "$SCRIPT_DIR/fixtures/secret-dirty" 2>&1)"
case "$out" in
  *values-bad.yaml*) printf "  PASS: %s\n" "names offending file"; PASS=$((PASS+1)) ;;
  *) printf "  FAIL: %s\n" "names offending file"; FAIL=$((FAIL+1)) ;;
esac

echo "== secret-guard: compound camelCase key flagged =="
tmp="$(mktemp "${TMPDIR:-/tmp}/secret-guard-XXXXXX")"
printf 'auth:\n  postgresPassword: literalpw\n' > "$tmp"
bash "$GUARD" "$tmp" >/dev/null 2>&1
assert_rc "$?" "2" "compound key postgresPassword exits 2"
rm -f "$tmp"

echo "== secret-guard: non-secret key NOT flagged =="
tmp="$(mktemp "${TMPDIR:-/tmp}/secret-guard-XXXXXX")"
printf 'model:\n  tokenizer: gpt2\n  image: postgres:16\n' > "$tmp"
bash "$GUARD" "$tmp" >/dev/null 2>&1
assert_rc "$?" "0" "non-secret keys (tokenizer/image) exit 0"
rm -f "$tmp"

echo ""
echo "secret-guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
