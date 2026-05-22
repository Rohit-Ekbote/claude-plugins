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

# --- Helm decision ---
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z0-9_-])helm([[:space:]]|$)"; then
    # Extract helm subcommand. Anything after `helm` and any flags up to first non-flag token.
    # Only "get" takes a 2-word subcommand (get values, get manifest, etc).
    helm_sub=$(echo "$ORIGINAL_CMD" \
        | sed 's/.*[^a-zA-Z0-9_-]helm/helm/' \
        | sed 's/^helm[[:space:]]*//' \
        | awk '{
            for (i=1; i<=NF; i++) {
                if ($i ~ /^-/) {
                    # skip flag; eat next token if --foo without =
                    if ($i !~ /=/) i++
                    continue
                }
                # First non-flag token is the subcommand
                scmd = $i
                if (NF >= i+1 && ($i == "get" || $i == "repo") && $(i+1) !~ /^-/) scmd = scmd " " $(i+1)
                print scmd
                exit
            }
        }')

    # Forbidden operations (install, uninstall, delete, repo add/remove, dependency)
    if is_helm_forbidden_operation "$helm_sub"; then
        block "helm '$helm_sub' is out of scope for this plugin; use the helm CLI directly outside Claude Code."
    fi

    # Required flags
    kc_esc=$(escape_regex "$RWLENV_KUBECONFIG")
    ctx_esc=$(escape_regex "$RWLENV_CONTEXT")
    ns_esc=$(escape_regex "$RWLENV_NAMESPACE")
    echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${kc_esc}([[:space:]]|$)" \
        || block "helm command missing or wrong --kubeconfig for rwl-env '$RWLENV_NAME' (expected $RWLENV_KUBECONFIG)."
    echo "$ORIGINAL_CMD" | grep -qE -- "--kube-context=${ctx_esc}([[:space:]]|$)" \
        || block "helm command missing or wrong --kube-context for rwl-env '$RWLENV_NAME' (expected $RWLENV_CONTEXT)."
    echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${ns_esc}([[:space:]]|$)" \
        || block "helm command missing or wrong -n/--namespace for rwl-env '$RWLENV_NAME' (expected $RWLENV_NAMESPACE)."

    # Release name must equal $RWLENV_RELEASE for upgrade/rollback/get/status/history
    # Extract first positional argument after subcommand
    rel_arg=$(echo "$ORIGINAL_CMD" \
        | sed 's/.*[^a-zA-Z0-9_-]helm/helm/' \
        | awk -v helmscmd="$helm_sub" '{
            for (i=1; i<=NF; i++) {
                if ($i == "helm") continue
                if ($i ~ /^-/) {
                    if ($i !~ /=/) i++
                    continue
                }
                # consume subcommand tokens
                if (split(helmscmd, parts, " ") >= 1 && $i == parts[1]) {
                    if (length(parts) > 1 && $(i+1) == parts[2]) i++
                    continue
                }
                print $i; exit
            }
        }')
    case "$helm_sub" in
        upgrade|rollback|"get values"|"get manifest"|"get metadata"|"get notes"|"get hooks"|history|status)
            if [[ -n "$rel_arg" && "$rel_arg" != "$RWLENV_RELEASE" ]]; then
                block "helm command targets release '$rel_arg' but active rwl-env '$RWLENV_NAME' uses release '$RWLENV_RELEASE'."
            fi
            ;;
    esac

    # readOnly enforcement
    if [[ "$RWLENV_READ_ONLY" == "true" ]] && is_helm_write_operation "$helm_sub"; then
        block "helm '$helm_sub' not allowed; rwl-env '$RWLENV_NAME' is read-only."
    fi

    allow
fi

# --- Kubectl decision ---
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z0-9_-])kubectl([[:space:]]|$)"; then
    # Escape rwl-env values for safe regex embedding
    kc_esc=$(escape_regex "$RWLENV_KUBECONFIG")
    ctx_esc=$(escape_regex "$RWLENV_CONTEXT")
    ns_esc=$(escape_regex "$RWLENV_NAMESPACE")

    # Required flags
    echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${kc_esc}([[:space:]]|$)" \
        || block "kubectl command missing or wrong --kubeconfig for rwl-env '$RWLENV_NAME' (expected $RWLENV_KUBECONFIG)."
    echo "$ORIGINAL_CMD" | grep -qE -- "--context=${ctx_esc}([[:space:]]|$)" \
        || block "kubectl command missing or wrong --context for rwl-env '$RWLENV_NAME' (expected $RWLENV_CONTEXT)."
    echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${ns_esc}([[:space:]]|$)" \
        || block "kubectl command missing or wrong -n/--namespace for rwl-env '$RWLENV_NAME' (expected $RWLENV_NAMESPACE)."

    # Extract kubectl subcommand (first non-flag token after kubectl, possibly 2-word)
    kubectl_sub=$(echo "$ORIGINAL_CMD" \
        | sed 's/.*[^a-zA-Z0-9_-]kubectl/kubectl/' \
        | awk '{
            for (i=2; i<=NF; i++) {
                if ($i ~ /^-/) {
                    if ($i !~ /=/) i++
                    continue
                }
                kscmd = $i
                if (NF >= i+1 && $(i+1) !~ /^-/) kscmd = kscmd " " $(i+1)
                print kscmd; exit
            }
        }')

    # Writes always blocked (only helm-ops can mutate). exec is exempt (handled in T9).
    if is_kubectl_write_operation "$kubectl_sub"; then
        case "$kubectl_sub" in
            exec*)
                : # exec extras handled in Task 9
                ;;
            *)
                block "kubectl '$kubectl_sub' not allowed for rwl-env '$RWLENV_NAME'; mutations must go through helm-ops (helm upgrade / rollback)."
                ;;
        esac
    fi

    allow
fi

# --- Psql decision (added in Task 9) ---

allow
