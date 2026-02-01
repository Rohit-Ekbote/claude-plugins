#!/usr/bin/env bash
# transform-commands.sh - Command transformation and safety enforcement for rwenv
#
# This hook intercepts kubectl, helm, flux, gcloud, and vault commands,
# transforms them to run through the dev container with explicit context/project flags,
# and enforces read-only mode for protected environments.
#
# Claude Code PreToolUse hooks receive JSON on stdin and must output JSON to modify tool input.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities
source "$PLUGIN_DIR/lib/rwenv-utils.sh"

# Commands that trigger rwenv handling
RWENV_COMMANDS="kubectl|helm|flux|gcloud|vault"

# Read JSON input from stdin
INPUT_JSON=$(cat)

# Extract the command from the JSON input
# Format: {"tool_name": "Bash", "tool_input": {"command": "...", "description": "...", ...}}
ORIGINAL_CMD=$(echo "$INPUT_JSON" | jq -r '.tool_input.command // empty')

# If no command found, pass through
if [[ -z "$ORIGINAL_CMD" ]]; then
    exit 0
fi

# Extract the base command (first word)
BASE_CMD=$(echo "$ORIGINAL_CMD" | awk '{print $1}')

# Check for dangerous docker commands that could affect the dev container
if [[ "$BASE_CMD" == "docker" ]]; then
    DEV_CONTAINER=$(get_dev_container 2>/dev/null) || true

    if [[ -n "$DEV_CONTAINER" ]]; then
        # Dangerous docker operations that could stop/remove the dev container
        DANGEROUS_DOCKER_OPS="stop|rm|remove|kill|restart|pause|update"

        # Check if command targets the dev container
        if echo "$ORIGINAL_CMD" | grep -qE "docker ($DANGEROUS_DOCKER_OPS).*$DEV_CONTAINER"; then
            cat >&2 <<EOF
ERROR: Cannot modify the dev container '$DEV_CONTAINER'.

Blocked command: $ORIGINAL_CMD

The dev container is required for rwenv operations. Stopping, removing,
or restarting it would break kubectl/helm/flux/gcloud command execution.

If you need to restart the container, do so manually outside of Claude Code.
EOF
            exit 2
        fi

        # Also check for docker commands that affect all containers
        if echo "$ORIGINAL_CMD" | grep -qE "docker (stop|rm|kill|restart|pause) -a|docker container prune|docker system prune"; then
            cat >&2 <<EOF
ERROR: Cannot run bulk container operations.

Blocked command: $ORIGINAL_CMD

This could affect the dev container '$DEV_CONTAINER' which is required
for rwenv operations.

Use specific container names instead of bulk operations.
EOF
            exit 2
        fi
    fi

    # Allow other docker commands (like docker ps, docker logs, etc.)
    exit 0
fi

# Check if this command should be handled by rwenv
if ! echo "$BASE_CMD" | grep -qE "^($RWENV_COMMANDS)$"; then
    # Not an rwenv command, pass through unchanged (exit 0 with no output)
    exit 0
fi

# Get current working directory
CWD="${PWD}"

# Function to display no-rwenv error and exit
show_no_rwenv_error() {
    cat >&2 <<'EOF'
ERROR: No rwenv configured for this project.

Run: /rwenv-set <environment>

Available environments:
EOF

    # List available rwenvs with name and description
    if envs=$(load_envs 2>/dev/null); then
        echo "$envs" | jq -r '.rwenvs | to_entries[] | "  \(.key) - \(.value.description) (\(.value.type))"' >&2
    else
        echo "  (none configured)" >&2
    fi

    echo >&2  # Empty line after environment list
    exit 2  # Exit code 2 blocks command and shows stderr to Claude
}

# Check if rwenv is set for current directory
# get_current_rwenv returns exit 1 if .claude/rwenv file doesn't exist
if ! CURRENT_RWENV=$(get_current_rwenv "$CWD" 2>/dev/null); then
    show_no_rwenv_error
fi

# Also handle case where file exists but is empty
if [[ -z "$CURRENT_RWENV" ]]; then
    show_no_rwenv_error
fi

# Load rwenv configuration
RWENV_CONFIG=$(get_rwenv_by_name "$CURRENT_RWENV") || {
    echo "ERROR: rwenv '$CURRENT_RWENV' not found in configuration." >&2
    exit 2
}

# Extract rwenv properties
RWENV_TYPE=$(echo "$RWENV_CONFIG" | jq -r '.type')
KUBECONFIG_PATH=$(echo "$RWENV_CONFIG" | jq -r '.kubeconfigPath')
K8S_CONTEXT=$(echo "$RWENV_CONFIG" | jq -r '.kubernetesContext')
GCP_PROJECT=$(echo "$RWENV_CONFIG" | jq -r '.gcpProject // empty')
READ_ONLY=$(echo "$RWENV_CONFIG" | jq -r '.readOnly')

# Get execution mode
USE_DEV_CONTAINER=$(get_use_dev_container)
DEV_CONTAINER=$(get_dev_container)

