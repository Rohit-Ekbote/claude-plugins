# Flux Infrastructure Guide Skill - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a reference skill that provides Claude with pre-documented infrastructure knowledge for faster debugging and operations.

**Architecture:** Two skills - a main reference skill (flux-infra-guide) with static docs and generated JSON data files, plus a regeneration skill (flux-infra-guide-regenerate) for updating data from the Flux repo.

**Tech Stack:** Markdown (SKILL.md), JSON (data files), Bash (for scanning Flux repo during regeneration)

---

## Task 1: Create Skill Directory Structure

**Files:**
- Create: `rwenv/skills/flux-infra-guide/SKILL.md`
- Create: `rwenv/skills/flux-infra-guide/data/.gitkeep`
- Create: `rwenv/skills/flux-infra-guide-regenerate/SKILL.md`

**Step 1: Create directories**

```bash
mkdir -p rwenv/skills/flux-infra-guide/data
mkdir -p rwenv/skills/flux-infra-guide-regenerate
```

**Step 2: Create .gitkeep for data directory**

```bash
touch rwenv/skills/flux-infra-guide/data/.gitkeep
```

**Step 3: Commit structure**

```bash
git add rwenv/skills/flux-infra-guide rwenv/skills/flux-infra-guide-regenerate
git commit -m "feat(rwenv): add flux-infra-guide skill directories"
```

---

## Task 2: Write Main Skill Header and Overview

**Files:**
- Create: `rwenv/skills/flux-infra-guide/SKILL.md`

**Step 1: Write the skill file with frontmatter and overview**

Write to `rwenv/skills/flux-infra-guide/SKILL.md`:

```markdown
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
  - service unhealthy
  - pod failing
---

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

## Loading Data Files

This skill uses lazy loading. Read data files only when needed:

| Question Type | Data File |
|---------------|-----------|
| Service location ("where does X run") | `data/services.json` |
| Flux status ("why isn't X syncing") | `data/flux-resources.json` |
| Secrets ("where does X get credentials") | `data/secrets-map.json` |
| Config ("what value does X have") | `data/configmaps.json` |

Data files are located in this skill's `data/` directory.
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/SKILL.md
git commit -m "feat(rwenv): add flux-infra-guide skill header and overview"
```

---

## Task 3: Add Service Map Section

**Files:**
- Modify: `rwenv/skills/flux-infra-guide/SKILL.md`

**Step 1: Append Service Map section**

Append to `rwenv/skills/flux-infra-guide/SKILL.md`:

```markdown

---

## Service Map

Quick lookup for where services run.

### How to Use

For service location questions ("where does X run", "what namespace is Y"):
1. Read `data/services.json` from this skill's directory
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
| `mimir` | Metrics storage |
| `vault` | Secrets management |
| `cortex` | Application metrics |
| `llm-gateway` | LLM proxy services |
| `runner-system` | Runner infrastructure |
| `corestate` | State management |
| `gitservice` | Git integration |
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/SKILL.md
git commit -m "feat(rwenv): add service map section to flux-infra-guide"
```

---

## Task 4: Add Flux Resources Section

**Files:**
- Modify: `rwenv/skills/flux-infra-guide/SKILL.md`

**Step 1: Append Flux Resources section**

Append to `rwenv/skills/flux-infra-guide/SKILL.md`:

```markdown

---

## Flux Resources

Inventory of Kustomizations and HelmReleases managed by Flux.

### How to Use

For Flux status questions ("why isn't X syncing", "what manages Y"):
1. Read `data/flux-resources.json` from this skill's directory
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
      "dependsOn": [],
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

**IMPORTANT: Check Flux status FIRST before debugging config issues.**

Many "config not applied" issues are actually failed HelmRelease upgrades or Kustomization reconciliation errors.

**Check order when something isn't deploying:**

1. GitRepository: `flux get source git flux-system -n flux-system`
2. Kustomization: `flux get kustomization <name> -n flux-system`
3. HelmRelease (if applicable): `flux get helmrelease <name> -n <namespace>`
4. Events: `kubectl get events -n flux-system --sort-by='.lastTimestamp'`

**Common failure patterns:**

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| Kustomization stuck "Reconciling" | Dependency not ready | Check `dependsOn` resources first |
| HelmRelease "upgrade retries exhausted" | Helm hook failed (migration) | `kubectl logs job/<release>-<hook> -n <namespace>` |
| "path not found" | Wrong path in Kustomization | Verify path exists in Flux repo |
| Config not updating | HelmRelease failed silently | `flux get helmrelease -A` to check all statuses |
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/SKILL.md
git commit -m "feat(rwenv): add flux resources section to flux-infra-guide"
```

