#!/usr/bin/env bash
# transform-commands.sh - Command transformation and safety enforcement for rwenv
#
# This hook intercepts kubectl, helm, flux, gcloud, and vault commands,
# transforms them to run through the dev container with explicit context/project flags,
# and enforces read-only mode for protected environments.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities
source "$PLUGIN_DIR/lib/rwenv-utils.sh"

# Commands that trigger rwenv handling
RWENV_COMMANDS="kubectl|helm|flux|gcloud|vault"

# Parse hook input (command is passed as arguments or via stdin)
ORIGINAL_CMD="$*"

# Extract the base command (first word)
BASE_CMD=$(echo "$ORIGINAL_CMD" | awk '{print $1}')

# Check if this command should be handled by rwenv
if ! echo "$BASE_CMD" | grep -qE "^($RWENV_COMMANDS)$"; then
    # Not an rwenv command, pass through unchanged
    echo "$ORIGINAL_CMD"
    exit 0
fi

# Get current working directory
CWD="${PWD}"

# Check if rwenv is set for current directory
CURRENT_RWENV=$(get_current_rwenv "$CWD" 2>/dev/null) || true

if [[ -z "$CURRENT_RWENV" ]]; then
    # No rwenv set - output error message and exit with error
    cat >&2 <<EOF
ERROR: No rwenv set for current directory.

Current directory: $CWD

Available environments:
EOF

    # List available rwenvs
    if envs=$(load_envs 2>/dev/null); then
        echo "$envs" | jq -r '.rwenvs | to_entries[] | "  - \(.key) (\(.value.type), \(.value.description))"' >&2
    else
        echo "  (none configured)" >&2
    fi

    cat >&2 <<EOF

Use /rwenv-set <name> to select an environment for this directory.
Use /rwenv-list to see all available environments.
EOF
    exit 1
fi

# Load rwenv configuration
RWENV_CONFIG=$(get_rwenv_by_name "$CURRENT_RWENV") || {
    echo "ERROR: rwenv '$CURRENT_RWENV' not found in configuration." >&2
    exit 1
}

# Extract rwenv properties
RWENV_TYPE=$(echo "$RWENV_CONFIG" | jq -r '.type')
KUBECONFIG_PATH=$(echo "$RWENV_CONFIG" | jq -r '.kubeconfigPath')
K8S_CONTEXT=$(echo "$RWENV_CONFIG" | jq -r '.kubernetesContext')
GCP_PROJECT=$(echo "$RWENV_CONFIG" | jq -r '.gcpProject // empty')
READ_ONLY=$(echo "$RWENV_CONFIG" | jq -r '.readOnly')
DEV_CONTAINER=$(get_dev_container)

# Check if dev container is running
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DEV_CONTAINER}$"; then
    echo "ERROR: Dev container '$DEV_CONTAINER' is not running." >&2
    echo "Start the container first, then retry the command." >&2
    exit 1
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
        exit 1
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
        exit 1
    fi
}

# Build the transformed command based on the base command
build_transformed_command() {
    local docker_prefix="docker exec -it $DEV_CONTAINER"

    case "$BASE_CMD" in
        kubectl)
            check_write_operation "$BASE_CMD" "$CMD_ARGS" "kubectl"
            echo "$docker_prefix kubectl --kubeconfig=$KUBECONFIG_PATH --context=$K8S_CONTEXT $CMD_ARGS"
            ;;
        helm)
            check_write_operation "$BASE_CMD" "$CMD_ARGS" "helm"
            echo "$docker_prefix helm --kubeconfig=$KUBECONFIG_PATH --kube-context=$K8S_CONTEXT $CMD_ARGS"
            ;;
        flux)
            check_write_operation "$BASE_CMD" "$CMD_ARGS" "flux"
            echo "$docker_prefix flux --kubeconfig=$KUBECONFIG_PATH --context=$K8S_CONTEXT $CMD_ARGS"
            ;;
        gcloud)
            check_gcloud_for_k3s
            # gcloud is ALWAYS read-only
            if is_gcloud_write_operation "$CMD_ARGS"; then
                cat >&2 <<EOF
ERROR: gcloud write operations are blocked for safety.

Blocked command: gcloud $CMD_ARGS

gcloud is always read-only regardless of rwenv settings.
Blocked operations include: create, delete, start, stop, reset, resize, patch, update, rm, cp, mv

Use the GCP Console or a dedicated deployment pipeline for write operations.
EOF
                exit 1
            fi
            echo "$docker_prefix gcloud --project=$GCP_PROJECT $CMD_ARGS"
            ;;
        vault)
            # Vault commands pass through with container prefix
            # Note: vault-specific safety could be added here
            echo "$docker_prefix vault $CMD_ARGS"
            ;;
        *)
            # Shouldn't reach here due to earlier check, but pass through just in case
            echo "$ORIGINAL_CMD"
            ;;
    esac
}

# Main execution
TRANSFORMED_CMD=$(build_transformed_command)

# Output the transformed command
echo "$TRANSFORMED_CMD"
