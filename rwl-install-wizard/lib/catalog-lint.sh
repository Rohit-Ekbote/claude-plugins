#!/usr/bin/env bash
# catalog-lint.sh - Validate knob-catalog.yaml + data/ integrity.
#
# Usage: catalog-lint.sh <knob-catalog.yaml> <data-dir>
# Exit:  0 = clean, 1 = problems found (printed to stderr)
#
# Heuristic, line-oriented checks (bash 3.2, no YAML parser). Relies on the
# authoring rule that `guide_sections:` / `known_issues:` are single-line inline
# arrays, e.g.  guide_sections: [a, b]
#   1. Every id in guide_sections has data/guide-sections/<id>.md
#   2. Every id in known_issues  has data/known-issues/<id>.md
#   3. No orphan (unreferenced) .md files in those dirs
#   4. No inline secret-shaped content in the catalog (reuses secret-guard.sh)
#   5. Every `- id:` block declares at least one of label/title/question
set -uo pipefail

CATALOG="${1:-}"; DATA="${2:-}"
[ -f "$CATALOG" ] || { echo "catalog-lint: catalog not found: $CATALOG" >&2; exit 1; }
[ -d "$DATA" ]    || { echo "catalog-lint: data dir not found: $DATA" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/secret-guard.sh"

problems=0
fail() { printf 'catalog-lint: %s\n' "$1" >&2; problems=1; }

# Extract ids from inline arrays for a given field name; one id per line.
extract_ids() {
    field="$1"
    grep -Eo "${field}:[[:space:]]*\[[^]]*\]" "$CATALOG" \
        | sed -E "s/${field}:[[:space:]]*\[//; s/\]//" \
        | tr ',' '\n' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | grep -v '^$'
}

# 1 & 2: referenced ids must have backing files.
check_refs() {
    field="$1"; subdir="$2"
    ids="$(extract_ids "$field" | sort -u)"
    OLDIFS="$IFS"; IFS='
'
    for id in $ids; do
        [ -n "$id" ] || continue
        [ -f "$DATA/$subdir/$id.md" ] || fail "referenced file not found: $subdir/$id.md (from $field)"
    done
    IFS="$OLDIFS"
}
check_refs guide_sections guide-sections
check_refs known_issues known-issues

# 3: orphan files.
check_orphans() {
    field="$1"; subdir="$2"
    [ -d "$DATA/$subdir" ] || return 0
    refs="$(extract_ids "$field" | sort -u)"
    for path in "$DATA/$subdir"/*.md; do
        [ -e "$path" ] || continue
        base="$(basename "$path" .md)"
        case "
$refs
" in
            *"
$base
"*) : ;;
            *) fail "orphan (unreferenced) file: $subdir/$base.md" ;;
        esac
    done
}
check_orphans guide_sections guide-sections
check_orphans known_issues known-issues

# 4: no inline secret-shaped content in the catalog.
if ! bash "$GUARD" "$CATALOG" >/dev/null 2>&1; then
    fail "secret-guard flagged inline secret-shaped content in catalog"
fi

# Check 5: every option/axis `- id:` block declares label/title/question.
# `- id:` lines nested inside an `emits:` block are skipped (emits is arbitrary
# chart YAML and may legitimately contain `- id:` list items).
if ! awk '
  { p=match($0, /[^ ]/); indent=(p?p-1:length($0)) }
  /^[[:space:]]*emits:/ { in_emits=1; emits_indent=indent; next }
  in_emits && /[^ ]/ && indent <= emits_indent { in_emits=0 }
  /^[[:space:]]*-[[:space:]]+id:/ {
      if (in_emits) next
      if (in_blk && !ok) bad++
      in_blk=1; ok=0; next
  }
  /^[[:space:]]*(label|title|question):/ { if (in_blk) ok=1 }
  END { if (in_blk && !ok) bad++; if (bad>0) exit 1; exit 0 }
' "$CATALOG"; then
    fail "one or more - id: blocks lack a label/title/question"
fi

exit "$problems"
