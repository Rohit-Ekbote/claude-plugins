#!/usr/bin/env bash
# test-catalog.sh - Validate services-catalog.json structure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CATALOG="$PLUGIN_DIR/data/services-catalog.json"

PASS=0; FAIL=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s\n" "$desc"; FAIL=$((FAIL+1))
    fi
}

echo "== services-catalog.json structure =="
check "JSON parses" jq . "$CATALOG"
check "has chartAppVersion" jq -e '.chartAppVersion' "$CATALOG"
check "has chartName" jq -e '.chartName == "runwhen-platform"' "$CATALOG"
check "has version" jq -e '.version' "$CATALOG"
check "services is an object" jq -e '.services | type == "object"' "$CATALOG"
check "services is non-empty" jq -e '.services | length > 0' "$CATALOG"

echo "== per-service required fields =="
check "every service has description" jq -e '.services | to_entries | map(select(.value.description == null)) | length == 0' "$CATALOG"
check "every service has namespace" jq -e '.services | to_entries | map(select(.value.namespace == null)) | length == 0' "$CATALOG"
check "every service has imageTagKey" jq -e '.services | to_entries | map(select(.value.imageTagKey == null)) | length == 0' "$CATALOG"
check "every service has podSelector" jq -e '.services | to_entries | map(select(.value.podSelector == null)) | length == 0' "$CATALOG"
check "every service has containerName (string, may be empty)" jq -e '.services | to_entries | map(select((.value.containerName | type) != "string")) | length == 0' "$CATALOG"
check "every service has probes object" jq -e '.services | to_entries | map(select((.value.probes | type) != "object")) | length == 0' "$CATALOG"
check "every service has deploymentWaitFor array" jq -e '.services | to_entries | map(select((.value.deploymentWaitFor | type) != "array")) | length == 0' "$CATALOG"

echo "== no _TODO_ placeholders remaining =="
check "no _TODO_ markers anywhere" sh -c "! grep -q '_TODO_' '$CATALOG'"

echo "== placeholders intact =="
check "<rwl-env-ns> appears (for runtime substitution)" sh -c "grep -q '<rwl-env-ns>' '$CATALOG'"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
