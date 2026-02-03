# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code plugin marketplace containing infrastructure and Kubernetes environment management tools. The main plugin is **rwenv** (v0.3.0), which provides multi-cluster GKE and k3s environment management with automatic safety enforcement.

## Repository Structure

```
claude-plugins/
├── .claude-plugin/marketplace.json   # Marketplace registration
└── rwenv/                            # Main plugin
    ├── .claude-plugin/plugin.json    # Plugin metadata
    ├── agents/                       # Subagent definitions (db-ops, k8s-ops, gcloud-ops, flux-ops)
    ├── skills/                       # User-facing CLI skills (9 skills)
    ├── hooks/                        # PreToolUse hooks (transform-commands.sh, validate-git.sh)
    ├── lib/rwenv-utils.sh            # Shared utility library (~544 lines)
    ├── scripts/                      # Helper scripts (pg_query.sh, command-builder.sh)
    ├── config/                       # Example configurations
    └── data/                         # Infrastructure catalog (infra-catalog.json)
```

## Architecture

**Hook-Based Command Transformation**: Commands (kubectl, helm, flux, gcloud, vault) are intercepted by `transform-commands.sh` and transformed to run through a dev container with explicit `--kubeconfig`, `--context`, and `--project` flags.

**Three-Layer Safety Enforcement**:
1. Pre-hook validation (dev container running, rwenv set)
2. Operation classification (write ops blocked in read-only mode)
3. Git branch protection (main/master/production protected in current project)

**Configuration Hierarchy**:
- Global: `~/.claude/rwenv/envs.json` (or `$RWENV_CONFIG_DIR`)
- Per-project: `./.claude/rwenv` (stores active rwenv name, auto-gitignored)

## Key Files

| File | Purpose |
|------|---------|
| `rwenv/lib/rwenv-utils.sh` | Core utilities: config loading, command builders, write detection, SQL validation |
| `rwenv/hooks/transform-commands.sh` | Intercepts and transforms kubectl/helm/flux/gcloud commands |
| `rwenv/hooks/validate-git.sh` | Blocks git operations on protected branches |
| `rwenv/scripts/pg_query.sh` | Executes read-only DB queries via K8s port-forward |
| `rwenv/data/infra-catalog.json` | Services, databases, Flux resources mapping |

## Development Patterns

**Skill Definition**: Skills are defined in `SKILL.md` files with YAML frontmatter (metadata) + markdown body (instructions). The documentation IS the specification.

**Write Operation Detection** (in `rwenv-utils.sh`):
- kubectl: `apply|delete|patch|create|edit|replace|scale`
- helm: `install|upgrade|uninstall|rollback`
- flux: `reconcile|suspend|resume`
- gcloud: Always blocked
- SQL: `INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE` blocked

**Exit Codes**:
- `0`: Success/allow command
- `1`: Soft error (continue)
- `2`: Block command (print to stderr)

**Bash Compatibility**: Scripts must work with bash 3.2 (macOS default).

## Testing

No automated test framework. Testing is manual via Claude Code CLI. Changes are validated through iterative commits.

## Version Bumping

Update version in `rwenv/.claude-plugin/plugin.json`.
