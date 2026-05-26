---
name: rwl-upgrade-image-tag
description: Update a service's image tag via helm upgrade (deterministically revertible)
triggers:
  - /rwl-upgrade-image-tag
  - bump image tag
  - update image tag
args:
  - name: service
    description: Service name (papi, agentfarm, ...) — must be in services-catalog.json
    required: true
  - name: new_tag
    description: New image tag (e.g., 2026-05-22.3)
    required: true
  - name: chart
    description: Optional --chart <local-path> override for offline/airgap upgrades
    required: false
---

# Upgrade Image Tag via helm

Canonical write operation. Updates a single service's image tag via `helm upgrade --reuse-values --set <key>=<tag>`. Lists every other service that shares the same `imageTagKey` (since one helm values key can drive multiple deployments).

## Instructions

```bash
source .claude/rwl-env-env
```

### Step 1: Target selection

Source `.claude/rwl-env-env`. If `$RWLENV_HAS_RUNNER` is `true`, ask which target:

AskUserQuestion: "Which target?"
- Options: Platform ($RWLENV_RELEASE in $RWLENV_NAMESPACE), Runner ($RWLENV_RUNNER_RELEASE in $RWLENV_RUNNER_NAMESPACE)

Set variables based on selection:
- **Platform:** `TARGET_KUBECONFIG=$RWLENV_KUBECONFIG`, `TARGET_CONTEXT=$RWLENV_CONTEXT`, `TARGET_NAMESPACE=$RWLENV_NAMESPACE`, `TARGET_RELEASE=$RWLENV_RELEASE`, `TARGET_CHART_REPO=$RWLENV_CHART_REPO`, `TARGET_CHART_NAME=$RWLENV_CHART_NAME`, `TARGET_READ_ONLY=$RWLENV_READ_ONLY`, `TARGET_CATALOG=${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json`
- **Runner:** `TARGET_KUBECONFIG=$RWLENV_RUNNER_KUBECONFIG`, `TARGET_CONTEXT=$RWLENV_RUNNER_CONTEXT`, `TARGET_NAMESPACE=$RWLENV_RUNNER_NAMESPACE`, `TARGET_RELEASE=$RWLENV_RUNNER_RELEASE`, `TARGET_CHART_REPO=$RWLENV_RUNNER_CHART_REPO`, `TARGET_CHART_NAME=$RWLENV_RUNNER_CHART_NAME`, `TARGET_READ_ONLY=$RWLENV_RUNNER_READ_ONLY`, `TARGET_CATALOG=${CLAUDE_PLUGIN_ROOT}/data/runner-services-catalog.json`

If no runner configured, skip the prompt and use platform variables.

All subsequent steps use `$TARGET_*` variables instead of `$RWLENV_*`.

### Step 2: Refuse if read-only

If `$TARGET_READ_ONLY == "true"`: abort with "rwl-env '$RWLENV_NAME' is read-only."

### Step 3: Resolve service → imageTagKey

```bash
key=$(jq -r --arg s "$service" '.services[$s].imageTagKey // empty' "$TARGET_CATALOG")
if [[ -z "$key" ]]; then
    echo "Service '$service' not in catalog. Available:"
    jq -r '.services | keys[]' "$TARGET_CATALOG"
    exit 1
fi
```

### Step 4: List all services sharing this imageTagKey

```bash
shared=$(jq -r --arg k "$key" '.services | to_entries | map(select(.value.imageTagKey == $k)) | .[].key' "$TARGET_CATALOG")
```

Show these to the user so they know what else is moving.

### Step 5: Read current tag and chart version

Use the helm-ops agent (Task tool with subagent_type: "rwl-env:helm-ops") to run:
```
helm get values $TARGET_RELEASE -n $TARGET_NAMESPACE -o yaml
helm get metadata $TARGET_RELEASE -n $TARGET_NAMESPACE
helm history $TARGET_RELEASE -n $TARGET_NAMESPACE -o json
```

Extract:
- `currentTag` (via `yq <values> .<imageTagKey>`)
- `chartVersion` (from metadata)
- `currentRevision` (from history, the highest revision number)

### Step 6: Diff and confirm

AskUserQuestion:
```
Service:        <service>
Also affected:  <shared list>
Image tag:      <currentTag>  →  <new_tag>
Chart version:  <chartVersion>  (unchanged, --reuse-values)
Rollback hint:  /rwl-rollback --to-revision <currentRevision>
```
Options: "Yes, upgrade" / "No, cancel".

### Step 7: Execute upgrade via helm-ops

```bash
chart_ref="${chart_override:-$TARGET_CHART_REPO/$TARGET_CHART_NAME}"

helm \
    --kubeconfig="$TARGET_KUBECONFIG" --kube-context="$TARGET_CONTEXT" \
    -n "$TARGET_NAMESPACE" \
    upgrade "$TARGET_RELEASE" "$chart_ref" \
    --version "$chartVersion" \
    --reuse-values \
    --set "$key=$new_tag"
```

### Step 8: Wait for rollouts

For every service sharing the `imageTagKey`, run via k8s-ops:
```bash
selector=$(jq -r --arg s "$svc" '.services[$s].podSelector' "$TARGET_CATALOG")
kubectl --kubeconfig="$TARGET_KUBECONFIG" --context="$TARGET_CONTEXT" \
    -n "$TARGET_NAMESPACE" \
    rollout status deploy/<resolve-deploy-name-from-podSelector> --timeout=3m
```

### Step 9: Report

```
Upgrade complete.
Revision: <currentRevision>  →  <newRevision>      (rollback: /rwl-rollback --to-revision <currentRevision>)
Rollout:  papi ✓  activities ✓  alerts ✓  ...
Image:    <imageTagKey>=<new_tag> pulled successfully.
```

### Step 10: If any rollout failed

Print the rollback command prominently:
```
*** ROLLOUT FAILED *** for: <deploy-name>
Run: /rwl-rollback --to-revision <currentRevision>
```
Offer to invoke `/rwl-rollback --to-revision <N>` directly via AskUserQuestion.

If the failure signature matches a known chart bug (e.g., the migration-controller hang on agentfarm tags predating `migration_controller.py`), end with:
```
This looks like a known chart-bug signature. Run /rwl-report-chart-bug --symptom "<recap>" to draft a report.
```

## Error Handling

- Service not in catalog → list available services and exit.
- helm-ops returns non-zero → surface the stderr verbatim. If it's a chart-fetch error, suggest the `--chart <local-path>` flag.
- Hook blocks the helm call → surface the hook's stderr; do not retry.
