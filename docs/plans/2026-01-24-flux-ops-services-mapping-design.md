# Flux-Ops Subagent and Services-Mapping Skill Design

**Date:** 2026-01-24
**Status:** Draft
**Author:** Claude (with user collaboration)

## Overview

This document describes two new additions to the rwenv plugin:

1. **flux-ops subagent** - Dedicated subagent for Flux CD resource management and GitOps deployment workflows
2. **services-mapping skill** - Static service catalog with namespace and Flux path information

## Goals

- Provide comprehensive Flux CD resource inspection and GitOps workflow capabilities
- Enable quick service lookups (namespace, Flux repo path, HelmRelease names)
- Maintain consistency with existing rwenv safety model (read-only enforcement)
- Keep configuration lean by separating static knowledge into dedicated skill/data files

## Non-Goals

- Dynamic service discovery at runtime (ConfigMaps, Secrets discovered on-demand)
- Flux repo access from inside dev container (git operations stay on local machine)
- Additional wrapper scripts for git operations (use Claude's native git capabilities)

---

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User / Claude                            │
└─────────────────┬───────────────────────────┬───────────────┘
                  │                           │
                  ▼                           ▼
┌─────────────────────────────┐   ┌───────────────────────────┐
│   flux-ops subagent         │   │  services-mapping skill   │
│   - Flux resource status    │◄──│  - Service catalog        │
│   - GitOps workflows        │   │  - Namespace mappings     │
│   - Deployment lifecycle    │   │  - Flux paths             │
└──────────┬──────────────────┘   └───────────────────────────┘
           │                                   ▲
           │                                   │
           ▼                                   │
┌─────────────────────────────┐               │
│   k8s-ops subagent          │───────────────┘
│   (existing - references    │
│    services-mapping)        │
└─────────────────────────────┘
```

**Key principle:** Services-mapping provides context; subagents consume it for smarter operations.

---

## Services-Mapping Skill

### File Structure

```
rwenv-plugin/
├── skills/
│   └── services-mapping.md      # Skill logic and triggers
└── data/
    └── services-catalog.json    # Static service data
```

### Skill File (`services-mapping.md`)

**Triggers:**
- "list services"
- "show services"
- "what namespace is X in"
- "where is X defined in flux"
- `/services-mapping` (explicit invocation)

**Behavior:**
- Reads `services-catalog.json` from plugin's `data/` directory
- Presents relevant info based on query
- Table view for listing all services
- Detailed view for single service lookup

### Data File Structure (`services-catalog.json`)

```json
{
  "version": "1.0",
  "generatedFrom": {
    "cluster": "rdebug-61",
    "fluxRepo": "https://github.com/...",
    "generatedAt": "2026-01-24T..."
  },
  "services": {
    "papi": {
      "description": "Platform API service",
      "namespace": "runwhen-local",
      "fluxPath": "clusters/rdebug/apps/papi/",
      "helmRelease": "papi",
      "kustomization": "apps-papi"
    },
    "frontend": {
      "description": "Web frontend application",
      "namespace": "runwhen-local",
      "fluxPath": "clusters/rdebug/apps/frontend/",
      "helmRelease": "frontend",
      "kustomization": "apps-frontend"
    }
  }
}
```

### Usage Examples

```
User: /services-mapping
→ Shows table of all services with namespace and flux path

User: "what namespace is papi in?"
→ Skill auto-invoked, returns: "papi runs in namespace runwhen-local"

User: "where is frontend defined in flux?"
→ Returns: "clusters/rdebug/apps/frontend/ (HelmRelease: frontend)"
```

---

## Flux-Ops Subagent

### File

`subagents/flux-ops.md`

### Capability Areas

#### A. Flux Resource Operations (via dev container)

| Operation | Command Pattern | Read-Only Safe |
|-----------|-----------------|----------------|
| List GitRepositories | `flux get sources git` | Yes |
| List Kustomizations | `flux get kustomizations` | Yes |
| List HelmReleases | `flux get helmreleases` | Yes |
| Check reconciliation status | `flux get all` | Yes |
| Inspect source details | `flux get source git <name> -o yaml` | Yes |
| View Flux events | `kubectl get events -n flux-system` | Yes |
| Trigger reconciliation | `flux reconcile kustomization <name>` | No |
| Suspend resource | `flux suspend <type> <name>` | No |
| Resume resource | `flux resume <type> <name>` | No |

#### B. GitOps Workflow Operations (via local machine)

| Operation | Method | Read-Only Safe |
|-----------|--------|----------------|
| Clone/pull Flux repo | Native git | Yes |
| Browse manifests | Read files | Yes |
| View git history | Native git | Yes |
| Create branch | Native git | No |
| Modify manifests | Edit files | No |
| Commit changes | Native git | No |
| Push to remote | Native git | No |
| Create PR | gh CLI | No |

**Safety enforcement:** All "No" operations blocked when rwenv `readOnly: true`

### Flux Repo Management

#### Location

```
~/.claude/rwenv/flux-repos/
├── dev/                    # Cloned repo for 'dev' rwenv
│   └── <flux-repo-clone>/
├── staging/                # Cloned repo for 'staging' rwenv
│   └── <flux-repo-clone>/
└── prod/                   # Cloned repo for 'prod' rwenv
    └── <flux-repo-clone>/
```

#### Behavior

| Scenario | Action |
|----------|--------|
| First access | Clone from `fluxGitRepo` in rwenv config |
| Subsequent access | `git fetch && git pull` to update |
| Missing `fluxGitRepo` config | Error with instructions to add it |
| Dirty working tree | Warn user, ask before proceeding |

### Deployment Workflow

#### When Not Read-Only

```
1. Pull latest from Flux repo
2. Create feature branch (e.g., deploy/<service>-<timestamp>)
3. Modify manifests (image tag, config values, etc.)
4. Commit with descriptive message
5. Push branch to remote
6. Create PR (using gh CLI)
7. [Optional] If direct push allowed: merge and trigger reconciliation
8. Monitor: flux get kustomization <name> --watch
```

#### When Read-Only

```
1. Pull latest from Flux repo (allowed)
2. Browse/read manifests (allowed)
3. Check Flux resource status (allowed)
4. Any write operation → blocked with message:
   "rwenv '<name>' is read-only. Cannot modify Flux repo or trigger reconciliation."
```

---

## Integration Between Components

### Subagent Service Lookup Flow

**k8s-ops example:**
```
User: "check if papi deployment is healthy"
         │
         ▼
k8s-ops subagent triggered
  1. Reads services-catalog.json
  2. Finds: papi → namespace: runwhen-local
  3. Runs: kubectl get deploy papi -n runwhen-local
```

**flux-ops example:**
```
User: "update papi to image tag v2.3.0"
         │
         ▼
flux-ops subagent triggered
  1. Checks rwenv read-only status → not read-only, proceed
  2. Reads services-catalog.json
  3. Finds: papi → fluxPath: clusters/rdebug/apps/papi/
  4. Pulls Flux repo, creates branch
  5. Edits clusters/rdebug/apps/papi/values.yaml
  6. Commits, pushes, creates PR
  7. Reports PR URL to user
```

### Subagent Prerequisites

Both k8s-ops and flux-ops subagents include:

```markdown
## Prerequisites
1. Verify rwenv is set for current directory
2. Load services-catalog.json for service context
3. [flux-ops only] Ensure Flux repo is cloned/updated
4. [k8s-ops only] Check dev container is running
```

### Fallback When Service Not in Catalog

- Warn: "Service 'foo' not found in services catalog"
- Ask user for namespace/path, or
- Attempt discovery via `kubectl get deploy -A | grep foo`

---

## Data Bootstrapping Process

During implementation, generate `services-catalog.json` by querying the actual cluster and Flux repo.

### Step 1: Query Cluster

```bash
# Via dev container
kubectl get deployments -A -o json
kubectl get services -A -o json
kubectl get helmreleases -A -o json
kubectl get kustomizations -A -o json
```

**Extracts:** service names, namespaces, HelmRelease names, Kustomization names

### Step 2: Clone and Scan Flux Repo

```bash
# On local machine
git clone <fluxGitRepo> ~/.claude/rwenv/flux-repos/<rwenv>/
```

**Scan for:**
- Directory structure under `clusters/` or `apps/`
- HelmRelease YAML files → map to service names
- Kustomization YAML files → map to paths

### Step 3: Correlate and Merge

| Source | Provides |
|--------|----------|
| Cluster | Actual namespaces, running services |
| Flux repo | Directory paths, manifest locations |
| Correlation | Match by HelmRelease name or app label |

### Step 4: Generate Catalog

- Write `services-catalog.json` to `data/` directory
- Include metadata about source cluster and generation time
- User reviews and commits to plugin

### Regeneration

User can run `/services-mapping regenerate` to rebuild from current cluster state.

---

## Implementation Plan

### New Files

| File | Purpose |
|------|---------|
| `subagents/flux-ops.md` | Flux resource management and GitOps workflow subagent |
| `skills/services-mapping.md` | Service catalog lookup skill |
| `data/services-catalog.json` | Static service data (bootstrapped from cluster) |

### Modified Files

| File | Change |
|------|--------|
| `subagents/k8s-ops.md` | Add prerequisite to load services-catalog for context |
| `manifest.json` | Add `data/` directory reference if needed |
| `lib/rwenv-utils.sh` | Add helper functions for Flux repo path management |

### Final Directory Structure

```
rwenv-plugin/
├── manifest.json
├── skills/
│   ├── rwenv-list.md
│   ├── rwenv-set.md
│   ├── rwenv-cur.md
│   ├── rwenv-add.md
│   └── services-mapping.md      # NEW
├── subagents/
│   ├── k8s-ops.md               # MODIFIED
│   ├── db-ops.md
│   ├── gcloud-ops.md
│   └── flux-ops.md              # NEW
├── data/
│   └── services-catalog.json    # NEW (bootstrapped)
├── hooks/
│   ├── pre-command.sh
│   └── validate-git.sh
├── scripts/
│   ├── pg_query.sh
│   └── command-builder.sh
└── lib/
    └── rwenv-utils.sh           # MODIFIED
```

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Flux repo on local machine, not dev container | Faster git operations, no container dependency for repo access |
| Services data in separate JSON file | Clean separation of data from skill logic, easier to regenerate |
| Follow rwenv read-only for Flux git writes | Consistent safety model across all operations |
| Use Claude's native git capabilities | Simple, no additional scripts needed |
| Persistent Flux repo cache | Avoid re-cloning, faster subsequent access |
| Services-mapping auto-invoked by subagents | Smarter context without user needing to specify namespaces |

---

## Open Questions

None at this time. All design decisions have been validated.

---

## Appendix: Example Services Catalog

```json
{
  "version": "1.0",
  "generatedFrom": {
    "cluster": "rdebug-61",
    "fluxRepo": "https://github.com/runwhen/flux-config",
    "generatedAt": "2026-01-24T10:30:00Z"
  },
  "services": {
    "papi": {
      "description": "Platform API - core backend service",
      "namespace": "runwhen-local",
      "fluxPath": "clusters/rdebug/apps/papi/",
      "helmRelease": "papi",
      "kustomization": "apps-papi"
    },
    "frontend": {
      "description": "Web frontend application",
      "namespace": "runwhen-local",
      "fluxPath": "clusters/rdebug/apps/frontend/",
      "helmRelease": "frontend",
      "kustomization": "apps-frontend"
    },
    "runner": {
      "description": "Task runner service",
      "namespace": "runwhen-local",
      "fluxPath": "clusters/rdebug/apps/runner/",
      "helmRelease": "runner",
      "kustomization": "apps-runner"
    }
  }
}
```
