---
name: rwl-upgrade-chart
description: Bump the chart itself to a newer version (preserves values via --reuse-values)
triggers:
  - /rwl-upgrade-chart
  - bump chart version
  - upgrade chart
args:
  - name: version
    description: New chart version (semver)
    required: true
  - name: chart
    description: Optional --chart <local-path>
    required: false
---

# Upgrade Chart Version

### Step 1: Target selection

Source `.claude/rwl-env-env`. If `$RWLENV_HAS_RUNNER` is `true`, ask which target:

AskUserQuestion: "Which target?"
- Options: Platform ($RWLENV_RELEASE in $RWLENV_NAMESPACE), Runner ($RWLENV_RUNNER_RELEASE in $RWLENV_RUNNER_NAMESPACE)

Set variables based on selection:
- **Platform:** `TARGET_KUBECONFIG=$RWLENV_KUBECONFIG`, `TARGET_CONTEXT=$RWLENV_CONTEXT`, `TARGET_NAMESPACE=$RWLENV_NAMESPACE`, `TARGET_RELEASE=$RWLENV_RELEASE`, `TARGET_CHART_REPO=$RWLENV_CHART_REPO`, `TARGET_CHART_NAME=$RWLENV_CHART_NAME`, `TARGET_READ_ONLY=$RWLENV_READ_ONLY`, `TARGET_CATALOG=${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json`
- **Runner:** `TARGET_KUBECONFIG=$RWLENV_RUNNER_KUBECONFIG`, `TARGET_CONTEXT=$RWLENV_RUNNER_CONTEXT`, `TARGET_NAMESPACE=$RWLENV_RUNNER_NAMESPACE`, `TARGET_RELEASE=$RWLENV_RUNNER_RELEASE`, `TARGET_CHART_REPO=$RWLENV_RUNNER_CHART_REPO`, `TARGET_CHART_NAME=$RWLENV_RUNNER_CHART_NAME`, `TARGET_READ_ONLY=$RWLENV_RUNNER_READ_ONLY`, `TARGET_CATALOG=${CLAUDE_PLUGIN_ROOT}/data/runner-services-catalog.json`

If no runner configured, skip the prompt and use platform variables.

All subsequent steps use `$TARGET_*` variables instead of `$RWLENV_*`.

### Step 2: Refuse if read-only.

### Step 3: Read current chart version

Via helm-ops: `helm get metadata "$TARGET_RELEASE" -n "$TARGET_NAMESPACE"`.
Extract `currentVersion`.

### Step 4: Soft-validate target chart exists

```bash
helm show chart "${chart_override:-$TARGET_CHART_REPO/$TARGET_CHART_NAME}" --version "$version"
```

If this fails, warn but allow the user to proceed (might be a private registry that requires auth helm will handle).

### Step 5: Diff and confirm

```
Chart version: <currentVersion>  →  <newVersion>
Rollback hint: /rwl-rollback --to-revision <currentRevision>

WARNING: Chart-version upgrades may change CRDs, RBAC, or values defaults.
         Review the chart's CHANGELOG before proceeding.
```
AskUserQuestion: Yes / No.

### Step 6: Execute

```bash
helm \
    --kubeconfig="$TARGET_KUBECONFIG" --kube-context="$TARGET_CONTEXT" \
    -n "$TARGET_NAMESPACE" \
    upgrade "$TARGET_RELEASE" "${chart_override:-$TARGET_CHART_REPO/$TARGET_CHART_NAME}" \
    --version "$version" \
    --reuse-values
```

### Step 7: Wait for rollouts and report

Same as `/rwl-upgrade-image-tag` steps 8–9.

### Step 8: Catalog-staleness check

If `$version`'s appVersion (from new release metadata) differs from `services-catalog.json.chartAppVersion`, print:
```
NOTE: Catalog appVersion (<catalog>) no longer matches live release (<new appVersion>).
      Debug recommendations may be stale until the catalog is updated.
```

## Error Handling

- `helm show chart` returns nothing → ask user to confirm proceeding without pre-flight.
- Same hook/helm error handling as image-tag skill.
