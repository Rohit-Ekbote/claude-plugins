#!/usr/bin/env bash
# transform-commands.sh - Validation, safety enforcement, and auto-approval for rwenv
#
# This hook validates that kubectl/helm/flux/gcloud commands have correct
# flags and wrapping for the current mode, enforces safety (read-only, gcloud
# restrictions), and auto-approves valid commands.
#
# It does NOT transform commands — agents construct mode-aware commands themselves.
#
# Claude Code PreToolUse hooks receive JSON on stdin and must output JSON to modify tool input.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities (for write-detection functions)
source "$PLUGIN_DIR/lib/rwenv-utils.sh"

# Commands that trigger rwenv validation
RWENV_COMMANDS="kubectl|helm|flux|gcloud|vault"

# Read JSON input from stdin
INPUT_JSON=$(cat)

# Extract the command
ORIGINAL_CMD=$(echo "$INPUT_JSON" | jq -r '.tool_input.command // empty')
if [[ -z "$ORIGINAL_CMD" ]]; then
    echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
    exit 0
fi

# Source the runtime env file
RWENV_ENV_FILE="${PWD}/.claude/rwenv-env"

# Check if command contains rwenv-managed commands
CONTAINS_RWENV_CMD=false
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])($RWENV_COMMANDS)(\s|$)"; then
    CONTAINS_RWENV_CMD=true
fi

# If no env file, only block rwenv commands — let everything else through
if [[ ! -f "$RWENV_ENV_FILE" ]]; then
    if [[ "$CONTAINS_RWENV_CMD" == "true" ]]; then
        cat >&2 <<'EOF'
ERROR: No rwenv configured for this project.

Run: /rwenv-set <environment>
EOF
        exit 2
    fi
    echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
    exit 0
fi

# Source env vars
source "$RWENV_ENV_FILE"

# --- Docker safety (container mode only) ---

if [[ "$RWENV_MODE" == "container" ]] && [[ -n "${RWENV_DEV_CONTAINER:-}" ]]; then
    DANGEROUS_DOCKER_OPS="stop|rm|remove|kill|restart|pause|update"

    # Block dangerous docker ops targeting the dev container
    if echo "$ORIGINAL_CMD" | grep -qE "docker ($DANGEROUS_DOCKER_OPS).*$RWENV_DEV_CONTAINER"; then
        cat >&2 <<EOF
ERROR: Cannot modify the dev container '$RWENV_DEV_CONTAINER'.

Blocked command: $ORIGINAL_CMD

The dev container is required for rwenv operations in container mode.
If you need to restart it, do so manually outside of Claude Code.
EOF
        exit 2
    fi

    # Block bulk container operations
    if echo "$ORIGINAL_CMD" | grep -qE "docker (stop|rm|kill|restart|pause) -a|docker container prune|docker system prune"; then
        cat >&2 <<EOF
ERROR: Cannot run bulk container operations.

Blocked command: $ORIGINAL_CMD

This could affect the dev container '$RWENV_DEV_CONTAINER'.
Use specific container names instead of bulk operations.
EOF
        exit 2
    fi
fi

# If command doesn't contain rwenv commands, check for other auto-approve cases
if [[ "$CONTAINS_RWENV_CMD" == "false" ]]; then
    # Auto-approve rwenv plugin scripts (e.g., pg_query.sh) — they enforce their own safety
    if echo "$ORIGINAL_CMD" | grep -qE "rwenv/scripts/"; then
        echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
        exit 0
    fi
    # Auto-approve docker exec to dev container
    if [[ "$RWENV_MODE" == "container" ]] && [[ -n "${RWENV_DEV_CONTAINER:-}" ]]; then
        if echo "$ORIGINAL_CMD" | grep -qE "docker exec.*$RWENV_DEV_CONTAINER"; then
            echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
            exit 0
        fi
    fi
    echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
    exit 0
fi

# --- Safety checks for rwenv commands ---

# gcloud for k3s: block
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])gcloud(\s)" && [[ "$RWENV_TYPE" == "k3s" ]]; then
    cat >&2 <<EOF
ERROR: gcloud not available for k3s rwenv '$RWENV_NAME'.

gcloud commands require a GKE environment with a configured GCP project.
Current rwenv type: k3s

Use a GKE rwenv for gcloud operations.
EOF
    exit 2
fi

# gcloud writes: always block
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])gcloud(\s)"; then
    gcloud_args=$(echo "$ORIGINAL_CMD" | grep -oE "gcloud\s+.*" | head -1 | cut -d' ' -f2-)
    if is_gcloud_write_operation "$gcloud_args"; then
        cat >&2 <<EOF
ERROR: gcloud write operations are blocked for safety.

Blocked command: $ORIGINAL_CMD

gcloud is always read-only regardless of rwenv settings.
EOF
        exit 2
    fi
fi

