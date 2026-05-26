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

    # Determine target: platform or runner
    HELM_TARGET=""

    # Try platform match (all three flags must match)
    kc_esc=$(escape_regex "$RWLENV_KUBECONFIG")
    ctx_esc=$(escape_regex "$RWLENV_CONTEXT")
    ns_esc=$(escape_regex "$RWLENV_NAMESPACE")
    if echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${kc_esc}([[:space:]]|$)" && \
       echo "$ORIGINAL_CMD" | grep -qE -- "--kube-context=${ctx_esc}([[:space:]]|$)" && \
       echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${ns_esc}([[:space:]]|$)"; then
        HELM_TARGET="platform"
    fi

    # Try runner match if platform didn't match and runner is configured
    if [[ -z "$HELM_TARGET" ]] && [[ "${RWLENV_HAS_RUNNER:-false}" == "true" ]]; then
        r_kc_esc=$(escape_regex "$RWLENV_RUNNER_KUBECONFIG")
        r_ctx_esc=$(escape_regex "$RWLENV_RUNNER_CONTEXT")
        r_ns_esc=$(escape_regex "$RWLENV_RUNNER_NAMESPACE")
        if echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${r_kc_esc}([[:space:]]|$)" && \
           echo "$ORIGINAL_CMD" | grep -qE -- "--kube-context=${r_ctx_esc}([[:space:]]|$)" && \
           echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${r_ns_esc}([[:space:]]|$)"; then
            HELM_TARGET="runner"
        fi
    fi

    # If neither matched, produce appropriate error
    if [[ -z "$HELM_TARGET" ]]; then
        # Check which specific flag failed to give a useful error message
        echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${kc_esc}([[:space:]]|$)" \
            || block "helm command missing or wrong --kubeconfig for rwl-env '$RWLENV_NAME' (expected $RWLENV_KUBECONFIG)."
        echo "$ORIGINAL_CMD" | grep -qE -- "--kube-context=${ctx_esc}([[:space:]]|$)" \
            || block "helm command missing or wrong --kube-context for rwl-env '$RWLENV_NAME' (expected $RWLENV_CONTEXT)."
        echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${ns_esc}([[:space:]]|$)" \
            || block "helm command missing or wrong -n/--namespace for rwl-env '$RWLENV_NAME' (expected $RWLENV_NAMESPACE)."
        # If all platform flags match individually but not together (shouldn't happen), block generically
        block "helm command credentials do not match any configured target for rwl-env '$RWLENV_NAME'."
    fi

    # Set target-specific vars for release and readOnly checks
    if [[ "$HELM_TARGET" == "runner" ]]; then
        TARGET_RELEASE="$RWLENV_RUNNER_RELEASE"
        TARGET_READ_ONLY="$RWLENV_RUNNER_READ_ONLY"
    else
        TARGET_RELEASE="$RWLENV_RELEASE"
        TARGET_READ_ONLY="$RWLENV_READ_ONLY"
    fi

    # Release name must equal the target's release for upgrade/rollback/get/status/history
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
            if [[ -n "$rel_arg" && "$rel_arg" != "$TARGET_RELEASE" ]]; then
                block "helm command targets release '$rel_arg' but active rwl-env '$RWLENV_NAME' uses release '$TARGET_RELEASE'."
            fi
            ;;
    esac

    # readOnly enforcement
    if [[ "$TARGET_READ_ONLY" == "true" ]] && is_helm_write_operation "$helm_sub"; then
        block "helm '$helm_sub' not allowed; rwl-env '$RWLENV_NAME' is read-only."
    fi

    allow
fi

