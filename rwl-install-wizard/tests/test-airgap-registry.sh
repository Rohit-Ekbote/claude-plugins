#!/usr/bin/env bash
# test-airgap-registry.sh — Regression guard for the air-gap install kit.
#
# Ground-truth review (v0.1.2) found the generated air-gap values were NOT
# installable. This guard asserts the fixes against the WORKING reference
# (infra-flux .../airgap/runwhen-platform/helmrelease.yaml) + the chart schema:
#
#   MISSED-1  no registryOverride; per-upstream, path-preserving image refs so
#             overlay == image-manifest push targets; no public registry survives.
#   MISSED-2  seaweedfs.s3.existingConfigSecret == <release>-seaweedfs-identities.
#   MISSED-3  metricstore.persistence.storageClassName (not the ignored storageClass).
#   MISSED-4  every stateful component (spilo/vault/neo4j/redis) wired to the class.
#   MISSED-5  llmBootstrap emitted (LLM stack seeded, not inert).
#   MISSED-6  codeCollections + cc-catalog sources repointed at the mirror.
#   MISSED-7  ccCatalog.auth.dockerconfigjsonSecret emitted.
#
# Static checks always run (no helm needed). The RENDER check runs when a chart
# is available (env RWL_CHART_PATH, else a known local path) — it `helm template`s
# the fixtures with a NON-`rw` release and asserts zero public/unresolved image
# refs and no validate fail-fast (the check the old public-host grep couldn't do).
#
# bash 3.2 compatible (macOS default). No YAML parser.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CATALOG="$PLUGIN_DIR/data/knob-catalog.yaml"
MANIFEST="$PLUGIN_DIR/data/guide-sections/airgap-image-manifest.md"
AIRGAP="$SCRIPT_DIR/fixtures/expected/airgap"
REG="$AIRGAP/values-registry.yaml"
STO="$AIRGAP/values-storage.yaml"
CLU="$AIRGAP/values-cluster.yaml"

PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }
has(){ grep -qF "$2" "$1"; }   # has <file> <literal>

option_block() {
  awk -v want="$1" '
    function fns(s){ return match(s, /[^ ]/) ? RSTART-1 : length(s) }
    {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/) {
        ind=fns($0); t=$0
        sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", t); sub(/[[:space:]].*$/, "", t)
        if (cap && ind<=start) cap=0
        if (t==want) { cap=1; start=ind; print; next }
      }
      if (cap) print
    }' "$CATALOG"
}

# Public hosts that must never survive into an air-gap overlay (git URLs excluded).
PUBLIC_HOSTS='us-docker\.pkg\.dev|ghcr\.io|quay\.io|registry-1\.docker\.io|docker\.io|registry\.k8s\.io|registry\.suse\.com'
no_public() {   # no_public <file> <label>
  if grep -nE "$PUBLIC_HOSTS" "$1" | grep -vE 'git_url|repoUrl|github\.com' >/dev/null; then
    no "$2 leaks a public registry host"; else ok "$2 has no public registry host"; fi
}

echo "== MISSED-1: registryOverride removed / per-upstream model =="
if grep -q 'id: flat-mirror' "$CATALOG"; then no "flat-mirror option still present (registryOverride footgun)"; else ok "flat-mirror option removed"; fi
if grep -q 'id: mirrored-per-upstream' "$CATALOG"; then ok "mirrored-per-upstream option present"; else no "mirrored-per-upstream option missing"; fi
# Match the emitted KEY only (strip comment lines first — the removal rationale
# legitimately names registryOverride in prose).
nocomment(){ grep -vE '^[[:space:]]*#' "$1"; }
if nocomment "$CATALOG" | grep -qE 'registryOverride[[:space:]]*:'; then no "catalog still emits a registryOverride key"; else ok "catalog never emits registryOverride"; fi
if nocomment "$REG" | grep -qE 'registryOverride[[:space:]]*:'; then no "values-registry.yaml sets registryOverride"; else ok "values-registry.yaml has no registryOverride"; fi

echo "== MISSED-1: overlays keep every image on the mirror (per-upstream paths) =="
no_public "$REG" "values-registry.yaml"
for ref in \
  "artifactory.corp.example/docker-runwhen-self-hosted/runwhen-self-hosted/platform-images" \
  "artifactory.corp.example/docker-ghcr/runwhen-contrib" \
  "artifactory.corp.example/docker-ghcr/berriai" \
  "artifactory.corp.example/docker-ghcr/zalando" \
  "artifactory.corp.example/docker-dockerhub/library/neo4j:5.26.0" \
  "artifactory.corp.example/docker-suse/bci/bci-base:15.7"; do
  if has "$REG" "$ref"; then ok "per-upstream ref present: ${ref##*/}"; else no "missing per-upstream ref: $ref"; fi
done