---

## Task 5: Add Secrets Map Section

**Files:**
- Modify: `rwenv/skills/flux-infra-guide/SKILL.md`

**Step 1: Append Secrets Map section**

Append to `rwenv/skills/flux-infra-guide/SKILL.md`:

```markdown

---

## Secrets Map

How secrets flow from Vault into services via CSI driver.

### How to Use

For secrets questions ("where does X get credentials", "why is secret missing"):
1. Read `data/secrets-map.json` from this skill's directory
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

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/SKILL.md
git commit -m "feat(rwenv): add secrets map section to flux-infra-guide"
```

---

## Task 6: Add ConfigMaps Section

**Files:**
- Modify: `rwenv/skills/flux-infra-guide/SKILL.md`

**Step 1: Append ConfigMaps section**

Append to `rwenv/skills/flux-infra-guide/SKILL.md`:

```markdown

---

## ConfigMaps

Environment variables and configuration injected into services.

### How to Use

For config questions ("what value does X have", "where is Y configured"):
1. Read `data/configmaps.json` from this skill's directory
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

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/SKILL.md
git commit -m "feat(rwenv): add configmaps section to flux-infra-guide"
```

---

## Task 7: Add Observability Section

**Files:**
- Modify: `rwenv/skills/flux-infra-guide/SKILL.md`

**Step 1: Append Observability section**

Append to `rwenv/skills/flux-infra-guide/SKILL.md`:

```markdown

---

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

### Key Config Files (in Flux repo)

| File | What It Controls |
|------|------------------|
| `infrastructure/grafana-alloy/metrics-and-logs/config.alloy` | Scrape targets, log collection |
| `infrastructure/grafana-alloy/metrics-and-logs/helm.yaml` | Alloy RBAC, DaemonSet settings |
| `infrastructure/mimir/helm.yaml` | Metrics retention, GCS bucket |
| `infrastructure/loki/helm.yaml` | Log retention, GCS bucket |
| `infrastructure/cortex/helm-cortex.yaml` | App metrics, alerting config |
| `infrastructure/opencost/helm.yaml` | Cost model, pricing rates |
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/SKILL.md
git commit -m "feat(rwenv): add observability section to flux-infra-guide"
```

---

## Task 8: Add Dependencies Section

**Files:**
- Modify: `rwenv/skills/flux-infra-guide/SKILL.md`

**Step 1: Append Dependencies section**

Append to `rwenv/skills/flux-infra-guide/SKILL.md`:

