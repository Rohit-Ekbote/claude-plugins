---
name: rwl-env-add
description: Interactively register a new rwl-env entry
triggers:
  - /rwl-env-add
  - add rwl-env
  - register helm deployment
  - new rwl-env
args:
  - name: rwlenv_name
    description: Optional name; prompted if omitted
    required: false
  - name: kubeconfig
    description: Optional --kubeconfig path
    required: false
  - name: context
    description: Optional --context name
    required: false
---

# Add rwl-env Entry

Interactively register a new helm-deployed RunWhen platform install. Walks through name, kubeconfig discovery, context, namespace, release name, chart source, read-only mode.

## Instructions

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
```

### Step 1: Name

If not provided, prompt:
```
What name for this rwl-env? (alphanumeric + hyphens)
Examples: helm-dev, helm-staging, customer-acme
```

Validate:
- Format: `^[a-z0-9-]+$`
- Not already in `envs.json` (error: "rwl-env '<name>' already exists.")

### Step 2: Description

Prompt:
```
Short description (e.g., 'Local k3d', 'Customer staging install'):
```

### Step 3: Kubeconfig resolution

**If `--kubeconfig` was passed:** validate the file exists, then use it.

**If `--context` was passed but no `--kubeconfig`:**
1. First, probe `~/.kube/config`:
   ```bash
   if list_contexts_in_file ~/.kube/config | grep -qxF "$context"; then
       kubeconfig=~/.kube/config
   fi
   ```
2. If not found, scan with `find_context_across_files`:
   ```bash
   matches=$(find_context_across_files "$context")
   match_count=$(echo "$matches" | grep -c '.')
   ```
3. Branch on count:
   - **1 match:** record (file, context). Show:
     ```
     Found context '<ctx>' in <file>
     ```
   - **>1:** AskUserQuestion with each `(file, context)` pair as an option.
   - **0:** error and list all contexts seen across scanned files:
     ```
     ERROR: Context '<ctx>' not found in any kubeconfig under ~/.kube/.

     Contexts seen:
       - ~/.kube/config: ctx-a, ctx-b
       - ~/.kube/staging.yaml: ctx-c

     Pass --kubeconfig <path> explicitly or use a different --context.
     ```

**If neither was passed:**
1. Default kubeconfig to `~/.kube/config` (or error if missing).
2. List contexts via `list_contexts_in_file ~/.kube/config`.
3. AskUserQuestion to pick.

**Validation (soft):**
```bash
kubectl --kubeconfig="$kubeconfig" --context="$context" auth can-i get pods 2>/dev/null \
    || echo "WARNING: Could not reach cluster (offline?). Continuing anyway."
```

### Step 4: Namespace

Prompt:
```
Which namespace is the helm release in?
```

Validate:
```bash
kubectl --kubeconfig="$kubeconfig" --context="$context" get ns "$ns" 2>/dev/null \
    || echo "WARNING: Namespace '$ns' not found via current credentials. Continuing anyway."
```

### Step 5: Release name

```bash
releases=$(helm --kubeconfig="$kubeconfig" --kube-context="$context" list -n "$ns" -o json 2>/dev/null | jq -r '.[].name')
count=$(echo "$releases" | grep -c '.')
```

Branch:
- **1:** auto-fill, show: `Using release '<name>' (only release in namespace).`
- **>1:** AskUserQuestion with each release name as an option.
- **0:** error: `No helm releases in namespace <ns> on context <ctx>. Is the chart installed?`

### Step 6: Chart repo + name

`chartName` is inferred from `helm get metadata`:
```bash
chartName=$(helm --kubeconfig="$kubeconfig" --kube-context="$context" \
    get metadata "$release" -n "$ns" 2>/dev/null | grep -E '^CHART:' | awk '{print $2}' | sed 's/-[0-9].*//')
```

Show inferred `chartName` and ask to confirm or override.

For `chartRepo`, AskUserQuestion with options:
- "OCI registry (oci://...)"
- "HTTPS chart museum (https://...)"

Then prompt for the URL.

Soft-validate:
```bash
helm show chart "$chartRepo/$chartName" 2>/dev/null \
    || echo "WARNING: Could not fetch chart from $chartRepo. Recording anyway."
```

### Step 7: Read-only mode

AskUserQuestion:
- "No (read-write) — allow helm upgrade/rollback" (default for dev)
- "Yes (read-only) — block all mutations" (recommended for shared/staging)

### Step 7b. Runner (optional)

AskUserQuestion: "Does this environment have a runner?"
- Options: No (default), Yes

If Yes, collect runner details following the same pattern as /rwl-runner-set steps 3-8. Build runner JSON and include in the atomic jq merge in step 9.

### Step 8: Set as active for current directory?

AskUserQuestion:
- "Yes, activate for $PWD"
- "No, just save the entry"

If yes:
```bash
set_rwlenv_for_dir "$PWD" "$name"
write_rwlenv_env "$PWD" "$name"
```

### Step 9: Save

Atomic jq merge into `envs.json`:

```bash
envs_file="${RWLENV_CONFIG_DIR:-$HOME/.claude/rwl-env}/envs.json"
mkdir -p "$(dirname "$envs_file")"
[[ -f "$envs_file" ]] || echo '{"version":"1.0","rwlenvs":{}}' > "$envs_file"

new_entry=$(jq -n \
    --arg desc "$description" \
    --arg kp "$kubeconfig" \
    --arg ctx "$context" \
    --arg ns "$ns" \
    --arg rel "$release" \
    --arg cr "$chartRepo" \
    --arg cn "$chartName" \
    --argjson ro $readOnly \
    '{description:$desc, kubeconfigPath:$kp, kubernetesContext:$ctx, namespace:$ns, releaseName:$rel, chart:{repo:$cr, name:$cn}, readOnly:$ro}')

jq --arg name "$name" --argjson entry "$new_entry" '.rwlenvs[$name] = $entry' "$envs_file" \
    > "${envs_file}.tmp" && mv "${envs_file}.tmp" "$envs_file"
```

### Step 10: Confirm

```
rwl-env 'helm-dev' created.

  Description:  Local k3d cluster
  Kubeconfig:   /Users/rohitekbote/.kube/config
  Context:      k3d-rwl-dev
  Namespace:    runwhen
  Release:      rwl
  Chart:        oci://registry.example.com/charts/runwhen-platform
  Read-Only:    No
  Active for:   /Users/rohitekbote/wd/myproject

Use /rwl-env-cur for full details (including live helm metadata).
Use /rwl-env-list to see all entries.
```

## Error Handling

- `~/.kube/` missing → "No kubeconfig found. Create `~/.kube/config` or pass `--kubeconfig`."
- Kubeconfig file unreadable/malformed → skip during scan, warn to stderr, continue.
- `$KUBECONFIG` set with multiple files → split on `:`, include each.
- User aborts (Ctrl-C) → no partial write; the jq merge in Step 9 is the last write.
- Name collision: refuse with "rwl-env '<name>' already exists. Use a different name or edit envs.json manually."
