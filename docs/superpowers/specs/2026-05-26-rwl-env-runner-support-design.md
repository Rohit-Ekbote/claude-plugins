# rwl-env Runner Support Design

## Overview

Add optional runner support to the rwl-env plugin so users can debug and mutate runner-side Kubernetes resources alongside the RunWhen platform. The runner is a separate helm release (chart: `runwhen-local`) that may be in a different namespace or an entirely different cluster/context from the platform.

Runner support is additive and optional. Existing platform-only configurations work unchanged.

## Requirements

- Full mutation parity with the platform side (kubectl reads, helm reads/writes, rollback)
- Runner can be on a different cluster/context, not just a different namespace
- Runner is always associated with a platform rwl-env (parent-child relationship)
- Setting a runner requires its platform to be active
- Single runner per platform (no multi-runner)
- Lightweight services catalog for runner, grown incrementally

## Configuration Schema

### envs.json

The `runner` key is optional. When absent, behavior is identical to today.

```json
{
  "version": "1.0",
  "rwlenvs": {
    "rawfuss": {
      "description": "rawfuss runwhen-platform install (k3s)",
      "kubeconfigPath": "/Users/rohitekbote/.kube/config-rawfuss",
      "kubernetesContext": "rawfuss",
      "namespace": "runwhen",
      "releaseName": "rw",
      "chart": { "repo": "", "name": "runwhen-platform" },
      "readOnly": false,
      "runner": {
        "kubeconfigPath": "/Users/rohitekbote/.kube/config-runner",
        "kubernetesContext": "runner-context",
        "namespace": "runwhen-runner",
        "releaseName": "rwl",
        "chart": { "repo": "", "name": "runwhen-local" },
        "readOnly": false
      }
    }
  }
}
```

When `runner.kubeconfigPath` and `runner.kubernetesContext` match the platform's, the runner is on the same cluster in a different namespace. When they differ, it's a separate cluster.

### Generated env file (.claude/rwl-env-env)

`write_rwlenv_env()` emits runner vars when the `runner` object is present:

```bash
# Platform (existing)
RWLENV_NAME="rawfuss"
RWLENV_KUBECONFIG="/Users/rohitekbote/.kube/config-rawfuss"
RWLENV_CONTEXT="rawfuss"
RWLENV_NAMESPACE="runwhen"
RWLENV_RELEASE="rw"
RWLENV_CHART_REPO=""
RWLENV_CHART_NAME="runwhen-platform"
RWLENV_READ_ONLY="false"

# Runner
RWLENV_HAS_RUNNER="true"
RWLENV_RUNNER_KUBECONFIG="/Users/rohitekbote/.kube/config-runner"
RWLENV_RUNNER_CONTEXT="runner-context"
RWLENV_RUNNER_NAMESPACE="runwhen-runner"
RWLENV_RUNNER_RELEASE="rwl"
RWLENV_RUNNER_CHART_REPO=""
RWLENV_RUNNER_CHART_NAME="runwhen-local"
RWLENV_RUNNER_READ_ONLY="false"
```

When no runner is configured: `RWLENV_HAS_RUNNER="false"` and no `RWLENV_RUNNER_*` vars.

## Hook Validation (transform-commands.sh)

The hook validates commands against two complete credential sets when a runner is configured.

### Matching logic

1. Source `.claude/rwl-env-env` as today.
2. Check if `RWLENV_HAS_RUNNER=true`.
3. For kubectl/helm commands, try matching against the platform credentials (kubeconfig + context + namespace) first. If that fails and runner is configured, try matching against the runner credentials.
4. A command must match one complete set. Mixing platform kubeconfig with runner namespace is blocked.
5. Commands missing required flags (bare `kubectl get pods` with no kubeconfig/context/namespace) are blocked, same as today.

### Validation matrix

| Command | Platform credentials | Runner credentials |
|---|---|---|
| kubectl read | Allow | Allow (if runner configured) |
| kubectl write | Block | Block |
| helm read | Allow (release = `$RWLENV_RELEASE`) | Allow (release = `$RWLENV_RUNNER_RELEASE`) |
| helm write | Allow / block if readOnly | Allow / block if runner readOnly |
| helm forbidden (install/uninstall/delete) | Block | Block |

### Release name validation

When the command targets runner credentials, the helm release name must match `$RWLENV_RUNNER_RELEASE`. The hook determines which target is in play by checking which kubeconfig+context+namespace set matches, then validates the release name against the corresponding variable.

## Agents

### Target-aware agents

`k8s-ops` and `helm-ops` become target-aware. The caller specifies which target (platform or runner) when dispatching. The agent uses the corresponding env var set:

- Platform target: `$RWLENV_KUBECONFIG`, `$RWLENV_CONTEXT`, `$RWLENV_NAMESPACE`, `$RWLENV_RELEASE`
- Runner target: `$RWLENV_RUNNER_KUBECONFIG`, `$RWLENV_RUNNER_CONTEXT`, `$RWLENV_RUNNER_NAMESPACE`, `$RWLENV_RUNNER_RELEASE`

Example runner kubectl command:

```bash
kubectl --kubeconfig="$RWLENV_RUNNER_KUBECONFIG" \
        --context="$RWLENV_RUNNER_CONTEXT" \
        -n "$RWLENV_RUNNER_NAMESPACE" get pods
```

