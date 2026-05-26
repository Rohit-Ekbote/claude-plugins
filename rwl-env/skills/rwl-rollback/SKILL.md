---
name: rwl-rollback
description: Roll back the active rwl-env release to a prior helm revision
triggers:
  - /rwl-rollback
  - helm rollback
  - revert release
args:
  - name: to_revision
    description: Optional revision number; prompted if omitted
    required: false
---

# Roll Back Helm Release

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

If `$TARGET_READ_ONLY == "true"`: abort.

### Step 3: Show helm history

Via helm-ops:
```bash
helm history "$TARGET_RELEASE" -n "$TARGET_NAMESPACE" -o json
```

Render a table: revision, updated, status, chart, appVersion, description.

### Step 4: Pick target revision

If `--to-revision N` was passed, use it. Otherwise AskUserQuestion with each revision as an option (most recent first).

### Step 5: Diff between current and target

```bash
helm get values "$TARGET_RELEASE" --revision "$currentRev" -n "$TARGET_NAMESPACE" -o yaml > /tmp/current.yaml
helm get values "$TARGET_RELEASE" --revision "$targetRev"  -n "$TARGET_NAMESPACE" -o yaml > /tmp/target.yaml
diff -u /tmp/current.yaml /tmp/target.yaml
```

Show a concise diff (changed keys only). Note both `chart` versions too — pull from `helm history -o json`.

### Step 6: Confirm

AskUserQuestion:
```
Roll back to revision <N>?
  Chart:       <X.Y.Z> → <A.B.C>  (or same)
  Image tag:   <new> → <old>     (sample key only)
  Description: <history entry description>
```
Options: "Yes, rollback" / "No, cancel".

### Step 7: Execute

Via helm-ops:
```bash
helm --kubeconfig="$TARGET_KUBECONFIG" --kube-context="$TARGET_CONTEXT" \
    -n "$TARGET_NAMESPACE" \
    rollback "$TARGET_RELEASE" "$targetRev"
```

### Step 8: Wait for rollouts

Via k8s-ops, for every deployment in the release:
```bash
for dep in $(kubectl get deploy -n "$TARGET_NAMESPACE" -l app.kubernetes.io/instance="$TARGET_RELEASE" -o name); do
    kubectl rollout status "$dep" --timeout=3m
done
```

### Step 9: Report

```
Rollback complete.
Revision: <currentRev>  →  <newRev>       (new revision created; history is append-only)
Rolled back to chart <chart>, appVersion <app>, image-tag <tag>.
Rollouts complete for: <list>.
```

## Error Handling

- `helm history` shows only one revision → "Nothing to roll back to."
- Target revision === current → no-op message.
- helm rollback failure → surface stderr; do not retry.
