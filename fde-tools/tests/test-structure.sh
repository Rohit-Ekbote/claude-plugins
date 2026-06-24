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

echo "== Task 4: guide assets =="
assert_file "$PLUGIN_DIR/assets/fde-guide.css" "fde-guide.css exists"
assert_file "$PLUGIN_DIR/assets/fde-guide-page.html.tmpl" "page template exists"
assert_grep "\\{\\{PAGE_BODY\\}\\}" "$PLUGIN_DIR/assets/fde-guide-page.html.tmpl" "template has PAGE_BODY token"
assert_grep "\\{\\{PAGER\\}\\}" "$PLUGIN_DIR/assets/fde-guide-page.html.tmpl" "template has PAGER token"

echo "== Task 5: build-guide command =="
assert_file "$CMD/build-guide.md" "build-guide.md exists"
assert_no_grep "~/.claude/commands" "$CMD/build-guide.md" "no home-path refs in build-guide"
assert_grep "CLAUDE_PLUGIN_ROOT" "$CMD/build-guide.md" "build-guide uses plugin-root refs"

echo "== Task 6: summarize-engagement command =="
assert_file "$CMD/summarize-engagement.md" "summarize-engagement.md exists"
assert_no_grep "~/.claude/commands" "$CMD/summarize-engagement.md" "no home-path refs in summarize"
assert_grep "How we solve each requirement" "$CMD/summarize-engagement.md" "summary keeps fixed sections"

echo "== Task 7: update-progress command =="
assert_file "$CMD/update-progress.md" "update-progress.md exists"
assert_no_grep "~/.claude/commands" "$CMD/update-progress.md" "no home-path refs in update-progress"
assert_grep "_date-parsing.md" "$CMD/update-progress.md" "update-progress references date-parsing include"
assert_grep "New blockers" "$CMD/update-progress.md" "update-progress keeps section structure"

echo "== Task 8: update-requirements command =="
assert_file "$CMD/update-requirements.md" "update-requirements.md exists"
assert_no_grep "~/.claude/commands" "$CMD/update-requirements.md" "no home-path refs in update-requirements"
assert_grep "_date-parsing.md" "$CMD/update-requirements.md" "requirements references date-parsing include"
assert_grep "requirements.md" "$CMD/update-requirements.md" "requirements writes requirements.md"

echo "== Task 9: qna command + engine =="
assert_file "$CMD/_qna-engine.md" "_qna-engine.md exists"
assert_file "$CMD/qna.md" "qna.md exists"
assert_no_grep "~/.claude/commands" "$CMD/qna.md" "no home-path refs in qna"
assert_grep "changelog.md" "$CMD/_qna-engine.md" "qna-engine defines changelog audit trail"
assert_grep "append-only" "$CMD/_qna-engine.md" "qna-engine marks changelog append-only"
assert_grep "read-only" "$CMD/_qna-engine.md" "qna-engine keeps raw inputs read-only"

echo "== Task 10: fixtures =="
FX="$PLUGIN_DIR/tests/fixtures/sample-engagement"
assert_file "$FX/granola/2026-03-12-kickoff.md" "kickoff fixture exists"
assert_file "$FX/slack/eng-channel.txt" "slack fixture exists"
assert_file "$FX/raw/field-notes.txt" "raw fixture exists"

# --- later tasks append assertion blocks below this line ---

echo ""
echo "TOTAL: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
