---
name: rwenv-cur
description: Show the current rwenv environment for this directory
triggers:
  - /rwenv-cur
  - current rwenv
  - what environment am I using
  - show current environment
  - which rwenv
---

# Show Current RunWhen Environment

Display the full details of the rwenv configured for the current working directory.

## Instructions

1. **Check for runtime config** at `.claude/rwenv-env` in the current working directory

2. **If `.claude/rwenv-env` exists**, source it and display all values:

```
Current rwenv: $RWENV_NAME

Type:        $RWENV_TYPE
Mode:        $RWENV_MODE
Context:     $RWENV_CONTEXT
Kubeconfig:  $RWENV_KUBECONFIG
Read-Only:   $RWENV_READ_ONLY
GCP Project: $RWENV_GCP_PROJECT
Dev Container: $RWENV_DEV_CONTAINER
Flux Repo:   $RWENV_FLUX_REPO

Project config: .claude/rwenv-env
```

For read-only environments, add warning:
```
WARNING: This environment is READ-ONLY. Write operations will be blocked.
```

3. **If `.claude/rwenv-env` does NOT exist**, show error and fall back to listing available environments by reading `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json`:

```
No rwenv configured for this project. Run /rwenv-set <environment>

Current directory: /path/to/project

Available environments:
  - rdebug     VM based dev setup (k3s)
  - gke-prod   GKE production cluster

Use /rwenv-set <name> to configure an environment for this project.
```

4. **Error handling**: if envs.json doesn't exist, suggest running setup. If JSON parsing fails, report error.
