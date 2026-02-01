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

1. **Read the project-local config** at `.claude/rwenv` in the current working directory

2. **If no `.claude/rwenv` file exists**, display an error with available environments:
```
No rwenv configured for this project. Run /rwenv-set <environment>

Current directory: /Users/rohitekbote/wd/myproject

Available environments:
  - rdebug     VM based dev setup (k3s)
  - gke-prod   GKE production cluster

Use /rwenv-set <name> to configure an environment for this project.
```

To list available environments, read `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json` and display all entries under `.rwenvs`.

3. **If rwenv is set**, read its full configuration from `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json` and display:

```
Current rwenv: rdebug

Type:        k3s
Description: VM based dev setup (k3s)
Context:     rdebug-61
Kubeconfig:  /root/.kube/config
Read-Only:   No
Exec Mode:   Dev Container (alpine-dev-container-zsh-rdebug)
GCP Project: N/A
Flux Repo:   https://gitea.rdebug-61.local.runwhen.com/platform-setup/runwhen-platform-self-hosted-local-dev

Services:
  papi:      https://papi.rdebug-61.local.runwhen.com
  app:       https://app.rdebug-61.local.runwhen.com
  vault:     https://vault.rdebug-61.local.runwhen.com
  gitea:     https://gitea.rdebug-61.local.runwhen.com
  minio:     https://minio-console.rdebug-61.local.runwhen.com
  agentfarm: https://agentfarm.rdebug-61.local.runwhen.com

Project config: .claude/rwenv -> rdebug
```

4. **Show execution mode**:
   - Read `useDevContainer` from `envs.json` (defaults to `true`)
   - If `true`: `Exec Mode:   Dev Container (<devContainer name>)`
   - If `false`: `Exec Mode:   Local (tools from PATH)`

5. **For GKE environments**, also show the GCP project:
```
Current rwenv: gke-prod

Type:        gke
Description: GKE production cluster
Context:     gke_project_region_cluster
Kubeconfig:  /root/.kube/gke-prod.config
Read-Only:   Yes
Exec Mode:   Dev Container (alpine-dev-container-zsh-gke-prod)
GCP Project: my-gcp-project
Flux Repo:   https://github.com/org/flux-repo

Services:
  papi: https://papi.prod.example.com

Project config: .claude/rwenv -> gke-prod

WARNING: This environment is READ-ONLY. Write operations will be blocked.
```

6. **If the rwenv name in `.claude/rwenv` doesn't exist in envs.json**, display:
```
ERROR: rwenv 'old-env' configured for this project but not found in envs.json.

This may happen if:
- The environment was deleted from envs.json
- The config file was updated by another user

Use /rwenv-set <name> to select a valid environment.
Available environments: rdebug, gke-prod
```

## Error Handling

- If `envs.json` doesn't exist, suggest running setup
- If JSON parsing fails, report the specific error
- Handle missing fields gracefully with "N/A" defaults
