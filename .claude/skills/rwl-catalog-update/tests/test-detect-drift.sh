#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$DIR")"
DET="$SKILL/detect-drift.sh"
FIX="$DIR/fixtures"
PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }
field(){ awk -F'\t' -v k="$1" '$2==k{print; exit}' "$2"; }   # first row with kind==k

echo "== chartCompat drift: chart 0.3.7 is outside >=0.2.37 <0.3 =="
OUT="$(mktemp -d)"
bash "$DET" --chart "$FIX/chart-compat" --out "$OUT" >/dev/null 2>&1
row="$(field chartCompat "$OUT/findings.tsv")"
[ -n "$row" ] && ok "emits a chartCompat finding" || no "no chartCompat finding"
echo "$row" | grep -q "0.3.7" && ok "records detected version 0.3.7" || no "version not recorded"
echo "$row" | grep -q "^decide" && ok "chartCompat out-of-range is needs-decision" || no "wrong bucket"
rm -rf "$OUT"

echo "== usage error without --chart =="
bash "$DET" --out /tmp/x >/dev/null 2>&1; [ "$?" = "2" ] && ok "exit 2 without --chart" || no "wrong exit"

echo ""; echo "detect-drift: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