# Read-only enforcement for kubectl/helm/flux
if [[ "$RWENV_READ_ONLY" == "true" ]]; then
    # Extract subcommand by stripping flags
    strip_flags() {
        echo "$1" | sed 's/--kubeconfig=[^ ]* *//g; s/--kube-context=[^ ]* *//g; s/--context=[^ ]* *//g; s/--project=[^ ]* *//g'
    }

    # Check kubectl write ops
    if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])kubectl(\s)"; then
        kubectl_args=$(echo "$ORIGINAL_CMD" | grep -oE "kubectl\s+[^|;&\"]*" | head -1 | sed 's/kubectl[[:space:]]*//')
        kubectl_subcmd=$(strip_flags "$kubectl_args")
        if is_kubectl_write_operation "$kubectl_subcmd"; then
            cat >&2 <<EOF
ERROR: rwenv '$RWENV_NAME' is read-only. Cannot execute write operation.

Blocked command: $ORIGINAL_CMD

Read-only environments block:
  - kubectl: apply, delete, patch, create, edit, replace, scale
  - helm: install, upgrade, uninstall, rollback
  - flux: reconcile, suspend, resume

Use a non-read-only environment for write operations.
EOF
            exit 2
        fi
    fi

    # Check helm write ops
    if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])helm(\s)"; then
        helm_args=$(echo "$ORIGINAL_CMD" | grep -oE "helm\s+[^|;&\"]*" | head -1 | sed 's/helm[[:space:]]*//')
        helm_subcmd=$(strip_flags "$helm_args")
        if is_helm_write_operation "$helm_subcmd"; then
            cat >&2 <<EOF
ERROR: rwenv '$RWENV_NAME' is read-only. Cannot execute write operation.

Blocked command: $ORIGINAL_CMD
EOF
            exit 2
        fi
    fi

    # Check flux write ops
    if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])flux(\s)"; then
        flux_args=$(echo "$ORIGINAL_CMD" | grep -oE "flux\s+[^|;&\"]*" | head -1 | sed 's/flux[[:space:]]*//')
        flux_subcmd=$(strip_flags "$flux_args")
        if is_flux_write_operation "$flux_subcmd"; then
            cat >&2 <<EOF
ERROR: rwenv '$RWENV_NAME' is read-only. Cannot execute write operation.

Blocked command: $ORIGINAL_CMD
EOF
            exit 2
        fi
    fi
fi

# --- Validation: ensure commands have required flags ---

# Helper: check a command has required flags
validate_has_flags() {
    local cmd_name="$1"
    local flag_pattern="$2"
    if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])${cmd_name}(\s)" && \
       ! echo "$ORIGINAL_CMD" | grep -qE "${cmd_name}[^|;&]*${flag_pattern}"; then
        cat >&2 <<EOF
ERROR: $cmd_name command missing required flags.

Current mode: $RWENV_MODE

Source .claude/rwenv-env to get the correct values:
  RWENV_KUBECONFIG=$RWENV_KUBECONFIG
  RWENV_CONTEXT=$RWENV_CONTEXT
EOF
        exit 2
    fi
}

# Container mode: validate docker exec wrapping
if [[ "$RWENV_MODE" == "container" ]]; then
    for cmd in kubectl helm flux; do
        if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])${cmd}(\s)"; then
            if ! echo "$ORIGINAL_CMD" | grep -qE "docker exec.*$RWENV_DEV_CONTAINER.*${cmd}"; then
                cat >&2 <<EOF
ERROR: In container mode, $cmd must run inside docker exec $RWENV_DEV_CONTAINER.

Expected pattern:
  docker exec -i $RWENV_DEV_CONTAINER $cmd --kubeconfig=\$RWENV_KUBECONFIG --context=\$RWENV_CONTEXT ...

Source .claude/rwenv-env for correct values.
EOF
                exit 2
            fi
        fi
    done
    if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])gcloud(\s)"; then
        if ! echo "$ORIGINAL_CMD" | grep -qE "docker exec.*$RWENV_DEV_CONTAINER.*gcloud"; then
            cat >&2 <<EOF
ERROR: In container mode, gcloud must run inside docker exec $RWENV_DEV_CONTAINER.

Expected pattern:
  docker exec -i $RWENV_DEV_CONTAINER gcloud --project=\$RWENV_GCP_PROJECT ...
EOF
            exit 2
        fi
    fi
fi

# Both modes: validate required flags are present
validate_has_flags "kubectl" "--kubeconfig=.*--context="
validate_has_flags "helm" "--kubeconfig=.*--kube-context="
validate_has_flags "flux" "--kubeconfig=.*--context="
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z_-])gcloud(\s)"; then
    if ! echo "$ORIGINAL_CMD" | grep -qE "gcloud[^|;&]*--project="; then
        cat >&2 <<EOF
ERROR: gcloud command missing --project flag.

Expected: gcloud --project=\$RWENV_GCP_PROJECT ...
EOF
        exit 2
    fi
fi

# --- Auto-approve: command passed all checks ---
echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
