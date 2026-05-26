---
name: rwl-runner-set
description: Add, update, or remove runner config on an existing platform rwl-env entry
triggers:
  - /rwl-runner-set
  - add runner
  - configure runner
  - set runner
  - remove runner
args:
  - name: platform_name
    description: Name of the platform rwl-env entry (required)
  - name: remove
    description: If passed, removes the runner config
---

# Set Runner for rwl-env

Add, update, or remove a runner configuration on an existing platform rwl-env entry.

## Prerequisites

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
```

## Instructions

### 1. Determine platform name

If `platform_name` arg provided, use it. Otherwise list available rwl-envs and ask:

```bash
list_rwlenv_names
```

Validate the platform entry exists:

```bash
get_rwlenv_by_name "$platform_name" >/dev/null || {
    echo "ERROR: rwl-env '$platform_name' not found."
    # list available entries
}
```

### 2. Handle --remove

If `--remove` was passed:

```bash
has_runner "$platform_name" || {
    echo "No runner configured for '$platform_name'. Nothing to remove."
    exit 0
}
```

Confirm with AskUserQuestion: "Remove runner config from '$platform_name'?"

If confirmed:
```bash
remove_runner_config "$platform_name"
```

If this platform is currently active (`get_current_rwlenv` matches), regenerate the env file:
```bash
write_rwlenv_env "$PWD" "$platform_name"
```

Print confirmation and return.

### 3. Collect runner kubeconfig

Ask the user for the runner's kubeconfig path, or discover it:

```bash
discover_kubeconfig_files
```

If the runner is on the same cluster as the platform, offer to reuse the platform's kubeconfig:

```bash
platform_kc=$(get_rwlenv_by_name "$platform_name" | jq -r '.kubeconfigPath')
```

AskUserQuestion: "Runner kubeconfig — same as platform ($platform_kc) or different?"

Validate the file exists: `[[ -f "$runner_kubeconfig" ]]`

### 4. Collect runner context

List available contexts in the chosen kubeconfig:

```bash
list_contexts_in_file "$runner_kubeconfig"
```

If only one context, use it. If multiple, ask the user to pick.

### 5. Collect runner namespace

Ask the user: "Which namespace is the runner deployed in?"

No default — must be explicitly provided.

### 6. Discover runner release

List helm releases in the runner namespace:

```bash
helm --kubeconfig="$runner_kubeconfig" --kube-context="$runner_context" \
    list -n "$runner_namespace" -o json | jq -r '.[].name'
```

If only one release, use it. If multiple, ask the user. If none, error.

### 7. Infer chart info

```bash
helm --kubeconfig="$runner_kubeconfig" --kube-context="$runner_context" \
    get metadata "$runner_release" -n "$runner_namespace" -o json
```

Extract chart name. For chart repo, ask the user or leave empty if local/unknown.

### 8. Read-only mode

AskUserQuestion: "Should the runner be read-only (block helm upgrade/rollback)?"
- Options: No (default), Yes

### 9. Write runner config

Build the runner JSON and save:

```bash
runner_json=$(jq -n \
    --arg kc "$runner_kubeconfig" \
    --arg ctx "$runner_context" \
    --arg ns "$runner_namespace" \
    --arg rel "$runner_release" \
    --arg repo "$runner_chart_repo" \
    --arg chart "$runner_chart_name" \
    --argjson ro "$runner_read_only" \
    '{
        kubeconfigPath: $kc,
        kubernetesContext: $ctx,
        namespace: $ns,
        releaseName: $rel,
        chart: { repo: $repo, name: $chart },
        readOnly: $ro
    }')

set_runner_config "$platform_name" "$runner_json"
```

### 10. Regenerate env file if active

If this platform is currently active:

```bash
current=$(get_current_rwlenv) || true
if [[ "$current" == "$platform_name" ]]; then
    write_rwlenv_env "$PWD" "$platform_name"
fi
```

### 11. Confirmation

Print:
```
Runner configured for rwl-env '$platform_name':

  Kubeconfig:  $runner_kubeconfig
  Context:     $runner_context
  Namespace:   $runner_namespace
  Release:     $runner_release
  Chart:       $runner_chart_repo/$runner_chart_name
  Read-Only:   $runner_read_only
```

## Error Handling

- Platform not found: list available entries, suggest `/rwl-env-add`
- Kubeconfig not found: suggest correct path, offer to discover
- No contexts: "Kubeconfig has no contexts. Verify the file."
- No releases: "No helm releases in namespace '$ns'. Is the runner deployed?"
- helm unreachable: surface stderr, suggest checking auth/DNS
