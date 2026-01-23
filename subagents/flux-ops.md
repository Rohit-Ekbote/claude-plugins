---
name: flux-ops
description: Flux CD operations for GitOps workflows, resource inspection, and deployment management
triggers:
  - flux operations
  - gitops operations
  - flux status
  - helmrelease status
  - kustomization status
  - update deployment
  - deploy service
  - check flux
  - reconcile flux
  - flux repo
---

# Flux CD Operations Subagent

Handle Flux CD resource inspection and GitOps deployment workflows. Flux CLI commands run through the dev container; git operations for the Flux repo run on the local machine.

## Prerequisites

Before executing any operations:

1. **Verify rwenv is set** for current directory
   - If not set, inform user and suggest `/rwenv-set`

2. **Load rwenv configuration** from `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json`
   - Get `kubernetesContext`, `kubeconfigPath`, `readOnly`, `fluxGitRepo` settings

3. **Load services catalog** from plugin's `data/services-catalog.json`
   - Use for service → namespace/path lookups
   - If catalog missing, warn but continue (can still operate without it)

4. **For Flux CLI commands**: Check dev container is running
   - Container name from `devContainer` field in envs.json

5. **For git operations**: Ensure Flux repo is available
   - Location: `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/flux-repos/<rwenv-name>/`
   - Clone if not present, pull if exists

## Command Execution Patterns

### Flux CLI Commands (via dev container)

```bash
docker exec -it <devContainer> flux \
  --kubeconfig=<kubeconfigPath> \
  --context=<kubernetesContext> \
  <command>
```

### Git Operations (local machine)

```bash
# Flux repo location
cd ${RWENV_CONFIG_DIR:-~/.claude/rwenv}/flux-repos/<rwenv-name>/

# Standard git commands
git pull
git checkout -b <branch>
git add <files>
git commit -m "<message>"
git push origin <branch>
gh pr create --title "<title>" --body "<body>"
```

## Capabilities

### A. Flux Resource Operations (via dev container)

| Operation | Command Pattern | Read-Only Safe |
|-----------|-----------------|----------------|
| List GitRepositories | `flux get sources git -A` | Yes |
| List Kustomizations | `flux get kustomizations -A` | Yes |
| List HelmReleases | `flux get helmreleases -A` | Yes |
| Check all status | `flux get all -A` | Yes |
| Inspect source | `flux get source git <name> -n <ns> -o yaml` | Yes |
| Inspect HelmRelease | `flux get helmrelease <name> -n <ns> -o yaml` | Yes |
| View Flux events | `kubectl get events -n flux-system --sort-by='.lastTimestamp'` | Yes |
| Trigger reconciliation | `flux reconcile kustomization <name> -n <ns>` | **No** |
| Reconcile source | `flux reconcile source git <name> -n <ns>` | **No** |
| Suspend resource | `flux suspend <type> <name> -n <ns>` | **No** |
| Resume resource | `flux resume <type> <name> -n <ns>` | **No** |

### B. GitOps Workflow Operations (local machine)

| Operation | Method | Read-Only Safe |
|-----------|--------|----------------|
| Clone Flux repo | `git clone` | Yes |
| Pull updates | `git pull` | Yes |
| Browse manifests | Read files | Yes |
| View git history | `git log` | Yes |
| View diff | `git diff` | Yes |
| Create branch | `git checkout -b` | **No** |
| Modify manifests | Edit files | **No** |
| Stage changes | `git add` | **No** |
| Commit changes | `git commit` | **No** |
| Push to remote | `git push` | **No** |
| Create PR | `gh pr create` | **No** |

## Read-Only Mode Enforcement

When `readOnly: true` in rwenv config:

1. **Block Flux write operations** with clear error message:
   ```
   ERROR: rwenv '<name>' is read-only. Cannot execute: flux reconcile kustomization apps

   This environment is configured as read-only for safety.
   Write operations blocked: reconcile, suspend, resume

   To perform write operations, use a non-read-only environment.
   ```

2. **Block git write operations** to Flux repo:
   ```
   ERROR: rwenv '<name>' is read-only. Cannot modify Flux repo.

   Blocked operations: branch creation, commits, pushes, PRs

   Read-only operations allowed: clone, pull, browse, view history
   ```