If `RWLENV_HAS_RUNNER=false` and runner target is requested, the agent responds: "No runner configured for this rwl-env."

### Unchanged agents

`db-ops` remains platform-only. No runner-side database exists.

## Services Catalog

New file: `data/runner-services-catalog.json`

```json
{
  "version": "1.0",
  "chartAppVersion": "0.10.55",
  "chartName": "runwhen-local",
  "services": {
    "runner": {
      "description": "Runner agent that executes CodeBundles and manages workers",
      "namespace": "<rwl-env-runner-ns>",
      "imageTagKey": "runner.image.tag",
      "podSelector": "app.kubernetes.io/component=runner",
      "containerName": "runner",
      "internalPort": 9090,
      "probes": null,
      "deploymentWaitFor": []
    },
    "otel-collector": {
      "description": "OpenTelemetry collector for runner metrics",
      "namespace": "<rwl-env-runner-ns>",
      "imageTagKey": null,
      "podSelector": "app.kubernetes.io/component=opentelemetry-collector",
      "containerName": "opentelemetry-collector",
      "internalPort": null,
      "probes": null,
      "deploymentWaitFor": []
    }
  },
  "databases": {},
  "subcharts": {}
}
```

Placeholder `<rwl-env-runner-ns>` is substituted with `$RWLENV_RUNNER_NAMESPACE` at runtime, matching the platform catalog pattern.

Agents check `runner-services-catalog.json` when targeting runner, `services-catalog.json` when targeting platform.

## Skills

### New skill

**`/rwl-runner-set <platform-name>`** — add, update, or remove runner config on an existing platform entry.

- **Add/Update:** Collects runner kubeconfig, context, namespace, release, chart. Writes `runner` object into the platform's envs.json entry. Regenerates `.claude/rwl-env-env` if that platform is currently active.
- **Remove:** `/rwl-runner-set <platform-name> --remove` strips the `runner` object from envs.json and regenerates the env file.
- **Validation:** Platform entry must exist. Runner kubeconfig file must exist. Context must exist in the kubeconfig. Namespace and release name must be provided.

### Updated skills

| Skill | Change |
|---|---|
| `/rwl-env-add` | Optional runner step at end of wizard: "Does this environment have a runner?" If yes, collect runner details. |
| `/rwl-env-set` | No invocation change. When the platform has a runner, both sets of env vars are generated. Print runner details alongside platform. |
| `/rwl-env-cur` | Show runner section below platform when configured. Live helm metadata for both releases. |
| `/rwl-env-list` | Show `[+runner]` flag next to entries that have a runner configured. |
| `/rwl-upgrade-image-tag` | Prompt for target (platform or runner) when runner is configured. Runner target uses `runner-services-catalog.json` and runner env vars. |
| `/rwl-upgrade-chart` | Prompt for target. Runner target uses runner chart/release vars. |
| `/rwl-set-values` | Prompt for target. Runner target uses runner env vars. |
| `/rwl-rollback` | Prompt for target. Runner target uses runner release/namespace. |

### Target selection UX

For mutation skills, if runner is configured, prompt once at the start: "Which target — platform or runner?" If no runner is configured, skip the prompt and proceed with platform.

## Utilities (rwlenv-utils.sh)

### Modified functions

**`write_rwlenv_env(dir, name)`** — after writing existing `RWLENV_*` vars, check for `.runner` object:
- If present: write `RWLENV_HAS_RUNNER="true"` and all `RWLENV_RUNNER_*` vars
- If absent: write `RWLENV_HAS_RUNNER="false"` only

### New functions

| Function | Purpose |
|---|---|
| `has_runner(name)` | Check if rwl-env entry has `.runner` object. rc=0 yes, rc=1 no. |
| `get_runner_config(name)` | Extract `.runner` object from envs.json entry. Returns JSON. |
| `set_runner_config(name, runner_json)` | Write/overwrite `.runner` in envs.json for given platform entry. |
| `remove_runner_config(name)` | Delete `.runner` key from envs.json entry. |
| `is_runner_readonly(name)` | Check `.runner.readOnly`. rc=0 if read-only, rc=1 otherwise. |

### Unchanged functions

`load_envs()`, `get_rwlenv_by_name()`, `list_rwlenv_names()`, `get_current_rwlenv()`, `escape_regex()`, `validate_psql_query()`, write-detection functions — all unchanged.

## Tests

### test-utils.sh additions

- `write_rwlenv_env()` with runner config: verify `RWLENV_HAS_RUNNER=true` and all `RWLENV_RUNNER_*` vars present
- `write_rwlenv_env()` without runner config: verify `RWLENV_HAS_RUNNER=false` and no `RWLENV_RUNNER_*` vars
- `has_runner()`, `set_runner_config()`, `remove_runner_config()` round-trip

### test-hooks.sh additions

- Platform command with platform credentials: allow
- Runner command with runner credentials: allow
- Mixed credentials (platform kubeconfig + runner namespace): block
- Runner command when no runner configured (`RWLENV_HAS_RUNNER=false`): block
- Runner helm write when `RWLENV_RUNNER_READ_ONLY=true`: block
- Runner helm release name must match `$RWLENV_RUNNER_RELEASE`

### Test fixtures

- envs.json fixture entry with `runner` object
- Corresponding `rwl-env-env` fixture with runner vars
