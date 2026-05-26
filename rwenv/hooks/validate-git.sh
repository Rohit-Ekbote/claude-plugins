#!/usr/bin/env bash
# validate-git.sh - Git branch protection for rwenv
#
# Protects the main branch in the current project (working directory)
# while allowing main branch operations in rwenv-related repositories.
#
# Rules:
# - Current project: Block commit/push/merge to main/master
# - Current project: Block tag operations unless repo is under github/Rohit-Ekbote
# - Flux repos + read-only rwenv: Block commit/push to main/master
# - Flux repos + not read-only: Allow all operations
# - Other external repos: Allow all operations
#
# Claude Code PreToolUse hooks receive JSON on stdin and must use exit code 2 to block.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities
source "$PLUGIN_DIR/lib/rwenv-utils.sh"

# Protected branches
PROTECTED_BRANCHES="main|master|production"

# Read JSON input from stdin
INPUT_JSON=$(cat)

# Extract the command from the JSON input
ORIGINAL_CMD=$(echo "$INPUT_JSON" | jq -r '.tool_input.command // empty')

# If no command found, auto-approve
if [[ -z "$ORIGINAL_CMD" ]]; then
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# Check if command contains any git operations (handles compound commands)
if ! echo "$ORIGINAL_CMD" | grep -qE "(^|&&|;|\|\|)\s*git "; then
    # No git command — auto-approve so this hook doesn't block other hooks' approval
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# Get the starting working directory
STARTING_CWD="${PWD}"

# Source rwenv-env if available (for RWENV_READ_ONLY)
RWENV_ENV_FILE="${PWD}/.claude/rwenv-env"
if [[ -f "$RWENV_ENV_FILE" ]]; then
    source "$RWENV_ENV_FILE"
fi

# Resolve a path (handles ~, relative paths, etc.)
resolve_path() {
    local path="$1"
    local base_dir="$2"

    # Expand ~ to home directory
    path="${path/#\~/$HOME}"

    # If absolute path, return it
    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        # Relative path - resolve from base_dir
        echo "$base_dir/$path"
    fi
}

# Extract -C path from git command (git -C <path> ...)
# Uses grep/sed due to Bash 3.2 regex capture group limitations on macOS
get_git_c_path() {
    local git_cmd="$1"

    # Extract path after -C using sed
    # Handles: git -C /path/to/dir commit, git -C "/path with spaces" commit
    local c_path
    c_path=$(echo "$git_cmd" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]*\([^[:space:]"'\'']*\|"[^"]*"\|'\''[^'\'']*'\''\).*/\1/p' | head -1)

    # If no match, try simpler extraction
    if [[ -z "$c_path" ]]; then
        c_path=$(echo "$git_cmd" | grep -oE '\-C[[:space:]]+[^[:space:]]+' | head -1 | sed 's/-C[[:space:]]*//')
    fi

    # Remove quotes if present
    if [[ -n "$c_path" ]]; then
        c_path=$(echo "$c_path" | sed "s/^['\"]//;s/['\"]$//")
        echo "$c_path"
    fi
}

# Extract effective working directory from compound command up to a git command
# Tracks cd commands to determine where git will actually run
# Also handles git -C <path> syntax
get_effective_cwd_for_git() {
    local full_cmd="$1"
    local git_cmd="$2"
    local effective_cwd="$STARTING_CWD"

    # First, check if the git command has -C flag
    local git_c_path
    git_c_path=$(get_git_c_path "$git_cmd")
    if [[ -n "$git_c_path" ]]; then
        # -C path takes precedence - resolve it relative to starting cwd
        # (cd commands before it don't affect -C path resolution in actual shell)
        effective_cwd=$(resolve_path "$git_c_path" "$STARTING_CWD")
        echo "$effective_cwd"
        return
    fi

    # No -C flag, track cd commands before this git command
    local before_git
    before_git=$(echo "$full_cmd" | sed "s|$git_cmd.*||")

    # Extract cd commands and track directory changes
    while read -r segment; do
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ "$segment" =~ ^cd[[:space:]]+(.*) ]]; then
            local cd_target="${BASH_REMATCH[1]}"
            # Remove quotes if present
            cd_target=$(echo "$cd_target" | sed "s/^['\"]//;s/['\"]$//")
            effective_cwd=$(resolve_path "$cd_target" "$effective_cwd")
        fi
    done < <(echo "$before_git" | tr ';&' '\n' | grep -E "^\s*cd\s")

    echo "$effective_cwd"
}

# Extract git commands from compound command string
extract_git_commands() {
    local cmd="$1"
    # Split by && || ; and filter for git commands
    echo "$cmd" | tr ';&|' '\n' | grep -E "^\s*git\s" | sed 's/^[[:space:]]*//'
}

