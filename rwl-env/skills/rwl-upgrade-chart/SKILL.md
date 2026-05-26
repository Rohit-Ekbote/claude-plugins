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

### Step 1: Refuse if read-only.

### Step 2: Read current chart version

Via helm-ops: `helm get metadata "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE"`.
Extract `currentVersion`.

### Step 3: Soft-validate target chart exists

```bash
helm show chart "${chart_override:-$RWLENV_CHART_REPO/$RWLENV_CHART_NAME}" --version "$version"
```

If this fails, warn but allow the user to proceed (might be a private registry that requires auth helm will handle).

### Step 4: Diff and confirm

```
Chart version: <currentVersion>  →  <newVersion>
Rollback hint: /rwl-rollback --to-revision <currentRevision>

WARNING: Chart-version upgrades may change CRDs, RBAC, or values defaults.
         Review the chart's CHANGELOG before proceeding.
```
AskUserQuestion: Yes / No.

### Step 5: Execute

```bash
helm \
    --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
    -n "$RWLENV_NAMESPACE" \
    upgrade "$RWLENV_RELEASE" "${chart_override:-$RWLENV_CHART_REPO/$RWLENV_CHART_NAME}" \
    --version "$version" \
    --reuse-values
```

### Step 6: Wait for rollouts and report

Same as `/rwl-upgrade-image-tag` steps 7–8.

### Step 7: Catalog-staleness check

If `$version`'s appVersion (from new release metadata) differs from `services-catalog.json.chartAppVersion`, print:
```
NOTE: Catalog appVersion (<catalog>) no longer matches live release (<new appVersion>).
      Debug recommendations may be stale until the catalog is updated.
```

## Error Handling

- `helm show chart` returns nothing → ask user to confirm proceeding without pre-flight.
- Same hook/helm error handling as image-tag skill.
