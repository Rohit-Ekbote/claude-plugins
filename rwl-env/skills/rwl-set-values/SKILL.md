---
name: rwl-set-values
description: Override arbitrary helm values via helm upgrade (deterministically revertible)
triggers:
  - /rwl-set-values
  - update helm values
  - override values
args:
  - name: sets
    description: Repeatable <key>=<value> overrides (e.g., papi.replicas=3)
    required: false
  - name: values_file
    description: Path to a values file (-f) for batch overrides
    required: false
  - name: chart
    description: Optional --chart <local-path>
    required: false
  - name: allow_subchart_toggle
    description: Required to permit toggling .deploy or .useSubchart keys
    required: false
---

# Override helm Values

Apply arbitrary helm value overrides via `helm upgrade --reuse-values`. Same diff-confirm-rollout cycle as `/rwl-upgrade-image-tag`.

### Step 1: Target selection

Source `.claude/rwl-env-env`. If `$RWLENV_HAS_RUNNER` is `true`, ask which target:

AskUserQuestion: "Which target?"
- Options: Platform ($RWLENV_RELEASE in $RWLENV_NAMESPACE), Runner ($RWLENV_RUNNER_RELEASE in $RWLENV_RUNNER_NAMESPACE)

Set variables based on selection:
- **Platform:** `TARGET_KUBECONFIG=$RWLENV_KUBECONFIG`, `TARGET_CONTEXT=$RWLENV_CONTEXT`, `TARGET_NAMESPACE=$RWLENV_NAMESPACE`, `TARGET_RELEASE=$RWLENV_RELEASE`, `TARGET_CHART_REPO=$RWLENV_CHART_REPO`, `TARGET_CHART_NAME=$RWLENV_CHART_NAME`, `TARGET_READ_ONLY=$RWLENV_READ_ONLY`, `TARGET_CATALOG=${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json`
- **Runner:** `TARGET_KUBECONFIG=$RWLENV_RUNNER_KUBECONFIG`, `TARGET_CONTEXT=$RWLENV_RUNNER_CONTEXT`, `TARGET_NAMESPACE=$RWLENV_RUNNER_NAMESPACE`, `TARGET_RELEASE=$RWLENV_RUNNER_RELEASE`, `TARGET_CHART_REPO=$RWLENV_RUNNER_CHART_REPO`, `TARGET_CHART_NAME=$RWLENV_RUNNER_CHART_NAME`, `TARGET_READ_ONLY=$RWLENV_RUNNER_READ_ONLY`, `TARGET_CATALOG=${CLAUDE_PLUGIN_ROOT}/data/runner-services-catalog.json`

If no runner configured, skip the prompt and use platform variables.

All subsequent steps use `$TARGET_*` variables instead of `$RWLENV_*`.

### Step 2: Read inputs

Require at least one of `--set <k>=<v>` (repeatable) or `--values-file <path>`.

### Step 3: Refuse subchart toggles without override

If any `<key>` matches `(^|\.)(deploy|useSubchart)$` and `--allow-subchart-toggle` was NOT passed, refuse:
```
Key '<k>' toggles a subchart deploy/useSubchart. This has data-migration implications
beyond a simple helm upgrade. Pass --allow-subchart-toggle if you understand the cost.
```

### Step 4: Refuse if read-only

### Step 5: Build helm args

```bash
helm_args=(upgrade "$TARGET_RELEASE" "${chart_override:-$TARGET_CHART_REPO/$TARGET_CHART_NAME}" \
    --version "$chartVersion" --reuse-values)
for set in "${sets[@]}"; do helm_args+=(--set "$set"); done
[[ -n "$values_file" ]] && helm_args+=(-f "$values_file")
```

### Step 6: Diff and confirm

Show:
- Each `--set` override (key → new value)
- If `--values-file`, show its content
- Current revision and chart version
- Rollback hint

AskUserQuestion: Yes / No.

### Step 7: Execute, wait for rollouts, report

Same as `/rwl-upgrade-image-tag` steps 7–9. Determine affected deployments by comparing `helm get manifest --revision <before>` vs after, or fall back to "all deployments in release".

## Error Handling

- Invalid `<key>=<value>` syntax → reject with a parser error.
- `--values-file` path doesn't exist or doesn't parse as YAML → reject.
- Same hook/helm error handling as `/rwl-upgrade-image-tag`.
