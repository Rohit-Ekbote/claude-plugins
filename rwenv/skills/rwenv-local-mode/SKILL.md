---
name: rwenv-local-mode
description: Toggle between dev container and local execution mode
triggers:
  - /rwenv-local-mode
  - switch to local mode
  - switch to dev container
  - toggle execution mode
---

# Toggle Execution Mode

Switch between dev container and local tool execution modes.

## Instructions

1. **Read current setting** from `~/.claude/rwenv/envs.json`:
   - Check `useDevContainer` field (defaults to `true` if not present)

2. **Read current rwenv** from `.claude/rwenv` in the current project directory:
   ```bash
   source "$RWENV_PLUGIN_DIR/lib/rwenv-utils.sh"
   rwenv_name=$(get_current_rwenv "$PWD")
   ```
   - If no rwenv set, error: "No rwenv configured. Run /rwenv-set first."

3. **Toggle the setting**:
   - If `true` → set to `false` (switching to local mode)
   - If `false` → set to `true` (switching to dev container mode)

4. **Validate target mode sub-object exists**:
   - Read the rwenv config for the current rwenv name from `envs.json`
   - Determine the target mode: `local` if toggling to `false`, `container` if toggling to `true`
   - Check if the target mode's sub-object exists and has both `kubeconfigPath` and `kubernetesContext`
   - If the `local` sub-object is `null` or missing when switching to local mode, trigger auto-detection:

   **Auto-detection flow** (same as /rwenv-set Step 3b):

   a. **Scan for kubeconfig files** in this order:
      - `~/.kube/config`
      - `~/.kube/*.yaml`
      - `~/.kube/*.yml`
      - `~/.kube/*-config`
      - Any paths in `KUBECONFIG` environment variable (split by `:`)

   b. **For each kubeconfig file found**, list available contexts:
      ```bash
      kubectl --kubeconfig=<path> config get-contexts -o name
      ```

   c. **Find contexts matching** the rwenv's container context name (from the `container` sub-object's `kubernetesContext` field). Look for exact matches first, then partial/substring matches.

   d. **Present matches to user** via AskUserQuestion:
      ```
      Local mode selected but no local kubeconfig is configured for '<rwenv_name>'.

      Found matching contexts for '<container_context>':
        1. ~/.kube/config -> context: <context_name>
        2. ~/.kube/<rwenv>-config -> context: <context_name>

      Which kubeconfig/context should be used for local mode?
      ```

   e. **Persist chosen values** into the `local` sub-object in `envs.json`:
      ```bash
      local envs_file="${RWENV_CONFIG_DIR:-$HOME/.claude/rwenv}/envs.json"
      jq --arg name "<rwenv_name>" \
         --arg kp "<chosen_kubeconfig_path>" \
         --arg ctx "<chosen_context>" \
         '.rwenvs[$name].local = {"kubeconfigPath": $kp, "kubernetesContext": $ctx}' \
         "$envs_file" > "${envs_file}.tmp" && mv "${envs_file}.tmp" "$envs_file"
      ```

   If no matching contexts are found, inform the user and abort the toggle:
   ```
   No local kubeconfig contexts matching '<container_context>' were found.

   To configure local mode manually, add a 'local' sub-object to the rwenv in envs.json:
   {
     "<rwenv_name>": {
       "local": {
         "kubeconfigPath": "/path/to/your/kubeconfig",
         "kubernetesContext": "your-context-name"
       }
     }
   }
   ```

5. **Validate tools when switching TO local mode** (`useDevContainer: false`):
   ```bash
   which kubectl || echo "WARNING: kubectl not found in PATH"
   which helm || echo "WARNING: helm not found in PATH"
   which flux || echo "WARNING: flux not found in PATH"
   which psql || echo "WARNING: psql not found in PATH"
   ```
   Show warnings but proceed anyway.

   **When switching TO dev container mode** (`useDevContainer: true`):
   ```bash
   docker ps --format '{{.Names}}' | grep -q "<devContainer>"
   ```
   Warn if container not running but proceed anyway.

6. **Update envs.json**:
   ```bash
   local envs_file="${RWENV_CONFIG_DIR:-$HOME/.claude/rwenv}/envs.json"
   jq '.useDevContainer = false' "$envs_file" > "${envs_file}.tmp" && mv "${envs_file}.tmp" "$envs_file"
   # or: jq '.useDevContainer = true' for the reverse direction
   ```

7. **Regenerate .claude/rwenv-env**:
   ```bash
   source "$RWENV_PLUGIN_DIR/lib/rwenv-utils.sh"
   write_rwenv_env "$PWD" "$(cat .claude/rwenv)"
   ```
   This ensures hooks and agents immediately pick up the new mode, kubeconfig, and context values.

8. **Confirm the change** showing resolved values from the regenerated env file:

   Read `.claude/rwenv-env` to get the resolved `RWENV_MODE`, `RWENV_KUBECONFIG`, and `RWENV_CONTEXT` values.

   If switched to local mode:
   ```
   Switched to LOCAL mode.

   Commands will run directly on your machine using:
     kubectl --kubeconfig=<RWENV_KUBECONFIG> --context=<RWENV_CONTEXT> ...
     helm --kubeconfig=<RWENV_KUBECONFIG> --kube-context=<RWENV_CONTEXT> ...
     flux --kubeconfig=<RWENV_KUBECONFIG> --context=<RWENV_CONTEXT> ...

   Resolved config:
     Kubeconfig: <RWENV_KUBECONFIG>
     Context:    <RWENV_CONTEXT>
     Read-Only:  <RWENV_READ_ONLY>

   To switch back: /rwenv-local-mode
   ```

   If switched to dev container mode:
   ```
   Switched to DEV CONTAINER mode.

   Commands will run through: <RWENV_DEV_CONTAINER>
     docker exec -i <RWENV_DEV_CONTAINER> kubectl --kubeconfig=<RWENV_KUBECONFIG> --context=<RWENV_CONTEXT> ...

   Resolved config:
     Kubeconfig: <RWENV_KUBECONFIG>
     Context:    <RWENV_CONTEXT>
     Read-Only:  <RWENV_READ_ONLY>

   To switch back: /rwenv-local-mode
   ```

## Error Handling

| Error | Response |
|-------|----------|
| envs.json not found | Create it with `{"version":"1.0","useDevContainer":false}` |
| No rwenv set | Error: "No rwenv configured. Run /rwenv-set first." |
| JSON parse error | Report error, don't modify file |
| Local sub-object auto-detection failure | Show manual configuration instructions and abort toggle |
| Write permission denied | Report error with suggestion to check permissions |
