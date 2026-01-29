# rwenv - Multi-Cluster Environment Management for Claude Code

A Claude Code plugin for managing Kubernetes environments. Enables safe interaction with GKE and k3s clusters through a dev container, with automatic context injection and safety enforcement.

## Features

- **Environment Switching** - Switch between GKE/k3s environments per working directory
- **Command Transformation** - kubectl/helm/flux/gcloud commands automatically run through dev container with explicit context flags
- **Write Protection** - Enforce read-only mode for sensitive environments
- **Git Safety** - Protect main/master/production branches from direct commits

## Installation

Clone the repository and install as a local plugin:

```bash
git clone https://github.com/Rohit-Ekbote/rwenv.git ~/.claude/plugins/rwenv
claude plugins install ~/.claude/plugins/rwenv
```

## Configuration

Create the configuration directory and add your environments:

```bash
mkdir -p ~/.claude/rwenv
cp ~/.claude/plugins/rwenv/config/envs.example.json ~/.claude/rwenv/envs.json
```

Edit `~/.claude/rwenv/envs.json` with your environment details:

```json
{
  "version": "1.0",
  "devContainer": "your-dev-container-name",
  "rwenvs": {
    "dev": {
      "description": "Development cluster",
      "type": "k3s",
      "kubeconfigPath": "/root/.kube/config",
      "kubernetesContext": "my-k3s-context",
      "readOnly": false
    },
    "prod": {
      "description": "Production cluster",
      "type": "gke",
      "kubeconfigPath": "/root/.kube/gke.config",
      "kubernetesContext": "gke_project_region_cluster",
      "gcpProject": "my-gcp-project",
      "readOnly": true
    }
  }
}
```

## Usage

```
/rwenv-list          # List available environments
/rwenv-set <name>    # Set environment for current directory
/rwenv-cur           # View current environment details
/rwenv-add           # Interactively create a new environment
```

Once an environment is set, kubectl/helm/flux/gcloud commands are automatically transformed to run through the dev container with the correct context.

## Safety Features

### Dev Container Protection

The dev container cannot be stopped, removed, or restarted by Claude:
- Blocks: `docker stop`, `docker rm`, `docker kill`, `docker restart`, `docker pause`
- Blocks bulk operations: `docker stop -a`, `docker container prune`, `docker system prune`

### Read-Only Environments

When `readOnly: true`, write operations are blocked:
- kubectl: apply, delete, patch, create, edit, replace, scale
- helm: install, upgrade, uninstall, rollback
- flux: reconcile, suspend, resume

### Always Read-Only

- **gcloud** - Write operations always blocked
- **Database queries** - Only SELECT allowed (via db-ops subagent)

### Git Branch Protection

In the current project:
- Cannot commit/push/merge to main/master/production branches
- Cannot create or push tags

External repos (flux repos, etc.) are not restricted.

## Requirements

- Claude Code CLI
- Docker with dev container running
- `jq` for JSON processing

## License

MIT
