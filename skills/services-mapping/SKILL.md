---
name: services-mapping
description: Map services to Kubernetes resources in this project
triggers:
  - /services-mapping
  - list services
  - show services
  - what namespace is
  - where is defined in flux
  - service mapping
  - find service
---

# Services Mapping

Look up service information including namespaces, Flux paths, and HelmRelease names from the static services catalog.

## Instructions

### For listing all services (`/services-mapping` or "list services")

1. **Read the catalog** from the plugin's `data/infra-catalog.json` file

2. **Display a formatted table:**

```
RunWhen Services Catalog:

  SERVICE     NAMESPACE       FLUX PATH                        HELM RELEASE
  papi        runwhen-local   clusters/rdebug/apps/papi/       papi
  frontend    runwhen-local   clusters/rdebug/apps/frontend/   frontend
  runner      runwhen-local   clusters/rdebug/apps/runner/     runner

Generated from cluster: rdebug-61
Last updated: 2026-01-24T10:30:00Z

Use /services-mapping regenerate to rebuild from current cluster state.
```

### For single service lookup ("what namespace is X in", "where is X defined")

1. **Read the catalog** from `data/infra-catalog.json`

2. **Search for the service** by name (case-insensitive partial match)

3. **Display detailed info:**

```
Service: papi
  Description:    Platform API - core backend service
  Namespace:      runwhen-local
  Flux Path:      clusters/rdebug/apps/papi/
  HelmRelease:    papi
  Kustomization:  apps-papi
```

4. **If not found**, suggest:
```
Service 'foo' not found in services catalog.

Available services: papi, frontend, runner

To discover dynamically, use: kubectl get deploy -A | grep foo
To rebuild catalog: /services-mapping regenerate
```

### For regeneration (`/services-mapping regenerate`)

Guide the user through regenerating the catalog:

1. **Verify rwenv is set** for current directory
2. **Query the cluster** for deployments and HelmReleases:
   ```bash
   kubectl get deployments -A -o json
   kubectl get helmreleases -A -o json
   kubectl get kustomizations -A -o json
   ```
3. **Clone/pull the Flux repo** (if configured in rwenv)
4. **Scan Flux repo** for HelmRelease/Kustomization YAML files
5. **Correlate** cluster data with Flux repo structure
6. **Write updated catalog** to `data/infra-catalog.json`
7. **Report** what was found and updated

## Data File Location

The services catalog is at: `<plugin-directory>/data/infra-catalog.json`

To find the plugin directory:
1. This skill file is located at `<plugin-directory>/skills/services-mapping.md`
2. Go up one level from `skills/` to get the plugin root
3. The catalog is at `data/infra-catalog.json` relative to plugin root

For programmatic access, check where this skill was loaded from and navigate accordingly.

## Error Handling

| Error | Response |
|-------|----------|
| Catalog file missing | "Services catalog not found. Run /services-mapping regenerate to create it." |
| Catalog JSON invalid | "Services catalog has invalid JSON. Check data/infra-catalog.json" |
| No services in catalog | "Services catalog is empty. Run /services-mapping regenerate to populate it." |
| rwenv not set (regeneration) | "No rwenv configured. Use /rwenv-set to select an environment before regenerating." |
| kubectl command fails | "Failed to query cluster. Check rwenv configuration and dev container status." |
| Flux repo not configured | "No fluxGitRepo configured for this rwenv. Add it to envs.json or skip Flux correlation." |
| Flux repo clone/pull fails | "Failed to access Flux repo. Check URL and credentials. Proceeding with cluster data only." |
| No write permission | "Cannot write to data/infra-catalog.json. Check file permissions." |