```markdown

---

## Dependencies

Service startup order and inter-service dependencies.

### Flux Dependency Chain

Kustomizations have explicit `dependsOn` declarations. Check these when something isn't deploying.

```
infrastructure (base)
    │
    ├──► vault
    │
    ├──► linkerd
    │
    ├──► loki
    │
    ├──► mimir
    │
    └──► cortex
         │
         └──► runwhen-backend-services
                   │
                   ├──► runwhen-corestate
                   ├──► runwhen-gitservice
                   ├──► runwhen-llm-gateway
                   └──► runwhen-runner-system
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

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/SKILL.md
git commit -m "feat(rwenv): add dependencies section to flux-infra-guide"
```

---

## Task 9: Generate services.json

**Files:**
- Create: `rwenv/skills/flux-infra-guide/data/services.json`

**Step 1: Scan Flux repo and create services.json**

Scan `apps/` directory in the Flux repo at `/Users/rohitekbote/wd/code/github.com/runwhen/infra-flux-nonprod-test/` and extract:
- Service names from deployment YAML files
- Namespace from kustomization.yaml
- Flux path

Write to `rwenv/skills/flux-infra-guide/data/services.json`:

```json
{
  "services": {
    "papi": {
      "namespace": "backend-services",
      "deployment": "papi",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Platform API - core backend service"
    },
    "activities": {
      "namespace": "backend-services",
      "deployment": "activities",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Activities service"
    },
    "alerts": {
      "namespace": "backend-services",
      "deployment": "alerts",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Alerts service for user notifications"
    },
    "modelsync": {
      "namespace": "backend-services",
      "deployment": "modelsync",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Model synchronization service"
    },
    "agentfarm": {
      "namespace": "backend-services",
      "deployment": "agentfarm",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Agent farm for AI agents"
    },
    "celery-worker": {
      "namespace": "backend-services",
      "deployment": "celery-worker",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Celery async task workers"
    },
    "celery-beat": {
      "namespace": "backend-services",
      "deployment": "beat",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Celery beat scheduler"
    },
    "flower": {
      "namespace": "backend-services",
      "deployment": "flower",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Celery monitoring UI"
    },
    "embedder": {
      "namespace": "backend-services",
      "deployment": "embedder",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Text embedding service"
    },
    "slackbot": {
      "namespace": "backend-services",
      "deployment": "slackbot",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Slack integration bot"
    },
    "sobow-index": {
      "namespace": "backend-services",
      "deployment": "sobow-index",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "SOBOW indexing service"
    },
    "sobow-search": {
      "namespace": "backend-services",
      "deployment": "sobow-search",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "SOBOW search service"
    },
    "usearch-indexer": {
      "namespace": "backend-services",
      "deployment": "usearch-indexer",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "USearch indexer"
    },
    "usearch-query": {
      "namespace": "backend-services",
      "deployment": "usearch-query",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "USearch query service"
    },
    "usearch-worker": {
      "namespace": "backend-services",
      "deployment": "usearch-worker",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "USearch background workers"
    },
    "usearch-beat": {
      "namespace": "backend-services",
      "deployment": "usearch-beat",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "USearch beat scheduler"
    },
    "sobrain": {
      "namespace": "backend-services",
      "deployment": "sobrain",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "SOBrain AI service"
    },
    "webhooks": {
      "namespace": "backend-services",
      "deployment": "webhooks",
      "fluxPath": "apps/backend-services/",
      "kustomization": "runwhen-backend-services",
      "description": "Webhook handler service"
    },
    "corestate": {
      "namespace": "corestate",
      "deployment": "corestate",
      "fluxPath": "apps/corestate/",
      "kustomization": "runwhen-corestate",
      "description": "State management service"
    },
    "gitservice": {
      "namespace": "gitservice",
      "deployment": "gitservice",
      "fluxPath": "apps/gitservice/",
      "kustomization": "runwhen-gitservice",
      "description": "Git integration service"
    },
    "litellm-proxy": {
      "namespace": "llm-gateway",
      "deployment": "litellm-proxy",
      "fluxPath": "apps/llm-gateway/",
      "kustomization": "runwhen-llm-gateway",
      "description": "LiteLLM proxy for LLM routing"
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T00:00:00Z",
    "fluxRepoPath": "/Users/rohitekbote/wd/code/github.com/runwhen/infra-flux-nonprod-test"
  }
}
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/data/services.json
git commit -m "feat(rwenv): generate services.json for flux-infra-guide"
```

---

## Task 10: Generate flux-resources.json

**Files:**
- Create: `rwenv/skills/flux-infra-guide/data/flux-resources.json`

**Step 1: Scan clusters/platform-cluster/ and create flux-resources.json**

Scan Kustomization YAMLs in `clusters/platform-cluster/` directory.

Write to `rwenv/skills/flux-infra-guide/data/flux-resources.json`:

```json
{
  "kustomizations": {
    "infrastructure": {
      "namespace": "flux-system",
      "path": "./infrastructure",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "runwhen-backend-services": {
      "namespace": "flux-system",
      "path": "./apps/backend-services",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true,
      "substituteFrom": "cluster-vars"
    },
    "runwhen-corestate": {
      "namespace": "flux-system",
      "path": "./apps/corestate",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "runwhen-gitservice": {
      "namespace": "flux-system",
      "path": "./apps/gitservice",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "runwhen-llm-gateway": {
      "namespace": "flux-system",
      "path": "./apps/llm-gateway",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "runwhen-runner-system": {
      "namespace": "flux-system",
      "path": "./apps/runner-system",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "loki": {
      "namespace": "flux-system",
      "path": "./infrastructure/loki",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "mimir": {
      "namespace": "flux-system",
      "path": "./infrastructure/mimir",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "cortex": {
      "namespace": "flux-system",
      "path": "./infrastructure/cortex",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "vault": {
      "namespace": "flux-system",
      "path": "./infrastructure/vault",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "linkerd": {
      "namespace": "flux-system",
      "path": "./infrastructure/linkerd",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    },
    "grafana-alloy": {
      "namespace": "flux-system",
      "path": "./infrastructure/grafana-alloy",
      "sourceRef": "flux-system",
      "dependsOn": [],
      "interval": "1m",
      "prune": true
    }
  },
  "helmReleases": {
    "loki": {
      "namespace": "loki",
      "chart": "loki",
      "chartSource": "grafana",
      "interval": "5m"
    },
    "mimir": {
      "namespace": "mimir",
      "chart": "mimir-distributed",
      "chartSource": "grafana",
      "interval": "5m"
    },
    "redis-sentinel": {
      "namespace": "backend-services",
      "chart": "redis",
      "chartSource": "bitnami",
      "interval": "5m"
    },
    "neo4j": {
      "namespace": "backend-services",
      "chart": "neo4j",
      "chartSource": "neo4j",
      "interval": "5m"
    },
    "qdrant": {
      "namespace": "backend-services",
      "chart": "qdrant",
      "chartSource": "qdrant",
      "interval": "5m"
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T00:00:00Z"
  }
}
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/data/flux-resources.json
git commit -m "feat(rwenv): generate flux-resources.json for flux-infra-guide"
```

---

## Task 11: Generate secrets-map.json

**Files:**
- Create: `rwenv/skills/flux-infra-guide/data/secrets-map.json`

**Step 1: Scan CSI secret class files and create secrets-map.json**

Scan `*-csi-secret-class.yaml` files in the Flux repo.

Write to `rwenv/skills/flux-infra-guide/data/secrets-map.json`:

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
          "objectName": "secrets.py",
          "vaultPath": "shared/data/secrets",
          "vaultKey": "secrets.py"
        },
        {
          "objectName": "gitlab_oauth_app_client_id",
          "vaultPath": "shared/data/gitlab_oauth",
          "vaultKey": "SOCIAL_ACCOUNT_PROVIDERS_GITLAB_APP_CLIENT_ID"
        },
        {
          "objectName": "gitlab_oauth_app_client_secret",
          "vaultPath": "shared/data/gitlab_oauth",
          "vaultKey": "SOCIAL_ACCOUNT_PROVIDERS_GITLAB_APP_CLIENT_SECRET"
        },
        {
          "objectName": "rw_shared_llm_vkey",
          "vaultPath": "shared/data/litellm-proxy/virtual-keys",
          "vaultKey": "RW_SHARED_LLM"
        }
      ],
      "k8sSecretName": "papi-secrets",
      "usedBy": ["papi", "celery-worker", "celery-beat", "activities", "alerts", "modelsync"]
    },
    "vault-slackbot": {
      "namespace": "backend-services",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [],
      "usedBy": ["slackbot"]
    },
    "vault-corestate": {
      "namespace": "corestate",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [],
      "usedBy": ["corestate"]
    },
    "vault-gitservice": {
      "namespace": "gitservice",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [],
      "usedBy": ["gitservice"]
    },
    "vault-litellm-proxy": {
      "namespace": "llm-gateway",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [],
      "usedBy": ["litellm-proxy"]
    },
    "vault-location": {
      "namespace": "locations",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [],
      "usedBy": ["location-services"]
    },
    "vault-linkerd-multicluster": {
      "namespace": "linkerd-multicluster",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [],
      "usedBy": ["linkerd-multicluster"]
    },
    "vault-grafana": {
      "namespace": "cortex",
      "provider": "vault",
      "vaultRole": "shared_secrets",
      "vaultMountPath": "kubernetes-${cluster_name}",
      "secrets": [],
      "usedBy": ["grafana"]
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T00:00:00Z"
  }
}
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/data/secrets-map.json
git commit -m "feat(rwenv): generate secrets-map.json for flux-infra-guide"
```

---

## Task 12: Generate configmaps.json

**Files:**
- Create: `rwenv/skills/flux-infra-guide/data/configmaps.json`

**Step 1: Scan kustomization.yaml files for configMapGenerator and create configmaps.json**

Write to `rwenv/skills/flux-infra-guide/data/configmaps.json`:

```json
{
  "configMaps": {
    "cluster-vars": {
      "namespace": "flux-system",
      "generatedBy": "crossplane-sync",
      "sourceFile": "infrastructure/crossplane-clusters/cluster-vars/",
      "description": "Cluster-wide variables for Flux substitution",
      "keys": {
        "cluster_name": "Variable: cluster name (e.g., platform-cluster-01)",
        "project_id": "Variable: GCP project ID",
        "domain": "Variable: base domain",
        "subdomain": "Variable: subdomain prefix",
        "vault_address": "Variable: Vault URL",
        "artifact_registry_path": "Variable: Container registry path"
      },
      "usedBy": "All Kustomizations via postBuild.substituteFrom"
    }
  },
  "variableSubstitution": {
    "mechanism": "Flux postBuild.substituteFrom",
    "sourceConfigMap": "cluster-vars",
    "namespace": "flux-system",
    "syntax": "${variable_name}",
    "commonVariables": {
      "${cluster_name}": "Cluster identifier",
      "${project_id}": "GCP project ID",
      "${domain}": "Base domain (e.g., runwhen.com)",
      "${subdomain}": "Subdomain prefix (e.g., nonprod)",
      "${vault_address}": "Vault server URL",
      "${artifact_registry_path}": "Path to container registry"
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T00:00:00Z"
  }
}
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide/data/configmaps.json
git commit -m "feat(rwenv): generate configmaps.json for flux-infra-guide"
```

---

## Task 13: Create Regeneration Skill

**Files:**
- Create: `rwenv/skills/flux-infra-guide-regenerate/SKILL.md`

**Step 1: Write the regeneration skill**

Write to `rwenv/skills/flux-infra-guide-regenerate/SKILL.md`:

```markdown
---
name: flux-infra-guide-regenerate
description: Regenerate infrastructure data files from Flux repo
triggers:
  - /flux-infra-guide-regenerate
  - regenerate infra guide
  - update infra catalog
  - refresh flux data
---

# Regenerate Flux Infrastructure Guide Data

Update the data files in flux-infra-guide skill from the current Flux repo.

## Prerequisites

1. **rwenv must be set** - Run `/rwenv-cur` to verify
2. **Flux repo must be accessible** at `~/.claude/rwenv/flux-repos/<rwenv-name>/`

## Regeneration Process

### Step 1: Verify Flux Repo

```bash
FLUX_REPO="${RWENV_CONFIG_DIR:-~/.claude/rwenv}/flux-repos/<rwenv-name>/"
ls -la "$FLUX_REPO"
```

If not present, clone it:
```bash
git clone <fluxGitRepo from envs.json> "$FLUX_REPO"
```

### Step 2: Generate services.json

Scan the `apps/` directory:

1. For each subdirectory in `apps/`:
   - Read `kustomization.yaml` for namespace
   - Find `*-deployment.yaml` files for service names
   - Extract service → namespace → deployment mappings

2. Write to `<plugin-dir>/skills/flux-infra-guide/data/services.json`

### Step 3: Generate flux-resources.json

Scan the `clusters/platform-cluster/` directory:

1. For each YAML file:
   - Parse Kustomization resources
   - Extract path, dependsOn, interval, prune settings

2. Scan for HelmRelease resources in `infrastructure/`

3. Write to `<plugin-dir>/skills/flux-infra-guide/data/flux-resources.json`

### Step 4: Generate secrets-map.json

Find all `*-csi-secret-class.yaml` files:

1. For each SecretProviderClass:
   - Extract namespace, provider, vaultRole
   - Extract vault paths and keys
   - Identify which services use it

2. Write to `<plugin-dir>/skills/flux-infra-guide/data/secrets-map.json`

### Step 5: Generate configmaps.json

Scan `kustomization.yaml` files for `configMapGenerator`:

1. Extract ConfigMap names and keys
2. Note variable substitution patterns

3. Write to `<plugin-dir>/skills/flux-infra-guide/data/configmaps.json`

### Step 6: Update Metadata

All JSON files should include:

```json
{
  "metadata": {
    "generatedFrom": "<flux-repo-name>",
    "generatedAt": "<ISO-8601-timestamp>",
    "fluxRepoPath": "<path-to-flux-repo>"
  }
}
```

## Output

After regeneration, report:

```
Regenerated flux-infra-guide data files:

  services.json:      21 services mapped
  flux-resources.json: 12 Kustomizations, 5 HelmReleases
  secrets-map.json:   8 SecretProviderClasses
  configmaps.json:    1 ConfigMaps, 6 variables

Source: infra-flux-nonprod-test
Generated at: 2026-02-02T10:00:00Z
```

## Error Handling

| Error | Response |
|-------|----------|
| rwenv not set | "No rwenv configured. Use /rwenv-set to select an environment." |
| Flux repo not found | "Flux repo not found. Clone it first or check fluxGitRepo in envs.json." |
| Permission denied | "Cannot write to data directory. Check file permissions." |
| Invalid YAML | "Failed to parse <file>: <error>. Check YAML syntax." |
```

**Step 2: Commit**

```bash
git add rwenv/skills/flux-infra-guide-regenerate/SKILL.md
git commit -m "feat(rwenv): add flux-infra-guide-regenerate skill"
```

---

## Task 14: Remove .gitkeep and Final Commit

**Files:**
- Delete: `rwenv/skills/flux-infra-guide/data/.gitkeep`

**Step 1: Remove .gitkeep (no longer needed with actual data files)**

```bash
rm rwenv/skills/flux-infra-guide/data/.gitkeep
git add -u rwenv/skills/flux-infra-guide/data/.gitkeep
```

**Step 2: Final verification**

```bash
ls -la rwenv/skills/flux-infra-guide/
ls -la rwenv/skills/flux-infra-guide/data/
ls -la rwenv/skills/flux-infra-guide-regenerate/
```

**Step 3: Commit**

```bash
git commit -m "chore(rwenv): remove .gitkeep from flux-infra-guide data"
```

---

## Task 15: Test Skill Loading

**Step 1: Verify skill structure**

Check that all files are in place:
- `rwenv/skills/flux-infra-guide/SKILL.md`
- `rwenv/skills/flux-infra-guide/data/services.json`
- `rwenv/skills/flux-infra-guide/data/flux-resources.json`
- `rwenv/skills/flux-infra-guide/data/secrets-map.json`
- `rwenv/skills/flux-infra-guide/data/configmaps.json`
- `rwenv/skills/flux-infra-guide-regenerate/SKILL.md`

**Step 2: Validate JSON files**

```bash
jq . rwenv/skills/flux-infra-guide/data/services.json > /dev/null && echo "services.json: valid"
jq . rwenv/skills/flux-infra-guide/data/flux-resources.json > /dev/null && echo "flux-resources.json: valid"
jq . rwenv/skills/flux-infra-guide/data/secrets-map.json > /dev/null && echo "secrets-map.json: valid"
jq . rwenv/skills/flux-infra-guide/data/configmaps.json > /dev/null && echo "configmaps.json: valid"
```

**Step 3: Report completion**

```
Flux Infrastructure Guide skill implementation complete.

Files created:
  - rwenv/skills/flux-infra-guide/SKILL.md (main reference skill)
  - rwenv/skills/flux-infra-guide/data/services.json (21 services)
  - rwenv/skills/flux-infra-guide/data/flux-resources.json (12 Kustomizations, 5 HelmReleases)
  - rwenv/skills/flux-infra-guide/data/secrets-map.json (8 SecretProviderClasses)
  - rwenv/skills/flux-infra-guide/data/configmaps.json (cluster-vars)
  - rwenv/skills/flux-infra-guide-regenerate/SKILL.md (regeneration skill)

To use:
  - Trigger with "where does papi run", "how to debug", "check logs", etc.
  - Data files are lazy-loaded when specific information is needed
  - Use /flux-infra-guide-regenerate to update data from Flux repo
```
