---
name: rwenv-add
description: Interactively create a new rwenv environment
triggers:
  - /rwenv-add
  - add new environment
  - create rwenv
  - new rwenv
  - add environment
---

# Add New RunWhen Environment

Interactively create a new rwenv environment configuration.

## Instructions

Guide the user through creating a new rwenv by collecting the required information step by step using AskUserQuestion.

### Step 1: Environment Name

Ask for the environment name:
```
What name would you like for this environment?

Examples: dev, staging, prod, gke-us-west, k3s-local
```

Validate:
- Name must be alphanumeric with hyphens allowed
- Name must not already exist in envs.json
- If name exists, ask if they want to edit it instead (future feature) or choose different name

### Step 2: Environment Type

Use AskUserQuestion with options:
- **k3s** - Lightweight Kubernetes (k3s/k3d, local dev)
- **gke** - Google Kubernetes Engine

### Step 3: GCP Project (GKE only)

If type is `gke`, ask:
```
What is the GCP project ID for this environment?

Example: my-company-prod-12345
```

### Step 4: Kubeconfig Path

Ask for the kubeconfig path inside the dev container:
```
What is the kubeconfig path (inside the dev container)?

Default: /root/.kube/config
Examples:
  - /root/.kube/config (default)
  - /root/.kube/gke-prod.config
  - /root/.kube/custom-cluster.yaml
```

Use AskUserQuestion with:
- "Use default (/root/.kube/config)"
- "Specify custom path"

### Step 5: Kubernetes Context

Ask for the context name:
```
What is the Kubernetes context name?

This should match a context in your kubeconfig.
Run 'kubectl config get-contexts' in the dev container to list available contexts.

Examples: rdebug-61, gke_myproject_us-central1_cluster-1
```

### Step 6: Description

Ask for a brief description:
```
Provide a brief description for this environment:

Examples:
  - "Local k3s development cluster"
  - "Production GKE cluster (US West)"
  - "Staging environment for testing"
```

### Step 7: Read-Only Mode

Use AskUserQuestion with options:
- **No (read-write)** - Allow all operations including writes
- **Yes (read-only)** - Block write operations (kubectl apply, delete, etc.)

Suggest read-only for production environments.

### Step 8: Flux Git Repository (Optional)

Ask:
```
What is the FluxCD git repository URL? (optional, press Enter to skip)

This is used for GitOps operations.
Examples:
  - https://github.com/org/flux-manifests
  - https://gitea.local/platform/flux-repo
```

### Step 9: Service URLs (Optional)

Ask if they want to add service URLs:

Use AskUserQuestion:
- "Yes, add service URLs"
- "No, skip this"

If yes, collect services one at a time:
```
Add a service (or type 'done' to finish):

Service name (e.g., papi, app, vault):
Service URL (e.g., https://papi.example.com):
```

Repeat until user says 'done'.

### Step 10: Set as Active

Use AskUserQuestion:
- "Yes, set as active for current directory"
- "No, just save the configuration"

### Step 11: Save and Confirm

1. Read existing `envs.json` (or create new if doesn't exist)
2. Add the new rwenv to the `rwenvs` object
3. Write updated config back to file
4. If "set as active" was chosen, update `env-consumers.json`

Display confirmation:
```
rwenv 'staging' created successfully!

Configuration:
  Name:        staging
  Type:        gke
  Description: Staging GKE cluster
  Context:     gke_myproject_us-central1_staging
  Kubeconfig:  /root/.kube/config
  Read-Only:   No
  GCP Project: myproject-staging
  Flux Repo:   https://github.com/org/flux-staging

Services:
  papi: https://papi.staging.example.com
  app:  https://app.staging.example.com

Status: Active for /Users/rohitekbote/wd/myproject

Use /rwenv-cur to see full details.
Use /rwenv-list to see all environments.
```

## Error Handling

**Config directory doesn't exist:**
Create it automatically: `mkdir -p ~/.claude/rwenv`

**envs.json doesn't exist:**
Create it with initial structure:
```json
{
  "version": "1.0",
  "devContainer": "alpine-dev-container-zsh-rdebug",
  "databases": {},
  "rwenvs": {}
}
```

**Name already exists:**
```
ERROR: rwenv 'staging' already exists.

Choose a different name or use /rwenv-edit staging (coming soon) to modify it.
```

**Invalid JSON in existing config:**
```
ERROR: Cannot parse existing envs.json - invalid JSON at line X.

Please fix the JSON syntax error and try again, or backup and recreate the file.
```
