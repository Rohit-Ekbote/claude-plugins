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
