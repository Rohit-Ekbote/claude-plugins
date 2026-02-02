---
name: rollout
description: Rollout latest image tag from feature branch to flux repo
triggers:
  - /rollout
  - rollout
  - deploy tag
  - update tag
  - push tag
---

# Rollout Image Tag

Update the image tag in the flux repo for a service using the current branch's PR number and commit SHA.

## Tag Format

**CRITICAL**: The image tag format is exactly:
```
pr-<pr_number>-<commit_sha_first_7_chars>
```

Example: `pr-123-a1b2c3d`

**Rules:**
- Prefix: `pr-` (not `ps-`)
- PR number: Get from `gh pr view --json number`
- Commit SHA: **Exactly 7 characters** - use `git rev-parse --short=7 HEAD`
- **DO NOT** check if tag exists in registry or git
- **DO NOT** verify if build pipeline passed (unless explicitly asked)
- **DO NOT** use 8 characters or full SHA

## Flux Repo Types

The rwenv config specifies `fluxGitRepoType`:

| Type | Hosting | Git Handling |
|------|---------|--------------|
| `gitea` | Local VM (self-signed SSL) | All git commands require `GIT_SSL_NO_VERIFY=1` |
| `github` | GitHub.com | Uses local git credentials (no special handling) |

## Instructions

### Step 1: Verify prerequisites

1. Check rwenv is set for current directory (use `/rwenv-cur`)
2. Get the flux repo URL from rwenv config: `fluxGitRepo`
3. Get the flux repo type from rwenv config: `fluxGitRepoType`

### Step 2: Construct the image tag

```bash
# Get PR number for current branch
PR_NUM=$(gh pr view --json number --jq '.number')

# Get first 7 chars of HEAD commit (EXACTLY 7, not 8)
COMMIT_SHA=$(git rev-parse --short=7 HEAD)

# Construct tag
TAG="pr-${PR_NUM}-${COMMIT_SHA}"
```

**Example:** PR #42, commit `a1b2c3def` → tag `pr-42-a1b2c3d`

### Step 3: Clone/update flux repo

Flux repo location: `~/.claude/rwenv/flux-repos/<rwenv-name>/`

```bash
FLUX_REPO_URL="<from rwenv config: fluxGitRepo>"
FLUX_REPO_TYPE="<from rwenv config: fluxGitRepoType>"
FLUX_REPO_PATH="$HOME/.claude/rwenv/flux-repos/<rwenv-name>"

# Set environment for gitea repos
if [[ "$FLUX_REPO_TYPE" == "gitea" ]]; then
    export GIT_SSL_NO_VERIFY=1
fi

if [[ -d "$FLUX_REPO_PATH/.git" ]]; then
    cd "$FLUX_REPO_PATH"
    git fetch origin
    git reset --hard origin/main
else
    rm -rf "$FLUX_REPO_PATH"
    git clone "$FLUX_REPO_URL" "$FLUX_REPO_PATH"
    cd "$FLUX_REPO_PATH"
fi
```

**Important:** Use `git fetch` + `git reset --hard` instead of `git pull` to avoid merge conflicts from previous failed attempts.

### Step 4: Discover flux path for service (on-demand)

Search the flux repo for the service's HelmRelease or values file:

```bash
cd "$FLUX_REPO_PATH"

# Find HelmRelease with matching name
HELM_RELEASE=$(grep -rl "name: <service>" --include="*.yaml" . | xargs grep -l "kind: HelmRelease" | head -1)

# Or find values.yaml in service directory
VALUES_FILE=$(find . -path "*/<service>/*" -name "values.yaml" | head -1)
```

Common patterns to check:
- `apps/<service>/helmrelease.yaml` - HelmRelease manifest
- `apps/<service>/values.yaml` - Helm values file
- `releases/<service>.yaml` - Release definition
- `clusters/*/apps/<service>/` - Cluster-specific paths

### Step 5: Update the image tag

Once the file is found, update the tag using `yq`:

**For values.yaml:**
```bash
yq -i '.image.tag = "<new_tag>"' <values_file>
```

**For HelmRelease with inline values:**
```bash
yq -i '.spec.values.image.tag = "<new_tag>"' <helmrelease_file>
```

**For nested image config:**
```bash
# Check structure first
yq '.image' <file>
# or
yq '.spec.values.image' <file>
```

### Step 6: Commit and push

**IMPORTANT:** Use explicit remote and branch refs to avoid upstream tracking issues.

