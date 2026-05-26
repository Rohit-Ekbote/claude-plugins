# rwl-env: Helm-Based RunWhen Platform Debug Plugin

## Context & Motivation

The RunWhen platform has been refactored to be CRD-less and deploy into a single namespace via a single helm chart (`runwhen-platform`). The SaaS deployment is managed by Flux; self-hosted deployments are installed and upgraded via `helm`. The existing `rwenv` plugin targets multi-cluster GKE/k3s topologies and is the wrong shape for the self-hosted helm path — it assumes a dev container, multiple clusters, GCP project handles, a Flux repo to pull from, and a multi-namespace service mapping.

`rwl-env` is a sibling plugin in this same marketplace, focused exclusively on **debugging and operating self-hosted, helm-deployed RunWhen platform installs from a local machine**. Mutations always go through `helm upgrade` / `helm rollback` so cluster state stays fully describable by `helm history` — every change is deterministically revertible.

### Hard requirements (from `/rwl-env` brainstorming, 2026-05-22)

1. The plugin cannot expect helm chart source code to be available at runtime.
2. All mutations go through `helm upgrade` (image-tag bumps, arbitrary values overrides, chart-version bumps) or `helm rollback`. No `kubectl apply|patch|edit|...` mutations are reachable from this plugin.
3. Every change must be deterministically revertible via `helm history` + `helm rollback`.
4. When a helm-chart bug is detected, the plugin produces a ready-to-share bug report (markdown GitHub-issue body) for the chart author.
5. The plugin must encode enough service-dependency and debug-workflow knowledge — drawn from the helm chart source and from the application source — to support real debugging without that source being present at runtime.
6. Config inputs are `(kubeconfig path, context name, namespace)`; default kubeconfig is `~/.kube/config`. If the named context isn't there, the plugin scans all kubeconfig files in `~/.kube/`.
7. **Local mode only** — no dev container support (unlike `rwenv`).
8. Skill surface mirrors `rwenv`'s `cur` / `list` / `set` / `add` pattern.

## Goals & Non-Goals

**Goals.** Inspect helm-deployed RunWhen platform installs read-only by default. Allow image-tag updates, arbitrary values overrides, chart-version upgrades, and rollbacks via helm. Encode service dependency graph (from chart) + runtime call graph (from app source) for a curated set of priority services. Ship a starter set of debug workflows for known failure modes drawn from `INSTALL-FRICTIONS.md`. Produce shareable helm-chart bug reports.

**Non-goals (v0).** Release lifecycle (`helm install` / `helm uninstall`). DB write operations of any kind (the plugin is a debugger; writes happen through migrations, not through `psql`). Flux/GitOps operations (that's `rwenv`'s SaaS territory). Dev container support. GCP project handling. Multi-cluster fan-out. Auto-regeneration of the service catalog from chart source at runtime. Inspection of redis / neo4j / qdrant data plane (Postgres only in v0).

## Architecture Overview

```
/rwl-env-set helm-dev
   reads ~/.claude/rwl-env/envs.json once
   writes <project>/.claude/rwl-env (plain-text name) and <project>/.claude/rwl-env-env (resolved KV)
        ↓
Skill or agent runs: helm upgrade rwl <repo>/<chart> --reuse-values --set images.backendServices.tag=X
   command sourced .claude/rwl-env-env, includes --kubeconfig/--kube-context/-n flags
        ↓
PreToolUse hook (transform-commands.sh)
   validates: --kubeconfig, --kube-context, -n flags all present and match active rwl-env
   classifies: is this a legal write? is it allowed under readOnly? is the helm subcommand on the allowlist?
   auto-approves on success, blocks with an actionable message otherwise
```

Two structural departures from `rwenv`:

- **No dev container wrapping.** Commands run directly from the user's `$PATH`.
- **The unit of identity is a helm release**, not a cluster. A single cluster can host multiple rwl-env entries (one per release/namespace pair).

## Directory Layout

```
rwl-env/
├── .claude-plugin/plugin.json          # name=rwl-env, version, keywords
├── README.md
├── LICENSE
├── agents/
│   ├── helm-ops.md                     # helm get|upgrade|rollback|history|status
│   ├── k8s-ops.md                      # kubectl get|logs|events|exec|port-forward
│   └── db-ops.md                       # read-only psql via kubectl exec into the pg pod
├── hooks/
│   ├── hooks.json                      # PreToolUse on Bash: transform-commands.sh
│   └── transform-commands.sh           # flag validation, readOnly enforcement, auto-approval
├── lib/
│   └── rwlenv-utils.sh                 # config IO, helm/kubectl/psql builders, write detection
├── data/
│   ├── services-catalog.json           # service → namespace, imageTagKey, deps, ports, probes, runtime
│   └── workflows-index.json            # symptom → recommended debug skill
├── skills/
│   ├── rwl-env-list/SKILL.md
│   ├── rwl-env-cur/SKILL.md
│   ├── rwl-env-set/SKILL.md
│   ├── rwl-env-add/SKILL.md
│   ├── rwl-upgrade-image-tag/SKILL.md
│   ├── rwl-set-values/SKILL.md
│   ├── rwl-upgrade-chart/SKILL.md
│   ├── rwl-rollback/SKILL.md
│   ├── rwl-report-chart-bug/SKILL.md
│   ├── rwl-debug/SKILL.md              # dispatcher
│   ├── rwl-debug-pod/SKILL.md
│   ├── rwl-debug-image-pull/SKILL.md
│   ├── rwl-debug-migrations/SKILL.md
│   ├── rwl-debug-vault/SKILL.md
│   ├── rwl-debug-papi/SKILL.md
│   ├── rwl-debug-agentfarm/SKILL.md
│   └── rwl-debug-llm/SKILL.md
├── scripts/                            # helper bash, no shell-state
└── tests/                              # hook + utility unit tests
```

## Config Schema

### Global config — `~/.claude/rwl-env/envs.json`

Path is overridable via the `RWLENV_CONFIG_DIR` env var.

