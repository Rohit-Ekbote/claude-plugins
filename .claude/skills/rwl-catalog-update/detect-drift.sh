#!/usr/bin/env bash
# detect-drift.sh --chart <dir> [--catalog <f>] [--out <dir>]
# Deterministic drift detector. Writes <out>/findings.tsv; never edits sources.
set -uo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SKILL_DIR/../../.." && pwd)"
CATALOG="$REPO/rwl-install-wizard/data/knob-catalog.yaml"
CHART=""; OUT="./.rwl-catalog-drift"

while [ $# -gt 0 ]; do
  case "$1" in
    --chart)   CHART="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$CHART" ] && [ -f "$CHART/Chart.yaml" ] || { echo "usage: --chart <dir with Chart.yaml>" >&2; exit 2; }
mkdir -p "$OUT"; FINDINGS="$OUT/findings.tsv"; : > "$FINDINGS"

# emit_finding <bucket:auto|decide> <kind> <option> <detail> <evidence> <current> <chart>
emit_finding() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$FINDINGS"
}

check_chartcompat() {
  local ver compat
  ver="$(awk '/^version:/{print $2; exit}' "$CHART/Chart.yaml")"
  compat="$(awk -F'"' '/^chartCompat:/{print $2; exit}' "$CATALOG")"
  local upper lower vmm
  upper="$(printf '%s' "$compat" | sed -nE 's/.*<([0-9]+\.[0-9]+).*/\1/p')"
  lower="$(printf '%s' "$compat" | sed -nE 's/.*>=([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')"
  vmm="$(printf '%s' "$ver" | sed -nE 's/^([0-9]+\.[0-9]+).*/\1/p')"
  local outside=""
  # At/above the exclusive upper bound (0.3.x is outside `<0.3`).
  if [ -n "$upper" ] && [ -n "$vmm" ] && [ "$(printf '%s\n%s\n' "$vmm" "$upper" | sort -V | head -1)" = "$upper" ]; then
    outside="above"
  fi
  # Below the inclusive lower bound.
  if [ -n "$lower" ] && [ "$(printf '%s\n%s\n' "$ver" "$lower" | sort -V | head -1)" = "$ver" ] && [ "$ver" != "$lower" ]; then
    outside="below"
  fi
  if [ -n "$outside" ]; then
    emit_finding decide chartCompat "" "chart $ver is outside catalog range $compat ($outside bound)" "$CHART/Chart.yaml" "$compat" "$ver"
  else
    emit_finding auto chartCompat "" "chart $ver within catalog range $compat" "$CHART/Chart.yaml" "$compat" "$ver"
  fi
}

check_validators() {
  local helpers="$CHART/templates/_helpers.tpl"; [ -f "$helpers" ] || return 0
  local baseline="$SKILL_DIR/validators.baseline"
  grep -oE 'define "runwhen\.[a-zA-Z.]*validate"' "$helpers" \
    | sed -E 's/define "(.*)"/\1/' | sort -u > "$OUT/validators.chart"
  # names in chart but not in baseline = newly added
  comm -13 <(sort -u "$baseline") "$OUT/validators.chart" | while IFS= read -r v; do
    [ -n "$v" ] || continue
    emit_finding decide validator "" "new fail-fast validator '$v' — may require a new question/param" "$helpers" "" "$v"
  done
}

# Read catalog pinnedTags via ruby (neo4j/vault/bciBaseHelmTest -> version string).
catalog_pinned() {
  ruby -ryaml -e '
    c=YAML.load_file(ARGV[0])
    c["axes"].each{|a| (a["options"]||[]).each{|o|
      n=((o["emits"]||{})["x-airgap-pinned-tags-notice"]||{})["pinnedTags"]
      next unless n
      n.each{|k,v| puts "#{k}\t#{v}"}
    }}' "$CATALOG" | sort -u
}

