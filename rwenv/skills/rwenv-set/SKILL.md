---
name: rwenv-set
description: Set the active rwenv environment for the current project (stored locally in .claude/rwenv)
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

Select an rwenv environment to use for the current project directory. The selection is stored locally in `.claude/rwenv` within the project (auto-gitignored).

## Instructions

### Step 1: Determine the target rwenv

**If rwenv name is provided** (e.g., `/rwenv-set rdebug`):
- Validate that the rwenv exists in `envs.json`
- If not found, show error with available options

**If no rwenv name is provided**:
- List all available environments using the format from `/rwenv-list`
- Ask the user to select one using AskUserQuestion tool

### Step 2: Check for existing mapping

Read `.claude/rwenv` in the current project directory to see if an rwenv is already set.

**If same rwenv is already set**:
```
rwenv 'rdebug' is already active for this project.

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

Use `set_rwenv_for_dir()` from `rwenv-utils.sh`:

1. Creates `.claude/` directory in the project if needed
2. Writes rwenv name to `.claude/rwenv`
3. Auto-adds `.claude/rwenv` to `.gitignore` (if git repo)

**Implementation:**
```bash
source "$RWENV_PLUGIN_DIR/lib/rwenv-utils.sh"
set_rwenv_for_dir "$PWD" "<rwenv_name>"
```

### Step 4: Display confirmation

```
rwenv set to 'rdebug' for this project
Stored in: /Users/rohitekbote/wd/myproject/.claude/rwenv (auto-gitignored)

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

**Permission error writing to project .claude directory:**
```
ERROR: Cannot write to <project>/.claude/rwenv

Check directory permissions and try again.
```

## Natural Language Handling

When user says things like:
- "switch to rdebug" → extract "rdebug" as rwenv_name
- "use gke-prod environment" → extract "gke-prod" as rwenv_name
- "change to production" → if "production" doesn't match, suggest closest match or list all
