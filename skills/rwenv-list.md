---
name: rwenv-list
description: List all available rwenv environments
triggers:
  - /rwenv-list
  - list environments
  - show rwenvs
  - list rwenvs
  - what environments are available
---

# List RunWhen Environments

List all configured rwenv environments showing their type, description, and status.

## Instructions

1. **Read the configuration file** at `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json`

2. **Read the consumer mapping** at `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/env-consumers.json` to determine which rwenv is active for the current directory

3. **Display a formatted table** with the following columns:
   - Name (with `*` indicator if active for current directory)
   - Type (k3s or gke)
   - Description
   - Read-Only status

4. **Example output format:**

```
RunWhen Environments:

  NAME        TYPE   DESCRIPTION                  READ-ONLY
* rdebug      k3s    VM based dev setup (k3s)     No
  gke-prod    gke    GKE production cluster       Yes
  gke-staging gke    GKE staging cluster          No

* = active for current directory (/Users/rohitekbote/wd/myproject)

Use /rwenv-set <name> to switch environments.
Use /rwenv-cur to see full details of the current environment.
```

5. **If no environments are configured**, show:
```
No rwenv environments configured.

Create ~/.claude/rwenv/envs.json with your environment definitions.
See config/envs.example.json for a template.
```

6. **If config directory doesn't exist**, show:
```
rwenv config directory not found at ~/.claude/rwenv/

To set up rwenv:
1. Create the directory: mkdir -p ~/.claude/rwenv
2. Copy the example config: cp config/envs.example.json ~/.claude/rwenv/envs.json
3. Edit the config with your environment details
```

## Error Handling

- If `envs.json` is malformed, report the JSON parsing error
- If `env-consumers.json` doesn't exist, proceed without active indicator (no rwenv selected)
