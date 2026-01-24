# rwenv - RunWhen Environment Management for Claude Code

A Claude Code plugin for managing multi-cluster Kubernetes environments. Enables safe interaction with GKE and k3s clusters through a dev container, with automatic context injection and safety enforcement.

## Features

- **Environment Switching** - Easily switch between GKE/k3s environments per working directory
- **Command Safety** - Commands automatically run through dev container with explicit `--context`/`--project` flags
- **Write Protection** - Enforce read-only mode for sensitive environments; gcloud and database always read-only
- **Git Safety** - Protect main branch in current project while allowing main in rwenv repos

## Installation

```bash
claude plugins add Rohit-Ekbote/rwenv
```

## Quick Start

1. **Set up configuration**
   ```bash
   mkdir -p ~/.claude/rwenv
   # Create envs.json with your environment details (see config/envs.example.json)
   ```

2. **Select an environment**
   ```
   /rwenv-list          # See available environments
   /rwenv-set rdebug    # Select environment for current directory
   /rwenv-cur           # View current environment details
   ```

3. **Use kubectl/helm/flux/gcloud as normal** - commands are automatically transformed

## Skills

| Skill | Description |
|-------|-------------|
| `/rwenv-list` | List all configured environments |
| `/rwenv-cur` | Show current environment for this directory |
| `/rwenv-set <name>` | Set environment for current directory |
| `/rwenv-add` | Interactively create a new environment |

## Safety Features

### Read-Only Environments

When `readOnly: true`:
- Blocks: `kubectl apply/delete/patch/create`, `helm install/upgrade/uninstall`, `flux reconcile/suspend/resume`
- Allows: `get`, `describe`, `logs`, `exec`, `top`

### Always Read-Only

These are always read-only regardless of environment settings:
- **gcloud** - All write operations blocked
- **Database** - Only SELECT queries allowed

### Git Branch Protection

In the current project directory:
- Cannot commit directly to main/master/production
- Cannot push to protected branches
- Cannot merge into protected branches
- Cannot create, delete, or push tags

External repos (flux repos, etc.) are not restricted.

## Directory Structure

```
rwenv/
├── .claude-plugin/
│   └── plugin.json        # Plugin metadata
├── config/
│   └── envs.example.json  # Example configuration
├── skills/
│   ├── rwenv-list.md      # List environments
│   ├── rwenv-cur.md       # Show current environment
│   ├── rwenv-set.md       # Set environment
│   ├── rwenv-add.md       # Add new environment
│   └── services-mapping.md # Map services to K8s resources
├── hooks/
│   ├── hooks.json         # Hook declarations
│   ├── transform-commands.sh  # Command transformation
│   └── validate-git.sh    # Git branch protection
├── subagents/
│   ├── k8s-ops.md         # Kubernetes operations
│   ├── db-ops.md          # Database queries
│   ├── flux-ops.md        # Flux GitOps operations
│   └── gcloud-ops.md      # GCP operations
├── scripts/
│   ├── pg_query.sh        # Database query script
│   └── command-builder.sh # Command wrapper
├── lib/
│   └── rwenv-utils.sh     # Shared utilities
└── docs/
    ├── INSTALLATION.md    # Installation guide
    ├── USAGE.md           # Usage guide
    └── CONFIGURATION.md   # Configuration reference
```

## Configuration

Configuration lives outside the plugin at `~/.claude/rwenv/` (configurable via `RWENV_CONFIG_DIR`):

- `envs.json` - Environment definitions and database configs
- `env-consumers.json` - Directory to environment mappings

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for full reference.

## Documentation

- [Installation Guide](docs/INSTALLATION.md)
- [Usage Guide](docs/USAGE.md)
- [Configuration Reference](docs/CONFIGURATION.md)

## Requirements

- Claude Code CLI
- Docker with dev container running (`alpine-dev-container-zsh-rdebug` by default)
- `jq` for JSON processing

## License

MIT
