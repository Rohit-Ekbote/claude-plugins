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
| Image tag location (for rollout) | `data/services.json` → `imageGroups` |
| Flux status ("why isn't X syncing") | `data/flux-resources.json` |
| Secrets ("where does X get credentials") | `data/secrets-map.json` |
| Config ("what value does X have") | `data/configmaps.json` |

Data files are located in this skill's `data/` directory.

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
      "description": "Platform API - core backend service",
      "imageGroup": "backend-services"
    }
  },
  "imageGroups": {
    "backend-services": {
      "file": "apps/backend-services/kustomization.yaml",
      "imageName": "backend-services",
      "type": "kustomize-images",
      "services": ["papi", "celery-worker", "..."]
    }
  },
  "metadata": {
    "generatedFrom": "infra-flux-nonprod-test",
    "generatedAt": "2026-02-02T10:00:00Z"
  }
}
```

### Image Groups (for rollout)

The `imageGroups` section maps image names to their location in the flux repo. This is used by the `/rollout` skill to update image tags without searching.

| Field | Description |
|-------|-------------|
| `file` | Path to kustomization.yaml with `images[]` section |
| `imageName` | The `name` field in `images[]` to match |
| `type` | Always `kustomize-images` for kustomize-based repos |
| `services` | List of services that share this image |

**Update command:**
```bash
yq -i '(.images[] | select(.name == "<imageName>")).newTag = "<tag>"' <file>
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