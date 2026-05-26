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

### Step 1: Refuse if read-only

If `$RWLENV_READ_ONLY == "true"`: abort.

### Step 2: Show helm history

Via helm-ops:
```bash
helm history "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" -o json
```

Render a table: revision, updated, status, chart, appVersion, description.

### Step 3: Pick target revision

If `--to-revision N` was passed, use it. Otherwise AskUserQuestion with each revision as an option (most recent first).

### Step 4: Diff between current and target

```bash
helm get values "$RWLENV_RELEASE" --revision "$currentRev" -n "$RWLENV_NAMESPACE" -o yaml > /tmp/current.yaml
helm get values "$RWLENV_RELEASE" --revision "$targetRev"  -n "$RWLENV_NAMESPACE" -o yaml > /tmp/target.yaml
diff -u /tmp/current.yaml /tmp/target.yaml
```

Show a concise diff (changed keys only). Note both `chart` versions too — pull from `helm history -o json`.

### Step 5: Confirm

AskUserQuestion:
```
Roll back to revision <N>?
  Chart:       <X.Y.Z> → <A.B.C>  (or same)
  Image tag:   <new> → <old>     (sample key only)
  Description: <history entry description>
```
Options: "Yes, rollback" / "No, cancel".

### Step 6: Execute

Via helm-ops:
```bash
helm --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
    -n "$RWLENV_NAMESPACE" \
    rollback "$RWLENV_RELEASE" "$targetRev"
```

### Step 7: Wait for rollouts

Via k8s-ops, for every deployment in the release:
```bash
for dep in $(kubectl get deploy -n "$RWLENV_NAMESPACE" -l app.kubernetes.io/instance="$RWLENV_RELEASE" -o name); do
    kubectl rollout status "$dep" --timeout=3m
done
```

### Step 8: Report

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
