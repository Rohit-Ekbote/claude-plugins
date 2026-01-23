---
name: rwenv-set
description: Set the active rwenv environment for the current directory
triggers:
  - /rwenv-set
  - switch to
  - use rwenv
  - set environment
  - change environment
args:
  - name: rwenv_name
    description: Name of the rwenv to activate (optional - will prompt if not provided)
    required: false
---

# Set RunWhen Environment

Select an rwenv environment to use for the current working directory.

## Instructions

### Step 1: Determine the target rwenv

**If rwenv name is provided** (e.g., `/rwenv-set rdebug`):
- Validate that the rwenv exists in `envs.json`
- If not found, show error with available options

**If no rwenv name is provided**:
- List all available environments using the format from `/rwenv-list`
- Ask the user to select one using AskUserQuestion tool

### Step 2: Check for existing mapping

Read `env-consumers.json` to see if current directory already has an rwenv set.

**If same rwenv is already set**:
```
rwenv 'rdebug' is already active for this directory.

Use /rwenv-cur to see full details.
```

**If different rwenv is set**, ask for confirmation:
```
Current rwenv: gke-prod (GKE production cluster, READ-ONLY)
Requested:     rdebug (VM based dev setup, read-write)

Switch from 'gke-prod' to 'rdebug'?
```

Use AskUserQuestion with options:
- "Yes, switch to rdebug"
- "No, keep gke-prod"

### Step 3: Update the mapping

1. Read `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/env-consumers.json`
2. Add/update entry: `"<current_directory>": "<rwenv_name>"`
3. Write the updated JSON back to the file
4. Create the file if it doesn't exist

### Step 4: Display confirmation

```
rwenv set to 'rdebug' for /Users/rohitekbote/wd/myproject

Environment Details:
  Type:        k3s
  Description: VM based dev setup (k3s)
  Context:     rdebug-61
  Read-Only:   No

All kubectl, helm, and flux commands will now use:
  - Context: rdebug-61
  - Kubeconfig: /root/.kube/config

Use /rwenv-cur for full details.
```

**For read-only environments**, add warning:
```
WARNING: This environment is READ-ONLY.
The following operations will be blocked:
  - kubectl apply, delete, patch, create, edit, replace, scale
  - helm install, upgrade, uninstall, rollback
  - flux reconcile, suspend, resume
```

## Error Handling

**rwenv not found:**
```
ERROR: rwenv 'foo' not found.

Available environments:
  - rdebug (k3s, VM based dev setup)
  - gke-prod (gke, GKE production cluster)

Use /rwenv-set <name> with one of the above.
```

**Config directory doesn't exist:**
```
ERROR: rwenv config directory not found at ~/.claude/rwenv/

Please set up rwenv first:
1. Create directory: mkdir -p ~/.claude/rwenv
2. Copy example config: cp config/envs.example.json ~/.claude/rwenv/envs.json
3. Edit with your environment details
```

**Permission error writing to env-consumers.json:**
```
ERROR: Cannot write to ~/.claude/rwenv/env-consumers.json

Check file permissions and try again.
```

## Natural Language Handling

When user says things like:
- "switch to rdebug" → extract "rdebug" as rwenv_name
- "use gke-prod environment" → extract "gke-prod" as rwenv_name
- "change to production" → if "production" doesn't match, suggest closest match or list all
