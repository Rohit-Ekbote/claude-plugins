#!/usr/bin/env bash
# test-structure.sh - Static structural lint for the fde-tools plugin.
# Grows one assertion block per implementation task.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CMD="$PLUGIN_DIR/commands"

PASS=0; FAIL=0
assert_file() {
    if [ -f "$1" ]; then printf "  PASS: %s\n" "$2"; PASS=$((PASS+1));
    else printf "  FAIL: %s (missing: %s)\n" "$2" "$1"; FAIL=$((FAIL+1)); fi
}
assert_grep() {
    if grep -qE "$1" "$2" 2>/dev/null; then printf "  PASS: %s\n" "$3"; PASS=$((PASS+1));
    else printf "  FAIL: %s (pattern '%s' not in %s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1)); fi
}
assert_no_grep() {
    if grep -qE "$1" "$2" 2>/dev/null; then printf "  FAIL: %s (forbidden '%s' found in %s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1));
    else printf "  PASS: %s\n" "$3"; PASS=$((PASS+1)); fi
}

echo "== Task 1: plugin manifest =="
assert_file "$PLUGIN_DIR/.claude-plugin/plugin.json" "plugin.json exists"
grep -q '"name": *"fde-tools"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null \
  && { echo "  PASS: plugin.json names fde-tools"; PASS=$((PASS+1)); } \
  || { echo "  FAIL: plugin.json does not name fde-tools"; FAIL=$((FAIL+1)); }

echo "== Task 2: _engagement-context include =="
assert_file "$CMD/_engagement-context.md" "_engagement-context.md exists"
assert_no_grep "~/.claude/commands" "$CMD/_engagement-context.md" "no home-path refs in context include"
assert_grep "latest-wins-by-topic" "$CMD/_engagement-context.md" "context include defines resolver"

echo "== Task 3: _date-parsing include =="
assert_file "$CMD/_date-parsing.md" "_date-parsing.md exists"
assert_grep "Date sources" "$CMD/_date-parsing.md" "date-parsing lists source priority"
assert_grep "date unknown" "$CMD/_date-parsing.md" "date-parsing defines ambiguity fallback"

# --- later tasks append assertion blocks below this line ---

echo ""
echo "TOTAL: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
