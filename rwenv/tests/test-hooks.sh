#!/usr/bin/env bash
# test-hooks.sh - Validate hook JSON output matches Claude Code's expected schema
#
# Catches bugs like:
#   - v0.5.0: Echoed full input JSON back (tool_name/tool_input in response)
#   - v0.5.1: Missing required hookEventName field
#
# Usage:
#   ./rwenv/tests/test-hooks.sh                    # test all hooks
#   ./rwenv/tests/test-hooks.sh rwenv/hooks/transform-commands.sh  # test one hook
#
# Requirements: jq, bash 3.2+

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

PASS=0
FAIL=0
SKIP=0

# --- Colors (if terminal supports them) ---
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    GREEN="" RED="" YELLOW="" DIM="" RESET=""
fi

# --- Test helpers ---

assert_hook_output() {
    local hook="$1"
    local input="$2"
    local description="$3"

    local output exit_code
    # Capture output and exit code in a single invocation
    output=$(echo "$input" | bash "$hook" 2>/dev/null) && exit_code=$? || exit_code=$?

    # Exit 2 = intentional block, skip output validation
    if [[ $exit_code -eq 2 ]]; then
        printf "  ${GREEN}PASS${RESET}: %s ${DIM}(blocked, exit 2)${RESET}\n" "$description"
        PASS=$((PASS + 1))
        return
    fi

    # Must exit 0
    if [[ $exit_code -ne 0 ]]; then
        printf "  ${RED}FAIL${RESET}: %s — exit code %d (expected 0 or 2)\n" "$description" "$exit_code"
        FAIL=$((FAIL + 1))
        return
    fi

    # Must be valid JSON
    if ! echo "$output" | jq empty 2>/dev/null; then
        printf "  ${RED}FAIL${RESET}: %s — invalid JSON output\n" "$description"
        printf "       Got: %s\n" "$output"
        FAIL=$((FAIL + 1))
        return
    fi

    # Must have hookSpecificOutput.hookEventName == "PreToolUse"
    if ! echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1; then
        printf "  ${RED}FAIL${RESET}: %s — missing or wrong hookEventName\n" "$description"
        printf "       Got: %s\n" "$output"
        FAIL=$((FAIL + 1))
        return
    fi

    # Must have hookSpecificOutput.permissionDecision
    if ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1; then
        printf "  ${RED}FAIL${RESET}: %s — missing permissionDecision\n" "$description"
        printf "       Got: %s\n" "$output"
        FAIL=$((FAIL + 1))
        return
    fi

    # Must NOT echo back input fields
    if echo "$output" | jq -e 'has("tool_input") or has("tool_name")' 2>/dev/null | grep -q true; then
        printf "  ${RED}FAIL${RESET}: %s — response contains input fields (tool_input/tool_name)\n" "$description"
        printf "       Got: %s\n" "$output"
        FAIL=$((FAIL + 1))
        return
    fi

    printf "  ${GREEN}PASS${RESET}: %s\n" "$description"
    PASS=$((PASS + 1))
}

# --- Test inputs ---

SIMPLE_CMD='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
GIT_STATUS='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
GIT_COMMIT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}'
KUBECTL_RAW='{"tool_name":"Bash","tool_input":{"command":"kubectl get pods"}}'
EMPTY_CMD='{"tool_name":"Bash","tool_input":{"command":""}}'
EMPTY_JSON='{}'
PYTHON_CMD='{"tool_name":"Bash","tool_input":{"command":"python3 -c \"print(1)\""}}'
GO_CMD='{"tool_name":"Bash","tool_input":{"command":"go test ./..."}}'
DOCKER_EXEC='{"tool_name":"Bash","tool_input":{"command":"docker exec -i alpine-dev-container-zsh-rdebug ls"}}'

# --- Run tests ---

run_tests_for_hook() {
    local hook="$1"
    local basename
    basename="$(basename "$hook")"

    printf "\n${YELLOW}--- %s ---${RESET}\n" "$basename"

    if [[ ! -f "$hook" ]]; then
        printf "  ${RED}SKIP${RESET}: file not found: %s\n" "$hook"
        SKIP=$((SKIP + 1))
        return
    fi

    if [[ ! -x "$hook" ]]; then
        printf "  ${RED}SKIP${RESET}: not executable: %s\n" "$hook"
        SKIP=$((SKIP + 1))
        return
    fi

    # Schema validation tests (all hooks must pass these)
    assert_hook_output "$hook" "$SIMPLE_CMD" "simple command (ls)"
    assert_hook_output "$hook" "$EMPTY_CMD" "empty command"
    assert_hook_output "$hook" "$EMPTY_JSON" "empty JSON input"
    assert_hook_output "$hook" "$DOCKER_EXEC" "docker exec command"

    # Hook-specific tests
    case "$basename" in
        validate-git.sh)
            assert_hook_output "$hook" "$GIT_STATUS" "git status (allowed)"
            assert_hook_output "$hook" "$GIT_COMMIT" "git commit on feature branch (allowed)"
            ;;
        transform-commands.sh)
            assert_hook_output "$hook" "$KUBECTL_RAW" "kubectl without env (should block or allow)"
            ;;
        validate-python-venv.sh)
            assert_hook_output "$hook" "$PYTHON_CMD" "python command (venv check)"
            ;;
        validate-go-venv.sh)
            assert_hook_output "$hook" "$GO_CMD" "go command (go.mod check)"
            ;;
    esac
}

# Determine which hooks to test
if [[ $# -gt 0 ]]; then
    # Test specific hooks passed as arguments
    for hook in "$@"; do
        run_tests_for_hook "$hook"
    done
else
    # Test all known hooks
    run_tests_for_hook "$PLUGIN_DIR/hooks/transform-commands.sh"
    run_tests_for_hook "$PLUGIN_DIR/hooks/validate-git.sh"
    run_tests_for_hook "$HOME/.claude/hooks/validate-python-venv.sh"
    run_tests_for_hook "$HOME/.claude/hooks/validate-go-venv.sh"
fi

# --- Summary ---
printf "\n${DIM}────────────────────────────────${RESET}\n"
printf "Results: ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}" "$PASS" "$FAIL"
if [[ $SKIP -gt 0 ]]; then
    printf ", ${YELLOW}%d skipped${RESET}" "$SKIP"
fi
printf "\n"

[[ $FAIL -eq 0 ]]
