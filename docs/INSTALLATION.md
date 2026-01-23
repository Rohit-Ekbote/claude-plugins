# Installation Guide

## Prerequisites

Before installing the rwenv plugin, ensure you have:

1. **Claude Code CLI** installed and configured
2. **Docker** installed and running
3. **Dev container** running (default: `alpine-dev-container-zsh-rdebug`)
4. **jq** installed for JSON processing

## Step 1: Get the Plugin

### Option A: Clone from Git

```bash
git clone https://github.com/your-org/rwenv-plugin.git ~/plugins/rwenv-plugin
```

### Option B: Copy Locally

```bash
cp -r /path/to/rwenv-plugin ~/plugins/rwenv-plugin
```

## Step 2: Add Plugin to Claude Code

```bash
claude plugins add ~/plugins/rwenv-plugin
```

Verify installation:
```bash
claude plugins list
```

## Step 3: Create Configuration Directory

The rwenv configuration lives outside the plugin for flexibility:

```bash
mkdir -p ~/.claude/rwenv
```

## Step 4: Create Configuration Files

### envs.json

Copy the example configuration:

```bash
cp ~/plugins/rwenv-plugin/config/envs.example.json ~/.claude/rwenv/envs.json
```

Edit with your environment details:

```bash
$EDITOR ~/.claude/rwenv/envs.json
```

Example configuration:

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
    }
  },
  "rwenvs": {
    "dev": {
      "description": "Local k3s development",
      "type": "k3s",
      "kubeconfigPath": "/root/.kube/config",
      "kubernetesContext": "k3s-local",
      "readOnly": false,
      "fluxGitRepo": "https://github.com/org/flux-dev"
    },
    "prod": {
      "description": "GKE production cluster",
      "type": "gke",
      "kubeconfigPath": "/root/.kube/gke-prod.config",
      "kubernetesContext": "gke_myproject_us-central1_prod",
      "gcpProject": "myproject-prod",
      "readOnly": true,
      "fluxGitRepo": "https://github.com/org/flux-prod"
    }
  }
}
```

### env-consumers.json (Optional)

This file is created automatically when you use `/rwenv-set`. You can also create it manually:

```bash
echo '{}' > ~/.claude/rwenv/env-consumers.json
```

## Step 5: Verify Dev Container

Ensure your dev container is running:

```bash
docker ps | grep alpine-dev-container-zsh-rdebug
```

If not running, start it according to your setup.

## Step 6: Test Installation

In Claude Code:

```
/rwenv-list
```

You should see your configured environments listed.

## Custom Configuration Location

To use a different configuration directory, set the `RWENV_CONFIG_DIR` environment variable:

```bash
export RWENV_CONFIG_DIR=/path/to/custom/rwenv
```

Or for team-shared configuration:

```bash
export RWENV_CONFIG_DIR=/shared/team/rwenv
```

## Troubleshooting

### "No rwenv environments configured"

- Check that `~/.claude/rwenv/envs.json` exists
- Verify the JSON is valid: `jq . ~/.claude/rwenv/envs.json`

### "Dev container not running"

- Start your dev container
- Verify container name matches `devContainer` in envs.json

### "Plugin not found"

- Run `claude plugins list` to verify installation
- Try reinstalling: `claude plugins remove rwenv && claude plugins add /path/to/rwenv-plugin`

### "Permission denied"

- Check file permissions on config directory
- Ensure scripts are executable: `chmod +x ~/plugins/rwenv-plugin/hooks/*.sh ~/plugins/rwenv-plugin/scripts/*.sh`

## Updating the Plugin

To update to a new version:

```bash
cd ~/plugins/rwenv-plugin
git pull origin main
```

Your configuration in `~/.claude/rwenv/` is preserved during updates.

## Uninstalling

```bash
# Remove plugin
claude plugins remove rwenv

# Optionally remove configuration
rm -rf ~/.claude/rwenv
```
