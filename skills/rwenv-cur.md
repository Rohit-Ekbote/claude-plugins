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

1. **Read the consumer mapping** at `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/env-consumers.json`

2. **Look up the current directory** (and parent directories for worktree support) in the mapping

3. **If no rwenv is set for this directory**, display:
```
No rwenv set for current directory.

Current directory: /Users/rohitekbote/wd/myproject

Use /rwenv-list to see available environments.
Use /rwenv-set <name> to select an environment for this directory.
```

4. **If rwenv is set**, read its full configuration from `envs.json` and display:

```
Current rwenv: rdebug

Type:        k3s
Description: VM based dev setup (k3s)
Context:     rdebug-61
Kubeconfig:  /root/.kube/config
Read-Only:   No
GCP Project: N/A
Flux Repo:   https://gitea.rdebug-61.local.runwhen.com/platform-setup/runwhen-platform-self-hosted-local-dev

Services:
  papi:      https://papi.rdebug-61.local.runwhen.com
  app:       https://app.rdebug-61.local.runwhen.com
  vault:     https://vault.rdebug-61.local.runwhen.com
  gitea:     https://gitea.rdebug-61.local.runwhen.com
  minio:     https://minio-console.rdebug-61.local.runwhen.com
  agentfarm: https://agentfarm.rdebug-61.local.runwhen.com

Directory mapping: /Users/rohitekbote/wd/myproject -> rdebug
```

5. **For GKE environments**, also show the GCP project:
```
Current rwenv: gke-prod

Type:        gke
Description: GKE production cluster
Context:     gke_project_region_cluster
Kubeconfig:  /root/.kube/gke-prod.config
Read-Only:   Yes
GCP Project: my-gcp-project
Flux Repo:   https://github.com/org/flux-repo

Services:
  papi: https://papi.prod.example.com

Directory mapping: /Users/rohitekbote/wd/project-b -> gke-prod

WARNING: This environment is READ-ONLY. Write operations will be blocked.
```

6. **If the rwenv name in consumer mapping doesn't exist in envs.json**, display:
```
ERROR: rwenv 'old-env' configured for this directory but not found in envs.json.

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
