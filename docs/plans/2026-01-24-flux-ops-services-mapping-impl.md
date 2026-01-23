# Flux-Ops Subagent and Services-Mapping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a flux-ops subagent for GitOps workflows and a services-mapping skill with static service catalog.

**Architecture:** Two new components - (1) flux-ops.md subagent handling Flux resource inspection and GitOps deployment workflows, (2) services-mapping.md skill with services-catalog.json data file for service/namespace/Flux path lookups. Subagents reference the services catalog for context.

**Tech Stack:** Markdown skills/subagents, JSON data file, shell utilities in rwenv-utils.sh

---

## Task 1: Create services-catalog.json Data File

**Files:**
- Create: `data/services-catalog.json`

**Step 1: Create data directory**

```bash
mkdir -p data
```

**Step 2: Create placeholder services-catalog.json**

Create `data/services-catalog.json`:

```json
{
  "version": "1.0",
  "generatedFrom": {
    "cluster": "placeholder",
    "fluxRepo": "placeholder",
    "generatedAt": "2026-01-24T00:00:00Z"
  },
  "services": {
    "_placeholder": {
      "description": "Placeholder service - run /services-mapping regenerate to populate from cluster",
      "namespace": "default",
      "fluxPath": "clusters/example/apps/placeholder/",
      "helmRelease": "placeholder",
      "kustomization": "apps-placeholder"
    }
  }
}
```

**Step 3: Verify JSON is valid**

Run: `jq . data/services-catalog.json`
Expected: Valid JSON output (no errors)

**Step 4: Commit**

```bash
git add data/services-catalog.json
git commit -m "feat: add services-catalog.json placeholder data file"
```

---

## Task 2: Create services-mapping Skill

**Files:**
- Create: `skills/services-mapping.md`

**Step 1: Create the skill file**

Create `skills/services-mapping.md`:

```markdown
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

1. **Read the catalog** from the plugin's `data/services-catalog.json` file

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

1. **Read the catalog** from `data/services-catalog.json`

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
6. **Write updated catalog** to `data/services-catalog.json`
7. **Report** what was found and updated

## Data File Location

The services catalog is at: `<plugin-directory>/data/services-catalog.json`

To find the plugin directory, check where this skill file is located and go up one level.

## Error Handling

| Error | Response |
|-------|----------|
| Catalog file missing | "Services catalog not found. Run /services-mapping regenerate to create it." |
| Catalog JSON invalid | "Services catalog has invalid JSON. Check data/services-catalog.json" |
| No services in catalog | "Services catalog is empty. Run /services-mapping regenerate to populate it." |
```

**Step 2: Verify markdown syntax**

Run: `head -20 skills/services-mapping.md`
Expected: Shows frontmatter and heading

**Step 3: Commit**

```bash
git add skills/services-mapping.md
git commit -m "feat: add services-mapping skill for service catalog lookups"
```

---

## Task 3: Add Flux Repo Helper Functions to rwenv-utils.sh

**Files:**
- Modify: `lib/rwenv-utils.sh`

**Step 1: Read current file**

Read `lib/rwenv-utils.sh` to understand current structure.

**Step 2: Add Flux repo helper functions**

Append to `lib/rwenv-utils.sh`:

```bash

# Get Flux repo URL for rwenv
get_flux_repo_url() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    echo "$rwenv" | jq -r '.fluxGitRepo // empty'
}

# Get Flux repo local path for rwenv
get_flux_repo_path() {
    local name="$1"
    local config_dir
    config_dir="$(get_config_dir)"

    echo "$config_dir/flux-repos/$name"
}

# Check if Flux repo is cloned for rwenv
is_flux_repo_cloned() {
    local name="$1"
    local repo_path
    repo_path="$(get_flux_repo_path "$name")"

    [[ -d "$repo_path/.git" ]]
}

# Clone or update Flux repo for rwenv
ensure_flux_repo() {
    local name="$1"
    local repo_url repo_path

    repo_url="$(get_flux_repo_url "$name")"
    if [[ -z "$repo_url" ]]; then
        echo "ERROR: No fluxGitRepo configured for rwenv '$name'" >&2
        return 1
    fi

    repo_path="$(get_flux_repo_path "$name")"

    if is_flux_repo_cloned "$name"; then
        # Update existing repo
        echo "Updating Flux repo at $repo_path..." >&2
        (cd "$repo_path" && git fetch origin && git pull --ff-only) || {
            echo "WARNING: Could not update Flux repo. Working with existing checkout." >&2
        }
    else
        # Clone new repo
        echo "Cloning Flux repo to $repo_path..." >&2
        mkdir -p "$(dirname "$repo_path")"
        git clone "$repo_url" "$repo_path" || {
            echo "ERROR: Failed to clone Flux repo from $repo_url" >&2
            return 1
        }
    fi

    echo "$repo_path"
}

# Check if Flux repo has uncommitted changes
is_flux_repo_dirty() {
    local name="$1"
    local repo_path
    repo_path="$(get_flux_repo_path "$name")"

    if [[ ! -d "$repo_path/.git" ]]; then
        return 1  # Not cloned, so not dirty
    fi

    (cd "$repo_path" && [[ -n "$(git status --porcelain)" ]])
}
```

**Step 3: Verify syntax**

Run: `bash -n lib/rwenv-utils.sh`
Expected: No output (valid syntax)

**Step 4: Commit**

```bash
git add lib/rwenv-utils.sh
git commit -m "feat: add Flux repo helper functions to rwenv-utils.sh"
```

---

## Task 4: Create flux-ops Subagent