check_tags() {
  local ex="$CHART/values-example-airgap-jcr.yaml"; [ -f "$ex" ] || return 0
  # chart tags for the three pinned images, parsed from the example.
  local c_neo4j c_vault c_bci
  c_neo4j="$(grep -oE 'library/neo4j:[^"[:space:]]+' "$ex" | head -1 | sed 's#.*:##')"
  c_vault="$(awk '/hashicorp\/vault/{f=1} f&&/tag:/{gsub(/[",]/,"",$2);print $2;exit}' "$ex")"
  c_bci="$(grep -oE 'bci/bci-base:[^"[:space:]]+' "$ex" | head -1 | sed 's#.*:##')"
  catalog_pinned | while IFS="$(printf '\t')" read -r name ver; do
    local chart_ver=""
    case "$name" in
      neo4j) chart_ver="$c_neo4j" ;;
      vault) chart_ver="$c_vault" ;;
      bciBaseHelmTest) chart_ver="$c_bci" ;;
    esac
    [ -n "$chart_ver" ] || continue
    if [ "$chart_ver" != "$ver" ]; then
      emit_finding auto tag "$name" "pinned $name tag $ver != chart example $chart_ver" "$ex" "$ver" "$chart_ver"
    fi
  done
}

PUBLIC_HOSTS='us-docker\.pkg\.dev|ghcr\.io|quay\.io|registry-1\.docker\.io|docker\.io|registry\.k8s\.io|registry\.suse\.com'

list_options() {
  ruby -ryaml -e '
    YAML.load_file(ARGV[0])["axes"].each{|a| (a["options"]||[]).each{|o|
      puts o["id"] if o["overlay"] && o["emits"] && o["emits"]!={} }}' "$CATALOG"
}

check_render() {
  if ! command -v helm >/dev/null 2>&1 || [ ! -f "$CHART/values.yaml" ]; then
    emit_finding auto renderSkipped "" "helm or chart values.yaml unavailable — render checks skipped" "$CHART" "" ""
    return 0
  fi
  local opt tmp ov llm_off
  for opt in $(list_options); do
    tmp="$(mktemp -d)"
    ov="$(ruby "$SKILL_DIR/gen-overlays.rb" "$CATALOG" "$tmp" "$opt")"
    [ -n "$ov" ] || { rm -rf "$tmp"; continue; }
    # The chart fail-fasts when llmGateway.deploy=true and models[] is empty — the
    # DEFAULT — so options that don't configure the gateway can't render in isolation.
    # Disable the gateway for those. Do NOT disable it for an overlay that configures
    # llmGateway itself (e.g. internal-openai): --set would override the overlay and
    # blind this check to llmGateway.*/llmBootstrap drift, the exact surface it must cover.
    llm_off="--set llmGateway.deploy=false"
    grep -q '^llmGateway:' "$tmp/$ov" && llm_off=""
    if helm template rw "$CHART" -f "$CHART/values.yaml" -f "$tmp/$ov" $llm_off \
         --set neo4j.disableLookups=true --set qdrant.disableLookups=true \
         > "$tmp/render.yaml" 2> "$tmp/err"; then
      # The public-ref invariant applies ONLY to the registry overlay — it is the
      # one that mirrors images. Every other overlay legitimately inherits the
      # chart's public default images for services it doesn't touch, so checking
      # those would emit noise, not drift.
      if [ "$ov" = "values-registry.yaml" ] && grep -Eo '(image|customImage): *"?[^" }]+' "$tmp/render.yaml" \
           | grep -vE 'git_url|github\.com' | grep -Eq "$PUBLIC_HOSTS"; then
        emit_finding decide publicRef "$opt" "registry option renders a public image ref against this chart" "$CHART" "" ""
      fi
    else
      emit_finding decide render "$opt" "option fails to render: $(head -1 "$tmp/err" | cut -c1-160)" "$CHART" "" ""
    fi
    rm -rf "$tmp"
  done
}

check_chartcompat
check_validators
check_tags
check_render
ruby "$SKILL_DIR/assemble-report.rb" "$FINDINGS" "$OUT"
A="$(awk -F'\t' '$1=="auto"' "$FINDINGS" | wc -l | tr -d ' ')"
D="$(awk -F'\t' '$1=="decide"' "$FINDINGS" | wc -l | tr -d ' ')"
echo "drift: $A auto-fixable, $D need decision -> $OUT/drift-report.md"
