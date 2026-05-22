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

### Step 1: Read inputs

Require at least one of `--set <k>=<v>` (repeatable) or `--values-file <path>`.

### Step 2: Refuse subchart toggles without override

If any `<key>` matches `(^|\.)(deploy|useSubchart)$` and `--allow-subchart-toggle` was NOT passed, refuse:
```
Key '<k>' toggles a subchart deploy/useSubchart. This has data-migration implications
beyond a simple helm upgrade. Pass --allow-subchart-toggle if you understand the cost.
```

### Step 3: Refuse if read-only

### Step 4: Build helm args

```bash
helm_args=(upgrade "$RWLENV_RELEASE" "${chart_override:-$RWLENV_CHART_REPO/$RWLENV_CHART_NAME}" \
    --version "$chartVersion" --reuse-values)
for set in "${sets[@]}"; do helm_args+=(--set "$set"); done
[[ -n "$values_file" ]] && helm_args+=(-f "$values_file")
```

### Step 5: Diff and confirm

Show:
- Each `--set` override (key → new value)
- If `--values-file`, show its content
- Current revision and chart version
- Rollback hint

AskUserQuestion: Yes / No.

### Step 6: Execute, wait for rollouts, report

Same as `/rwl-upgrade-image-tag` steps 6–8. Determine affected deployments by comparing `helm get manifest --revision <before>` vs after, or fall back to "all deployments in release".

## Error Handling

- Invalid `<key>=<value>` syntax → reject with a parser error.
- `--values-file` path doesn't exist or doesn't parse as YAML → reject.
- Same hook/helm error handling as `/rwl-upgrade-image-tag`.