# Check if a directory is the current project (where Claude Code was started)
is_current_project_dir() {
    local check_dir="$1"

    # Normalize the check directory
    local normalized_check_dir
    normalized_check_dir=$(cd "$check_dir" 2>/dev/null && pwd -P) || return 1

    # Get git root for the check directory
    local check_git_root
    check_git_root=$(cd "$check_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1

    # Normalize starting cwd
    local normalized_starting_cwd
    normalized_starting_cwd=$(cd "$STARTING_CWD" && pwd -P)

    # Get git root for starting cwd
    local starting_git_root
    starting_git_root=$(cd "$STARTING_CWD" && git rev-parse --show-toplevel 2>/dev/null) || return 1

    # Compare git roots - if they're the same, it's the current project
    # This handles worktrees correctly since they share the same git root
    if [[ "$check_git_root" == "$starting_git_root" ]]; then
        return 0  # Same project
    fi

    # Also check if check_dir is within the starting cwd tree (for nested repos edge case)
    if [[ "$normalized_check_dir" == "$normalized_starting_cwd"* ]]; then
        return 0  # Is within current project tree
    fi

    return 1  # External repo
}

# Check if a directory is under an rwenv flux repo
is_flux_repo_dir() {
    local check_dir="$1"
    local normalized_check_dir
    normalized_check_dir=$(cd "$check_dir" 2>/dev/null && pwd -P) || return 1
    local flux_repos_dir="${HOME}/.claude/rwenv/flux-repos"
    [[ "$normalized_check_dir" == "$flux_repos_dir"* ]]
}

# Check if a directory is under a Rohit-Ekbote owned repo
is_owned_repo() {
    local check_dir="$1"
    local git_root
    git_root=$(cd "$check_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ "$git_root" == *"github.com/Rohit-Ekbote"* || "$git_root" == *"github/Rohit-Ekbote"* ]]
}

# Get current branch name for a specific directory
get_current_branch() {
    local dir="${1:-$STARTING_CWD}"
    (cd "$dir" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null) || echo ""
}

# Get git root for a specific directory
get_git_root() {
    local dir="${1:-$STARTING_CWD}"
    (cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || echo ""
}

# Check if a branch name is protected
is_protected_branch() {
    local branch="$1"
    echo "$branch" | grep -qE "^($PROTECTED_BRANCHES)$"
}

# Extract the git subcommand, ignoring global options like -C, -c, --git-dir, etc.
# e.g., "git -C /path commit -m test" -> "commit"
get_git_subcommand() {
    local git_cmd="$1"

    # Remove 'git' prefix and global options to find the subcommand
    # Global options: -C <path>, -c <name>=<value>, --git-dir=<path>, --work-tree=<path>, etc.
    echo "$git_cmd" | sed -E '
        s/^git[[:space:]]+//;                           # Remove git prefix
        s/-C[[:space:]]+[^[:space:]]+[[:space:]]+//g;   # Remove -C <path>
        s/-c[[:space:]]+[^[:space:]]+[[:space:]]+//g;   # Remove -c name=value
        s/--git-dir[=[:space:]][^[:space:]]+[[:space:]]+//g;  # Remove --git-dir
        s/--work-tree[=[:space:]][^[:space:]]+[[:space:]]+//g; # Remove --work-tree
        s/^[[:space:]]*//;                              # Trim leading whitespace
    ' | cut -d' ' -f1
}

# Check if git command is a specific subcommand (handles -C and other global options)
is_git_subcommand() {
    local git_cmd="$1"
    local subcommand="$2"
    local actual_subcmd
    actual_subcmd=$(get_git_subcommand "$git_cmd")
    [[ "$actual_subcmd" == "$subcommand" ]]
}

# Extract target branch from git commands
get_target_branch_from_cmd() {
    local cmd="$1"

    # git push origin main
    if echo "$cmd" | grep -qE "git push .* ($PROTECTED_BRANCHES)"; then
        echo "$cmd" | grep -oE "($PROTECTED_BRANCHES)" | head -1
        return
    fi

    # git push (to current branch if it's protected)
    if echo "$cmd" | grep -qE "^git push(\s|$)"; then
        get_current_branch
        return
    fi

    # git merge main, git merge origin/main
    if echo "$cmd" | grep -qE "git merge .*(^|/|\\s)($PROTECTED_BRANCHES)"; then
        echo "$cmd" | grep -oE "($PROTECTED_BRANCHES)" | head -1
        return
    fi

    echo ""
}

# Check for dangerous git operations on protected branches
# Takes: git_cmd (the git command), effective_cwd (directory where it runs)
check_git_safety() {
    local git_cmd="$1"
    local effective_cwd="$2"
    local current_branch
    local git_root

    # Get branch and git root for the effective directory
    current_branch=$(get_current_branch "$effective_cwd")
    git_root=$(get_git_root "$effective_cwd")

    # Skip if not in a git repo
    if [[ -z "$git_root" ]]; then
        return 0
    fi

    # --- Determine scope: current project, flux repo, or other external ---

    if is_current_project_dir "$effective_cwd"; then
        # === CURRENT PROJECT RULES ===

        # Block: commit to protected branch
        if is_git_subcommand "$git_cmd" "commit"; then
            if is_protected_branch "$current_branch"; then
                cat >&2 <<EOF
ERROR: Cannot commit directly to '$current_branch' branch in current project.

Current branch: $current_branch
Project: $git_root

Create a feature branch instead:
  git checkout -b feature/my-change
EOF
                exit 2
            fi
        fi

        # Block: push to protected branch
        if is_git_subcommand "$git_cmd" "push"; then
            local target_branch
            target_branch=$(get_target_branch_from_cmd "$git_cmd")
            if [[ -z "$target_branch" ]]; then
                target_branch="$current_branch"
            fi
            if is_protected_branch "$target_branch"; then
                cat >&2 <<EOF
ERROR: Cannot push to '$target_branch' branch in current project.

Command: $git_cmd
Project: $git_root

Push to a feature branch and create a pull request instead.
EOF
                exit 2
            fi
        fi

        # Block: merge into protected branch
        if is_git_subcommand "$git_cmd" "merge"; then
            if is_protected_branch "$current_branch"; then
                cat >&2 <<EOF
ERROR: Cannot merge into '$current_branch' branch directly in current project.

Use a pull request to merge changes into $current_branch.
EOF
                exit 2
            fi
        fi

        # Block: tag operations (unless repo is under Rohit-Ekbote)
        if ! is_owned_repo "$effective_cwd"; then
            if is_git_subcommand "$git_cmd" "tag" && ! echo "$git_cmd" | grep -qE "git.*tag.*(-l|--list)"; then
                cat >&2 <<EOF
ERROR: Cannot create or modify tags in current project.

Command: $git_cmd
Project: $git_root

Tag operations should be performed through CI/CD pipelines or release processes.
EOF
                exit 2
            fi

            if is_git_subcommand "$git_cmd" "push" && echo "$git_cmd" | grep -qE "\-\-tags"; then
                cat >&2 <<EOF
ERROR: Cannot push tags in current project.

Command: $git_cmd
Project: $git_root
EOF
                exit 2
            fi

            if is_git_subcommand "$git_cmd" "push" && echo "$git_cmd" | grep -qE ":refs/tags/"; then
                cat >&2 <<EOF
ERROR: Cannot delete remote tags in current project.

Command: $git_cmd
Project: $git_root
EOF
                exit 2
            fi
        fi

        # Block: push --delete of protected branches
        if is_git_subcommand "$git_cmd" "push" && echo "$git_cmd" | grep -qE "\-\-delete"; then
            if echo "$git_cmd" | grep -qE "\-\-delete[[:space:]]+($PROTECTED_BRANCHES)(\s|$)"; then
                cat >&2 <<EOF
ERROR: Cannot delete protected branch in current project.

Command: $git_cmd
Project: $git_root
EOF
                exit 2
            fi
        fi

        # Warn: git reset --hard on protected branch
        if is_git_subcommand "$git_cmd" "reset" && echo "$git_cmd" | grep -qE "\-\-hard"; then
            if is_protected_branch "$current_branch"; then
                cat >&2 <<EOF
WARNING: Running 'git reset --hard' on '$current_branch' branch.

This is a destructive operation. Proceeding with caution.
EOF
            fi
        fi

    elif is_flux_repo_dir "$effective_cwd"; then
        # === FLUX REPO RULES ===

        # If rwenv is read-only, block commit/push to protected branches
        if [[ "${RWENV_READ_ONLY:-false}" == "true" ]]; then
            if is_git_subcommand "$git_cmd" "commit"; then
                if is_protected_branch "$current_branch"; then
                    cat >&2 <<EOF
ERROR: Cannot commit to '$current_branch' in flux repo — rwenv '$RWENV_NAME' is read-only.

Current branch: $current_branch
Repo: $git_root

Use a non-read-only rwenv for write operations on flux repos.
EOF
                    exit 2
                fi
            fi

            if is_git_subcommand "$git_cmd" "push"; then
                local target_branch
                target_branch=$(get_target_branch_from_cmd "$git_cmd")
                if [[ -z "$target_branch" ]]; then
                    target_branch="$current_branch"
                fi
                if is_protected_branch "$target_branch"; then
                    cat >&2 <<EOF
ERROR: Cannot push to '$target_branch' in flux repo — rwenv '$RWENV_NAME' is read-only.

Repo: $git_root

Use a non-read-only rwenv for write operations on flux repos.
EOF
                    exit 2
                fi
            fi
        fi
        # Not read-only: allow all flux repo operations (including main)

    fi
    # Other external repos: no restrictions

    return 0
}

# Main execution - process all git commands in compound command
HAS_GIT_CMD=false

# Split by command separators and process each git command
while IFS= read -r git_cmd; do
    # Skip empty lines
    [[ -z "$git_cmd" ]] && continue

    # Trim whitespace
    git_cmd=$(echo "$git_cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip if not a git command
    [[ ! "$git_cmd" =~ ^git[[:space:]] ]] && continue

    HAS_GIT_CMD=true

    # Determine effective working directory for this git command
    effective_cwd=$(get_effective_cwd_for_git "$ORIGINAL_CMD" "$git_cmd")

    # Check git safety for this command
    check_git_safety "$git_cmd" "$effective_cwd"
done < <(echo "$ORIGINAL_CMD" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g')

# Auto-approve git commands that passed all safety checks
if [[ "$HAS_GIT_CMD" == "true" ]]; then
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# No git commands — auto-approve so this hook doesn't block other hooks' approval
echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
exit 0
