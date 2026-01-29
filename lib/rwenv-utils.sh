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

# Load infra-catalog.json content
load_infra_catalog() {
    local plugin_dir catalog_file
    plugin_dir="$(get_plugin_dir)"
    catalog_file="$plugin_dir/data/infra-catalog.json"

    if [[ ! -f "$catalog_file" ]]; then
        echo '{"version":"1.0","services":{},"databases":{}}' >&2
        return 1
    fi

    cat "$catalog_file"
}

# Get database config by name (from infra-catalog.json)
get_database_by_name() {
    local name="$1"
    local catalog
    catalog="$(load_infra_catalog)" || return 1

    echo "$catalog" | jq -e --arg name "$name" '.databases[$name]' 2>/dev/null
}

# List all rwenv names
list_rwenv_names() {
    local envs
    envs="$(load_envs)"
    echo "$envs" | jq -r '.rwenvs | keys[]'
}

# List all database names (from infra-catalog.json)
list_database_names() {
    local catalog
    catalog="$(load_infra_catalog)" || return 1
    echo "$catalog" | jq -r '.databases | keys[]'
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
# Note: Use -i only (not -it) since Claude Code runs non-interactively
build_docker_exec_prefix() {
    local container
    container="$(get_dev_container)"
    echo "docker exec -i $container"
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

# Validate database query based on rwenv settings
# Returns 0 if allowed, returns 1 with error message if blocked
validate_db_query() {
    local query="$1"
    local rwenv_name="$2"
    local query_upper
    query_upper=$(echo "$query" | tr '[:lower:]' '[:upper:]')

    # DDL patterns - ALWAYS blocked regardless of rwenv
    local ddl_patterns="CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|VACUUM|REINDEX|CLUSTER"

    # DML patterns - blocked only if readOnly=true
    local dml_patterns="INSERT|UPDATE|DELETE|MERGE|UPSERT"

    # Check DDL (always blocked)
    if echo "$query_upper" | grep -qE "(^|[^A-Z])($ddl_patterns)([^A-Z]|$)"; then
        echo "ERROR: DDL operation blocked. Schema modifications are never allowed." >&2
        echo "Blocked query: $query" >&2
        return 1
    fi

    # Check COPY TO (always blocked - file writes)
    if echo "$query_upper" | grep -qE "COPY.*TO"; then
        echo "ERROR: COPY TO operation blocked. File writes are not allowed." >&2
        return 1
    fi

    # Check DML only if readOnly
    if is_readonly "$rwenv_name"; then
        if echo "$query_upper" | grep -qE "(^|[^A-Z])($dml_patterns)([^A-Z]|$)"; then
            echo "ERROR: Write operation blocked. Environment '$rwenv_name' is read-only." >&2
            echo "Blocked query: $query" >&2
            return 1
        fi
    fi

    return 0
}

# Build psql command using port-forward approach
# Usage: build_psql_cmd <rwenv_name> <database_name> <query> [local_port]
# Outputs executable commands to stdout
build_psql_cmd() {
    local rwenv_name="$1"
    local db_name="$2"
    local query="$3"
    local local_port="${4:-3105}"  # Use 3105 - already exposed by dev container

    # Validate query first
    validate_db_query "$query" "$rwenv_name" || return 1

    # Get database config
    local db_config
    db_config=$(get_database_by_name "$db_name") || {
        echo "ERROR: Database '$db_name' not found" >&2
        return 1
    }

    # Parse config
    local namespace secret_name pgbouncer_host database username
    namespace=$(echo "$db_config" | jq -r '.namespace')
    secret_name=$(echo "$db_config" | jq -r '.secretName')
    pgbouncer_host=$(echo "$db_config" | jq -r '.pgbouncerHost')
    database=$(echo "$db_config" | jq -r '.database')
    username=$(echo "$db_config" | jq -r '.username')

    # Extract service name from pgbouncer host (e.g., core-pgbouncer.backend-services.svc.cluster.local -> core-pgbouncer)
    local pgbouncer_svc
    pgbouncer_svc=$(echo "$pgbouncer_host" | cut -d'.' -f1)

    # Get rwenv settings
    local kubeconfig context container
    kubeconfig=$(get_kubeconfig_path "$rwenv_name")
    context=$(get_kubernetes_context "$rwenv_name")
    container=$(get_dev_container)

    # Build the command sequence
    cat <<EOF
# 1. Get password
PASSWORD=\$(docker exec $container kubectl --kubeconfig=$kubeconfig --context=$context get secret $secret_name -n $namespace -o jsonpath='{.data.password}' | base64 -d)

# 2. Port-forward (background, bind to 0.0.0.0 for host access)
docker exec $container kubectl --kubeconfig=$kubeconfig --context=$context port-forward --address 0.0.0.0 svc/$pgbouncer_svc $local_port:5432 -n $namespace &
PF_PID=\$!
sleep 2

# 3. Execute query (can run from host or container)
# From container:
docker exec $container sh -c "PGPASSWORD='\$PASSWORD' psql -h 127.0.0.1 -p $local_port -U $username -d $database -c '$query'"
# Or from host (if psql installed):
# PGPASSWORD="\$PASSWORD" psql -h localhost -p $local_port -U $username -d $database -c '$query'

# 4. Cleanup
kill \$PF_PID 2>/dev/null
EOF
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

# Get Flux repo URL for rwenv
get_flux_repo_url() {
    local name="$1"
    local rwenv
    rwenv="$(get_rwenv_by_name "$name")" || return 1

    echo "$rwenv" | jq -r '.fluxGitRepo // empty'
}

# Get Flux repo local path for rwenv
get_flux_repo_path() {
    local name="$1"
    get_rwenv_by_name "$name" >/dev/null || return 1
    local config_dir
    config_dir="$(get_config_dir)"

    echo "$config_dir/flux-repos/$name"
}

# Check if Flux repo is cloned for rwenv
is_flux_repo_cloned() {
    local name="$1"
    local repo_path
    repo_path="$(get_flux_repo_path "$name")" || return 1

    [[ -d "$repo_path/.git" ]]
}

# Clone or update Flux repo for rwenv
ensure_flux_repo() {
    local name="$1"
    local repo_url repo_path

    repo_url="$(get_flux_repo_url "$name")"
    if [[ -z "$repo_url" ]]; then
        echo "ERROR: No fluxGitRepo configured for rwenv '$name'" >&2
        return 1
    fi

    repo_path="$(get_flux_repo_path "$name")"

    if is_flux_repo_cloned "$name"; then
        # Update existing repo
        echo "Updating Flux repo at $repo_path..." >&2
        (cd "$repo_path" && git fetch origin && git pull --ff-only) || {
            echo "WARNING: Could not update Flux repo. Working with existing checkout." >&2
        }
    else
        # Clone new repo
        echo "Cloning Flux repo to $repo_path..." >&2
        mkdir -p "$(dirname "$repo_path")"
        git clone "$repo_url" "$repo_path" || {
            echo "ERROR: Failed to clone Flux repo from $repo_url" >&2
            return 1
        }
    fi

    echo "$repo_path"
}

# Check if Flux repo has uncommitted changes
is_flux_repo_dirty() {
    local name="$1"
    local repo_path
    repo_path="$(get_flux_repo_path "$name")" || return 1

    if [[ ! -d "$repo_path/.git" ]]; then
        return 1  # Not cloned, so not dirty
    fi

    (cd "$repo_path" && [[ -n "$(git status --porcelain)" ]])
}

# Get the plugin directory
get_plugin_dir() {
    # Try environment variable first, then default location
    echo "${RWENV_PLUGIN_DIR:-$HOME/.claude/plugins/cache/Rohit-Ekbote-rwenv/rwenv}"
}

# Get service connection info from infra catalog
# Usage: get_service_info <service_name>
# Returns JSON with resolved address (rwenv-name replaced)
get_service_info() {
    local service_name="$1"
    local rwenv_name
    rwenv_name=$(get_current_rwenv) || {
        echo "ERROR: No rwenv set for current directory" >&2
        return 1
    }

    # Load infra catalog
    local catalog
    catalog="$(load_infra_catalog)" || {
        echo "ERROR: Infra catalog not found" >&2
        return 1
    }

    # Get service entry
    local service
    service=$(echo "$catalog" | jq -e --arg name "$service_name" '.services[$name]' 2>/dev/null) || {
        echo "ERROR: Service '$service_name' not found in catalog" >&2
        echo "Available services:" >&2
        echo "$catalog" | jq -r '.services | keys[]' >&2
        return 1
    }

    # Replace <rwenv-name> placeholder in address
    local address
    address=$(echo "$service" | jq -r '.address // empty' | sed "s/<rwenv-name>/$rwenv_name/g")

    # Build response with resolved address
    echo "$service" | jq --arg addr "$address" '. + {resolvedAddress: $addr}'
}

# List all services in infra catalog
list_services() {
    local catalog
    catalog="$(load_infra_catalog)" || {
        echo "ERROR: Infra catalog not found" >&2
        return 1
    }

    echo "$catalog" | jq -r '.services | to_entries[] | "\(.key): \(.value.description) [exposed=\(.value.exposed)]"'
}
