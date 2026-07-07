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

echo "== chartCompat: a chart below the >= floor is also flagged =="
OUTLO="$(mktemp -d)"; CHLO="$OUTLO/chart"; mkdir -p "$CHLO"
printf 'apiVersion: v2\nname: runwhen-platform\nversion: 0.1.5\n' > "$CHLO/Chart.yaml"
bash "$DET" --chart "$CHLO" --out "$OUTLO" >/dev/null 2>&1
row="$(field chartCompat "$OUTLO/findings.tsv")"
echo "$row" | grep -q "^decide" && ok "below-floor 0.1.5 flagged decide" || no "below-floor not flagged"
rm -rf "$OUTLO"

echo "== validator inventory: a new validate helper is flagged =="
OUT2="$(mktemp -d)"; CH="$OUT2/chart"; mkdir -p "$CH/templates"
printf 'apiVersion: v2\nname: runwhen-platform\nversion: 0.2.54\n' > "$CH/Chart.yaml"
cp "$FIX/helpers-extra-validator.tpl" "$CH/templates/_helpers.tpl"
bash "$DET" --chart "$CH" --out "$OUT2" >/dev/null 2>&1
if grep -q $'\tvalidator\t.*workspaceBootstrap' "$OUT2/findings.tsv"; then ok "new validator workspaceBootstrap flagged"; else no "new validator not flagged"; fi
grep -q $'\tvalidator\t.*objectStorage' "$OUT2/findings.tsv" && no "baseline validator wrongly flagged" || ok "baseline validators not re-flagged"
rm -rf "$OUT2"

echo "== tag drift: neo4j bumped in chart example is flagged auto-fixable =="
OUT3="$(mktemp -d)"; CH3="$OUT3/chart"; mkdir -p "$CH3"
printf 'apiVersion: v2\nname: runwhen-platform\nversion: 0.2.54\n' > "$CH3/Chart.yaml"
cp "$FIX/example-bumped-tag.yaml" "$CH3/values-example-airgap-jcr.yaml"
bash "$DET" --chart "$CH3" --out "$OUT3" >/dev/null 2>&1
row="$(field tag "$OUT3/findings.tsv")"
echo "$row" | grep -q "neo4j" && ok "neo4j tag drift detected" || no "neo4j tag drift missing"
echo "$row" | grep -q "5.26.99" && ok "records chart tag 5.26.99" || no "chart tag not recorded"
echo "$row" | grep -q "^auto" && ok "tag drift is auto-fixable" || no "wrong bucket for tag"
# vault unchanged (1.21.2 == catalog) must NOT be flagged
awk -F'\t' '$2=="tag"&&$3=="vault"' "$OUT3/findings.tsv" | grep -q . && no "unchanged vault flagged" || ok "unchanged vault not flagged"
rm -rf "$OUT3"

echo ""; echo "detect-drift: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
