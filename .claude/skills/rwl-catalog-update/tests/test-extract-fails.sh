#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$DIR")"
EX="$SKILL/extract-fails.rb"
PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== extract-fails: finds template fail builtins, ignores prose 'fail' =="
T="$(mktemp -d)"; mkdir -p "$T/sub"
cat > "$T/a.tpl" <<'TPL'
# this comment mentions fail but is not a builtin invocation
{{- if not .Values.foo }}{{ fail "foo is required: set foo.bar" }}{{- end }}
TPL
cat > "$T/sub/b.yaml" <<'YML'
{{- fail (printf "kind=%q is invalid, must be one of: a, b." $k) }}
YML
OUT="$(ruby "$EX" "$T")"
echo "$OUT" | grep -q 'foo is required: set foo.bar' && ok "captures fail \"...\" message" || no "missed direct fail message"
echo "$OUT" | grep -q 'kind=% is invalid, must be one of: a, b.' && ok "captures printf fail + normalizes %q" || no "missed/unnormalized printf fail"
[ "$(printf '%s\n' "$OUT" | grep -c .)" = "2" ] && ok "exactly two signatures (prose 'fail' ignored)" || no "wrong signature count: $(printf '%s' "$OUT" | grep -c .)"
rm -rf "$T"

echo "== extract-fails: %q/%s + whitespace collapse to ONE signature =="
T2="$(mktemp -d)"
cat > "$T2/c.tpl" <<'TPL'
{{ fail "x=%q  is    bad" }}
{{ fail (printf "x=%s is bad" $v) }}
TPL
OUT2="$(ruby "$EX" "$T2")"
[ "$(printf '%s\n' "$OUT2" | grep -c .)" = "1" ] && ok "%q and %s + whitespace normalize to one signature" || no "did not collapse to one"
printf '%s\n' "$OUT2" | cut -f1 | grep -qx 'x=% is bad' && ok "signature is 'x=% is bad'" || no "unexpected signature: $(printf '%s' "$OUT2" | cut -f1)"
rm -rf "$T2"

echo ""
echo "extract-fails: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
