#!/usr/bin/env bash
# test-airgap-registry.sh — Regression guard for air-gap registry routing.
#
# Would have caught the BLOCKER: registry-routing→flat-mirror emitted only
# `registryOverride` + pull secrets. The chart's own `registryOverride` doc
# (values.yaml) states it CANNOT reach subchart-emitted images (vault, redis,
# neo4j, qdrant, mimir, seaweedfs, spilo, pgbouncer). With subcharts=bundled-all
# in an air-gapped cluster those images resolve to public registries and
# ImagePullBackOff. This test asserts every mirror option emits an explicit
# per-subchart image override, and that no rendered air-gap overlay leaks a
# public registry host.
#
# bash 3.2 compatible (macOS default). No YAML parser.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CATALOG="$PLUGIN_DIR/data/knob-catalog.yaml"
FIXT="$SCRIPT_DIR/fixtures"

PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

# Print the body of a catalog option (`- id: <want>` … next `- id:` at same or
# shallower indent). BSD-awk safe: no gawk match() capture groups.
option_block() {
  awk -v want="$1" '
    function fns(s){ return match(s, /[^ ]/) ? RSTART-1 : length(s) }
    {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/) {
        ind=fns($0); t=$0
        sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", t)
        sub(/[[:space:]].*$/, "", t)
        if (cap && ind<=start) cap=0
        if (t==want) { cap=1; start=ind; print; next }
      }
      if (cap) print
    }' "$CATALOG"
}

# Public registry hosts that must NEVER survive into a mirror emit/overlay.
PUBLIC_HOSTS='us-docker\.pkg\.dev|ghcr\.io|quay\.io|registry-1\.docker\.io|docker\.io|registry\.k8s\.io|registry\.suse\.com'

# Subchart images `registryOverride` cannot reach — each needs its own override.
# Markers are the distinctive emit keys the override introduces per subchart.
REQUIRED_MARKERS="spilo: redis: customImage: server: qdrant: seaweedfs:"

check_option_covers_subcharts() {
  opt="$1"; blk="$(option_block "$opt")"
  [ -n "$blk" ] || { no "$opt: option block not found in catalog"; return; }
  for m in $REQUIRED_MARKERS; do
    if printf '%s\n' "$blk" | grep -q "$m"; then ok "$opt emits subchart override '$m'"
    else no "$opt MISSING subchart image override '$m' (public-registry pull in air-gap)"; fi
  done
  # Check emitted VALUES only — strip YAML comments so upstream-registry names
  # used in explanatory comments (e.g. "# ghcr.io/zalando/spilo-17") don't trip it.
  if printf '%s\n' "$blk" | sed 's/#.*$//' | grep -Eq "$PUBLIC_HOSTS"; then
    no "$opt emit references a public registry host"
  else ok "$opt emit references no public registry host"; fi
}

echo "== flat-mirror covers every subchart image (the check that catches #1) =="
check_option_covers_subcharts flat-mirror

echo "== jfrog-per-upstream covers every subchart image =="
check_option_covers_subcharts jfrog-per-upstream

echo "== rendered air-gap overlays keep every image on the mirror host =="
for f in "$FIXT"/expected/airgap-flat-mirror/values-registry.yaml \
         "$FIXT"/expected/airgap-jfrog/values-registry.yaml; do
  label="$(basename "$(dirname "$f")")/$(basename "$f")"
  if [ ! -f "$f" ]; then no "missing expected overlay: $label"; continue; fi
  if grep -Eq "$PUBLIC_HOSTS" "$f"; then
    no "public registry host survives in $label"
  else ok "no public registry host in $label"; fi
done

# --- N1 guard: pinned subchart tags must be self-warning and must NOT drift
# from the airgap-image-manifest baseline. This is the check that would have
# caught v0.1.1 silently hard-pinning tags with no verify warning.
MANIFEST="$PLUGIN_DIR/data/guide-sections/airgap-image-manifest.md"
# canonical pinned tag -> the exact ref that must appear in the manifest baseline.
PIN_neo4j="library/neo4j:5.26.0"
PIN_vault="hashicorp/vault:1.21.2"
PIN_bci="bci/bci-base:15.7"

echo "== manifest baseline lists each hard-pinned tag (single source of truth) =="
for ref in "$PIN_neo4j" "$PIN_vault" "$PIN_bci"; do
  if grep -qF "$ref" "$MANIFEST"; then ok "manifest baseline has $ref"
  else no "manifest baseline MISSING $ref (overlay would drift from manifest)"; fi
done

echo "== every pinned tag in the overlay is self-warning AND matches the manifest =="
for f in "$FIXT"/expected/airgap-flat-mirror/values-registry.yaml \
         "$FIXT"/expected/airgap-jfrog/values-registry.yaml; do
  label="$(basename "$(dirname "$f")")/$(basename "$f")"
  [ -f "$f" ] || { no "missing expected overlay: $label"; continue; }
  # (b1) a visible verify-against-Chart.lock warning rides with the overlay.
  if grep -q 'x-airgap-pinned-tags-notice' "$f" && grep -q 'Chart.lock' "$f"; then
    ok "$label carries an x-airgap-pinned-tags-notice / Chart.lock warning"
  else no "$label has NO verify-against-Chart.lock warning for its pinned tags"; fi
  # (b2) each pinned version appears in the overlay AND equals the manifest ref.
  for pair in "neo4j 5.26.0 $PIN_neo4j" "vault 1.21.2 $PIN_vault" "bci 15.7 $PIN_bci"; do
    set -- $pair; name="$1"; ver="$2"; ref="$3"
    if grep -qF "$ver" "$f" && grep -qF "$ref" "$MANIFEST"; then
      ok "$label pins $name $ver, matching the manifest"
    else no "$label pins $name $ver but it does NOT match the manifest baseline"; fi
  done
done

echo "== catalog registry options declare the pinned-tags notice (structural guard) =="
for opt in flat-mirror jfrog-per-upstream; do
  if option_block "$opt" | grep -q 'x-airgap-pinned-tags-notice'; then
    ok "$opt emits x-airgap-pinned-tags-notice"
  else no "$opt lost its x-airgap-pinned-tags-notice (pinned tags would be silent again)"; fi
done

echo ""
echo "airgap-registry: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
