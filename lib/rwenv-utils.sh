#!/usr/bin/env bash
# rwenv-utils.sh - Shared utility functions for rwenv plugin

set -euo pipefail

# Get the config directory (supports RWENV_CONFIG_DIR override)
get_config_dir() {
    echo "${RWENV_CONFIG_DIR:-$HOME/.claude/rwenv}"
}

# Get the dev container name from envs.json
get_dev_container() {
    local config_dir
    config_dir="$(get_config_dir)"
    local envs_file="$config_dir/envs.json"

    if [[ ! -f "$envs_file" ]]; then
        echo "alpine-dev-container-zsh-rdebug"  # Default fallback
        return
    fi

    jq -r '.devContainer // "alpine-dev-container-zsh-rdebug"' "$envs_file"
}

# Load envs.json content
load_envs() {
    local config_dir
    config_dir="$(get_config_dir)"
    local envs_file="$config_dir/envs.json"

    if [[ ! -f "$envs_file" ]]; then
        echo '{"version":"1.0","rwenvs":{},"databases":{}}'
        return 1
    fi

    cat "$envs_file"
}

# Load env-consumers.json content
load_consumers() {
    local config_dir
    config_dir="$(get_config_dir)"
    local consumers_file="$config_dir/env-consumers.json"

    if [[ ! -f "$consumers_file" ]]; then
        echo '{}'
        return 1
    fi

    cat "$consumers_file"
}

# Get current rwenv for a given directory (defaults to PWD)
get_current_rwenv() {
    local dir="${1:-$PWD}"
    local consumers
    consumers="$(load_consumers)"

    # Normalize path (resolve symlinks, remove trailing slash)
    dir="$(cd "$dir" 2>/dev/null && pwd -P)" || dir="$1"

    # Check for exact match first
    local rwenv
    rwenv="$(echo "$consumers" | jq -r --arg dir "$dir" '.[$dir] // empty')"

    if [[ -n "$rwenv" ]]; then
        echo "$rwenv"
        return 0
    fi

    # Check parent directories (for worktrees)
    local parent="$dir"
    while [[ "$parent" != "/" ]]; do
        parent="$(dirname "$parent")"
        rwenv="$(echo "$consumers" | jq -r --arg dir "$parent" '.[$dir] // empty')"
        if [[ -n "$rwenv" ]]; then
            echo "$rwenv"
            return 0
        fi
    done

    return 1
}

# Get rwenv config by name
get_rwenv_by_name() {
    local name="$1"
    local envs
    envs="$(load_envs)"

    echo "$envs" | jq -e --arg name "$name" '.rwenvs[$name]' 2>/dev/null
}

# Get database config by name
get_database_by_name() {
    local name="$1"
    local envs
    envs="$(load_envs)"

    echo "$envs" | jq -e --arg name "$name" '.databases[$name]' 2>/dev/null
}

# List all rwenv names
list_rwenv_names() {
    local envs
    envs="$(load_envs)"
    echo "$envs" | jq -r '.rwenvs | keys[]'
}

# List all database names
list_database_names() {
    local envs
    envs="$(load_envs)"
    echo "$envs" | jq -r '.databases | keys[]'
}

# Check if rwenv is read-only
is_readonly() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    echo "$rwenv" | jq -e '.readOnly == true' >/dev/null 2>&1
}

# Get rwenv type (gke or k3s)
get_rwenv_type() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    echo "$rwenv" | jq -r '.type'
}

# Get kubernetes context for rwenv
get_kubernetes_context() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    echo "$rwenv" | jq -r '.kubernetesContext'
}

# Get kubeconfig path for rwenv
get_kubeconfig_path() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    echo "$rwenv" | jq -r '.kubeconfigPath'
}

# Get GCP project for rwenv (empty for k3s)
get_gcp_project() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    echo "$rwenv" | jq -r '.gcpProject // empty'
}

# Build docker exec command prefix
build_docker_exec_prefix() {
    local container
    container="$(get_dev_container)"
    echo "docker exec -it $container"
}

# Build kubectl command with rwenv context
build_kubectl_cmd() {
    local rwenv_name="$1"
    shift
    local kubectl_args="$*"

    local kubeconfig context docker_prefix
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    docker_prefix="$(build_docker_exec_prefix)"

    echo "$docker_prefix kubectl --kubeconfig=$kubeconfig --context=$context $kubectl_args"
}