**Files:**
- Create: `subagents/flux-ops.md`

**Step 1: Create the subagent file**

Create `subagents/flux-ops.md`:

```markdown
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
   - Location: `~/.claude/rwenv/flux-repos/<rwenv-name>/`
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
cd ~/.claude/rwenv/flux-repos/<rwenv-name>/

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
~/.claude/rwenv/flux-repos/
├── dev/           # Cloned repo for 'dev' rwenv
├── staging/       # Cloned repo for 'staging' rwenv
└── prod/          # Cloned repo for 'prod' rwenv
```

### Behavior

| Scenario | Action |
|----------|--------|
| First access | Clone from `fluxGitRepo` in rwenv config |
| Subsequent access | `git fetch && git pull` to update |
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
2. Find manifest at: ~/.claude/rwenv/flux-repos/<rwenv>/clusters/rdebug/apps/papi/
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
cd ~/.claude/rwenv/flux-repos/<rwenv>/
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
cd ~/.claude/rwenv/flux-repos/<rwenv>/
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
```

**Step 2: Verify markdown syntax**

Run: `head -30 subagents/flux-ops.md`
Expected: Shows frontmatter and heading

**Step 3: Commit**

```bash
git add subagents/flux-ops.md
git commit -m "feat: add flux-ops subagent for GitOps workflows"
```

---

## Task 5: Update k8s-ops Subagent to Reference Services Catalog

**Files:**
- Modify: `subagents/k8s-ops.md`

**Step 1: Read current file**

Read `subagents/k8s-ops.md` to find the Prerequisites section.

**Step 2: Update Prerequisites section**

Find the Prerequisites section and add services catalog loading. Change from:

```markdown
## Prerequisites

Before executing any operations:

1. **Verify rwenv is set** for current directory
   - If not set, inform user and suggest `/rwenv-set`

2. **Load rwenv configuration** from `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json`
   - Get `kubernetesContext`, `kubeconfigPath`, `readOnly` settings

3. **Check dev container** is running
   - Container name from `devContainer` field in envs.json
```

To:

```markdown
## Prerequisites

Before executing any operations:

1. **Verify rwenv is set** for current directory
   - If not set, inform user and suggest `/rwenv-set`

2. **Load rwenv configuration** from `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json`
   - Get `kubernetesContext`, `kubeconfigPath`, `readOnly` settings

3. **Load services catalog** from plugin's `data/services-catalog.json`
   - Use for service → namespace lookups (e.g., "papi" → namespace: runwhen-local)
   - If catalog missing, warn but continue (can specify namespace manually)

4. **Check dev container** is running
   - Container name from `devContainer` field in envs.json
```

**Step 3: Add Service Context section**

After the "Error Handling" section, add:

```markdown

## Service Context Integration

When a service name is mentioned without a namespace:

1. **Look up in services catalog** (`data/services-catalog.json`)
2. **Extract namespace** from catalog entry
3. **Use namespace** in kubectl commands automatically

Example:
```
User: "get logs for papi"

1. Lookup: papi → namespace: runwhen-local
2. Execute: kubectl logs -l app=papi -n runwhen-local
```

If service not in catalog:
```
Service 'foo' not found in services catalog.
Please specify the namespace, or run /services-mapping regenerate to rebuild the catalog.
```
```

**Step 4: Verify the edit**

Run: `grep -A 10 "Prerequisites" subagents/k8s-ops.md`
Expected: Shows updated prerequisites with services catalog step

**Step 5: Commit**

```bash
git add subagents/k8s-ops.md
git commit -m "feat: update k8s-ops to reference services catalog for namespace lookups"
```

---

## Task 6: Verify All Shell Scripts Have Valid Syntax

**Files:**
- Verify: `lib/rwenv-utils.sh`
- Verify: `hooks/pre-command.sh`
- Verify: `scripts/*.sh`

**Step 1: Run syntax check on all shell scripts**

Run: `bash -n lib/rwenv-utils.sh && bash -n hooks/pre-command.sh && bash -n scripts/command-builder.sh && bash -n scripts/pg_query.sh && echo "All scripts valid"`

Expected: "All scripts valid"

**Step 2: Verify JSON data file**

Run: `jq . data/services-catalog.json > /dev/null && echo "JSON valid"`

Expected: "JSON valid"

---

## Task 7: Final Verification and Summary Commit

**Step 1: Check git status**

Run: `git status`
Expected: Clean working tree (all changes committed)

**Step 2: Review commit history**

Run: `git log --oneline -10`
Expected: Shows all commits from this implementation

**Step 3: Verify file structure**

Run: `find . -type f -name "*.md" -o -name "*.json" -o -name "*.sh" | grep -E "(flux-ops|services)" | sort`

Expected:
```
./data/services-catalog.json
./skills/services-mapping.md
./subagents/flux-ops.md
```

**Step 4: Create summary commit if any uncommitted changes**

If there are uncommitted changes:
```bash
git add -A
git commit -m "chore: final cleanup for flux-ops and services-mapping implementation"
```

---

## Implementation Complete Checklist

After all tasks, verify:

- [ ] `data/services-catalog.json` exists with valid JSON
- [ ] `skills/services-mapping.md` exists with proper frontmatter
- [ ] `subagents/flux-ops.md` exists with proper frontmatter
- [ ] `subagents/k8s-ops.md` updated with services catalog reference
- [ ] `lib/rwenv-utils.sh` has Flux repo helper functions
- [ ] All shell scripts pass `bash -n` syntax check
- [ ] All commits made with descriptive messages
- [ ] Branch ready for PR or merge
