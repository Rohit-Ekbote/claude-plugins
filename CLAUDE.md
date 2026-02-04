# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code plugin marketplace containing infrastructure and Kubernetes environment management tools. The main plugin is **rwenv**, which provides multi-cluster GKE and k3s environment management with automatic safety enforcement.

## Architecture

### Command Flow

```
User runs: kubectl get pods
         ↓
PreToolUse hook (transform-commands.sh)
         ↓
Checks: rwenv set? → dev container running? → read-only mode?
         ↓
Transforms to: docker exec -i <container> kubectl --kubeconfig=<path> --context=<ctx> get pods
         ↓
Returns modified JSON to Claude Code
```

### Skills vs Agents

| Concept | Location | Invoked By | Purpose |
|---------|----------|------------|---------|
| **Skills** | `skills/<name>/SKILL.md` | User via `/skill-name` | Interactive workflows with prompts |
| **Agents** | `agents/<name>.md` | Task tool `subagent_type` | Autonomous operations |

Skills guide Claude through multi-step workflows. Agents are specialized subprocesses for specific domains (k8s-ops, db-ops, gcloud-ops, flux-ops).

### Configuration Hierarchy

- **Global config**: `~/.claude/rwenv/envs.json` defines all rwenvs
- **Per-project**: `./.claude/rwenv` stores active rwenv name (auto-gitignored)
- **Plugin data**: `rwenv/data/infra-catalog.json` maps services → namespaces

### Safety Enforcement

Hooks enforce safety at three levels:
1. **Pre-execution**: Require rwenv set, dev container running
2. **Command classification**: Block write ops in read-only mode
3. **Git protection**: Block commits to main/master/production

## Key Files

| File | Purpose |
|------|---------|
| `rwenv/lib/rwenv-utils.sh` | Core utilities (~550 lines): config loading, command builders, write detection |
| `rwenv/hooks/transform-commands.sh` | PreToolUse hook that intercepts kubectl/helm/flux/gcloud |
| `rwenv/hooks/validate-git.sh` | PreToolUse hook that enforces branch protection |
| `rwenv/data/infra-catalog.json` | Service → namespace/port mapping |

## Development

### Testing Changes

No test framework. Test manually with Claude Code:
```bash
# Test hook transformation
claude --print "kubectl get pods"

# Test skill
claude "/rwenv-list"
```

### Adding a New Skill

1. Create `rwenv/skills/<name>/SKILL.md` with YAML frontmatter:
   ```yaml
   ---
   name: skill-name
   description: One-line description
   triggers:
     - /skill-name
     - natural language trigger
   ---
   ```
2. Add instructions in markdown body - this IS the specification
3. Test with `/skill-name` in Claude Code

### Adding a New Agent

1. Create `rwenv/agents/<name>.md` with YAML frontmatter:
   ```yaml
   ---
   name: agent-name
   description: One-line description for Task tool
   triggers:
     - when to use this agent
   ---
   ```
2. Document capabilities, command patterns, error handling
3. Agent invoked via `Task` tool with `subagent_type: "rwenv:agent-name"`

### Exit Codes (for hooks)

- `0`: Success/allow command (output JSON to modify, or nothing to pass through)
- `1`: Soft error (continue)
- `2`: Block command (stderr shown to Claude)

### Bash Compatibility

Scripts must work with bash 3.2 (macOS default). Avoid:
- `declare -A` (associative arrays)
- `${var,,}` (lowercase expansion)
- `|&` (pipe stderr)

## Version Bumping

Update version in `rwenv/.claude-plugin/plugin.json`.
