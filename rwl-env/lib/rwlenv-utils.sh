#!/usr/bin/env bash
# rwlenv-utils.sh - Shared utility functions for rwl-env plugin

set -euo pipefail

# Get the config directory (supports RWLENV_CONFIG_DIR override)
get_config_dir() {
    echo "${RWLENV_CONFIG_DIR:-$HOME/.claude/rwl-env}"
}

# Get the plugin directory
get_plugin_dir() {
    echo "${RWLENV_PLUGIN_DIR:-$HOME/.claude/plugins/cache/Rohit-Ekbote-rwl-env/rwl-env}"
}

# Load envs.json content. Echoes empty skeleton + rc=1 if missing.
load_envs() {
    local envs_file
    envs_file="$(get_config_dir)/envs.json"
    if [[ ! -f "$envs_file" ]]; then
        echo '{"version":"1.0","rwlenvs":{}}'
        return 1
    fi
    cat "$envs_file"
}

# Get rwlenv entry by name. rc=1 if not found.
get_rwlenv_by_name() {
    local name="$1"
    local envs
    envs="$(load_envs)"
    echo "$envs" | jq -e --arg name "$name" '.rwlenvs[$name]' 2>/dev/null
}

# List all rwlenv names.
list_rwlenv_names() {
    local envs
    envs="$(load_envs)"
    echo "$envs" | jq -r '.rwlenvs | keys[]'
}

# Get current rwlenv for a directory (defaults to PWD).
get_current_rwlenv() {
    local dir="${1:-$PWD}"
    local file="$dir/.claude/rwl-env"
    if [[ -f "$file" ]]; then
        tr -d '[:space:]' < "$file"
        return 0
    fi
    return 1
}

# Check if rwlenv is read-only. rc=0 if read-only, rc=1 otherwise.
is_readonly() {
    local name="$1"
    local rwlenv
    rwlenv="$(get_rwlenv_by_name "$name")" || return 1
    echo "$rwlenv" | jq -e '.readOnly == true' >/dev/null 2>&1
}

# --- Kubeconfig discovery ---

# List contexts in a single kubeconfig file. Returns rc=1 if file invalid.
list_contexts_in_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    kubectl --kubeconfig="$file" config get-contexts -o name 2>/dev/null || return 1
}

# Discover candidate kubeconfig files under KUBE_SEARCH_ROOT (defaults to ~/.kube/).
# Also includes $KUBECONFIG colon-split paths if set.
discover_kubeconfig_files() {
    local root="${KUBE_SEARCH_ROOT:-$HOME/.kube}"
    if [[ -d "$root" ]]; then
        # Match: config, *.yaml, *.yml, *-config, *.config
        find "$root" -maxdepth 1 -type f \
            \( -name 'config' -o -name '*.yaml' -o -name '*.yml' \
               -o -name '*-config' -o -name '*.config' \) 2>/dev/null
    fi
    if [[ -n "${KUBECONFIG:-}" ]]; then
        echo "$KUBECONFIG" | tr ':' '\n' | while read -r p; do
            [[ -f "$p" ]] && echo "$p"
        done
    fi
}

# Find (file, context) pairs matching context_name. Tab-separated lines.
# Exact match first, substring match fallback. rc=0 even if no matches.
find_context_across_files() {
    local target="$1"
    local files
    files=$(discover_kubeconfig_files)
    local found_exact=0
    local f ctx
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        while IFS= read -r ctx; do
            [[ -z "$ctx" ]] && continue
            if [[ "$ctx" == "$target" ]]; then
                printf "%s\t%s\n" "$f" "$ctx"
                found_exact=1
            fi
        done < <(list_contexts_in_file "$f" 2>/dev/null || true)
    done <<< "$files"

    # Substring fallback only if no exact matches
    if [[ "$found_exact" -eq 0 ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            while IFS= read -r ctx; do
                [[ -z "$ctx" ]] && continue
                if [[ "$ctx" == *"$target"* ]]; then
                    printf "%s\t%s\n" "$f" "$ctx"
                fi
            done < <(list_contexts_in_file "$f" 2>/dev/null || true)
        done <<< "$files"
    fi
}

# --- Write detection ---

# Returns 0 if the helm subcommand is a write (upgrade/rollback/install/uninstall/etc).
is_helm_write_operation() {
    local cmd="$1"
    local write_ops="install|upgrade|uninstall|rollback|delete|repo add|repo remove|dependency"
    echo "$cmd" | grep -qE "^($write_ops)([[:space:]]|$)"
}

# Returns 0 if the helm subcommand is FORBIDDEN by rwl-env (out of scope for this plugin).
is_helm_forbidden_operation() {
    local cmd="$1"
    local forbidden="install|uninstall|delete|repo add|repo remove|dependency"
    echo "$cmd" | grep -qE "^($forbidden)([[:space:]]|$)"
}

# Returns 0 if the kubectl subcommand is a write.
# NOTE: "rollout status" and "rollout history" are reads; "rollout restart" is a write.
is_kubectl_write_operation() {
    local cmd="$1"
    # rollout subcommands: writes (pause|restart|resume|undo) checked before reads (history|status).
    # Bare `rollout` with no subcommand falls through and is treated as not-a-write (no match in general pattern).
    if echo "$cmd" | grep -qE "^rollout[[:space:]]+(pause|restart|resume|undo)([[:space:]]|$)"; then return 0; fi
    if echo "$cmd" | grep -qE "^rollout[[:space:]]+(history|status)([[:space:]]|$)"; then return 1; fi
    local write_ops="apply|delete|patch|create|edit|replace|scale|set[[:space:]]+image|set[[:space:]]+resources|set[[:space:]]+env|label|annotate|taint|cordon|uncordon|drain|exec"
    echo "$cmd" | grep -qE "^($write_ops)([[:space:]]|$)"
}

# Validate a SQL query for read-only safety. rc=0 if safe, rc=1 with stderr if blocked.
# Always blocks DDL, DML, COPY ... TO regardless of any readOnly flag.
validate_psql_query() {
    local query="$1"
    local query_upper
    query_upper=$(echo "$query" | tr '[:lower:]' '[:upper:]')

    local ddl="CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|VACUUM|REINDEX|CLUSTER"
    local dml="INSERT|UPDATE|DELETE|MERGE|UPSERT"

    if echo "$query_upper" | grep -qE "(^|[^A-Z])($ddl)([^A-Z]|$)"; then
        echo "ERROR: DDL blocked. rwl-env db access is read-only. Query: $query" >&2
        return 1
    fi
    if echo "$query_upper" | grep -qE "(^|[^A-Z])($dml)([^A-Z]|$)"; then
        echo "ERROR: DML blocked. rwl-env db access is read-only. Query: $query" >&2
        return 1
    fi
    if echo "$query_upper" | grep -qE "COPY.*TO"; then
        echo "ERROR: COPY TO blocked. File writes not allowed." >&2
        return 1
    fi
    return 0
}