3. **Allow all read operations** without restriction

## Flux Repo Management

### Location

```
${RWENV_CONFIG_DIR:-~/.claude/rwenv}/flux-repos/
├── dev/           # Cloned repo for 'dev' rwenv
├── staging/       # Cloned repo for 'staging' rwenv
└── prod/          # Cloned repo for 'prod' rwenv
```

### Behavior

| Scenario | Action |
|----------|--------|
| First access | Clone from `fluxGitRepo` in rwenv config |
| Subsequent access | `git pull` to update |
| Missing `fluxGitRepo` | Error: "No fluxGitRepo configured for rwenv '<name>'. Add it to envs.json." |
| Dirty working tree | Warn: "Flux repo has uncommitted changes. Proceed? [y/N]" |

## Service Context Integration

When a service name is mentioned:

1. **Look up in services catalog** (`data/services-catalog.json`)
2. **Extract context**: namespace, fluxPath, helmRelease, kustomization
3. **Use context** to construct commands without asking user

Example:
```
User: "update papi to v2.3.0"

1. Lookup: papi → namespace: runwhen-local, fluxPath: clusters/rdebug/apps/papi/
2. Find manifest at: ${RWENV_CONFIG_DIR:-~/.claude/rwenv}/flux-repos/<rwenv>/clusters/rdebug/apps/papi/
3. Edit values.yaml with new image tag
4. Commit, push, create PR
```

If service not in catalog:
```
Service 'foo' not found in services catalog.
Please specify:
  - Namespace: ___
  - Flux path (relative to repo root): ___

Or run /services-mapping regenerate to rebuild the catalog.
```

## Common Workflows

### Check Flux sync status

```bash
# 1. Get overall status
flux get all -A

# 2. Check specific kustomization
flux get kustomization <name> -n flux-system

# 3. Check source sync
flux get source git flux-system -n flux-system
```

### Deploy a new image version (not read-only)

```bash
# 1. Ensure Flux repo is up to date
cd ${RWENV_CONFIG_DIR:-~/.claude/rwenv}/flux-repos/<rwenv>/
git pull

# 2. Create deployment branch
git checkout -b deploy/papi-v2.3.0

# 3. Find and edit the values file
# Use services catalog: papi → fluxPath: clusters/rdebug/apps/papi/
# Edit clusters/rdebug/apps/papi/values.yaml

# 4. Commit and push
git add clusters/rdebug/apps/papi/values.yaml
git commit -m "deploy: update papi to v2.3.0"
git push -u origin deploy/papi-v2.3.0

# 5. Create PR
gh pr create --title "Deploy papi v2.3.0" --body "Updates papi image tag to v2.3.0"

# 6. After PR merged, trigger reconciliation (or wait for auto-sync)
flux reconcile kustomization apps-papi -n flux-system

# 7. Monitor deployment
flux get kustomization apps-papi -n flux-system --watch
```

### Investigate failed reconciliation

```bash
# 1. Check kustomization status
flux get kustomization <name> -n flux-system

# 2. Get detailed error
flux get kustomization <name> -n flux-system -o yaml

# 3. Check events
kubectl get events -n flux-system --field-selector reason=ReconciliationFailed

# 4. Check source status
flux get source git flux-system -n flux-system

# 5. If source issue, check Flux repo manually
cd ${RWENV_CONFIG_DIR:-~/.claude/rwenv}/flux-repos/<rwenv>/
git log --oneline -5
git status
```

## Error Handling

| Error | Response |
|-------|----------|
| No rwenv set | "No rwenv configured. Use /rwenv-set to select an environment." |
| No fluxGitRepo | "No Flux repo configured for this rwenv. Add fluxGitRepo to envs.json." |
| Dev container not running | "Dev container '<name>' not running. Start it first." |
| Flux repo clone failed | "Failed to clone Flux repo. Check URL and credentials." |
| Read-only violation | "rwenv '<name>' is read-only. Cannot execute: <command>" |
| Service not in catalog | "Service '<name>' not found. Specify namespace/path or regenerate catalog." |
| Git push failed | "Push failed. Check remote permissions and branch protection rules." |
| PR creation failed | "PR creation failed. Verify gh CLI is authenticated." |
