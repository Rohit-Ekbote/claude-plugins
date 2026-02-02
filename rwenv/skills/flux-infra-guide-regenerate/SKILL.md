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
