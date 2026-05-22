#!/usr/bin/env bash
# transform-commands.sh - Validation, safety enforcement, and auto-approval for rwl-env
#
# Sources $PWD/.claude/rwl-env-env. If missing, passes through silently.
# Validates kubectl/helm/psql commands against the active rwl-env:
#   - flags must match (kubeconfig, context, namespace, release)
#   - readOnly blocks helm writes
#   - kubectl writes always blocked
#   - psql DDL/DML always blocked

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/lib/rwlenv-utils.sh"

# Commands rwl-env opines on
RWLENV_BINARIES="kubectl|helm|psql"

# Read stdin
INPUT_JSON=$(cat)
ORIGINAL_CMD=$(echo "$INPUT_JSON" | jq -r '.tool_input.command // empty')

allow() {
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
}

block() {
    echo "BLOCKED by rwl-env: $1" >&2
    exit 2
}

# No command, nothing to inspect
if [[ -z "$ORIGINAL_CMD" ]]; then
    allow
fi

# Source the runtime env file
ENV_FILE="${PWD}/.claude/rwl-env-env"

# Determine if command involves an rwl-env-managed binary
CONTAINS_MANAGED=false
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z0-9_-])($RWLENV_BINARIES)([[:space:]]|$)"; then
    CONTAINS_MANAGED=true
fi

# If no env file: pass through everything (no opinion).
# (Unlike rwenv, we deliberately do NOT block kubectl/helm here — user may be working
#  on multiple non-rwl projects in this terminal.)
if [[ ! -f "$ENV_FILE" ]]; then
    allow
fi

# If env file exists but command doesn't involve managed binaries, allow.
if [[ "$CONTAINS_MANAGED" == "false" ]]; then
    allow
fi

# Source env vars for decision-making
# shellcheck source=/dev/null
source "$ENV_FILE"

# Validation + classification logic added in subsequent tasks (T7, T8, T9).
# For now, allow everything matched so the engagement tests pass.
allow
