#!/usr/bin/env bash
# validate-git.sh - Git branch protection for rwenv
#
# Protects the main branch in the current project (working directory)
# while allowing main branch operations in rwenv-related repositories.
#
# Rules:
# - Current project (cwd): Block push/commit/merge to main/master
# - rwenv repos (not cwd): Allow all git operations including main branch

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities
source "$PLUGIN_DIR/lib/rwenv-utils.sh"

# Protected branches
PROTECTED_BRANCHES="main|master|production"

# Parse the git command
ORIGINAL_CMD="$*"

# Check if this is a git command
if ! echo "$ORIGINAL_CMD" | grep -q "^git "; then
    # Not a git command, pass through
    echo "$ORIGINAL_CMD"
    exit 0
fi

# Get current working directory and git root
CWD="${PWD}"
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    # Not in a git repository, pass through
    echo "$ORIGINAL_CMD"
    exit 0
}

# Check if we're operating on the current project or an external repo
# External repos include flux repos cloned elsewhere, rwenv config repos, etc.
is_current_project() {
    # Normalize paths for comparison
    local normalized_cwd normalized_git_root
    normalized_cwd=$(cd "$CWD" && pwd -P)
    normalized_git_root=$(cd "$GIT_ROOT" && pwd -P)

    # Check if git root is within or equal to cwd
    # This handles worktrees as well
    if [[ "$normalized_cwd" == "$normalized_git_root"* ]]; then
        return 0  # Is current project
    fi

    return 1  # External repo
}

# Get current branch name
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

# Check if a branch name is protected
is_protected_branch() {
    local branch="$1"
    echo "$branch" | grep -qE "^($PROTECTED_BRANCHES)$"
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
check_git_safety() {
    local cmd="$1"
    local current_branch
    current_branch=$(get_current_branch)

    # Only enforce protection for current project
    if ! is_current_project; then
        return 0  # Allow all operations on external repos
    fi

    # Check: git commit while on protected branch
    if echo "$cmd" | grep -qE "^git commit"; then
        if is_protected_branch "$current_branch"; then
            cat >&2 <<EOF
ERROR: Cannot commit directly to '$current_branch' branch in current project.

Current branch: $current_branch
Project: $GIT_ROOT

Create a feature branch instead:
  git checkout -b feature/my-change
  git commit ...
  git push -u origin feature/my-change

Then create a pull request to merge into $current_branch.
EOF
            exit 1
        fi
    fi

    # Check: git push to protected branch
    if echo "$cmd" | grep -qE "^git push"; then
        local target_branch
        target_branch=$(get_target_branch_from_cmd "$cmd")

        if is_protected_branch "$target_branch"; then
            cat >&2 <<EOF
ERROR: Cannot push to '$target_branch' branch in current project.

Command: $cmd
Project: $GIT_ROOT

Push to a feature branch instead and create a pull request:
  git push -u origin feature/my-change

Then create a pull request to merge into $target_branch.
EOF
            exit 1
        fi

        # Also check if current branch is protected (for plain 'git push')
        if [[ -z "$target_branch" ]] && is_protected_branch "$current_branch"; then
            cat >&2 <<EOF
ERROR: Cannot push from '$current_branch' branch in current project.

Current branch: $current_branch
Project: $GIT_ROOT

Create a feature branch instead:
  git checkout -b feature/my-change
  git push -u origin feature/my-change
EOF
            exit 1
        fi
    fi

    # Check: git merge into protected branch (when on protected branch)
    if echo "$cmd" | grep -qE "^git merge"; then
        if is_protected_branch "$current_branch"; then
            cat >&2 <<EOF
ERROR: Cannot merge into '$current_branch' branch directly in current project.

Current branch: $current_branch
Project: $GIT_ROOT

Use a pull request to merge changes into $current_branch.
EOF
            exit 1
        fi
    fi

    # Check: git checkout main/master (allow, but warn)
    # This is allowed as reading/checking out is fine

    # Check: git reset --hard on protected branch
    if echo "$cmd" | grep -qE "git reset --hard"; then
        if is_protected_branch "$current_branch"; then
            cat >&2 <<EOF
WARNING: Running 'git reset --hard' on '$current_branch' branch.

This is a destructive operation. Proceeding with caution.
EOF
            # Allow but warn - user may need to recover from bad state
        fi
    fi

    return 0
}

# Main execution
check_git_safety "$ORIGINAL_CMD"

# If we get here, command is allowed
echo "$ORIGINAL_CMD"
