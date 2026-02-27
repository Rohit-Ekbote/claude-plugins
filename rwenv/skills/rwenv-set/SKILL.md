---
name: rwenv-set
description: Set the active rwenv environment for the current project (stored locally in .claude/rwenv)
triggers:
  - /rwenv-set
  - switch to
  - use rwenv
  - set environment
  - change environment
args:
  - name: rwenv_name
    description: Name of the rwenv to activate (optional - will prompt if not provided)
    required: false
---

# Set RunWhen Environment

Select an rwenv environment to use for the current project directory. The selection is stored in two files inside the project's `.claude/` directory (both auto-gitignored):

- **`.claude/rwenv`** - plain-text rwenv name (backward compatible, read by `get_current_rwenv()`)
- **`.claude/rwenv-env`** - resolved runtime config with mode, kubeconfig, context, etc. (read by hooks and agents)

## Instructions

### Step 1: Determine the target rwenv

**If rwenv name is provided** (e.g., `/rwenv-set rdebug`):
- Validate that the rwenv exists in `envs.json` under `.rwenvs`
- If not found, show error with available options

**If no rwenv name is provided**:
- List all available environments using the format from `/rwenv-list`
- Ask the user to select one using AskUserQuestion tool

### Step 2: Check for existing mapping

Read `.claude/rwenv` in the current project directory to see if an rwenv is already set.

**If same rwenv is already set**:
```
rwenv 'rdebug' is already active for this project.

Use /rwenv-cur to see full details.
```

**If different rwenv is set**, ask for confirmation:
```
Current rwenv: gke-prod (GKE production cluster, READ-ONLY)
Requested:     rdebug (VM based dev setup, read-write)

Switch from 'gke-prod' to 'rdebug'?
```

Use AskUserQuestion with options:
- "Yes, switch to rdebug"
- "No, keep gke-prod"

### Step 3: Update the mapping and generate runtime config

Use `set_rwenv_for_dir()` and `write_rwenv_env()` from `rwenv-utils.sh`:

1. `set_rwenv_for_dir()` creates `.claude/` directory, writes rwenv name to `.claude/rwenv`, and auto-gitignores it
2. `write_rwenv_env()` reads the active mode's sub-object from `envs.json`, generates `.claude/rwenv-env` with resolved values, and auto-gitignores it

**Implementation:**
```bash
source "$RWENV_PLUGIN_DIR/lib/rwenv-utils.sh"
set_rwenv_for_dir "$PWD" "<rwenv_name>"
write_rwenv_env "$PWD" "<rwenv_name>"
```

If `write_rwenv_env` fails (exit code 1), it means the active mode's sub-object is missing or incomplete in `envs.json`. Display the error and advise:
```
ERROR: 'container' sub-object missing or incomplete for rwenv 'rdebug'. Update envs.json.

The envs.json schema requires a 'container' and/or 'local' sub-object per rwenv:
{
  "rdebug": {
    "type": "k3s",
    "container": {
      "kubeconfigPath": "/home/rundev/.kube/rdebug-61-config",
      "kubernetesContext": "rdebug-61"
    },
    "local": null,
    ...
  }
}

Add the missing sub-object to ~/.claude/rwenv/envs.json and retry.
```

### Step 3b: Local mode auto-detection

This step runs **only** when both conditions are true:
- `useDevContainer` is `false` in `envs.json` (meaning local mode is active)
- The rwenv's `local` sub-object is `null` in `envs.json`

When triggered, auto-detect local kubeconfig and context:

1. **Scan for kubeconfig files** in this order:
   - `~/.kube/config`
   - `~/.kube/*.yaml`
   - `~/.kube/*.yml`
   - `~/.kube/*-config`
   - Any paths in `KUBECONFIG` environment variable (split by `:`)

2. **For each kubeconfig file found**, list available contexts:
   ```bash
   kubectl --kubeconfig=<path> config get-contexts -o name
   ```

3. **Find contexts matching** the rwenv's container context name (from the `container` sub-object's `kubernetesContext` field). Look for exact matches first, then partial/substring matches.

4. **Present matches to user** via AskUserQuestion:
   ```
   Local mode is active but no local kubeconfig is configured for 'rdebug'.

   Found matching contexts for 'rdebug-61':
     1. ~/.kube/config -> context: rdebug-61
     2. ~/.kube/rdebug-61-config -> context: rdebug-61

   Which kubeconfig/context should be used for local mode?
   ```

5. **Persist chosen values** into the `local` sub-object in `envs.json`:
   ```json
   {
     "rdebug": {
       "local": {
         "kubeconfigPath": "/Users/rohitekbote/.kube/rdebug-61-config",
         "kubernetesContext": "rdebug-61"
       }
     }
   }
   ```

   Use `jq` to update `envs.json` in place:
   ```bash
   local envs_file="${RWENV_CONFIG_DIR:-$HOME/.claude/rwenv}/envs.json"
   jq --arg name "<rwenv_name>" \
      --arg kp "<chosen_kubeconfig_path>" \
      --arg ctx "<chosen_context>" \
      '.rwenvs[$name].local = {"kubeconfigPath": $kp, "kubernetesContext": $ctx}' \
      "$envs_file" > "${envs_file}.tmp" && mv "${envs_file}.tmp" "$envs_file"
   ```