# Handle dev container mode
if [[ "$USE_DEV_CONTAINER" == "true" ]]; then
    # Check if dev container is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DEV_CONTAINER}$"; then
        cat >&2 <<EOF
Dev container '$DEV_CONTAINER' is not running.

Options:
1. Start the container and retry
2. Switch to local mode (requires kubectl/helm/flux installed locally)

To switch to local mode, run: /rwenv-local-mode
EOF
        exit 2
    fi
fi

# Extract command arguments (everything after the base command)
CMD_ARGS=$(echo "$ORIGINAL_CMD" | cut -d' ' -f2-)

# Function to check and block write operations
check_write_operation() {
    local cmd="$1"
    local args="$2"
    local cmd_type="$3"

    if [[ "$READ_ONLY" != "true" ]]; then
        return 0  # Not read-only, allow everything
    fi

    local is_write=false

    case "$cmd_type" in
        kubectl)
            if is_kubectl_write_operation "$args"; then
                is_write=true
            fi
            ;;
        helm)
            if is_helm_write_operation "$args"; then
                is_write=true
            fi
            ;;
        flux)
            if is_flux_write_operation "$args"; then
                is_write=true
            fi
            ;;
        gcloud)
            # gcloud is ALWAYS read-only regardless of rwenv setting
            if is_gcloud_write_operation "$args"; then
                is_write=true
            fi
            ;;
    esac

    if [[ "$is_write" == "true" ]]; then
        cat >&2 <<EOF
ERROR: rwenv '$CURRENT_RWENV' is read-only. Cannot execute write operation.

Blocked command: $cmd $args

Read-only environments block:
  - kubectl: apply, delete, patch, create, edit, replace, scale
  - helm: install, upgrade, uninstall, rollback
  - flux: reconcile, suspend, resume

Use a non-read-only environment for write operations.
EOF
        exit 2
    fi
}

# Function to check gcloud availability for k3s
check_gcloud_for_k3s() {
    if [[ "$BASE_CMD" == "gcloud" && "$RWENV_TYPE" == "k3s" ]]; then
        cat >&2 <<EOF
ERROR: gcloud not available for k3s rwenv '$CURRENT_RWENV'.

gcloud commands require a GKE environment with a configured GCP project.

Current rwenv type: k3s
Use a GKE rwenv for gcloud operations.
EOF
        exit 2
    fi
}

# Build the transformed command based on the base command
build_transformed_command() {
    local cmd_prefix=""
    local kubeconfig_flag=""

    if [[ "$USE_DEV_CONTAINER" == "true" ]]; then
        # Dev container mode: use docker exec with full kubeconfig path
        cmd_prefix="docker exec -i $DEV_CONTAINER"
        kubeconfig_flag="--kubeconfig=$KUBECONFIG_PATH"
    fi

    case "$BASE_CMD" in
        kubectl)
            check_write_operation "$BASE_CMD" "$CMD_ARGS" "kubectl"
            if [[ -n "$cmd_prefix" ]]; then
                echo "$cmd_prefix kubectl $kubeconfig_flag --context=$K8S_CONTEXT $CMD_ARGS"
            else
                echo "kubectl --context=$K8S_CONTEXT $CMD_ARGS"
            fi
            ;;
        helm)
            check_write_operation "$BASE_CMD" "$CMD_ARGS" "helm"
            if [[ -n "$cmd_prefix" ]]; then
                echo "$cmd_prefix helm $kubeconfig_flag --kube-context=$K8S_CONTEXT $CMD_ARGS"
            else
                echo "helm --kube-context=$K8S_CONTEXT $CMD_ARGS"
            fi
            ;;
        flux)
            check_write_operation "$BASE_CMD" "$CMD_ARGS" "flux"
            if [[ -n "$cmd_prefix" ]]; then
                echo "$cmd_prefix flux $kubeconfig_flag --context=$K8S_CONTEXT $CMD_ARGS"
            else
                echo "flux --context=$K8S_CONTEXT $CMD_ARGS"
            fi
            ;;
        gcloud)
            check_gcloud_for_k3s
            if is_gcloud_write_operation "$CMD_ARGS"; then
                cat >&2 <<EOF
ERROR: gcloud write operations are blocked for safety.

Blocked command: gcloud $CMD_ARGS

gcloud is always read-only regardless of rwenv settings.
EOF
                exit 2
            fi
            if [[ -n "$cmd_prefix" ]]; then
                echo "$cmd_prefix gcloud --project=$GCP_PROJECT $CMD_ARGS"
            else
                echo "gcloud --project=$GCP_PROJECT $CMD_ARGS"
            fi
            ;;
        vault)
            if [[ -n "$cmd_prefix" ]]; then
                echo "$cmd_prefix vault $CMD_ARGS"
            else
                echo "vault $CMD_ARGS"
            fi
            ;;
        *)
            echo "$ORIGINAL_CMD"
            ;;
    esac
}

# Main execution
TRANSFORMED_CMD=$(build_transformed_command)

# Output JSON with the modified tool_input
# The hook must return JSON with the modified tool_input to change the command
echo "$INPUT_JSON" | jq --arg cmd "$TRANSFORMED_CMD" '.tool_input.command = $cmd'