# Build gcloud command with rwenv project
build_gcloud_cmd() {
    local rwenv_name="$1"
    shift
    local gcloud_args="$*"

    local project docker_prefix
    project="$(get_gcp_project "$rwenv_name")"
    docker_prefix="$(build_docker_exec_prefix)"

    if [[ -z "$project" ]]; then
        echo "ERROR: gcloud not available for k3s rwenv '$rwenv_name'" >&2
        return 1
    fi

    echo "$docker_prefix gcloud --project=$project $gcloud_args"
}

# Build helm command with rwenv context
build_helm_cmd() {
    local rwenv_name="$1"
    shift
    local helm_args="$*"

    local kubeconfig context docker_prefix
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    docker_prefix="$(build_docker_exec_prefix)"

    echo "$docker_prefix helm --kubeconfig=$kubeconfig --kube-context=$context $helm_args"
}

# Build flux command with rwenv context
build_flux_cmd() {
    local rwenv_name="$1"
    shift
    local flux_args="$*"

    local kubeconfig context docker_prefix
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    docker_prefix="$(build_docker_exec_prefix)"

    echo "$docker_prefix flux --kubeconfig=$kubeconfig --context=$context $flux_args"
}

# Check if command is a write operation for kubectl
is_kubectl_write_operation() {
    local cmd="$1"
    local write_ops="apply|delete|patch|create|edit|replace|scale|rollout|set|label|annotate|taint|cordon|uncordon|drain"
    echo "$cmd" | grep -qE "^($write_ops)(\s|$)"
}

# Check if command is a write operation for helm
is_helm_write_operation() {
    local cmd="$1"
    local write_ops="install|upgrade|uninstall|rollback|repo add|repo remove"
    echo "$cmd" | grep -qE "^($write_ops)(\s|$)"
}

# Check if command is a write operation for flux
is_flux_write_operation() {
    local cmd="$1"
    local write_ops="reconcile|suspend|resume|create|delete|export"
    echo "$cmd" | grep -qE "^($write_ops)(\s|$)"
}

# Check if command is a write operation for gcloud
is_gcloud_write_operation() {
    local cmd="$1"
    local write_patterns="create|delete|start|stop|reset|resize|patch|update|set-iam|remove-iam|add-iam|rm |cp |mv "
    echo "$cmd" | grep -qiE "$write_patterns"
}

# Set rwenv for a directory
set_rwenv_for_dir() {
    local dir="$1"
    local rwenv_name="$2"
    local config_dir
    config_dir="$(get_config_dir)"
    local consumers_file="$config_dir/env-consumers.json"

    # Ensure config dir exists
    mkdir -p "$config_dir"

    # Initialize empty consumers if file doesn't exist
    if [[ ! -f "$consumers_file" ]]; then
        echo '{}' > "$consumers_file"
    fi

    # Update the mapping
    local tmp_file
    tmp_file="$(mktemp)"
    jq --arg dir "$dir" --arg rwenv "$rwenv_name" '.[$dir] = $rwenv' "$consumers_file" > "$tmp_file"
    mv "$tmp_file" "$consumers_file"
}

# Validate that dev container is running
check_dev_container() {
    local container
    container="$(get_dev_container)"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "ERROR: Dev container '$container' not running. Start it first." >&2
        return 1
    fi

    return 0
}

# Format rwenv details for display
format_rwenv_details() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    local type desc context kubeconfig readonly project flux_repo
    type="$(echo "$rwenv" | jq -r '.type')"
    desc="$(echo "$rwenv" | jq -r '.description // "No description"')"
    context="$(echo "$rwenv" | jq -r '.kubernetesContext')"
    kubeconfig="$(echo "$rwenv" | jq -r '.kubeconfigPath')"
    readonly="$(echo "$rwenv" | jq -r '.readOnly')"
    project="$(echo "$rwenv" | jq -r '.gcpProject // "N/A"')"
    flux_repo="$(echo "$rwenv" | jq -r '.fluxGitRepo // "N/A"')"

    cat <<EOF
Name:        $name
Type:        $type
Description: $desc
Context:     $context
Kubeconfig:  $kubeconfig
Read-Only:   $readonly
GCP Project: $project
Flux Repo:   $flux_repo
EOF

    # Services if present
    local services
    services="$(echo "$rwenv" | jq -r '.services // empty')"
    if [[ -n "$services" && "$services" != "null" ]]; then
        echo "Services:"
        echo "$services" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    fi
}
