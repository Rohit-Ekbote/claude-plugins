# Configuration Reference

## Configuration Location

By default, rwenv configuration lives at:

```
~/.claude/rwenv/
├── envs.json           # Environment definitions
└── env-consumers.json  # Directory mappings
```

### Custom Location

Set `RWENV_CONFIG_DIR` environment variable to use a different location:

```bash
export RWENV_CONFIG_DIR=/path/to/custom/rwenv
```

Use cases:
- **Team shared config**: `/shared/team-a/rwenv/`
- **Per-project config**: `./project/.rwenv/`

## envs.json

The main configuration file containing environment definitions and database configs.

### Schema

```json
{
  "version": "1.0",
  "devContainer": "string",
  "databases": { ... },
  "rwenvs": { ... }
}
```

### Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | Yes | Config version (currently "1.0") |
| `devContainer` | string | Yes | Docker container name for command execution |
| `databases` | object | No | Shared database configurations |
| `rwenvs` | object | Yes | Environment definitions |

### rwenvs Object

Each key is an environment name, value is the environment config:

```json
{
  "rwenvs": {
    "dev": { ... },
    "staging": { ... },
    "prod": { ... }
  }
}
```

### rwenv Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | No | Human-readable description |
| `type` | string | Yes | Environment type: `"k3s"` or `"gke"` |
| `kubeconfigPath` | string | Yes | Path to kubeconfig inside dev container |
| `kubernetesContext` | string | Yes | Kubernetes context name |
| `gcpProject` | string | GKE only | GCP project ID (required for gke type) |
| `readOnly` | boolean | No | Block write operations (default: false) |
| `fluxGitRepo` | string | No | FluxCD git repository URL |
| `fluxGitRepoType` | string | No | Flux repo hosting type: `"gitea"` or `"github"` |
| `services` | object | No | Service name to URL mappings |

### rwenv Example (k3s)

```json
{
  "dev": {
    "description": "Local k3s development cluster",
    "type": "k3s",
    "kubeconfigPath": "/root/.kube/config",
    "kubernetesContext": "k3s-local",
    "readOnly": false,
    "fluxGitRepo": "https://gitea.local/org/flux-dev",
    "fluxGitRepoType": "gitea",
    "services": {
      "papi": "https://papi.dev.local",
      "app": "https://app.dev.local",
      "vault": "https://vault.dev.local"
    }
  }
}
```

### rwenv Example (gke)

```json
{
  "prod": {
    "description": "GKE production cluster (US Central)",
    "type": "gke",
    "kubeconfigPath": "/root/.kube/gke-prod.config",
    "kubernetesContext": "gke_myproject-prod_us-central1_prod-cluster",
    "gcpProject": "myproject-prod",
    "readOnly": true,
    "fluxGitRepo": "https://github.com/org/flux-prod",
    "fluxGitRepoType": "github",
    "services": {
      "papi": "https://papi.prod.example.com",
      "app": "https://app.prod.example.com"
    }
  }
}
```

### databases Object

Shared database configurations accessible from any rwenv:

```json
{
  "databases": {
    "core": { ... },
    "analytics": { ... }
  }
}
```

### database Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `namespace` | string | Yes | Kubernetes namespace containing the secret |
| `secretName` | string | Yes | Name of K8s secret with credentials |
| `pgbouncerHost` | string | Yes | PgBouncer service hostname (FQDN) |
| `database` | string | Yes | Database name |
| `username` | string | Yes | Database username |

### database Example

```json
{
  "core": {
    "namespace": "backend-services",
    "secretName": "core-pguser-core",
    "pgbouncerHost": "core-pgbouncer.backend-services.svc.cluster.local",
    "database": "core",
    "username": "core"
  }
}
```

**Note:** Passwords are fetched from the Kubernetes secret at runtime and never stored in configuration.

## env-consumers.json

Maps working directories to active environments.

### Schema

```json
{
  "/path/to/directory": "rwenv-name",
  "/another/path": "another-rwenv"
}
```

### Example

```json
{
  "/Users/me/projects/app-backend": "dev",
  "/Users/me/projects/app-frontend": "dev",
  "/Users/me/projects/infra": "staging",
  "/Users/me/projects/prod-debug": "prod"
}
```

### Automatic Management

This file is automatically updated when you use `/rwenv-set`. You rarely need to edit it manually.

