---
name: rwl-env-cur
description: Show the current rwl-env for this project directory
triggers:
  - /rwl-env-cur
  - current rwl-env
  - which rwl-env
  - show current rwl-env
---

# Show Current rwl-env

Display full details of the rwl-env configured for the current project directory.

## Instructions

1. Check for `.claude/rwl-env-env` in `$PWD`:

   **If missing:** print an error and offer setup:
   ```
   No rwl-env set for this project.
   Current directory: <pwd>

   Run /rwl-env-set <name> or /rwl-env-add to configure one.
   ```
   Then list available entries by reading `${RWLENV_CONFIG_DIR:-~/.claude/rwl-env}/envs.json` (same format as /rwl-env-list).

2. **If present:** source it and display:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
   source .claude/rwl-env-env
   ```

3. Print:
   ```
   Current rwl-env: $RWLENV_NAME

   Kubeconfig:   $RWLENV_KUBECONFIG
   Context:      $RWLENV_CONTEXT
   Namespace:    $RWLENV_NAMESPACE
   Release:      $RWLENV_RELEASE
   Chart:        $RWLENV_CHART_REPO/$RWLENV_CHART_NAME
   Read-Only:    $RWLENV_READ_ONLY
   ```

4. Augment with live helm metadata when reachable:
   ```bash
   helm --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
        get metadata "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" 2>/dev/null
   ```
   Then show:
   ```
   Live Release State:
     Chart version:  <chart>
     App version:    <appVersion>
     Last upgraded:  <timestamp>
     Revision:       <n>
   ```
   If the helm command fails, print "Cluster unreachable (offline?) — cannot show live state."

### 4b. Runner details

If `$RWLENV_HAS_RUNNER` is `true`:

```
Runner:
  Kubeconfig:   $RWLENV_RUNNER_KUBECONFIG
  Context:      $RWLENV_RUNNER_CONTEXT
  Namespace:    $RWLENV_RUNNER_NAMESPACE
  Release:      $RWLENV_RUNNER_RELEASE
  Chart:        $RWLENV_RUNNER_CHART_REPO/$RWLENV_RUNNER_CHART_NAME
  Read-Only:    $RWLENV_RUNNER_READ_ONLY
```

Augment with live runner helm metadata:
```bash
helm --kubeconfig="$RWLENV_RUNNER_KUBECONFIG" --kube-context="$RWLENV_RUNNER_CONTEXT" \
     get metadata "$RWLENV_RUNNER_RELEASE" -n "$RWLENV_RUNNER_NAMESPACE" 2>/dev/null
```

Show runner live state (chart version, app version, revision, timestamp).
If unreachable, print "Runner cluster unreachable — cannot show live state."

Runner stale-catalog check:
```bash
runner_catalog_av=$(jq -r '.chartAppVersion' "${CLAUDE_PLUGIN_ROOT}/data/runner-services-catalog.json")
```
Compare against live runner appVersion and warn if mismatched.

5. Stale-catalog check:
   ```bash
   catalog_av=$(jq -r '.chartAppVersion' "${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json")
   ```
   If `catalog_av != <live appVersion>`, print:
   ```
   WARNING: Catalog appVersion ($catalog_av) does not match live release. Debug recommendations may be stale.
   ```

6. Read-only warning:
   ```
   WARNING: This rwl-env is READ-ONLY. helm upgrade and helm rollback are blocked.
   ```

## Error Handling

- Missing `envs.json` is fine — runtime env file is self-contained.
- helm/kubectl errors are non-fatal: report and continue.
