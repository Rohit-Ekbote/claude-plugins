#!/usr/bin/env bash
# pg_query.sh - Execute read-only PostgreSQL queries via Kubernetes
#
# Usage: pg_query.sh <database_name> "<sql_query>"
#
# This script:
# 1. Loads database config from envs.json
# 2. Fetches credentials from Kubernetes secret
# 3. Validates query is read-only
# 4. Executes query via kubectl exec

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
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
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

# Print info message
info() {
    echo -e "${GREEN}INFO:${NC} $1" >&2
}

# Show usage
usage() {
    cat <<EOF
Usage: $(basename "$0") <database_name> "<sql_query>" [options]

Execute read-only PostgreSQL queries via Kubernetes.

Arguments:
  database_name    Name of the database (from envs.json databases section)
  sql_query        SQL query to execute (must be read-only)

Options:
  -f, --format     Output format: table (default), csv, json
  -t, --timeout    Query timeout in seconds (default: 30)
  -h, --help       Show this help message

Examples:
  $(basename "$0") core "SELECT * FROM users LIMIT 10"
  $(basename "$0") usearch "SELECT COUNT(*) FROM documents" --format=json
  $(basename "$0") agentfarm "\\dt" --format=table

Available databases:
EOF
    # List available databases
    list_database_names 2>/dev/null | while read -r db; do
        echo "  - $db"
    done
    exit 0
}

# Validate query is read-only
validate_readonly_query() {
    local query="$1"
    local query_upper
    query_upper=$(echo "$query" | tr '[:lower:]' '[:upper:]')

    # Patterns that indicate write operations
    local write_patterns=(
        "INSERT"
        "UPDATE"
        "DELETE"
        "DROP"
        "CREATE"
        "ALTER"
        "TRUNCATE"
        "GRANT"
        "REVOKE"
        "MERGE"
        "UPSERT"
        "VACUUM"
        "REINDEX"
        "CLUSTER"
    )

    for pattern in "${write_patterns[@]}"; do
        # Check if pattern appears as a word (not part of another word)
        if echo "$query_upper" | grep -qE "(^|[^A-Z])${pattern}([^A-Z]|$)"; then
            error "Write operation detected: '$pattern'. Database access is read-only.

Blocked query: $query

Only SELECT, EXPLAIN, and metadata queries are allowed."
        fi
    done

    # Check for COPY TO (file writes)
    if echo "$query_upper" | grep -qE "COPY.*TO"; then
        error "COPY TO operation detected. Database access is read-only."
    fi

    return 0
}

# Fetch password from Kubernetes secret
fetch_password() {
    local namespace="$1"
    local secret_name="$2"
    local rwenv_name="$3"

    local kubeconfig context docker_prefix
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    docker_prefix="$(build_docker_exec_prefix)"

    # Fetch the password from the secret
    local password
    password=$($docker_prefix kubectl \
        --kubeconfig="$kubeconfig" \
        --context="$context" \
        get secret "$secret_name" -n "$namespace" \
        -o jsonpath='{.data.password}' 2>/dev/null) || {
        error "Cannot fetch credentials: secret '$secret_name' not found in namespace '$namespace'"
    }

    # Decode base64
    echo "$password" | base64 -d
}

# Find a pod that can run psql
find_psql_pod() {
    local namespace="$1"
    local rwenv_name="$2"

    local kubeconfig context docker_prefix
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    docker_prefix="$(build_docker_exec_prefix)"

    # Try to find a postgres-related pod in the namespace
    local pod
    pod=$($docker_prefix kubectl \
        --kubeconfig="$kubeconfig" \
        --context="$context" \
        get pods -n "$namespace" \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' \
        2>/dev/null | tr ' ' '\n' | grep -E '(postgres|pg|psql)' | head -1) || true

    if [[ -z "$pod" ]]; then
        # Fallback: try to find any running pod in the namespace
        pod=$($docker_prefix kubectl \
            --kubeconfig="$kubeconfig" \
            --context="$context" \
            get pods -n "$namespace" \
            -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' \
            2>/dev/null | tr ' ' '\n' | head -1) || true
    fi

    echo "$pod"
}

# Execute query via kubectl exec
execute_query() {
    local db_config="$1"
    local query="$2"
    local format="$3"
    local timeout="$4"
    local rwenv_name="$5"

    # Parse database config
    local namespace pgbouncer_host database username
    namespace=$(echo "$db_config" | jq -r '.namespace')
    secret_name=$(echo "$db_config" | jq -r '.secretName')
    pgbouncer_host=$(echo "$db_config" | jq -r '.pgbouncerHost')
    database=$(echo "$db_config" | jq -r '.database')
    username=$(echo "$db_config" | jq -r '.username')

    # Fetch password
    info "Fetching credentials from secret '$secret_name'..."
    local password
    password=$(fetch_password "$namespace" "$secret_name" "$rwenv_name")

    # Build connection string
    local conn_string="postgresql://${username}:${password}@${pgbouncer_host}/${database}"

    # Get kubectl settings
    local kubeconfig context docker_prefix
    kubeconfig="$(get_kubeconfig_path "$rwenv_name")"
    context="$(get_kubernetes_context "$rwenv_name")"
    docker_prefix="$(build_docker_exec_prefix)"

    # Find a pod to execute from
    info "Finding pod to execute query..."
    local pod
    pod=$(find_psql_pod "$namespace" "$rwenv_name")

    if [[ -z "$pod" ]]; then
        error "No suitable pod found in namespace '$namespace' to execute psql"
    fi

    info "Using pod: $pod"

    # Build psql options based on format
    local psql_opts=""
    case "$format" in
        csv)
            psql_opts="--csv"
            ;;
        json)
            # PostgreSQL doesn't have native JSON output, use a workaround
            psql_opts="-t"
            query="SELECT json_agg(t) FROM ($query) t"
            ;;
        table|*)
            psql_opts=""
            ;;
    esac

    # Execute query
    info "Executing query..."
    $docker_prefix kubectl \
        --kubeconfig="$kubeconfig" \
        --context="$context" \
        exec -i "$pod" -n "$namespace" -- \
        timeout "$timeout" psql "$conn_string" $psql_opts -c "$query"
}

# Main
main() {
    local database_name=""
    local query=""
    local format="table"
    local timeout=30

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            --format=*)
                format="${1#*=}"
                shift
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            *)
                if [[ -z "$database_name" ]]; then
                    database_name="$1"
                elif [[ -z "$query" ]]; then
                    query="$1"
                else
                    error "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    # Validate arguments
    if [[ -z "$database_name" ]]; then
        error "Database name is required. Use --help for usage."
    fi

    if [[ -z "$query" ]]; then
        error "SQL query is required. Use --help for usage."
    fi

    # Check rwenv is set
    local rwenv_name
    rwenv_name=$(get_current_rwenv) || {
        error "No rwenv set for current directory.

Use /rwenv-set <name> to select an environment.
Use /rwenv-list to see available environments."
    }

    info "Using rwenv: $rwenv_name"

    # Check dev container is running
    check_dev_container || exit 1

    # Get database config
    local db_config
    db_config=$(get_database_by_name "$database_name") || {
        echo "ERROR: Database '$database_name' not found." >&2
        echo "" >&2
        echo "Available databases:" >&2
        list_database_names | while read -r db; do
            echo "  - $db" >&2
        done
        exit 1
    }

    # Validate query is read-only
    validate_readonly_query "$query"

    # Execute query
    execute_query "$db_config" "$query" "$format" "$timeout" "$rwenv_name"
}

main "$@"