```json
{
  "version": "1.0",
  "rwlenvs": {
    "helm-dev": {
      "description": "Local k3d cluster, single-namespace platform install",
      "kubeconfigPath": "/Users/rohitekbote/.kube/config",
      "kubernetesContext": "k3d-rwl-dev",
      "namespace": "runwhen",
      "releaseName": "rwl",
      "chart": {
        "repo": "oci://us-docker.pkg.dev/runwhen-self-hosted/charts",
        "name": "runwhen-platform"
      },
      "readOnly": false
    },
    "helm-staging": {
      "description": "Shared staging install (view-only)",
      "kubeconfigPath": "/Users/rohitekbote/.kube/staging-config",
      "kubernetesContext": "gke_runwhen-staging_us-central1_staging",
      "namespace": "runwhen",
      "releaseName": "rwl",
      "chart": {
        "repo": "https://charts.runwhen.com",
        "name": "runwhen-platform"
      },
      "readOnly": true
    }
  }
}
```

Notes:

- No `container` / `local` sub-objects — every entry is local-only.
- No `gcpProject` or `fluxGitRepo` — out of scope.
- Chart **version** is not stored; it is read live from `helm get metadata <release>` so the catalog always reflects what's actually deployed. Pinned-version overrides for image-tag upgrades use `--reuse-values --version <current>`.
- `kubeconfigPath` is recorded as resolved at add-time (tilde already expanded).

### Per-project active marker — `<project>/.claude/rwl-env`

Plain text, one line: the entry name (e.g., `helm-dev`). Auto-gitignored on first write.

### Per-project runtime config — `<project>/.claude/rwl-env-env`

Generated by `/rwl-env-set` from the active entry. Sourced by hooks and agents at runtime:

```bash
# Generated by /rwl-env-set. Do not edit manually.
RWLENV_NAME=helm-dev
RWLENV_KUBECONFIG=/Users/rohitekbote/.kube/config
RWLENV_CONTEXT=k3d-rwl-dev
RWLENV_NAMESPACE=runwhen
RWLENV_RELEASE=rwl
RWLENV_CHART_REPO=oci://us-docker.pkg.dev/runwhen-self-hosted/charts
RWLENV_CHART_NAME=runwhen-platform
RWLENV_READ_ONLY=false
```

