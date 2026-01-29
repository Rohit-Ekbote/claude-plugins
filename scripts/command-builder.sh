#!/usr/bin/env bash
# command-builder.sh - Build docker exec commands with rwenv context
#
# Usage: command-builder.sh <tool> [args...]
#
# Supported tools: kubectl, helm, flux, gcloud, vault
#
# This script builds the full command with:
# - Docker exec prefix for the dev container
# - Kubeconfig and context flags (for k8s tools)
# - Project flag (for gcloud)
# - Safety checks for read-only environments

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities
source "$PLUGIN_DIR/lib/rwenv-utils.sh"

# Color output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Print error message and exit
error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

# Print warning message
warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

# Print the built command (for display/logging)
print_cmd() {
    echo -e "${BLUE}Command:${NC} $1" >&2
}

# Show usage
usage() {
    cat <<EOF
Usage: $(basename "$0") <tool> [args...]

Build docker exec commands with rwenv context for Kubernetes tools.

Supported tools:
  kubectl    Kubernetes CLI
  helm       Helm package manager
  flux       FluxCD CLI
  gcloud     Google Cloud CLI
  vault      HashiCorp Vault CLI

Options:
  --dry-run    Print the command without executing
  --no-check   Skip read-only safety checks
  -h, --help   Show this help message

Examples:
  $(basename "$0") kubectl get pods -n production
  $(basename "$0") helm list -A
  $(basename "$0") flux get kustomizations
  $(basename "$0") gcloud compute instances list
  $(basename "$0") --dry-run kubectl delete pod mypod -n default

The script automatically:
  - Uses the active rwenv for the current directory
  - Wraps commands in docker exec for the dev container
  - Adds --kubeconfig and --context flags for k8s tools
  - Adds --project flag for gcloud
  - Blocks write operations on read-only environments
EOF
    exit 0
}

# Check if operation is a write for the given tool
check_write_safety() {
    local tool="$1"
    local args="$2"
    local rwenv_name="$3"
    local no_check="$4"

    # Skip check if --no-check was passed
    if [[ "$no_check" == "true" ]]; then
        return 0
    fi

    local is_readonly
    is_readonly=$(is_readonly "$rwenv_name" && echo "true" || echo "false")

    # gcloud is always read-only regardless of rwenv setting
    if [[ "$tool" == "gcloud" ]]; then
        if is_gcloud_write_operation "$args"; then
            error "gcloud write operations are always blocked for safety.

Blocked: gcloud $args

Use GCP Console or deployment pipelines for write operations."
        fi
        return 0
    fi

    # Skip further checks if rwenv is not read-only
    if [[ "$is_readonly" != "true" ]]; then
        return 0
    fi

    # Check based on tool
    case "$tool" in
        kubectl)
            if is_kubectl_write_operation "$args"; then
                error "rwenv '$rwenv_name' is read-only. Cannot execute write operation.

Blocked: kubectl $args

Read-only blocks: apply, delete, patch, create, edit, replace, scale"
            fi
            ;;
        helm)
            if is_helm_write_operation "$args"; then
                error "rwenv '$rwenv_name' is read-only. Cannot execute write operation.

Blocked: helm $args

Read-only blocks: install, upgrade, uninstall, rollback"
            fi
            ;;
        flux)
            if is_flux_write_operation "$args"; then
                error "rwenv '$rwenv_name' is read-only. Cannot execute write operation.

Blocked: flux $args

Read-only blocks: reconcile, suspend, resume, create, delete"
            fi
            ;;
    esac

    return 0
}

# Build command for kubectl
build_kubectl() {
    local rwenv_name="$1"
    shift
    local args="$*"

    local kubeconfig context container
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    container="$(get_dev_container)"

    echo "docker exec -i $container kubectl --kubeconfig=$kubeconfig --context=$context $args"
}

# Build command for helm
build_helm() {
    local rwenv_name="$1"
    shift
    local args="$*"

    local kubeconfig context container
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    container="$(get_dev_container)"

    echo "docker exec -i $container helm --kubeconfig=$kubeconfig --kube-context=$context $args"
}

# Build command for flux
build_flux() {
    local rwenv_name="$1"
    shift
    local args="$*"

    local kubeconfig context container
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    container="$(get_dev_container)"

    echo "docker exec -i $container flux --kubeconfig=$kubeconfig --context=$context $args"
}

# Build command for gcloud
build_gcloud() {
    local rwenv_name="$1"
    shift
    local args="$*"

    local project rwenv_type container
    rwenv_type="$(get_rwenv_type "$rwenv_name")"
    container="$(get_dev_container)"

    # Check if this is a k3s environment
    if [[ "$rwenv_type" == "k3s" ]]; then
        error "gcloud not available for k3s rwenv '$rwenv_name'.

gcloud commands require a GKE environment with a configured GCP project.
Use a GKE rwenv: /rwenv-set <gke-rwenv-name>"
    fi

    project="$(get_gcp_project "$rwenv_name")"

    if [[ -z "$project" ]]; then
        error "No GCP project configured for rwenv '$rwenv_name'"
    fi

    echo "docker exec -i $container gcloud --project=$project $args"
}

# Build command for vault
build_vault() {
    local rwenv_name="$1"
    shift
    local args="$*"

    local container
    container="$(get_dev_container)"

    # Vault doesn't need kubeconfig/context, just run through container
    echo "docker exec -i $container vault $args"
}

# Main
main() {
    local tool=""
    local dry_run=false
    local no_check=false
    local args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-check)
                no_check=true
                shift
                ;;
            *)
                if [[ -z "$tool" ]]; then
                    tool="$1"
                else
                    args+=("$1")
                fi
                shift
                ;;
        esac
    done

    # Validate tool
    if [[ -z "$tool" ]]; then
        error "Tool is required. Use --help for usage."
    fi

    case "$tool" in
        kubectl|helm|flux|gcloud|vault)
            ;;
        *)
            error "Unsupported tool: $tool

Supported tools: kubectl, helm, flux, gcloud, vault"
            ;;
    esac

    # Check rwenv is set
    local rwenv_name
    rwenv_name=$(get_current_rwenv) || {
        error "No rwenv set for current directory.

Use /rwenv-set <name> to select an environment.
Use /rwenv-list to see available environments."
    }

    # Check dev container is running
    check_dev_container || exit 1

    # Convert args array to string
    local args_str="${args[*]:-}"

    # Check write safety
    check_write_safety "$tool" "$args_str" "$rwenv_name" "$no_check"

    # Build the command
    local cmd=""
    case "$tool" in
        kubectl)
            cmd=$(build_kubectl "$rwenv_name" "${args[@]:-}")
            ;;
        helm)
            cmd=$(build_helm "$rwenv_name" "${args[@]:-}")
            ;;
        flux)
            cmd=$(build_flux "$rwenv_name" "${args[@]:-}")
            ;;
        gcloud)
            cmd=$(build_gcloud "$rwenv_name" "${args[@]:-}")
            ;;
        vault)
            cmd=$(build_vault "$rwenv_name" "${args[@]:-}")
            ;;
    esac

    # Output or execute
    if [[ "$dry_run" == "true" ]]; then
        print_cmd "$cmd"
        echo "$cmd"
    else
        print_cmd "$cmd"
        eval "$cmd"
    fi
}

main "$@"