# --- Kubectl decision ---
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z0-9_-])kubectl([[:space:]]|$)"; then
    # Determine target: platform or runner
    KUBECTL_TARGET=""

    # Try platform match (all three flags must match)
    kc_esc=$(escape_regex "$RWLENV_KUBECONFIG")
    ctx_esc=$(escape_regex "$RWLENV_CONTEXT")
    ns_esc=$(escape_regex "$RWLENV_NAMESPACE")
    if echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${kc_esc}([[:space:]]|$)" && \
       echo "$ORIGINAL_CMD" | grep -qE -- "--context=${ctx_esc}([[:space:]]|$)" && \
       echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${ns_esc}([[:space:]]|$)"; then
        KUBECTL_TARGET="platform"
    fi

    # Try runner match if platform didn't match and runner is configured
    if [[ -z "$KUBECTL_TARGET" ]] && [[ "${RWLENV_HAS_RUNNER:-false}" == "true" ]]; then
        r_kc_esc=$(escape_regex "$RWLENV_RUNNER_KUBECONFIG")
        r_ctx_esc=$(escape_regex "$RWLENV_RUNNER_CONTEXT")
        r_ns_esc=$(escape_regex "$RWLENV_RUNNER_NAMESPACE")
        if echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${r_kc_esc}([[:space:]]|$)" && \
           echo "$ORIGINAL_CMD" | grep -qE -- "--context=${r_ctx_esc}([[:space:]]|$)" && \
           echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${r_ns_esc}([[:space:]]|$)"; then
            KUBECTL_TARGET="runner"
        fi
    fi

    # If neither matched, produce appropriate error
    if [[ -z "$KUBECTL_TARGET" ]]; then
        echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=${kc_esc}([[:space:]]|$)" \
            || block "kubectl command missing or wrong --kubeconfig for rwl-env '$RWLENV_NAME' (expected $RWLENV_KUBECONFIG)."
        echo "$ORIGINAL_CMD" | grep -qE -- "--context=${ctx_esc}([[:space:]]|$)" \
            || block "kubectl command missing or wrong --context for rwl-env '$RWLENV_NAME' (expected $RWLENV_CONTEXT)."
        echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)[[:space:]]+${ns_esc}([[:space:]]|$)" \
            || block "kubectl command missing or wrong -n/--namespace for rwl-env '$RWLENV_NAME' (expected $RWLENV_NAMESPACE)."
        block "kubectl command credentials do not match any configured target for rwl-env '$RWLENV_NAME'."
    fi

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
                # If the inner command invokes psql, validate it.
                if echo "$ORIGINAL_CMD" | grep -qE "[^a-zA-Z0-9_-]psql([[:space:]]|$)"; then
                    # Only -c '<query>' form is supported
                    if ! echo "$ORIGINAL_CMD" | grep -qE -- "psql[[:space:]]+([^|;&]*[[:space:]]+)?-c[[:space:]]+['\"]"; then
                        block "psql via kubectl exec must use -c '<query>' form for rwl-env '$RWLENV_NAME'; -f/stdin/interactive psql are not auto-approvable."
                    fi
                    # Extract query between first matching pair of quotes after -c
                    query=$(echo "$ORIGINAL_CMD" \
                        | sed -n "s/.*psql[^|;&]*-c[[:space:]]*'\\([^']*\\)'.*/\\1/p")
                    if [[ -z "$query" ]]; then
                        # Try double quotes
                        query=$(echo "$ORIGINAL_CMD" \
                            | sed -n 's/.*psql[^|;&]*-c[[:space:]]*"\([^"]*\)".*/\1/p')
                    fi
                    if [[ -z "$query" ]]; then
                        block "could not extract psql -c query for validation in rwl-env '$RWLENV_NAME'; reformulate with single-quoted -c '<query>'."
                    fi
                    # Validate read-only safety
                    validate_psql_query "$query" 2>/tmp/rwl-env-psql-err.$$ || {
                        msg=$(cat /tmp/rwl-env-psql-err.$$)
                        rm -f /tmp/rwl-env-psql-err.$$
                        block "$msg"
                    }
                    rm -f /tmp/rwl-env-psql-err.$$
                fi
                # Interactive shells (sh/bash without psql) pass through
                ;;
            *)
                block "kubectl '$kubectl_sub' not allowed for rwl-env '$RWLENV_NAME'; mutations must go through helm-ops (helm upgrade / rollback)."
                ;;
        esac
    fi

    allow
fi

# Standalone psql (not under kubectl exec) is not validated in v0.
# It's reachable only if the user has set up a port-forward (which kubectl exec
# allows) and then runs psql directly against 127.0.0.1. Out of scope for now;
# revisit if real usage surfaces it.

allow