```bash
cd "$FLUX_REPO_PATH"

# Ensure SSL handling for gitea
if [[ "$FLUX_REPO_TYPE" == "gitea" ]]; then
    export GIT_SSL_NO_VERIFY=1
fi

# Stage and commit
git add <updated_file>
git commit -m "chore(<service>): update image tag to <new_tag>"

# Push with explicit refs (works regardless of upstream config)
git push origin HEAD:main
```

### Step 7: Report success

```
✓ Updated <service> to <tag>

Flux repo: <flux_repo_url>
File: <updated_file>
Tag: <new_tag>

Flux will reconcile automatically. To force immediate sync:
  flux reconcile kustomization <name> --with-source
```

## Example Session

**User:** rollout papi

**Claude:**
1. Checks rwenv is set → `rdebug`
2. Gets flux repo type → `gitea`
3. Gets PR number → `42`
4. Gets commit SHA → `a1b2c3d` (7 chars)
5. Constructs tag → `pr-42-a1b2c3d`
6. Sets `GIT_SSL_NO_VERIFY=1` (gitea repo)
7. Updates flux repo at `~/.claude/rwenv/flux-repos/rdebug/`
8. Finds `apps/papi/values.yaml`
9. Updates `.image.tag` to `pr-42-a1b2c3d`
10. Commits and pushes with `git push origin HEAD:main`
11. Reports: "✓ Updated papi to pr-42-a1b2c3d"

## Error Handling

| Error | Response |
|-------|----------|
| No rwenv set | "No rwenv set. Use `/rwenv-set` first." |
| No PR for branch | "No PR found for current branch. Create a PR first with `gh pr create`." |
| No fluxGitRepo in rwenv | "No flux repo configured for this rwenv. Add `fluxGitRepo` to rwenv config." |
| No fluxGitRepoType in rwenv | "No flux repo type configured. Add `fluxGitRepoType: gitea` or `fluxGitRepoType: github` to rwenv config." |
| Service not found in flux repo | "Could not find flux config for '<service>'. Searched for HelmRelease and values.yaml." Then ask user to provide the path. |
| Git push fails | See Troubleshooting section below. |

## Troubleshooting

### Common Errors and Recovery

| Error | Cause | Recovery |
|-------|-------|----------|
| `SSL certificate problem: unable to get local issuer certificate` | Gitea with self-signed cert | Verify `fluxGitRepoType: gitea` in rwenv config. All git commands must use `GIT_SSL_NO_VERIFY=1` |
| `The current branch has no upstream branch` | Remote branch not tracked | Use `git push origin HEAD:main` instead of `git push` |
| `fatal: couldn't find remote ref main` | Remote uses different default branch | Check with `git remote show origin`, use correct branch name (e.g., `master`) |
| `Permission denied (publickey)` | GitHub SSH key not configured | Use HTTPS URL, or verify `~/.ssh/config` has GitHub key |
| `remote: Permission to X denied to Y` | GitHub token lacks write access | Check `gh auth status`, re-auth with `gh auth login` |
| `error: failed to push some refs` | Remote has newer commits | Run `git fetch origin && git reset --hard origin/main` then redo changes and push |
| `fatal: not a git repository` | Clone failed or corrupted | Remove `$FLUX_REPO_PATH` directory completely and re-clone |

### Recovery Pattern

When git operations fail, follow this sequence:

```bash
# 1. Set environment for repo type
FLUX_REPO_TYPE="<from rwenv config>"
[[ "$FLUX_REPO_TYPE" == "gitea" ]] && export GIT_SSL_NO_VERIFY=1

# 2. Check remote state
git remote -v
git fetch origin

# 3. Check local state
git status
git log --oneline -3

# 4. Reset to clean state
git reset --hard origin/main

# 5. Redo changes and push
# ... make changes again ...
git add <file>
git commit -m "chore(<service>): update image tag to <tag>"
git push origin HEAD:main --verbose
```

### Nuclear Option

If the flux repo clone is corrupted beyond repair:

```bash
rm -rf "$HOME/.claude/rwenv/flux-repos/<rwenv-name>"
# Then restart the rollout process from Step 3
```

## What NOT To Do

- **DO NOT** run `git tag` or `git ls-remote --tags`
- **DO NOT** run `gcloud container images list-tags`
- **DO NOT** check GitHub Actions or build pipeline status
- **DO NOT** use 8 characters for SHA (must be exactly 7)
- **DO NOT** verify the image exists before updating
- **DO NOT** use `git push` without explicit remote and branch refs
- **DO NOT** use `git pull` (use `fetch` + `reset --hard` to avoid merge issues)
