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