echo "== N1 pinned tags: self-warning + match manifest baseline =="
if has "$REG" "x-airgap-pinned-tags-notice" && has "$REG" "Chart.lock"; then ok "overlay carries the pinned-tags verify warning"; else no "overlay missing pinned-tags verify warning"; fi
for pair in "5.26.0 library/neo4j:5.26.0" "1.21.2 hashicorp/vault:1.21.2" "15.7 bci/bci-base:15.7"; do
  set -- $pair; ver="$1"; mref="$2"
  if has "$REG" "$ver" && has "$MANIFEST" "$mref"; then ok "pinned $ver matches manifest ($mref)"; else no "pinned $ver does not match manifest baseline"; fi
done

echo "== MISSED-2: seaweedfs identities pinned to <release>-seaweedfs-identities =="
if has "$STO" "rw-airgap-seaweedfs-identities"; then ok "seaweedfs.s3.existingConfigSecret set to release-scoped identities Secret"; else no "seaweedfs identities Secret not wired (validate will fail-fast)"; fi

echo "== MISSED-3/4: storage classes wired via the correct keys =="
if grep -A4 'metricstore:' "$STO" | grep -q 'storageClassName'; then ok "metricstore uses persistence.storageClassName"; else no "metricstore still uses the ignored storageClass key"; fi
for probe in "spilo:" "dataStorage:" "mode: dynamic" "master:"; do
  if has "$STO" "$probe"; then ok "storage wires component ($probe)"; else no "storage missing component override ($probe)"; fi
done
if [ "$(grep -c 'standard-rwo' "$STO")" -ge 8 ]; then ok "chosen StorageClass wired into every stateful component"; else no "StorageClass not wired into all components"; fi

echo "== MISSED-5/8: llmBootstrap + model_info.mode =="
for probe in "llmBootstrap:" "provider:" "dimension: 1536" "mode: chat" "mode: embedding"; do
  if has "$CLU" "$probe"; then ok "llm overlay has $probe"; else no "llm overlay missing $probe"; fi
done

echo "== MISSED-6/7: codeCollections + cc-catalog repointed; ccCatalog auth =="
if has "$REG" "dockerconfigjsonSecret: jcr-pull-secret"; then ok "ccCatalog.auth.dockerconfigjsonSecret wired"; else no "ccCatalog auth secret missing"; fi
if grep -E 'imageRegistry:|image_registry:' "$REG" | grep -q 'ghcr\.io'; then no "codecollection registry still public ghcr.io"; else ok "every codecollection registry points at the mirror"; fi
no_public "$STO" "values-storage.yaml"; no_public "$CLU" "values-cluster.yaml"

echo "== RENDER (oracle): helm template fixtures with a NON-rw release =="
CHART="${RWL_CHART_PATH:-/Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform}"
if command -v helm >/dev/null 2>&1 && [ -f "$CHART/Chart.yaml" ]; then
  TMP="$(mktemp)"
  # RENDER THE GENERATED OVERLAYS VERBATIM. Never pass --set values the plugin
  # does not emit — a --set crutch here is exactly what let MISSED-10 ship green
  # (the overlay omitted neo4j.disableLookups while the test injected it). The
  # overlays must render as an operator installs them, with no extra flags.
  if helm template rw-airgap "$CHART" -f "$CHART/values.yaml" -f "$REG" -f "$STO" -f "$CLU" >"$TMP" 2>"$TMP.err"; then
    ok "helm template succeeds (non-rw release; no validate fail-fast)"
    if grep -nE '(image|customImage): *"?('"$PUBLIC_HOSTS"')' "$TMP" >/dev/null; then
      no "rendered manifests contain a public image ref"; else ok "every rendered image ref is on the mirror"; fi
  else
    no "helm template FAILED: $(head -1 "$TMP.err")"
  fi
  # byo-datastores must ALSO render verbatim — external datastores layered with
  # the storage + cluster overlays. Exercises vault.external.address, whose flat
  # `vault.address` shape nil-pointered on the webhooks/agentfarm/csi templates
  # (the render guard only covered the bundled-datastores profile before). Uses
  # only plugin-emitted fixtures; NO --set.
  BYO="$(dirname "$AIRGAP")/byo-datastores/values-cluster.yaml"
  if helm template rw-airgap "$CHART" -f "$CHART/values.yaml" -f "$STO" -f "$CLU" -f "$BYO" >"$TMP" 2>"$TMP.err"; then
    if grep -q 'vault.example.com' "$TMP"; then
      ok "byo-datastores renders (external vault.external.address wired)"
    else no "byo-datastores rendered but external vault address absent"; fi
  else
    no "byo-datastores helm template FAILED: $(head -1 "$TMP.err")"
  fi
  rm -f "$TMP" "$TMP.err"
else
  echo "  SKIP: chart not found at \$RWL_CHART_PATH ($CHART) — static checks only"
fi

echo ""
echo "airgap-registry: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
