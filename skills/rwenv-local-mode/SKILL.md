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

2. **Toggle the setting**:
   - If `true` → set to `false`
   - If `false` → set to `true`

3. **Validate before switching**:

   **When switching TO local mode (`useDevContainer: false`):**
   ```bash
   which kubectl || echo "WARNING: kubectl not found in PATH"
   which helm || echo "WARNING: helm not found in PATH"
   which flux || echo "WARNING: flux not found in PATH"
   ```
   Show warnings but proceed anyway.

   **When switching TO dev container mode (`useDevContainer: true`):**
   ```bash
   docker ps --format '{{.Names}}' | grep -q "<devContainer>"
   ```
   Warn if container not running but proceed anyway.

4. **Update the config file**:
   ```bash
   # Read, modify, write back
   jq '.useDevContainer = false' ~/.claude/rwenv/envs.json > /tmp/envs.json
   mv /tmp/envs.json ~/.claude/rwenv/envs.json
   ```

5. **Confirm the change**:

   If switched to local mode:
   ```
   Switched to LOCAL mode.

   Commands will run directly on your machine using:
     kubectl --context=<context> ...
     helm --kube-context=<context> ...
     flux --context=<context> ...

   Requirements:
   - kubectl, helm, flux must be installed locally
   - Kubeconfig must be configured with the correct context

   To switch back: /rwenv-local-mode
   ```

   If switched to dev container mode:
   ```
   Switched to DEV CONTAINER mode.

   Commands will run through: <devContainer>
     docker exec -i <container> kubectl --kubeconfig=... --context=... ...

   To switch back: /rwenv-local-mode
   ```

## Error Handling

| Error | Response |
|-------|----------|
| envs.json not found | Create it with `{"version":"1.0","useDevContainer":false}` |
| JSON parse error | Report error, don't modify file |
| Write permission denied | Report error with suggestion to check permissions |
