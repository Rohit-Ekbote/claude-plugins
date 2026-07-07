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

echo "== render check: runs against real chart if available, else skips cleanly =="
OUT4="$(mktemp -d)"
REALCHART="${RWL_CHART_PATH:-/Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform}"
if command -v helm >/dev/null 2>&1 && [ -f "$REALCHART/values.yaml" ]; then
  bash "$DET" --chart "$REALCHART" --out "$OUT4" >/dev/null 2>&1
  # mirrored-per-upstream must render clean against the current chart -> no render/publicRef finding for it
  if awk -F'\t' '($2=="render"||$2=="publicRef")&&$3=="mirrored-per-upstream"' "$OUT4/findings.tsv" | grep -q .; then
    no "mirrored-per-upstream unexpectedly flagged against current chart"
  else ok "mirrored-per-upstream renders clean against current chart"; fi
  # internal-openai configures the gateway, so it must render at full fidelity
  # (gateway NOT force-disabled) and therefore not be flagged.
  if awk -F'\t' '($2=="render"||$2=="publicRef")&&$3=="internal-openai"' "$OUT4/findings.tsv" | grep -q .; then
    no "internal-openai unexpectedly flagged (gateway render fidelity lost)"
  else ok "internal-openai renders clean with gateway enabled"; fi
else
  bash "$DET" --chart "$FIX/chart-compat" --out "$OUT4" >/dev/null 2>&1
  grep -q $'\trenderSkipped\t' "$OUT4/findings.tsv" && ok "render check skips cleanly without chart/helm" || no "no renderSkipped note"
fi
rm -rf "$OUT4"

echo "== report assembly: md + json grouped by bucket =="
OUT5="$(mktemp -d)"
bash "$DET" --chart "$FIX/chart-compat" --out "$OUT5" >/dev/null 2>&1
[ -f "$OUT5/drift-report.md" ] && ok "writes drift-report.md" || no "no drift-report.md"
[ -f "$OUT5/drift-report.json" ] && ok "writes drift-report.json" || no "no drift-report.json"
ruby -rjson -e 'j=JSON.parse(File.read(ARGV[0])); abort unless j.key?("autoFixable")&&j.key?("needsDecision")' "$OUT5/drift-report.json" && ok "json has both buckets" || no "json shape wrong"
grep -q "Needs decision" "$OUT5/drift-report.md" && ok "md has needs-decision section" || no "md missing section"
rm -rf "$OUT5"

echo "== tag drift: bci-base bumped in chart values.yaml is flagged =="
OUTB="$(mktemp -d)"; CHB="$OUTB/chart"; mkdir -p "$CHB"
printf 'apiVersion: v2\nname: runwhen-platform\nversion: 0.2.54\n' > "$CHB/Chart.yaml"
cat > "$CHB/values-example-airgap-jcr.yaml" <<'YML'
neo4j:
  image:
    customImage: "h/docker-dockerhub/library/neo4j:5.26.0"
vault:
  server:
    image:
      repository: "h/docker-dockerhub/hashicorp/vault"
      tag: "1.21.2"
YML
cat > "$CHB/values.yaml" <<'YML'
qdrant:
  chartTests:
    dbInteraction:
      image: registry.suse.com/bci/bci-base:15.99
YML
bash "$DET" --chart "$CHB" --out "$OUTB" >/dev/null 2>&1
brow="$(awk -F'\t' '$2=="tag"&&$3=="bciBaseHelmTest"' "$OUTB/findings.tsv")"
[ -n "$brow" ] && ok "bci-base tag drift detected from values.yaml" || no "bci-base drift missing"
echo "$brow" | grep -q "15.99" && ok "records chart bci tag 15.99" || no "chart bci tag not recorded"
awk -F'\t' '$2=="tag"&&($3=="neo4j"||$3=="vault")' "$OUTB/findings.tsv" | grep -q . && no "unchanged neo4j/vault flagged" || ok "unchanged neo4j/vault not flagged"
rm -rf "$OUTB"

echo "== consumer check: only the KNOWN byo-datastores neo4j mismatch, nothing else =="
REALCHART="${RWL_CHART_PATH:-/Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform}"
if command -v helm >/dev/null 2>&1 && [ -f "$REALCHART/values.yaml" ]; then
  OUTC="$(mktemp -d)"
  bash "$DET" --chart "$REALCHART" --out "$OUTC" >/dev/null 2>&1
  # byo-datastores + external Neo4j is a KNOWN chart bug (agentfarm/usearch hardcode
  # the bundled neo4j host) — see data/known-issues/neo4j-external-agentfarm-usearch.md.
  # The detector is EXPECTED to flag exactly that option and no other.
  if awk -F'\t' '$2=="consumerMismatch" && $3=="byo-datastores"' "$OUTC/findings.tsv" | grep -q .; then
    ok "detector flags the known byo-datastores neo4j consumerMismatch"
  else no "detector did not flag byo-datastores (consumer check not running?)"; fi
  unexpected="$(awk -F'\t' '$2=="consumerMismatch" && $3!="byo-datastores"{print $3}' "$OUTC/findings.tsv" | sort -u | tr '\n' ' ')"
  [ -z "$unexpected" ] && ok "no unexpected consumerMismatch" || no "unexpected consumerMismatch: $unexpected"
  rm -rf "$OUTC"
else
  ok "SKIP consumer check (no chart/helm)"
fi

echo ""; echo "detect-drift: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