Auto-gitignored. Single source of truth at runtime — skills and agents source this rather than re-parsing `envs.json` on every call (mirrors rwenv's `.claude/rwenv-env`).

## Skills Surface

### Env management

| Skill | Args | Behavior |
|---|---|---|
| `/rwl-env-list` | — | Read `envs.json`, render table: `NAME · CONTEXT · NAMESPACE · RELEASE · READ-ONLY`. Mark current-dir's active entry with `*`. |
| `/rwl-env-cur` | — | Source `.claude/rwl-env-env`; show resolved values + live `helm get metadata` (chart version, last revision, last upgrade timestamp). Show stale-catalog warning if live `appVersion` ≠ `services-catalog.json.chartAppVersion`. Warn if `readOnly: true`. |
| `/rwl-env-set [name]` | optional entry name | Switches active entry for current project dir. Writes `.claude/rwl-env` + `.claude/rwl-env-env`. Prompts if `[name]` omitted. |
| `/rwl-env-add [name]` | optional name | Interactive add (Section 8). Offers "set as active for this dir" at the end. |

### Helm operations — every write goes through `helm upgrade` or `helm rollback`

| Skill | Args | Behavior |
|---|---|---|
| `/rwl-upgrade-image-tag` | `<service> <new-tag> [--chart <local-path>]` | Resolves `<service>` → `imageTagKey` via catalog. Runs `helm upgrade <release> <chart-repo>/<chart-name> --reuse-values --version <current> --set <key>=<tag> -n <ns>`. Shows diff (current tag → new tag) and lists every other service that shares the same `imageTagKey`. Prompts before execution. After upgrade, polls `kubectl rollout status` for all affected deployments and reports. `--chart` overrides the entry's default chart source for a single call (airgapped / offline use). |
| `/rwl-set-values` | `<key>=<value>` (repeatable) or `--values-file <path>` `[--chart <local-path>]` | Arbitrary overrides via `helm upgrade --reuse-values --set ...` (or `-f <file>`). Same diff-then-confirm flow. Refuses keys that toggle subchart deploy/useSubchart (e.g., `postgresql.deploy`) without `--allow-subchart-toggle` because those changes have non-trivial data-migration implications. `--chart` override behaves the same as above. |
| `/rwl-upgrade-chart` | `--version <X.Y.Z>` `[--chart <local-path>]` | Bumps the chart: `helm upgrade <release> <chart-repo>/<chart-name> --version <X.Y.Z> --reuse-values`. Shows the chart-version diff first and prints the rollback command prominently. `--chart` override behaves the same as above. |
| `/rwl-rollback` | optional `--to-revision <N>` | If `--to-revision` omitted, lists `helm history <release>` and prompts via AskUserQuestion. Shows the values diff between target and current. Then `helm rollback <release> <N>`. Always allowed unless `readOnly: true`. No `--chart` flag — rollback uses the chart already in helm history. |

### Bug reporting

| Skill | Args | Behavior |
|---|---|---|
| `/rwl-report-chart-bug` | optional `--symptom <free text>`, `--service <name>`, `--resource <kind/name>` | Collects chart metadata, values, failing resources, logs, events. Renders markdown GitHub-issue body inline AND saves to `./helm-bug-reports/<release>-<svc-or-res>-<YYYY-MM-DD-HHMM>.md`. Auto-gitignores `helm-bug-reports/` on first write. Redaction applied (Section 9). |

### Debug workflows — starter set, grows over time

Narrative markdown skills that walk the user through diagnosis. They lean on `helm-ops` / `k8s-ops` / `db-ops` agents for command execution and read `services-catalog.json` for facts.

v0 starter set:

- `/rwl-debug` — dispatcher; takes a free-text symptom, scores it against `workflows-index.json` `matchHints`, recommends the right `rwl-debug-<topic>` skill.
- `/rwl-debug-pod` — generic CrashLoopBackOff / pending-pod triage.
- `/rwl-debug-image-pull` — ImagePullBackOff diagnosis (registry, pullSecrets, airgap/JFrog paths from INSTALL-FRICTIONS).
- `/rwl-debug-migrations` — db-init-job + migration-controller hang flow.
- `/rwl-debug-vault` — sealed vault, unsealer crashloop, vault-init-job.
- `/rwl-debug-papi` — papi runtime failures (calls out → alert-query / usearch / vault / redis / postgres:core).
- `/rwl-debug-agentfarm` — agentfarm runtime + LLM gateway chain.
- `/rwl-debug-llm` — llm-bootstrap + llm-gateway + provider config.

### Out of v0 (notes for later)

- `/rwl-env-edit` / `/rwl-env-remove` (manual edit of `envs.json` for now).
- `/rwl-env-refresh-catalog` (catalog is hand-maintained in v0).

## Agents

Three agents, all invoked via `Task` with `subagent_type: "rwl-env:<name>"`. Each agent doc declares its capabilities, command patterns, and refuses commands outside its surface.

### `agents/helm-ops.md` — owns the `helm` binary

- Reads: `helm list`, `helm status`, `helm history`, `helm get values|manifest|metadata`.
- Writes: `helm upgrade <release> <chartref> --reuse-values --version <ver> [--set k=v] [-f file]`, `helm rollback <release> <rev>`.
- **Always sources `.claude/rwl-env-env` first** and includes `--kubeconfig=$RWLENV_KUBECONFIG --kube-context=$RWLENV_CONTEXT -n $RWLENV_NAMESPACE` on every call. Refuses to run if any of those are unset.
- **Never calls `helm install` or `helm uninstall`** — release lifecycle is deliberate, not casual; out of scope for this agent.
- On any helm write, captures the prior revision number from `helm history` and includes it in the structured result so the caller can suggest `--to-revision <N>` for rollback if needed.
- Returns: `{ok, revisionBefore, revisionAfter, valuesDiff, chartVersionBefore, chartVersionAfter, stderr}`.

### `agents/k8s-ops.md` — owns the `kubectl` binary

- Read-by-default: `kubectl get|describe|logs|events|top`, `kubectl rollout status|history`, `kubectl auth can-i`, `kubectl version`, `kubectl cluster-info`.
- Interactive (allowed): `kubectl exec` (shells, diagnostic probes, psql against in-pod Postgres), `kubectl port-forward`.
- Writes (`apply|delete|patch|edit|create|replace|scale|rollout restart|set image|label|annotate|cordon|drain`) **always blocked**. The only legal mutation path from this plugin is `helm-ops`. Hook enforces this independently; the agent doc explicitly refuses to construct these commands.
- Always includes `--kubeconfig=$RWLENV_KUBECONFIG --context=$RWLENV_CONTEXT` and defaults `-n $RWLENV_NAMESPACE` unless the caller overrides for a known subchart namespace (e.g., a separated vault namespace).
- Uses `services-catalog.json` to resolve "look at papi" → pod selector / port / dependency edges.

### `agents/db-ops.md` — read-only Postgres inspection via `kubectl exec`

- Service discovery: `kubectl get svc -l app.kubernetes.io/instance=$RWLENV_RELEASE -o name` plus the catalog's `serviceLabelSelector` / `fallbackServiceName`.
- Credentials: pull password from the K8s secret matching the catalog's `secretNamePattern`. Never logged, never written to disk.
- **Default mechanism: `kubectl exec` into the Postgres pod**, run psql against `127.0.0.1` inside the pod. Credentials passed via `env PGPASSWORD=...` to the exec'd shell. No port-forward, no background pid, no host psql dependency.
- Port-forward kept as an opt-in fallback for the (uncommon) case of an interactive `psql` session the user explicitly requests.
- **Always read-only, regardless of `readOnly`:**
  - DDL (`CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|VACUUM|REINDEX|CLUSTER`) — always blocked.
  - DML (`INSERT|UPDATE|DELETE|MERGE|UPSERT`) — always blocked from this plugin (helm upgrade is the only write path; DB writes happen through chart-managed migrations, not psql).
  - `COPY ... TO` — blocked (file writes).
  - Reads (`SELECT`, `EXPLAIN`, `\d`) — allowed.

## Safety Hook

A single PreToolUse hook on `Bash` does all enforcement. Same pattern as rwenv's `transform-commands.sh` but simpler (no devcontainer wrapping, no GCP).

### `hooks/hooks.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/transform-commands.sh" }
        ]
      }
    ]
  }
}
```

One hook, one file. No git-protection hook (rwl-env doesn't touch git state).

### Engagement and flag validation

The hook sources `$PWD/.claude/rwl-env-env` first. If that file is missing, the hook passes through silently — no active rwl-env, no opinion.

Otherwise it inspects the Bash command's first significant binary against `{kubectl, helm, psql}`. Anything else is passed through.

The command must include flags exactly matching the active rwl-env, or it's blocked with an actionable explanation:

| Tool | Required flags |
|---|---|
| `kubectl` | `--kubeconfig=$RWLENV_KUBECONFIG`, `--context=$RWLENV_CONTEXT`, `-n $RWLENV_NAMESPACE` (or explicit `-n <other-ns>` only for catalog-known subchart namespaces) |
| `helm` | `--kubeconfig=$RWLENV_KUBECONFIG`, `--kube-context=$RWLENV_CONTEXT`, `-n $RWLENV_NAMESPACE`, and the release argument equal to `$RWLENV_RELEASE` |
| `psql` | Only when piped through `kubectl exec`. The outer `kubectl exec` must already pass its own flag validation; the inner `psql` runs against `127.0.0.1` and is validated for query safety only. |

### Decision matrix

| Tool | Subcommand class | `readOnly: false` | `readOnly: true` |
|---|---|---|---|
| `helm` | `get`, `history`, `status`, `list`, `template`, `show`, `lint` | Allow | Allow |
| `helm` | `upgrade`, `rollback` | Allow | Block — read-only env |
| `helm` | `install`, `uninstall`, `delete`, `repo add`, `repo remove`, `dependency *` | Block always (out of scope) | Block |
| `kubectl` | `get`, `describe`, `logs`, `events`, `top`, `auth can-i`, `version`, `cluster-info`, `rollout status`, `rollout history` | Allow | Allow |
| `kubectl` | `exec`, `port-forward` (with extra checks below) | Allow | Allow (reads from rwl-env's perspective) |
| `kubectl` | `apply`, `delete`, `patch`, `edit`, `create`, `replace`, `scale`, `rollout restart`, `set image`, `label`, `annotate`, `cordon`, `drain` | Block always (only helm-ops mutates) | Block |
| `psql` | Pure SELECT / EXPLAIN / `\d` / metadata reads | Allow | Allow |
| `psql` | DDL, DML, `COPY ... TO` | Block always | Block |

### Extra checks for `kubectl exec` and `kubectl port-forward`

- `kubectl exec ... -- <cmd>`: if `<cmd>` invokes `psql`, only the `psql -c '<query>'` form is supported. The `-c '<query>'` argument is extracted and validated against the SQL rules above. **Other psql invocation forms are blocked** (`psql -f <file>`, `psql` reading from stdin without `-c`, `psql` with no query argument starting an interactive session) — the hook cannot introspect what would be sent, so it refuses rather than waving them through. Interactive psql sessions are reachable only via the explicit port-forward fallback path. If `<cmd>` is an interactive shell (`sh`/`bash`/`-it`), it's allowed — the user takes the controls and operates outside the agent's auto-approval contract.
- `kubectl port-forward`: target must be a `svc/...` or `pod/...` in `$RWLENV_NAMESPACE` or a catalog-known subchart namespace. Local port is unrestricted but logged in the hook's structured output for traceability.

### Decision output

- **Allow:** emit `{"hookSpecificOutput":{"permissionDecision":"allow"}}` and exit 0.
- **Block:** single-line, actionable stderr message naming the rwl-env. Exit 2. Examples:
  - `BLOCKED by rwl-env: helm upgrade not allowed; rwl-env 'helm-staging' is read-only.`
  - `BLOCKED by rwl-env: kubectl --context flag is 'prod' but active rwl-env 'helm-dev' uses 'k3d-rwl-dev'.`
  - `BLOCKED by rwl-env: psql query contains DDL (DROP TABLE); the rwl-env db-ops surface is read-only.`

### What the hook does NOT do

- Doesn't rewrite commands. If flags are wrong, it blocks and tells the agent to construct correctly. (Auto-rewriting hides bugs in agent command construction.)
- Doesn't gate on `readOnly` for kubectl reads or psql reads — those are always safe.
- Doesn't try to parse multi-statement SQL semantically. A `;` joining two statements is treated as multiple statements and blocked if any one violates the rules. Conservative; correct.

## Service Catalog & Workflows Index

Two files. Hand-authored at plugin build time from the helm chart + application source. Pinned to a chart `appVersion`. Refreshed on chart bumps (manually in v0).

### `data/services-catalog.json` — facts the agents and skills query

```json
{
  "version": "1.0",
  "chartAppVersion": "1.0.0",
  "chartName": "runwhen-platform",
  "services": {
    "papi": {
      "description": "Public REST API",
      "namespace": "<rwl-env-ns>",
      "imageTagKey": "images.backendServices.tag",
      "podSelector": "app=papi",
      "containerName": "papi",
      "internalPort": 8080,
      "probes": { "readiness": "/healthz", "liveness": "/healthz" },
      "deploymentWaitFor": ["db-init", "vault-init", "migration-controller"],
      "runtime": {
        "summary": "REST entrypoint; fans out to alert-* services, usearch, and core DB.",
        "callsOut": ["alert-query", "alert-worker", "usearch", "vault", "redis", "postgres:core"],
        "calledBy": ["user-pages", "external clients via ingress"],
        "knownFailureChains": [
          {
            "symptom": "5xx on /api/v1/alerts",
            "checkOrder": ["alert-query pod ready", "redis reachable", "postgres core writable"],
            "skill": "rwl-debug-papi"
          }
        ]
      }
    }
  },
  "databases": {
    "core": {
      "description": "Core platform DB (papi, alerts, taskiq)",
      "secretNamePattern": "core-pguser-core",
      "serviceLabelSelector": "app.kubernetes.io/instance=<release>,application=spilo,cluster-name=core",
      "fallbackServiceName": "core-pgbouncer",
      "database": "core",
      "username": "core",
      "consumedBy": ["papi", "alerts", "taskiq-worker", "taskiq-scheduler"]
    }
  },
  "subcharts": {
    "vault":      { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=vault" },
    "redis":      { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=redis" },
    "neo4j":      { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=neo4j" },
    "qdrant":     { "namespace": "<rwl-env-ns>", "selector": "app=qdrant" },
    "seaweedfs":  { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=seaweedfs" },
    "postgresql": { "namespace": "<rwl-env-ns>", "selector": "application=spilo" }
  }
}
```

Placeholder convention: `<release>` and `<rwl-env-ns>` are substituted at runtime from `$RWLENV_RELEASE` / `$RWLENV_NAMESPACE` (same `sed` substitution rwenv already does in `get_service_info`).

**The JSON examples in this document are illustrative.** Exact label selectors, secret name patterns, container names, and `imageTagKey` paths are confirmed by reading the chart's templates and `values.yaml` during catalog authoring (Authoring process, below). Where the document shows `app.kubernetes.io/instance=<release>,application=spilo,cluster-name=core`, the real value comes from the rendered Spilo manifests; treat the shown form as a placeholder for "the right selector once we verify it."

#### Runtime-block coverage in v0

The 5–7 priority services get a full `runtime` block. The rest get deployment-graph fields only and grow `runtime` blocks lazily as debug sessions reveal need.

| Full `runtime` block (v0) | Deployment-graph fields only (v0) |
|---|---|
| papi, agentfarm, embedder, llm-gateway, taskiq-worker, sobow-search/sobrain, migration-controller | activities, alerts, alert-ingestor, alert-query, alert-worker, cc-catalog-svc, llm-bootstrap, mcp-server, metricstore, runner-control, runner-metric-proxy, slackbot, sobow-index, taskiq-scheduler, usearch, user-pages, webhooks, vault-unsealer |

### `data/workflows-index.json` — symptom → debug skill

```json
{
  "version": "1.0",
  "chartAppVersion": "1.0.0",
  "symptoms": {
    "pod-stuck-init-wait-for-migrations": {
      "matchHints": ["initContainer wait-for-migrations", "migration-controller CrashLoop"],
      "skill": "rwl-debug-migrations",
      "likelyCauses": [
        "agentfarm image predates webapp/migration_controller.py",
        "db-init-job failed",
        "core DB not reachable from migration-controller"
      ],
      "firstChecks": [
        "kubectl logs <release>-migration-controller-0 -c migration-controller",
        "helm get values <release> | yq .images.agentfarm.tag",
        "kubectl get job <release>-db-init -o yaml"
      ]
    }
  }
}
```

`/rwl-debug` dispatcher scores user symptoms against `matchHints` and routes to the recommended skill (or asks for clarification when scores tie).

### Authoring process

Documented in `docs/CATALOG-AUTHORING.md`, executed once during implementation:

1. Walk `runwhen-platform/templates/` to enumerate first-party services and extract: namespace (from rendered metadata), `imageTagKey` (path in `values.yaml` controlling the tag), labels/selector, container name, ports, probes, init-container chain (`deploymentWaitFor`).
2. Read `runwhen-platform/INSTALL-FRICTIONS.md` end-to-end. Every numbered friction becomes a candidate `symptoms.*` entry, clustered by service/topic into the dispatcher skills.
3. For each of the 5–7 priority services, **read the application source** to populate the `runtime` block (`summary`, `callsOut`, `calledBy`, `knownFailureChains`). This step requires access to per-service source repos / monorepo paths — to be re-confirmed at implementation time.
4. Pin both files to the chart's `appVersion` from `Chart.yaml` and to `chartName`. At runtime, `/rwl-env-cur` reads `helm get metadata` and warns if live `appVersion` ≠ catalog pin.

### Where knowledge lives

| Knowledge | Lives in | Why |
|---|---|---|
| Service facts (selector, tag-key, namespace, deps, probes) | `services-catalog.json` | Queryable by agents; testable as data |
| Symptom → skill mapping | `workflows-index.json` | Dispatcher needs it as data |
| Narrative debug procedures | `skills/rwl-debug-<topic>/SKILL.md` | Markdown is the right shape for stepwise human-readable guidance |
| Likely-causes lists & first-checks | `workflows-index.json` AND the matching `SKILL.md` | Index helps the dispatcher score; SKILL.md explains it to a human. Intentional duplication. |

### Staleness handling

- Catalog pins to `chartAppVersion`. `/rwl-env-cur` shows: `Catalog appVersion: 1.0.0 (matches live release ✓)` or `(live release on 1.1.0 — catalog may be out of date)`.
- A follow-up `/rwl-env-refresh-catalog` skill (not v0) would re-author from a freshly pointed-at chart + app source. v0 expects the maintainer to do this by hand on a chart bump.

## Canonical Flows

### Image-tag upgrade — `/rwl-upgrade-image-tag papi 2026-05-22.3`

```
1. Source .claude/rwl-env-env  →  RWLENV_{NAME,KUBECONFIG,CONTEXT,NAMESPACE,RELEASE,CHART_REPO,CHART_NAME,READ_ONLY}
2. If RWLENV_READ_ONLY=true     →  refuse with explanation, exit.
3. Look up "papi" in services-catalog.json
   →  imageTagKey = "images.backendServices.tag"
   (one tag often controls multiple services — list every service that shares this key)
4. helm-ops: helm get values <release> -n <ns> -o yaml  →  yq '.images.backendServices.tag'
   →  currentTag = "2026-05-20.1"
5. helm-ops: helm get metadata <release> -n <ns>
   →  currentChartVersion = "0.2.0", currentRevision = 7
6. Present diff and AskUserQuestion to confirm:
       Service:        papi   (also: activities, alerts, slackbot, sobrain, sobow-*, taskiq-*)
       Image tag:      2026-05-20.1  →  2026-05-22.3
       Chart version:  0.2.0  (unchanged, --reuse-values)
       Rollback hint:  /rwl-rollback --to-revision 7
   Options: "Yes, upgrade" / "No, cancel"
7. helm-ops:
       helm upgrade <release> <chart-repo>/<chart-name>
         --kubeconfig=<kubeconfig> --kube-context=<context> -n <ns>
         --version <currentChartVersion>
         --reuse-values
         --set images.backendServices.tag=2026-05-22.3
   Hook validates flags → allows (readOnly=false, subcommand=upgrade, release matches).
8. k8s-ops: kubectl rollout status -n <ns> deploy/<name> --timeout=3m
   (for every deployment that uses the shared backendServices tag — catalog tells us which)
9. Report:
       Upgrade complete.
       Revision: 7  →  8         (rollback: /rwl-rollback --to-revision 7)
       Rollout:  papi ✓  activities ✓  alerts ✓  …
       Image:    backend-services:2026-05-22.3 pulled successfully.
```

If step 8 reports any deployment stuck in CrashLoop or ImagePullBackOff, the skill prints the rollback command prominently and offers to invoke `/rwl-rollback --to-revision 7` directly.

### Rollback — `/rwl-rollback`

```
1. Source .claude/rwl-env-env, refuse if RWLENV_READ_ONLY=true.
2. helm-ops: helm history <release> -n <ns>
3. If --to-revision N given, use it. Otherwise present table (revision, updated, status, chart, app-version, description) via AskUserQuestion.
4. Compute diff between target revision and current:
       helm get values <release> --revision <current>  vs  --revision <target>
   Show concise diff (changed keys only).
5. Confirm: "Roll back to revision <N>? (chart version <X>, image tag <Y>)"  ·  Yes / No
6. helm-ops: helm rollback <release> <N> -n <ns> --kubeconfig=... --kube-context=...
7. k8s-ops: wait for kubectl rollout status on every deployment the helm release manages.
8. Report final state with new revision number (rollback creates a new revision; helm history grows, never shrinks — so subsequent rollbacks remain deterministic).
```

### Why this satisfies the "deterministic revert" requirement

- The only mutation paths are `helm upgrade` and `helm rollback`. Both are recorded in `helm history`, creating an append-only log.
- `--reuse-values` ensures image-tag changes don't accidentally pick up new values defaults — the rolled-back state is exactly the prior recorded values + chart.
- Every write skill prints the rollback command before it runs.
- The hook blocks every kubectl write, so out-of-band drift (kubectl edit/patch/scale) cannot enter the picture. Cluster state is always describable by `helm history <release>`.

### `/rwl-env-add` flow

```
1. Name — [a-z0-9-]+, must not already exist.
2. Description — free text.
3. Kubeconfig resolution:
   3a. If user passed --kubeconfig <path>: use it. Skip to 3d.
   3b. Default: probe ~/.kube/config; list its contexts as default candidates.
   3c. If user passed --context <ctx>:
       - If ~/.kube/config contains <ctx> exactly: record (~/.kube/config, <ctx>). Skip to 3e.
       - Else SCAN:
            find ~/.kube/ -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \
                          -o -name 'config' -o -name '*-config' -o -name '*.config' \)
            plus colon-split paths in $KUBECONFIG.
       - For each file, run `kubectl --kubeconfig=<f> config get-contexts -o name`; collect (file, context) pairs.
       - Exact-match filter on <ctx>; substring-match fallback if zero exact.
       - 1 match: record it. >1: AskUserQuestion. 0: error with the full list of contexts seen.
   3d. If no --context was passed but kubeconfig resolved: list contexts and prompt to choose.
   3e. Validate (path, ctx) is reachable: kubectl auth can-i get pods. Soft check — warn but proceed.
4. Namespace — validate via `kubectl get ns <ns>`.
5. Release name —
       helm list -n <ns> -o json | jq '.[].name'
   - exactly 1: auto-fill, show "Using release '<name>' (only release in namespace)."
   - >1: AskUserQuestion.
   - 0: error.
6. Chart repo & name —
       chartName inferred from `helm get metadata <release>`
       chartRepo asked via AskUserQuestion: OCI vs HTTPS, then the URL.
       Soft validation: `helm show chart <repo>/<chartName>`.
7. Read-only mode — AskUserQuestion: "No (read-write)" / "Yes (read-only)".
8. Set as active for current dir? — Yes / No.
9. Save: jq-based atomic merge into envs.json. Show resolved entry summary.
```

Library functions added to `lib/rwlenv-utils.sh`:

| Function | Purpose |
|---|---|
| `resolve_kubeconfig_and_context(user_kubeconfig, user_context)` | Implements 3a–3d. Returns `(path, context)` or error with candidates. |
| `discover_kubeconfig_files()` | Newline-separated candidate files under `~/.kube/` (filtered to parseable). |
| `list_contexts_in_file(file)` | Wraps `kubectl config get-contexts -o name`. |
| `find_context_across_files(context_name)` | `(file, context)` pairs matching exact then substring. |
| `discover_helm_releases(kubeconfig, context, namespace)` | Wraps `helm list -n <ns> -o json`. |
| `infer_chart_name(kubeconfig, context, namespace, release)` | Wraps `helm get metadata` and pulls `.chart`. |
| `set_rwlenv_for_dir(dir, name)` / `write_rwlenv_env(dir, name)` | Per-project file writes. |

Add-flow edge cases:

- `~/.kube/` doesn't exist → error: "No kubeconfig found. Create `~/.kube/config` or pass `--kubeconfig`."
- Kubeconfig file unreadable/malformed → skip during scan, warn to stderr, continue.
- `$KUBECONFIG` lists multiple files → split on `:`, include each in the scan.
- Same context name across two files → user is prompted; chosen `(file, context)` pair is recorded.
- Ctrl-C mid-flow → no partial write to `envs.json` (jq merge is the last step).

### `/rwl-report-chart-bug` flow

Triggered manually or proactively from a write/debug skill that detects a known-bug signature.

```
1. Source .claude/rwl-env-env.
2. helm-ops:
     helm get metadata <release> -n <ns>           →  chart name, chart version, app version, last upgrade ts, revision
     helm get values   <release> -n <ns> -o yaml
     helm history      <release> -n <ns> -o json   (last 5 revisions)
3. If --service: look up in services-catalog.json, get selector → kubectl get deploy,sts,pod -l <sel> -n <ns> -o yaml.
4. If --resource <kind/name>: kubectl get/describe <kind> <name> -n <ns>.
5. For every implicated pod:
     kubectl logs <pod> [-c <container>] -n <ns> --tail=200
     kubectl logs <pod> --previous --tail=100   (if available)
6. kubectl get events -n <ns> --sort-by=.lastTimestamp [--field-selector involvedObject.name=<x>]
7. If symptom maps to a workflows-index entry: pull likelyCauses + firstChecks into the report.
8. Compose markdown, redact, render inline, write file.
```

#### Redaction rules

Applied to every collected blob *before* it enters the report:

| Source | Redaction |
|---|---|
| `helm get values` | Values at keys matching `(?i)(password\|secret\|token\|apikey\|api_key\|credential\|.*-key\|privatekey)` → `***REDACTED***`. Key name retained so reviewers see it was set. |
| `kubectl get ... -o yaml` | `data:` and `stringData:` on Secret resources dropped entirely, replaced with `data: { <N entries redacted> }`. |
| Logs | Regex sweep for AWS/GCP/Azure access-key patterns, JWT-shaped tokens, basic-auth URIs. Conservative — when in doubt, redact. |
| ConfigMaps | Kept as-is unless data value matches the secret-key regex above. |
| Image references | Kept (registry/tag are debug-critical and not sensitive). |

Banner at the top of rendered output: `"Redaction applied: 3 helm-values keys, 1 Secret resource, 2 log lines. Review the full file before posting publicly."`

#### Generated artifact

Markdown shape:

```markdown
# [chart-bug] <release> · <service-or-resource> · <one-line-symptom>

**Reporter context** (auto-generated by rwl-env v<plugin-version>)

| | |
|---|---|
| Chart            | `runwhen-platform` |
| Chart version    | `0.2.0`            |
| App version      | `1.0.0`            |
| Release          | `rwl`              |
| Revision         | `7` (last upgraded 2026-05-22 14:03 UTC) |
| Kubernetes       | `v1.30.2` (k3d-rwl-dev) |
| rwl-env          | `helm-dev` |

## Observed
<symptom — from --symptom or detected signature>

## Expected
<chart docs / values.yaml comment that describes intended behavior, if the workflows-index has it>

## Minimal repro
1. `helm upgrade rwl runwhen/runwhen-platform --version 0.2.0 --reuse-values …`
2. <next steps from the failure chain>

## Diagnostic snapshot
### helm get values (redacted)
\`\`\`yaml
<redacted values>
\`\`\`

### Failing resource(s)
<kubectl get -o yaml output, redacted>

### Recent events
<kubectl events output>

### Recent logs (last 200 lines, redacted)
\`\`\`
<logs>
\`\`\`

## Likely causes (from rwl-env workflows-index)
- <cause 1>
- <cause 2>

## Already-tried
<placeholder for the user to fill in before posting>

---
*Generated by rwl-env. Redaction applied: 3 helm-values keys, 1 Secret resource, 2 log lines.*
```

#### File output

- Path: `./helm-bug-reports/<release>-<service-or-resource>-<YYYY-MM-DD-HHMM>.md`.
- `helm-bug-reports/` is auto-added to the project's `.gitignore` on first write.
- Skill prints the path prominently at end of run.

#### What it does NOT do

- Doesn't post to GitHub. (Follow-up via `gh issue create` if/when a target repo is confirmed.)
- Doesn't gather cluster-wide state — only the configured namespace + implicated resources. Avoids leaking unrelated tenant data on shared clusters.
- Doesn't store reports in `~/.claude/rwl-env/` — they're per-project artifacts.
- Doesn't auto-fill "Expected" when the workflows-index has no entry — renders a `<!-- describe expected behavior -->` placeholder.

## Error Handling

| Category | Trigger | Surface |
|---|---|---|
| No active rwl-env | Skill runs without `.claude/rwl-env-env` | "No rwl-env set for this project. Run `/rwl-env-set <name>` or `/rwl-env-add` first." Skill exits cleanly, no partial state. |
| No global config | `~/.claude/rwl-env/envs.json` missing | `/rwl-env-list` / `/rwl-env-set` print: "rwl-env config not found at `~/.claude/rwl-env/envs.json`. Run `/rwl-env-add` to create your first entry." |
| Malformed `envs.json` | jq parse fails | Show parse error + line, refuse to write (don't compound corruption), suggest manual fix. |
| Cluster unreachable | `kubectl` returns network/dial error | Distinguish three sub-cases: (a) wrong context — list available contexts in the kubeconfig; (b) auth expired — suggest the right `gcloud auth` / `kubectl config` step; (c) DNS/network — print the underlying error and stop. |
| Release missing | `helm get metadata` returns "not found" | "Helm release '<release>' not in namespace '<ns>' on context '<ctx>'. Was it uninstalled, or is the rwl-env entry pointing at the wrong release? Run `/rwl-env-cur` to verify." |
| Chart repo unreachable | `helm upgrade` fails on fetch | Surface helm's own error. Suggest `--chart <local-path>` override. Do not retry automatically. |
| Service not in catalog | `/rwl-upgrade-image-tag <svc>` where svc isn't keyed | List services that are in the catalog. Refuse to guess image-tag keys — wrong guess corrupts the release. |
| Stale catalog | Live `appVersion` ≠ `services-catalog.json.chartAppVersion` | Warn (not block) on `/rwl-env-cur` and at the top of every debug skill. Mutations still proceed; debug recommendations get an "(catalog may be stale)" badge. |
| Hook block | Hook exit 2 | Single-line stderr message is the user-facing error. Skills don't try to "fix" a block; they surface it and stop. |
| Helm lock contention | "another operation in progress" | Tell the user a helm op is already running for `<release>`, suggest `helm history` to inspect. No retry. |
| Partial rollout after upgrade | `helm upgrade` returned 0 but `kubectl rollout status` times out | Print rollback command prominently with pre-upgrade revision number. Offer to invoke `/rwl-rollback --to-revision <N>` directly. |
| Bug-report write failure | Can't create `./helm-bug-reports/` (read-only fs, etc.) | Fall back to printing markdown body inline only, with note that file persistence failed. |

### Cross-cutting principles

- **No silent recovery.** If something the user might want to know about goes sideways, surface it.
- **No automatic retry on mutations.** Helm operations are single-attempt by design — retry might land in a half-applied state.
- **Read failures degrade gracefully.** If `helm history` is slow or events are unavailable, skills note the missing piece and continue with what they have.
- **One stderr line per blocked op.** Hook messages are single-line, actionable, and name the rwl-env.
- **Exit codes match rwenv's convention.** `0` = success/allow, `1` = soft error, `2` = block/refuse.

## Bash 3.2 Compatibility

Per project CLAUDE.md: macOS ships bash 3.2. Hook + utils stick to portable bash.

- No `declare -A` (associative arrays).
- No `${var,,}` lowercase expansion.
- No `|&` stderr piping.
- No `local` outside functions.

## Testing

Mirror `rwenv/tests/` layout. Three layers, no test framework dependency.

| Layer | What | How |
|---|---|---|
| Hook unit tests | `transform-commands.sh` decision matrix | Synthetic Bash command inputs piped to the hook; assert on stderr + JSON stdout + exit code. One test per row of the decision matrix (allow/block, read/write, readOnly on/off, missing flag, wrong context, etc.). Bash + small assert helper. |
| Library unit tests | `lib/rwlenv-utils.sh` functions | `resolve_kubeconfig_and_context` against synthetic `~/.kube/` fixtures in tmpdir. SQL validator against fixture of allowed/blocked queries. Placeholder substitution (`<release>`, `<rwl-env-ns>`). |
| Catalog schema tests | `services-catalog.json` + `workflows-index.json` | jq-based: every service has `imageTagKey`, every `workflows.symptoms.*.skill` points at an existing `skills/<name>/SKILL.md`, every `consumedBy` reference resolves, `chartAppVersion` matches `Chart.yaml` at catalog-author time. |

No live-cluster integration tests in the automated suite. Manual runbook in `docs/MANUAL-TESTING.md` covering k3d cluster spin-up, chart install, end-to-end smoke of every skill.

## Versioning & Release

- `rwl-env/.claude-plugin/plugin.json` starts at `0.1.0`. Bump per the rwenv pattern; no auto-bump.
- Marketplace entry added alongside the existing `rwenv` entry.
- Project CLAUDE.md gets a short rwl-env section so future agents know the plugin's safety invariants.

## Open Questions / Follow-ups

These were deliberately deferred from v0:

- **Application source for `embedder` and `webhooks`.** Six of the seven v0 priority services have source-repo pointers (see Reference Material). Embedder ships from the `shared-services` image whose repo path is not yet provided — if not provided before catalog authoring starts, embedder ships with deployment-graph fields only in v0.
- **`/rwl-env-edit` / `/rwl-env-remove`.** Manual `envs.json` edit suffices for v0.
- **`/rwl-env-refresh-catalog`.** Hand-maintained in v0.
- **`gh issue create` integration for bug reports.** Local markdown only in v0.
- **redis / neo4j / qdrant data-plane introspection.** v0 ships Postgres-only db-ops; add a dedicated agent if real debug sessions surface the need.
- **Subchart toggle flow (`postgresql.deploy: true → false`).** `/rwl-set-values` refuses these without `--allow-subchart-toggle`; the actual data-migration story is out of v0 scope.
- **Read-only k3d topology constraints.** If a customer requests a "view but cannot port-forward / cannot exec" mode (stricter than the current `readOnly: true`), revisit in v0.x.

## Reference Material

### Helm chart (one-time read at catalog-authoring time)

- Chart root: `/Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/`
- `INSTALL-FRICTIONS.md` (~153 KB) inside that path is the primary source for `workflows-index.json` symptom entries.

### Application source repos (for `runtime` blocks on priority services)

| Image (per `values.yaml`) | Services it ships | Source repo |
|---|---|---|
| `backend-services` | papi, activities, alerts, alert-ingestor, alert-query, alert-worker, slackbot, sobrain, sobow-index, sobow-search, taskiq-scheduler, taskiq-worker | `/Users/rohitekbote/wd/code/github.com/project-468/468-platform/backend-services-v2` |
| `agent-farm` | agentfarm, migration-controller (runs `webapp/migration_controller.py` from the same image) | `/Users/rohitekbote/wd/code/github.com/runwhen/agentfarm` |
| `usearch` | usearch (indexer, query, worker, beat) | `/Users/rohitekbote/wd/code/github.com/runwhen/usearch` |
| `ui` | user-pages (Next.js frontend) | `/Users/rohitekbote/wd/code/github.com/project-468/468-platform/user-pages` |
| `runner-control` | runner-control, runner-metric-proxy | `/Users/rohitekbote/wd/code/github.com/runwhen/runwhen-runner` |
| `shared-services` | embedder | **Repo path TBD** — request at implementation start, otherwise embedder ships with deployment-graph fields only in v0 (no `runtime` block). |
| `litellm` (third-party, `ghcr.io/berriai/litellm`) | llm-gateway | Public docs only; no source read needed. Encode known proxy behaviors from `values.yaml` comments and INSTALL-FRICTIONS. |
| `runwhen-platform-mcp` (`ghcr.io/runwhen-contrib/runwhen-platform-mcp`) | mcp-server | Public GH repo (`runwhen-contrib/runwhen-platform-mcp`) — clone-and-read at authoring time if a `runtime` block is needed. Not v0 priority. |
| `cc-catalog-svc` (`ghcr.io/runwhen-contrib/cc-catalog-svc`) | cc-catalog-svc | Public GH repo (`runwhen-contrib/cc-catalog-svc`). Not v0 priority. |
| `webhooks-service` | webhooks | **Repo path TBD.** Not v0 priority. |

#### v0 priority-service coverage after this mapping

| Priority service | Source available | Notes |
|---|---|---|
| papi | ✓ `backend-services-v2` | Read REST handlers + service-call code paths |
| agentfarm | ✓ `agentfarm` | Read main runtime + `webapp/migration_controller.py` (the known-failure source) |
| migration-controller | ✓ `agentfarm` (same image, separate StatefulSet) | |
| taskiq-worker | ✓ `backend-services-v2` | Task definitions, queue names, result writes |
| sobow-search / sobrain | ✓ `backend-services-v2` | gRPC service contracts |
| embedder | ✗ awaiting `shared-services` repo path | v0 falls back to deployment-graph-only if source isn't provided in time |
| llm-gateway | N/A (third-party) | Encode from chart comments + INSTALL-FRICTIONS only |

### Existing `rwenv` plugin (code patterns to mirror)

`rwenv/lib/rwenv-utils.sh`, `rwenv/hooks/transform-commands.sh`, `rwenv/skills/rwenv-{set,add,cur,list}/SKILL.md`.
