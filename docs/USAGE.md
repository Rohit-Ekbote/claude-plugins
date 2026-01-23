# Usage Guide

## Skills Overview

rwenv provides four main skills for environment management:

| Skill | Purpose |
|-------|---------|
| `/rwenv-list` | List all available environments |
| `/rwenv-cur` | Show current environment details |
| `/rwenv-set <name>` | Set environment for current directory |
| `/rwenv-add` | Create a new environment interactively |

## Listing Environments

```
/rwenv-list
```

Or use natural language:
- "list environments"
- "show rwenvs"
- "what environments are available"

**Example output:**
```
RunWhen Environments:

  NAME        TYPE   DESCRIPTION                  READ-ONLY
* dev         k3s    Local k3s development        No
  staging     gke    GKE staging cluster          No
  prod        gke    GKE production cluster       Yes

* = active for current directory (/Users/me/myproject)
```

## Viewing Current Environment

```
/rwenv-cur
```

Or use natural language:
- "current rwenv"
- "what environment am I using"
- "which rwenv"

**Example output:**
```
Current rwenv: dev

Type:        k3s
Description: Local k3s development
Context:     k3s-local
Kubeconfig:  /root/.kube/config
Read-Only:   No
GCP Project: N/A
Flux Repo:   https://github.com/org/flux-dev

Services:
  papi: https://papi.dev.local
  app:  https://app.dev.local

Directory mapping: /Users/me/myproject -> dev
```

## Setting Environment

```
/rwenv-set dev
```

Or use natural language:
- "switch to dev"
- "use prod environment"
- "change to staging"

**Without arguments** - shows list and prompts for selection:
```
/rwenv-set
```

**Switching environments** - asks for confirmation:
```
Current rwenv: dev (Local k3s development, read-write)
Requested:     prod (GKE production cluster, READ-ONLY)

Switch from 'dev' to 'prod'?
```

## Creating Environments

```
/rwenv-add
```

This launches an interactive wizard that prompts for:

1. **Name** - Unique identifier (e.g., `staging`, `gke-us-west`)
2. **Type** - `k3s` or `gke`
3. **GCP Project** - Required for GKE type
4. **Kubeconfig Path** - Path inside dev container
5. **Kubernetes Context** - Context name in kubeconfig
6. **Description** - Brief description
7. **Read-Only Mode** - Whether to block write operations
8. **Flux Git Repo** - Optional FluxCD repository URL
9. **Service URLs** - Optional service endpoint URLs
10. **Set as Active** - Whether to activate for current directory

## Command Transformation

Once an environment is set, kubectl/helm/flux/gcloud commands are automatically transformed:

**Original:**
```bash
kubectl get pods -n production
```

**Transformed:**
```bash
docker exec -it alpine-dev-container-zsh-rdebug \
  kubectl --kubeconfig=/root/.kube/config \
          --context=k3s-local \
          get pods -n production
```

This happens transparently - you just use commands normally.

## Read-Only Mode

When an environment has `readOnly: true`, write operations are blocked:

**Blocked kubectl operations:**
- `apply`, `delete`, `patch`, `create`, `edit`, `replace`, `scale`, `rollout`

**Blocked helm operations:**
- `install`, `upgrade`, `uninstall`, `rollback`

**Blocked flux operations:**
- `reconcile`, `suspend`, `resume`, `create`, `delete`

**Error example:**
```
ERROR: rwenv 'prod' is read-only. Cannot execute write operation.

Blocked command: kubectl delete pod mypod -n production

Use a non-read-only environment for write operations.
```

## Always Read-Only Operations

Regardless of environment settings:

### gcloud

All gcloud write operations are blocked:
```
ERROR: gcloud write operations are blocked for safety.

Blocked command: gcloud compute instances delete my-instance

Use GCP Console or deployment pipelines for write operations.
```

### Database Queries

Only SELECT queries are allowed:
```
ERROR: Write operation detected. Database access is read-only.

Blocked query: DELETE FROM users WHERE id = 1

Only SELECT, EXPLAIN, and metadata queries are allowed.
```

## Database Queries

Use the db-ops subagent or pg_query.sh script:

```bash
# Via script
./scripts/pg_query.sh core "SELECT * FROM users LIMIT 10"

# With format option
./scripts/pg_query.sh core "SELECT COUNT(*) FROM orders" --format=json
```

Available databases are defined in the `databases` section of envs.json.

## Git Branch Protection

In your current project directory:

**Blocked:**
- `git commit` while on main/master/production
- `git push origin main`
- `git merge ... main` (when on main)

**Allowed:**
- All git operations in external repos (flux repos, etc.)
- Checkout main (reading is fine)
- Feature branch workflows

## Per-Directory Environments

Each working directory can have its own environment:

```
/Users/me/project-a  -> dev
/Users/me/project-b  -> staging
/Users/me/project-c  -> prod
```

This is managed via `env-consumers.json` and persists across sessions.

## Worktree Support

Git worktrees inherit the parent directory's environment unless explicitly overridden:

```
/Users/me/myproject              -> dev
/Users/me/myproject/.worktrees/feature-x  -> (inherits dev)
```

You can override with `/rwenv-set` in the worktree directory.

## Natural Language Support

The plugin responds to natural language queries:

| Phrase | Skill |
|--------|-------|
| "list environments" | `/rwenv-list` |
| "show rwenvs" | `/rwenv-list` |
| "switch to dev" | `/rwenv-set dev` |
| "use production" | `/rwenv-set production` |
| "what environment am I using" | `/rwenv-cur` |
| "current rwenv" | `/rwenv-cur` |
| "add new environment" | `/rwenv-add` |
| "create rwenv" | `/rwenv-add` |

## Common Workflows

### Starting work on a project

```
cd ~/projects/myapp
/rwenv-list                    # See available environments
/rwenv-set dev                 # Select dev environment
kubectl get pods               # Commands use dev context
```

### Checking production (read-only)

```
/rwenv-set prod                # Switch to production
kubectl get pods -n backend    # Read operations work
kubectl delete pod mypod       # Blocked - read-only
/rwenv-set dev                 # Switch back to dev
```

### Querying databases

```
/rwenv-set dev
# Use db-ops subagent
"query core database for recent users"
# Or use script
./scripts/pg_query.sh core "SELECT * FROM users ORDER BY created_at DESC LIMIT 10"
```
