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

### Step 1: Get current rwenv

**IMPORTANT:** The active rwenv is stored in the project's `.claude/rwenv` file, NOT in `~/.claude/rwenv/current/`.

```bash
# Read rwenv name from project directory
RWENV_NAME=$(cat .claude/rwenv 2>/dev/null)

if [[ -z "$RWENV_NAME" ]]; then
    echo "No rwenv set. Use /rwenv-set first."
    exit 1
fi
```

Then get the rwenv config:
```bash
# Get flux repo config from global envs.json
FLUX_REPO_URL=$(jq -r ".rwenvs.${RWENV_NAME}.fluxGitRepo" ~/.claude/rwenv/envs.json)
FLUX_REPO_TYPE=$(jq -r ".rwenvs.${RWENV_NAME}.fluxGitRepoType // \"github\"" ~/.claude/rwenv/envs.json)
```

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
FLUX_REPO_PATH="$HOME/.claude/rwenv/flux-repos/${RWENV_NAME}"

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

### Step 4: Look up image tag location from flux-infra-guide

**Read the services.json from flux-infra-guide skill to find where to update the tag.**

The data file is at: `<plugin-dir>/skills/flux-infra-guide/data/services.json`

```bash
# Read service config
SERVICE_CONFIG=$(jq ".services.${SERVICE_NAME}" <plugin-dir>/skills/flux-infra-guide/data/services.json)
IMAGE_GROUP=$(echo "$SERVICE_CONFIG" | jq -r '.imageGroup')

# Read imageGroup config
IMAGE_GROUP_CONFIG=$(jq ".imageGroups.${IMAGE_GROUP}" <plugin-dir>/skills/flux-infra-guide/data/services.json)
TAG_FILE=$(echo "$IMAGE_GROUP_CONFIG" | jq -r '.file')
IMAGE_NAME=$(echo "$IMAGE_GROUP_CONFIG" | jq -r '.imageName')
```

**Data structure:**
```json
{
  "services": {
    "papi": {
      "imageGroup": "backend-services"
    }
  },
  "imageGroups": {
    "backend-services": {
      "file": "apps/backend-services/kustomization.yaml",
      "imageName": "backend-services",
      "type": "kustomize-images"
    }
  }
}
```

### Step 5: Update the image tag

For `kustomize-images` type (most common):

```bash
cd "$FLUX_REPO_PATH"

# Update the newTag for the specific image name
yq -i "(.images[] | select(.name == \"${IMAGE_NAME}\")).newTag = \"${TAG}\"" "${TAG_FILE}"
```

**Verify the change:**
```bash
grep -A2 "name: ${IMAGE_NAME}" "${TAG_FILE}"
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
git add "${TAG_FILE}"
git commit -m "chore(${IMAGE_GROUP}): update image tag to ${TAG}"

# Push with explicit refs (works regardless of upstream config)
git push origin HEAD:main
```

### Step 7: Report success

```
✓ Updated ${IMAGE_GROUP} to ${TAG}

Flux repo: ${FLUX_REPO_URL}
File: ${TAG_FILE}
Image: ${IMAGE_NAME}
Tag: ${TAG}

Services affected: ${SERVICES_LIST}

Flux will reconcile automatically. To force immediate sync:
  flux reconcile kustomization ${KUSTOMIZATION} --with-source
```

## Example Session

**User:** rollout papi

**Claude:**
1. Reads `.claude/rwenv` → `rdebug`
2. Reads `~/.claude/rwenv/envs.json` → gets `fluxGitRepo`, `fluxGitRepoType: gitea`
3. Gets PR number → `42`
4. Gets commit SHA → `a1b2c3d` (7 chars)
5. Constructs tag → `pr-42-a1b2c3d`
6. Reads `flux-infra-guide/data/services.json`:
   - papi.imageGroup → `backend-services`
   - backend-services.file → `apps/backend-services/kustomization.yaml`
   - backend-services.imageName → `backend-services`
7. Sets `GIT_SSL_NO_VERIFY=1` (gitea repo)
8. Updates flux repo at `~/.claude/rwenv/flux-repos/rdebug/`
9. Runs: `yq -i '(.images[] | select(.name == "backend-services")).newTag = "pr-42-a1b2c3d"' apps/backend-services/kustomization.yaml`
10. Commits and pushes with `git push origin HEAD:main`
11. Reports: "✓ Updated backend-services to pr-42-a1b2c3d"

## Error Handling

| Error | Response |
|-------|----------|
| No `.claude/rwenv` file | "No rwenv set. Use `/rwenv-set` first." |
| No PR for branch | "No PR found for current branch. Create a PR first with `gh pr create`." |
| No fluxGitRepo in rwenv | "No flux repo configured for this rwenv. Add `fluxGitRepo` to rwenv config." |
| Service not in services.json | "Service '<name>' not found in flux-infra-guide. Run `/flux-infra-guide-regenerate` or provide the file path manually." |
| No imageGroup for service | "No imageGroup configured for '<name>'. Update services.json or provide the file path manually." |
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
yq -i '(.images[] | select(.name == "<image>")).newTag = "<tag>"' <file>
git add <file>
git commit -m "chore(<image>): update image tag to <tag>"
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
- **DO NOT** look for rwenv in `~/.claude/rwenv/current/` (use `.claude/rwenv` in project dir)
- **DO NOT** search for tag location manually (use flux-infra-guide data)
