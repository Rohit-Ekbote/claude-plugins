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

# Date sources — one distinct check per source the commands must parse:
# (1) filename date — verified via the dated filename itself, NOT its body
ls "$FX"/granola/2026-03-12-*.md >/dev/null 2>&1 && ok "filename date present (granola filename)" || no "filename date missing"
# (2) body date — a date written into the note content
grep -q "Date: 2026-03-12" "$FX/granola/2026-03-12-kickoff.md" && ok "body date present (granola body)" || no "body date missing"
# (3) slack message timestamp
grep -q "\[2026-03-19" "$FX/slack/eng-channel.txt" && ok "slack timestamp present" || no "slack timestamp missing"
# (4) raw-note date
grep -q "2026-04-01" "$FX/raw/field-notes.txt" && ok "raw date present" || no "raw date missing"

# Planted contradiction: NFS-only vs block storage.
grep -qi "NFS-only" "$FX/granola/2026-03-12-kickoff.md" && grep -qi "block storage" "$FX/slack/eng-channel.txt" \
  && ok "material contradiction planted" || no "contradiction not planted"

# Feature asks for update-requirements — match the distinctive "new ask" marker in both forums,
# not the loose substring "ask" (which also matches "task", "asked", etc.).
grep -qi "new ask" "$FX/granola/2026-03-12-kickoff.md" && grep -qi "new ask" "$FX/slack/eng-channel.txt" \
  && ok "feature asks present in two forums" || no "feature asks missing"

# Product-problem hints for design-solutions (SME dependency + recurring prep-job failure).
grep -qi "SME" "$FX/raw/field-notes.txt" && grep -qi "prep job" "$FX/raw/field-notes.txt" \
  && ok "product-problem hints present (SME dependency + prep-job failure)" || no "product-problem hints missing"

echo ""
echo "TOTAL: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
