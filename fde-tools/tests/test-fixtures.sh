#!/usr/bin/env bash
# test-fixtures.sh - Assert the sample engagement fixture is complete and read-only-safe to use.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FX="$SCRIPT_DIR/fixtures/sample-engagement"
PASS=0; FAIL=0
ok() { printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== fixture completeness =="
[ -d "$FX/granola" ] && [ -d "$FX/slack" ] && [ -d "$FX/raw" ] && ok "all three source dirs present" || no "missing a source dir"

# Date sources: filename date, body date, slack timestamp, raw date.
grep -q "2026-03-12" "$FX/granola/2026-03-12-kickoff.md" && ok "granola body date present" || no "granola body date missing"
grep -q "2026-03-19" "$FX/slack/eng-channel.txt" && ok "slack timestamp present" || no "slack timestamp missing"
grep -q "2026-04-01" "$FX/raw/field-notes.txt" && ok "raw date present" || no "raw date missing"

# Planted contradiction: NFS-only vs block storage.
grep -qi "NFS-only" "$FX/granola/2026-03-12-kickoff.md" && grep -qi "block storage" "$FX/slack/eng-channel.txt" \
  && ok "material contradiction planted" || no "contradiction not planted"

# Feature asks for update-requirements.
grep -qi "ask" "$FX/granola/2026-03-12-kickoff.md" && grep -qi "ask" "$FX/slack/eng-channel.txt" \
  && ok "feature asks present in two forums" || no "feature asks missing"

echo ""
echo "TOTAL: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
