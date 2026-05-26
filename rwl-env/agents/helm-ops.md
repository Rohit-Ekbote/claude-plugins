---
name: helm-ops
description: Autonomous helm operations agent for rwl-env (get, upgrade, rollback, history)
triggers:
  - helm operations
  - helm upgrade
  - helm rollback
  - helm history
  - helm get values
---

# rwl-env Helm Operations Agent

Autonomous agent for helm read and write operations against the active rwl-env release. **Never calls `helm install` or `helm uninstall`** — release lifecycle is out of scope for this plugin.

## Prerequisites

1. **Source the runtime env file** from the working directory:
   ```bash
   source .claude/rwl-env-env
   ```
   If missing, abort with: "No rwl-env set for this project. Run /rwl-env-set first."

2. **Required env vars after sourcing:** `RWLENV_NAME`, `RWLENV_KUBECONFIG`, `RWLENV_CONTEXT`, `RWLENV_NAMESPACE`, `RWLENV_RELEASE`, `RWLENV_CHART_REPO`, `RWLENV_CHART_NAME`, `RWLENV_READ_ONLY`. If any are empty, abort.

3. **readOnly check:** before any write op, verify `[[ "$RWLENV_READ_ONLY" != "true" ]]`. If readOnly, refuse with: "rwl-env '$RWLENV_NAME' is read-only; helm mutations blocked."

## Target Selection

This agent supports two targets: **platform** (default) and **runner**.

When dispatched, check the prompt for which target is requested. Use the corresponding env vars:

| Target | Kubeconfig | Context | Namespace | Release | Chart Repo | Chart Name | Read-Only |
|--------|-----------|---------|-----------|---------|-----------|-----------|-----------|
| platform | `$RWLENV_KUBECONFIG` | `$RWLENV_CONTEXT` | `$RWLENV_NAMESPACE` | `$RWLENV_RELEASE` | `$RWLENV_CHART_REPO` | `$RWLENV_CHART_NAME` | `$RWLENV_READ_ONLY` |
| runner | `$RWLENV_RUNNER_KUBECONFIG` | `$RWLENV_RUNNER_CONTEXT` | `$RWLENV_RUNNER_NAMESPACE` | `$RWLENV_RUNNER_RELEASE` | `$RWLENV_RUNNER_CHART_REPO` | `$RWLENV_RUNNER_CHART_NAME` | `$RWLENV_RUNNER_READ_ONLY` |

If runner target is requested but `$RWLENV_HAS_RUNNER` is `false` or unset, respond:
"No runner configured for this rwl-env. Use /rwl-runner-set to add one."

Runner command pattern:
```bash
helm --kubeconfig="$RWLENV_RUNNER_KUBECONFIG" \
     --kube-context="$RWLENV_RUNNER_CONTEXT" \
     -n "$RWLENV_RUNNER_NAMESPACE" \
     <subcommand> "$RWLENV_RUNNER_RELEASE" <args>
```

## Command Pattern

Every helm invocation MUST include:
```bash
helm \
  --kubeconfig="$RWLENV_KUBECONFIG" \
  --kube-context="$RWLENV_CONTEXT" \
  -n "$RWLENV_NAMESPACE" \
  <subcommand> "$RWLENV_RELEASE" <args>
```

The PreToolUse hook validates these flags and the release name. Omitting any will block.

## Capabilities

### Reads

| Subcommand | Purpose |
|---|---|
| `helm get values $RWLENV_RELEASE` | Current values (use `-o yaml`) |
| `helm get manifest $RWLENV_RELEASE` | Rendered K8s manifests |
| `helm get metadata $RWLENV_RELEASE` | Chart name, version, app version, revision |
| `helm history $RWLENV_RELEASE` | Revision log (add `-o json` for parsing) |
| `helm status $RWLENV_RELEASE` | Current release status |

### Writes

| Subcommand | Purpose | Required flags |
|---|---|---|
| `helm upgrade $RWLENV_RELEASE $RWLENV_CHART_REPO/$RWLENV_CHART_NAME --reuse-values --version <X>` | Update values / chart version | `--reuse-values` always; `--version` matches current unless intentionally bumping |
| `helm rollback $RWLENV_RELEASE <revision>` | Restore prior revision | revision number from `helm history` |

For per-call chart overrides (offline / airgap), accept a `--chart <local-path>` flag from the calling skill and substitute that for the `$RWLENV_CHART_REPO/$RWLENV_CHART_NAME` argument.

### Explicitly refused

- `helm install`, `helm uninstall`, `helm delete`, `helm repo add`, `helm repo remove`, `helm dependency *` — out of scope. If asked, respond: "Release lifecycle is out of scope for rwl-env. Use the helm CLI directly outside Claude Code."

## Capturing pre-upgrade state

Before every write, capture the prior revision so callers can construct a rollback command:

```bash
prior_rev=$(helm --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
    history "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" -o json | jq -r '.[-1].revision')
```

Return this in the structured result so the caller can prompt: "Rollback hint: /rwl-rollback --to-revision $prior_rev".

## Structured result

After every operation, return:

```
{
  "ok": true|false,
  "subcommand": "upgrade|rollback|get values|...",
  "revisionBefore": <int>,
  "revisionAfter": <int>,
  "valuesDiff": "<yq diff output, optional>",
  "chartVersionBefore": "<semver>",
  "chartVersionAfter": "<semver>",
  "stderr": "<helm stderr if any>"
}
```

## Error handling

- **Cluster unreachable:** surface helm's exact stderr. Distinguish wrong-context (list contexts) vs auth-expired vs DNS.
- **Release missing:** "Helm release '$RWLENV_RELEASE' not in namespace '$RWLENV_NAMESPACE' on context '$RWLENV_CONTEXT'. Run /rwl-env-cur to verify."
- **Lock contention** (`another operation in progress`): do not retry; report and suggest `helm history` to inspect.
- **Chart fetch failure:** surface helm error; suggest `--chart <local-path>` override.
- **Partial rollout after upgrade succeeds:** the caller (skill) is responsible for `kubectl rollout status` polling; helm-ops returns success on helm-side success.

## Invocation

```
Task tool with subagent_type: "rwl-env:helm-ops"
```