### Worktree Inheritance

If a directory is not explicitly mapped, the plugin checks parent directories. This allows git worktrees to inherit the main project's environment.

## Complete Example

### envs.json

```json
{
  "version": "1.0",
  "devContainer": "alpine-dev-container-zsh-rdebug",
  "databases": {
    "core": {
      "namespace": "backend-services",
      "secretName": "core-pguser-core",
      "pgbouncerHost": "core-pgbouncer.backend-services.svc.cluster.local",
      "database": "core",
      "username": "core"
    },
    "usearch": {
      "namespace": "backend-services",
      "secretName": "core-pguser-usearch",
      "pgbouncerHost": "core-pgbouncer.backend-services.svc.cluster.local",
      "database": "usearch",
      "username": "usearch"
    },
    "agentfarm": {
      "namespace": "databases",
      "secretName": "postgres-pguser-agentfarm",
      "pgbouncerHost": "core-pgbouncer.backend-services.svc.cluster.local",
      "database": "app_users",
      "username": "agentfarm"
    }
  },
  "rwenvs": {
    "rdebug": {
      "description": "VM based dev setup (k3s)",
      "type": "k3s",
      "kubeconfigPath": "/root/.kube/config",
      "kubernetesContext": "rdebug-61",
      "readOnly": false,
      "fluxGitRepo": "https://gitea.rdebug-61.local.runwhen.com/platform-setup/runwhen-platform-self-hosted-local-dev",
      "fluxGitRepoType": "gitea",
      "services": {
        "papi": "https://papi.rdebug-61.local.runwhen.com",
        "app": "https://app.rdebug-61.local.runwhen.com",
        "vault": "https://vault.rdebug-61.local.runwhen.com",
        "gitea": "https://gitea.rdebug-61.local.runwhen.com",
        "minio": "https://minio-console.rdebug-61.local.runwhen.com",
        "agentfarm": "https://agentfarm.rdebug-61.local.runwhen.com"
      }
    },
    "gke-staging": {
      "description": "GKE staging cluster",
      "type": "gke",
      "kubeconfigPath": "/root/.kube/gke-staging.config",
      "kubernetesContext": "gke_myproject-staging_us-central1_staging",
      "gcpProject": "myproject-staging",
      "readOnly": false,
      "fluxGitRepo": "https://github.com/org/flux-staging",
      "fluxGitRepoType": "github",
      "services": {
        "papi": "https://papi.staging.example.com"
      }
    },
    "gke-prod": {
      "description": "GKE production cluster",
      "type": "gke",
      "kubeconfigPath": "/root/.kube/gke-prod.config",
      "kubernetesContext": "gke_myproject-prod_us-central1_prod",
      "gcpProject": "myproject-prod",
      "readOnly": true,
      "fluxGitRepo": "https://github.com/org/flux-prod",
      "fluxGitRepoType": "github",
      "services": {
        "papi": "https://papi.prod.example.com"
      }
    }
  }
}
```

## Validation

### Check JSON Syntax

```bash
jq . ~/.claude/rwenv/envs.json
```

### Required Fields Check

Ensure each rwenv has:
- `type` (k3s or gke)
- `kubeconfigPath`
- `kubernetesContext`
- `gcpProject` (if type is gke)

### Common Issues

| Issue | Solution |
|-------|----------|
| Invalid JSON | Use `jq` to validate and format |
| Missing gcpProject for GKE | Add `gcpProject` field |
| Wrong kubeconfig path | Path must be inside dev container |
| Context not found | Verify context exists in kubeconfig |

## Multi-Team Support

### Shared Team Configuration

```bash
# Team lead sets up shared config
mkdir -p /shared/team-a/rwenv
cp envs.json /shared/team-a/rwenv/

# Team members point to shared config
export RWENV_CONFIG_DIR=/shared/team-a/rwenv
```

### Per-User Overrides

Users can maintain personal `env-consumers.json` while sharing `envs.json`:

```bash
# Shared envs.json
/shared/team/rwenv/envs.json

# Personal consumer mappings
~/.claude/rwenv/env-consumers.json
```

Set up with symlinks:
```bash
mkdir -p ~/.claude/rwenv
ln -s /shared/team/rwenv/envs.json ~/.claude/rwenv/envs.json
touch ~/.claude/rwenv/env-consumers.json
```
