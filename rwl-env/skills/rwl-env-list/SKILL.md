---
name: rwl-env-list
description: List all configured rwl-env entries
triggers:
  - /rwl-env-list
  - list rwl-envs
  - show rwl-envs
  - what rwl-envs are available
---

# List rwl-env Entries

List all configured rwl-env entries from `~/.claude/rwl-env/envs.json`.

## Instructions

1. Source the plugin utilities and read envs.json:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
   ```

2. Check the active rwl-env for the current project by reading `.claude/rwl-env`.

3. If `~/.claude/rwl-env/envs.json` doesn't exist, show:
   ```
   No rwl-env entries configured.

   Run /rwl-env-add to register your first deployment.
   ```

4. Otherwise, render a table:

   ```
   rwl-env Entries:

     NAME          CONTEXT             NAMESPACE   RELEASE   READ-ONLY   DESCRIPTION
   * helm-dev      k3d-rwl-dev         runwhen     rwl       No          Local k3d [+runner]
     helm-staging  gke_..._staging     runwhen     rwl       Yes         Customer staging

   * = active for current directory (<pwd>)

   Use /rwl-env-set <name> to switch.
   Use /rwl-env-cur to see full details.
   ```

5. Mark the active entry with `*`. If no active entry, no marker.

6. For each entry, check if it has a runner configured (`has_runner`). If yes, append `[+runner]` after the description column.

## Implementation

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"

if ! load_envs >/dev/null 2>&1; then
    echo "No rwl-env entries configured."
    echo "Run /rwl-env-add to register your first deployment."
    exit 0
fi

active=""
if get_current_rwlenv >/dev/null 2>&1; then
    active=$(get_current_rwlenv)
fi

printf "rwl-env Entries:\n\n"
printf "  %-14s %-22s %-12s %-10s %-11s %s\n" NAME CONTEXT NAMESPACE RELEASE READ-ONLY DESCRIPTION
load_envs | jq -r '.rwlenvs | to_entries[] |
    [.key, .value.kubernetesContext, .value.namespace, .value.releaseName,
     (if .value.readOnly then "Yes" else "No" end),
     (.value.description // ""),
     (if .value.runner then "true" else "false" end)] | @tsv' | while IFS=$'\t' read -r name ctx ns rel ro desc has_run; do
    marker=" "; [[ "$name" == "$active" ]] && marker="*"
    runner_tag=""; [[ "$has_run" == "true" ]] && runner_tag=" [+runner]"
    printf "%s %-14s %-22s %-12s %-10s %-11s %s\n" "$marker" "$name" "$ctx" "$ns" "$rel" "$ro" "${desc}${runner_tag}"
done

echo
[[ -n "$active" ]] && echo "* = active for current directory ($PWD)" || echo "(no active rwl-env for $PWD)"
echo "Use /rwl-env-set <name> to switch."
```

## Error Handling

- `envs.json` malformed: surface jq parse error, suggest manual fix.
- Empty `.rwlenvs`: show "No entries yet. Run /rwl-env-add."