6. **Re-run** `write_rwenv_env` after persisting the local config so `.claude/rwenv-env` gets the correct values:
   ```bash
   write_rwenv_env "$PWD" "<rwenv_name>"
   ```

If no matching contexts are found, inform the user:
```
No local kubeconfig contexts matching 'rdebug-61' were found.

To configure local mode manually, add a 'local' sub-object to the rwenv in envs.json:
{
  "rdebug": {
    "local": {
      "kubeconfigPath": "/path/to/your/kubeconfig",
      "kubernetesContext": "your-context-name"
    }
  }
}

Or use /rwenv-local-mode to switch execution mode.
```

### Step 4: Display confirmation

Read back the generated `.claude/rwenv-env` to determine the resolved mode, kubeconfig, and context. Then display:

```
rwenv set to 'rdebug' for this project
Stored in: /path/to/project/.claude/rwenv (auto-gitignored)
Runtime config: /path/to/project/.claude/rwenv-env (auto-gitignored)

Environment Details:
  Name:        rdebug
  Type:        k3s
  Mode:        container
  Description: VM based dev setup (k3s)
  Context:     rdebug-61
  Kubeconfig:  /home/rundev/.kube/rdebug-61-config
  Read-Only:   No

All kubectl, helm, and flux commands will use:
  - Mode: container (via alpine-dev-container-zsh-rdebug)
  - Context: rdebug-61
  - Kubeconfig: /home/rundev/.kube/rdebug-61-config

Use /rwenv-cur for full details.
Use /rwenv-local-mode to switch execution mode.
```

- The **Mode** line should show `container (via <devContainer>)` or `local (tools from PATH)` depending on the active mode.
- The **Context** and **Kubeconfig** values come from the active mode's sub-object (container or local).

**For read-only environments**, add warning:
```
WARNING: This environment is READ-ONLY.
The following operations will be blocked:
  - kubectl apply, delete, patch, create, edit, replace, scale
  - helm install, upgrade, uninstall, rollback
  - flux reconcile, suspend, resume
```

### Step 5: Validation

Before completing, validate that the active mode's sub-object has the required fields:

- Read `useDevContainer` from `envs.json` to determine the active mode (`container` if true, `local` if false)
- Check that the corresponding sub-object (`container` or `local`) exists and is not `null`
- Check that the sub-object contains both `kubeconfigPath` and `kubernetesContext`

If validation fails, `write_rwenv_env()` will have already returned an error in Step 3. The skill should not proceed to Step 4 confirmation in that case.

## envs.json Schema Reference

The new envs.json schema uses `container`/`local` sub-objects per rwenv:

```json
{
  "version": "1.0",
  "devContainer": "alpine-dev-container-zsh-rdebug",
  "useDevContainer": true,
  "rwenvs": {
    "rdebug": {
      "type": "k3s",
      "description": "VM based dev setup (k3s)",
      "container": {
        "kubeconfigPath": "/home/rundev/.kube/rdebug-61-config",
        "kubernetesContext": "rdebug-61"
      },
      "local": null,
      "readOnly": false,
      "gcpProject": null,
      "fluxGitRepo": "https://gitea.rdebug-61.local.runwhen.com/..."
    },
    "gke-prod": {
      "type": "gke",
      "description": "GKE production cluster",
      "container": {
        "kubeconfigPath": "/home/rundev/.kube/gke-prod-config",
        "kubernetesContext": "gke_project_region_cluster"
      },
      "local": {
        "kubeconfigPath": "/Users/rohitekbote/.kube/gke-prod-config",
        "kubernetesContext": "gke_project_region_cluster"
      },
      "readOnly": true,
      "gcpProject": "my-gcp-project",
      "fluxGitRepo": "https://github.com/org/flux-repo"
    }
  }
}
```

## Error Handling

**rwenv not found:**
```
ERROR: rwenv 'foo' not found.

Available environments:
  - rdebug (k3s, VM based dev setup)
  - gke-prod (gke, GKE production cluster)

Use /rwenv-set <name> with one of the above.
```

**Config directory doesn't exist:**
```
ERROR: rwenv config directory not found at ~/.claude/rwenv/

Please set up rwenv first:
1. Create directory: mkdir -p ~/.claude/rwenv
2. Copy example config: cp config/envs.example.json ~/.claude/rwenv/envs.json
3. Edit with your environment details
```

**Permission error writing to project .claude directory:**
```
ERROR: Cannot write to <project>/.claude/rwenv

Check directory permissions and try again.
```

**Active mode sub-object missing:**
```
ERROR: '<mode>' sub-object missing or incomplete for rwenv '<name>'. Update envs.json.

Required structure in envs.json for each rwenv:
  "container": { "kubeconfigPath": "...", "kubernetesContext": "..." }
  "local": { "kubeconfigPath": "...", "kubernetesContext": "..." }  (or null)
```

## Natural Language Handling

When user says things like:
- "switch to rdebug" -> extract "rdebug" as rwenv_name
- "use gke-prod environment" -> extract "gke-prod" as rwenv_name
- "change to production" -> if "production" doesn't match, suggest closest match or list all
