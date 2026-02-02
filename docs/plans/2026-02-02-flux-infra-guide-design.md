# Flux Infrastructure Guide Skill - Design Document

**Date:** 2026-02-02
**Status:** Draft
**Author:** Claude + Rohit

## Overview

A reference skill that provides Claude with a "mental map" of the Flux-managed infrastructure. Instead of exploring the Flux repo on every operation, Claude consults this pre-documented structure to quickly navigate debugging, deployments, and configuration tasks.

## Problem Statement

Currently, when debugging or performing operations:
1. Claude must explore the Flux repo to find service locations, namespaces, and paths
2. This exploration adds latency and token cost to every operation
3. Developers may miss issues (e.g., failed Helm upgrades) because Claude doesn't know the "check this first" patterns
4. Tribal knowledge about observability, dependencies, and common failures isn't captured

## Solution

A hybrid skill consisting of:
1. **Static documentation** (SKILL.md) - Patterns, workflows, observability queries, debugging guides
2. **Generated data files** (data/*.json) - Service mappings, Flux resources, secrets, ConfigMaps
3. **Regeneration skill** - Instructions to rebuild data files from the Flux repo

### File Structure

```
rwenv/skills/flux-infra-guide/
├── SKILL.md                    # Main skill - structure, context, how to use
└── data/
    ├── services.json           # Generated: service → namespace → deployment mappings
    ├── flux-resources.json     # Generated: Kustomizations, HelmReleases inventory
    ├── secrets-map.json        # Generated: secret names, Vault paths, mount points
    └── configmaps.json         # Generated: ConfigMap names, key variables

rwenv/skills/flux-infra-guide-regenerate/
└── SKILL.md                    # Instructions for regenerating the data files
```

### Loading Strategy

**Lazy loading** - Load each JSON file only when that type of information is needed:
- Service location questions → Read `data/services.json`
- Flux status questions → Read `data/flux-resources.json`
- Secrets/config questions → Read `data/secrets-map.json` and `data/configmaps.json`

---

## Skill Specification

### SKILL.md Structure

```yaml
---
name: flux-infra-guide
description: Infrastructure reference for debugging and operations in the Flux-managed environment
triggers:
  - infrastructure guide
  - where does X run
  - what namespace
  - how to debug
  - check logs
  - flux resources
---
```

### Section 1: Overview & Purpose

```markdown
# Flux Infrastructure Guide

Quick reference for navigating the RunWhen infrastructure managed by Flux CD.

## When to Use This Skill

- Debugging service issues (unhealthy pods, failed migrations)
- Finding where a service/config is defined
- Understanding how secrets and config flow into services
- Querying logs and metrics for a specific service
- Tracing Flux reconciliation failures

## Prerequisites

- rwenv must be set (`/rwenv-cur` to verify)
- For Flux CLI commands: dev container running
- For log queries: access to observability stack
```

### Section 2: Service Map

```markdown
## Service Map

Quick lookup for where services run.

### How to Use

For service location questions ("where does X run", "what namespace is Y"):
1. Read `data/services.json`
2. Find the service entry
3. Use namespace/deployment info for kubectl commands

### Data Format (services.json)

```json
{
  "services": {
    "papi": {
      "namespace": "backend-services",
      "deployment": "papi",
      "fluxPath": "apps/backend-services/",
      "helmRelease": null,
      "kustomization": "runwhen-backend-services",
      "description": "Platform API - core backend service"
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T10:00:00Z"
  }
}
```

### Common Namespaces

| Namespace | Purpose |
|-----------|---------|
| `backend-services` | Core platform services (PAPI, Celery, etc.) |
| `flux-system` | Flux controllers and sources |
| `linkerd` | Service mesh control plane |
| `loki` | Log aggregation |
| `vault` | Secrets management |
```

### Section 3: Flux Resources

```markdown
## Flux Resources

Inventory of Kustomizations and HelmReleases managed by Flux.

### How to Use

For Flux status questions ("why isn't X syncing", "what manages Y"):
1. Read `data/flux-resources.json`
2. Find the Kustomization or HelmRelease
3. Check status with `flux get kustomization <name>` or `flux get helmrelease <name>`

### Data Format (flux-resources.json)

```json
{
  "kustomizations": {
    "runwhen-backend-services": {
      "namespace": "flux-system",
      "path": "./apps/backend-services",
      "sourceRef": "flux-system",
      "dependsOn": ["infrastructure-vault", "infrastructure-linkerd"],
      "interval": "1m",
      "prune": true,
      "manages": ["papi", "celery-worker", "celery-beat", "activities", "alerts"]
    }
  },
  "helmReleases": {
    "loki": {
      "namespace": "loki",
      "chart": "loki",
      "chartSource": "grafana",
      "kustomization": "infrastructure-loki",
      "interval": "5m"
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T10:00:00Z"
  }
}
```

### Debugging Flux Failures

**Check order when something isn't deploying:**

1. GitRepository: `flux get source git flux-system -n flux-system`
2. Kustomization: `flux get kustomization <name> -n flux-system`
3. HelmRelease (if applicable): `flux get helmrelease <name> -n <namespace>`
4. Events: `kubectl get events -n flux-system --sort-by='.lastTimestamp'`

**Common failure patterns:**

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| Kustomization stuck "Reconciling" | Dependency not ready | Check `dependsOn` resources |
| HelmRelease "upgrade retries exhausted" | Helm hook failed (migration) | `kubectl logs job/<release>-<hook>` |
| "path not found" | Wrong path in Kustomization | Verify path exists in repo |
```

### Section 4: Secrets Map

```markdown
## Secrets Map

How secrets flow from Vault into services via CSI driver.

### How to Use

For secrets questions ("where does X get credentials", "why is secret missing"):
1. Read `data/secrets-map.json`
2. Find the service's secret configuration
3. Trace from Vault path → SecretProviderClass → Pod mount

### Data Format (secrets-map.json)

```json
{
  "secretProviderClasses": {
    "vault-papi": {
      "namespace": "backend-services",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [
        {
          "vaultPath": "shared/data/secrets",
          "vaultKey": "secrets.py",
          "k8sSecretName": "papi-secrets",
          "mountPath": "/secrets/secrets.py"
        }
      ],
      "usedBy": ["papi", "celery-worker", "celery-beat"]
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T10:00:00Z"
  }
}
```

### Secret Flow Diagram

```
Vault (source of truth)
    │
    ├── Path: shared/data/secrets
    │
    ▼
SecretProviderClass (vault-papi)
    │
    ├── vaultRole: shared_secrets
    ├── vaultMountPath: kubernetes-${cluster_name}
    │
    ▼
CSI Volume Mount (in Pod spec)
    │
    ├── mountPath: /secrets/
    │
    ▼
Pod reads secret file at /secrets/secrets.py
```

### Debugging Secrets

**Check order when secrets are missing:**

1. SecretProviderClass exists: `kubectl get secretproviderclass -n <namespace>`
2. Vault auth working: `kubectl logs -n vault vault-0 | grep auth`
3. CSI driver running: `kubectl get pods -n kube-system -l app=secrets-store-csi-driver`
4. Pod events: `kubectl describe pod <pod> -n <namespace>` (look for mount errors)

**Common failure patterns:**

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| "secret not found" on pod start | Vault role missing/wrong | Vault policy for `kubernetes-${cluster_name}` |
| Pod stuck in ContainerCreating | CSI driver timeout | CSI driver pods, Vault connectivity |
| Secret file empty | Vault path incorrect | `vault kv get shared/data/secrets` |
```

### Section 5: ConfigMaps

```markdown
## ConfigMaps

Environment variables and configuration injected into services.

### How to Use

For config questions ("what value does X have", "where is Y configured"):
1. Read `data/configmaps.json`
2. Find the ConfigMap and key
3. Trace variable substitution if `${variable}` syntax is used

### Data Format (configmaps.json)

```json
{
  "configMaps": {
    "papi-env-vars-cm": {
      "namespace": "backend-services",
      "generatedBy": "kustomization",
      "sourceFile": "apps/backend-services/kustomization.yaml",
      "keys": {
        "DEFAULT_GITLAB_GROUP": "${cluster_name}",
        "GIT_SERVICE_URL": "https://git.${subdomain}.${domain}",
        "CONTAINER_REGISTRY": "gcr.io/${project_id}",
        "PAPI_SERVICE_URL": "http://papi.backend-services.svc.cluster.local"
      },
      "usedBy": ["papi", "celery-worker"]
    },
    "cluster-vars": {
      "namespace": "flux-system",
      "generatedBy": "crossplane-sync",
      "sourceFile": "infrastructure/crossplane-clusters/cluster-vars/",
      "keys": {
        "cluster_name": "platform-cluster-01",
        "project_id": "runwhen-nonprod",
        "domain": "runwhen.com",
        "subdomain": "nonprod"
      },
      "usedBy": ["all kustomizations via postBuild.substituteFrom"]
    }
  },
  "variableSubstitution": {
    "mechanism": "Flux postBuild.substituteFrom",
    "sourceConfigMap": "cluster-vars",
    "namespace": "flux-system",
    "syntax": "${variable_name}"
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T10:00:00Z"
  }
}
```

### Variable Substitution Flow

```
cluster-vars ConfigMap (flux-system)
    │
    ├── cluster_name: platform-cluster-01
    ├── project_id: runwhen-nonprod
    │
    ▼
Kustomization spec.postBuild.substituteFrom
    │
    ▼
Apps reference ${cluster_name} → resolved to "platform-cluster-01"
```

### Debugging Config Issues

**Check order when config seems wrong:**

1. Check raw ConfigMap: `kubectl get cm <name> -n <namespace> -o yaml`
2. Check cluster-vars (source of substitution): `kubectl get cm cluster-vars -n flux-system -o yaml`
3. Check pod's actual env: `kubectl exec <pod> -n <namespace> -- env | grep <VAR>`
4. Check if Kustomization reconciled: `flux get kustomization <name>`

**Common failure patterns:**

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| `${variable}` literal in pod env | Kustomization didn't substitute | cluster-vars ConfigMap exists? |
| Old value still present | Pod not restarted after ConfigMap update | `kubectl rollout restart deployment/<name>` |
| Value different than expected | Wrong cluster-vars source | Check Crossplane sync status |
```

### Section 6: Observability

```markdown
## Observability

Two separate data paths: infrastructure observability (Ops/SRE) and application metrics (product feature).

### Stack Overview

| Use Case | Purpose | Components | Who Consumes |
|----------|---------|------------|--------------|
| **Infrastructure** | Monitor infra (CPU, memory, logs) | Mimir, Loki, Grafana (shared) | SRE/Ops team |
| **Application** | RunWhen platform features (alerting for end-users) | Cortex, Consul | End-users of RunWhen |

### Component Map

| Component | Purpose | Namespace | Storage |
|-----------|---------|-----------|---------|
| **Grafana Alloy** | Collection agent (metrics + logs) | `grafana-alloy` | N/A |
| **Mimir** | Infrastructure metrics storage | `mimir` | GCS: `${project_id}-mimir` |
| **Loki** | Infrastructure logs storage | `loki` | GCS: `${project_id}-loki` |
| **Cortex** | Application metrics storage | `cortex` | GCS: `${cortex_bucket_name}` |
| **Grafana** | Visualization (shared cluster) | `grafana` | Stateless |
| **OpenCost** | Cost analysis | `opencost` | N/A |

### Data Flow

```
INFRASTRUCTURE PATH                    APPLICATION PATH
──────────────────                    ────────────────
cAdvisor, kubelet, ServiceMonitors    Runner pods (:9090/metrics)
         │                                    │
         ▼                                    ▼
    Grafana Alloy ◄────────────────► Grafana Alloy
         │                                    │
         ├──► Mimir (metrics)                 ▼
         │                            cortex-tenant (adds tenant)
         └──► Loki (logs)                     │
                                              ▼
                                         Cortex
                                              │
              ┌───────────────────────────────┘
              ▼
    Grafana (shared cluster)
    grafana.shared.runwhen.com
    Queries via X-Scope-OrgID header
```

### Multi-Tenancy

Each project has isolated data via `X-Scope-OrgID` header:
- `runwhen-dev-panda`
- `runwhen-nonprod-test`
- etc.

Grafana datasources are configured per project with the appropriate tenant ID.

### Log Queries (LogQL)

**Via kubectl (quick):**
```bash
# Recent logs
kubectl logs -n backend-services -l app=papi --tail=100

# Follow logs
kubectl logs -n backend-services -l app=papi -f

# Previous container (after crash)
kubectl logs -n backend-services -l app=papi --previous
```

**Via Loki (historical):**
```logql
# All logs for papi
{namespace="backend-services", app="papi"}

# Error logs only
{namespace="backend-services", app="papi"} |= "ERROR"

# Filter pattern
{namespace="backend-services", app="papi"} |~ "connection refused|timeout"

# Count errors over time
count_over_time({namespace="backend-services", app="papi"} |= "ERROR" [5m])
```

**Access:** Grafana UI → Explore → Loki datasource

### Metrics Queries (PromQL)

**Via kubectl (quick):**
```bash
kubectl top pods -n backend-services
kubectl top nodes
```

**Via Mimir (infrastructure):**
```promql
# CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="backend-services", pod=~"papi.*"}[5m]))

# Memory usage
sum(container_memory_working_set_bytes{namespace="backend-services", pod=~"papi.*"})
```

**Access:** Grafana UI → Explore → Mimir datasource (select correct project)

### Application Alerting Flow

```
Alert Rules (GCS bucket)
         │
         ▼
   Cortex Ruler (evaluates rules)
         │
         ▼
   Cortex Alertmanager (groups, deduplicates)
         │
         ▼
   Alerts Service (alerts.backend-services.svc.cluster.local:8000)
         │
         ▼
   End-user notifications (Slack, Email, PagerDuty)
```

### Key Config Files

| File | What It Controls |
|------|------------------|
| `infrastructure/grafana-alloy/metrics-and-logs/config.alloy` | Scrape targets, log collection |
| `infrastructure/grafana-alloy/metrics-and-logs/helm.yaml` | Alloy RBAC, DaemonSet settings |
| `infrastructure/mimir/helm.yaml` | Metrics retention, GCS bucket |
| `infrastructure/loki/helm.yaml` | Log retention, GCS bucket |
| `infrastructure/cortex/helm-cortex.yaml` | App metrics, alerting config |
| `infrastructure/opencost/helm.yaml` | Cost model, pricing rates |
```

### Section 7: Dependencies

```markdown
## Dependencies

Service startup order and inter-service dependencies.

### Flux Dependency Chain

Kustomizations have explicit `dependsOn` declarations. Check these when something isn't deploying.

```
infrastructure-base
    │
    ├──► infrastructure-vault
    │        │
    │        └──► infrastructure-linkerd
    │                  │
    │                  └──► runwhen-backend-services
    │                             │
    │                             ├──► runwhen-corestate
    │                             ├──► runwhen-gitservice
    │                             └──► runwhen-llm-gateway
    │
    ├──► infrastructure-loki
    │
    ├──► infrastructure-mimir
    │
    └──► infrastructure-cortex
```

### Service Dependencies

| Service | Depends On | Failure Impact |
|---------|------------|----------------|
| **papi** | PostgreSQL, Redis, Vault, Neo4j | Core API unavailable |
| **celery-worker** | papi, Redis, PostgreSQL | Async tasks fail |
| **celery-beat** | Redis | Scheduled tasks stop |
| **gitservice** | GitLab, Vault | Git operations fail |
| **llm-gateway** | External LLM APIs | AI features unavailable |
| **corestate** | PostgreSQL | State management fails |
| **runner** | papi, cortex | Task execution fails |

### Infrastructure Dependencies

| Component | Depends On | Check Command |
|-----------|------------|---------------|
| **All apps** | Linkerd (mesh) | `linkerd check` |
| **All apps** | Vault (secrets) | `kubectl get pods -n vault` |
| **Secrets** | CSI driver | `kubectl get pods -n kube-system -l app=secrets-store-csi-driver` |
| **Ingress** | cert-manager | `kubectl get certificates -A` |
| **Metrics** | Alloy → Mimir | `kubectl logs -n grafana-alloy -l app.kubernetes.io/name=alloy` |
| **Logs** | Alloy → Loki | Same as above |

### Debugging Dependency Failures

**When a service won't start:**

1. Check Flux dependencies first:
   ```bash
   flux get kustomization <name> -n flux-system
   # Look at "dependsOn" and check those are Ready
   ```

2. Check infrastructure components:
   ```bash
   # Vault
   kubectl get pods -n vault

   # Linkerd
   linkerd check

   # CSI driver
   kubectl get pods -n kube-system -l app=secrets-store-csi-driver
   ```

3. Check the service's own dependencies:
   ```bash
   # Database connectivity
   kubectl exec -n backend-services deploy/papi -- nc -zv postgres-primary.postgres.svc 5432

   # Redis connectivity
   kubectl exec -n backend-services deploy/papi -- nc -zv redis-master.redis.svc 6379
   ```

### Common Dependency Issues

| Symptom | Likely Cause | Resolution |
|---------|--------------|------------|
| Pod stuck in Init | Vault/secrets not ready | Check Vault pods, CSI driver |
| Connection refused to DB | PostgreSQL not ready | Check postgres namespace pods |
| Kustomization waiting | Dependency Kustomization failed | Fix upstream Kustomization first |
| Linkerd inject failed | Linkerd not installed | Check infrastructure-linkerd Kustomization |
| Certificate not ready | cert-manager issue | `kubectl describe certificate <name>` |
```

---

## Regeneration Skill Specification

### flux-infra-guide-regenerate/SKILL.md

```yaml
---
name: flux-infra-guide-regenerate
description: Regenerate infrastructure data files from Flux repo
triggers:
  - /flux-infra-guide-regenerate
  - regenerate infra guide
  - update infra catalog
---
```

### Regeneration Process

1. **Verify prerequisites**
   - rwenv is set
   - Flux repo is accessible at `~/.claude/rwenv/flux-repos/<rwenv-name>/`

2. **Generate services.json**
   - Scan `apps/` directory for deployments
   - Extract namespace from kustomization.yaml
   - Map service name → namespace → deployment

3. **Generate flux-resources.json**
   - Scan `clusters/<cluster-type>/` for Kustomization YAMLs
   - Extract dependsOn, path, interval, prune settings
   - Scan for HelmRelease resources

4. **Generate secrets-map.json**
   - Find all SecretProviderClass resources
   - Extract Vault paths, mount points, roles
   - Map which services use each secret class

5. **Generate configmaps.json**
   - Find configMapGenerator entries in kustomization.yaml files
   - Extract key-value pairs
   - Note variable substitution patterns

6. **Write files**
   - Output to `flux-infra-guide/data/` directory
   - Include metadata (source repo, timestamp)

---

## Implementation Plan

### Phase 1: Create Skill Structure
1. Create `rwenv/skills/flux-infra-guide/` directory
2. Create `rwenv/skills/flux-infra-guide/data/` directory
3. Write `SKILL.md` with all sections

### Phase 2: Generate Initial Data Files
1. Explore `infra-flux-nonprod-test` repo
2. Generate `services.json` from apps/ directory
3. Generate `flux-resources.json` from clusters/ directory
4. Generate `secrets-map.json` from SecretProviderClass resources
5. Generate `configmaps.json` from kustomization.yaml files

### Phase 3: Create Regeneration Skill
1. Create `rwenv/skills/flux-infra-guide-regenerate/` directory
2. Write `SKILL.md` with regeneration instructions

### Phase 4: Testing
1. Test skill triggers
2. Verify lazy loading works correctly
3. Test debugging workflows with the new skill

---

## Success Criteria

1. Claude can answer "where does papi run?" without exploring the Flux repo
2. Claude can trace secret flow from Vault to pod without manual exploration
3. Claude checks Helm upgrade status before debugging config issues
4. Regeneration skill can update data files when Flux repo changes

---

## Open Questions

1. **Scope:** Should this skill cover multiple Flux repos (nonprod-test, dev-panda) or one at a time?
2. **Staleness:** How often should data files be regenerated? On-demand only, or periodic?
3. **Validation:** Should the skill validate that data files match current cluster state?

---

## References

- Flux repo: `/Users/rohitekbote/wd/code/github.com/runwhen/infra-flux-nonprod-test`
- Observability architecture: `/Users/rohitekbote/wd/code/github.com/runwhen/infra-flux-dev-panda/docs/plans/2026-01-31-observability-stack-architecture.md`
- Existing skills: `rwenv/skills/rollout/`, `rwenv/skills/services-mapping/`, `rwenv/agents/flux-ops.md`
