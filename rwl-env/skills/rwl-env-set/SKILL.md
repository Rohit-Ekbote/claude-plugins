---
name: rwl-env-set
description: Set the active rwl-env for the current project directory
triggers:
  - /rwl-env-set
  - switch rwl-env
  - use rwl-env
  - set rwl-env
args:
  - name: rwlenv_name
    description: Name of the rwl-env to activate (prompted if omitted)
    required: false
---

# Set Active rwl-env

Switch the active rwl-env for `$PWD`. Writes `.claude/rwl-env` (plain text) and `.claude/rwl-env-env` (resolved KV). Both auto-gitignored.

## Instructions

1. **Determine target name:**
   - If user passed a name: validate it exists in `envs.json`.
   - Otherwise: list entries via `list_rwlenv_names` and prompt with `AskUserQuestion`.

2. **Check current state:**
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
   current=$(get_current_rwlenv 2>/dev/null) || current=""
   ```
   - If `current == target`: report "Already active." and exit.
   - If different: AskUserQuestion to confirm switch.

3. **Write files:**
   ```bash
   set_rwlenv_for_dir "$PWD" "$target"
   write_rwlenv_env "$PWD" "$target"
   ```

4. **Display confirmation** using `format_rwlenv_details`:
   ```bash
   format_rwlenv_details "$target"
   ```

5. **Runner info**

If the rwl-env has a runner configured:

```bash
has_runner "$target_name" && {
    runner=$(get_runner_config "$target_name")
    echo ""
    echo "Runner:"
    echo "  Kubeconfig:  $(echo "$runner" | jq -r '.kubeconfigPath')"
    echo "  Context:     $(echo "$runner" | jq -r '.kubernetesContext')"
    echo "  Namespace:   $(echo "$runner" | jq -r '.namespace')"
    echo "  Release:     $(echo "$runner" | jq -r '.releaseName')"
    echo "  Chart:       $(echo "$runner" | jq -r '.chart.repo')/$(echo "$runner" | jq -r '.chart.name')"
    echo "  Read-Only:   $(echo "$runner" | jq -r '.readOnly')"
}
```

6. **Read-only warning** (if applicable):
   ```
   WARNING: This rwl-env is READ-ONLY. The following are blocked:
     - helm upgrade, helm rollback
   Reads (helm get/history/status, kubectl get/logs/events, psql SELECT) remain allowed.
   ```

## Error Handling

**Unknown name:**
```
ERROR: rwl-env '<name>' not found.

Available:
  - helm-dev
  - helm-staging

Use /rwl-env-set <name> with one of the above, or /rwl-env-add to create a new entry.
```

**envs.json missing:**
```
ERROR: rwl-env config not found at ~/.claude/rwl-env/envs.json.
Run /rwl-env-add to create your first entry.
```

**`set_rwlenv_for_dir` returns non-zero:** surface the stderr message; do not proceed to `write_rwlenv_env`.

## Natural Language

- "switch to helm-staging" → `target=helm-staging`
- "use helm-dev for this project" → `target=helm-dev`
- "set rwl-env to production" → if exact match fails, suggest closest by substring.
