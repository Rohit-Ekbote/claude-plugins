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
    grep -v '^[[:space:]]*#' "$CATALOG" \
        | grep -Eo "${field}:[[:space:]]*\[[^]]*\]" \
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

# Check 6: consumers: metadata shape — equals/contains must be arrays of
# non-empty string keys, and no other keys allowed under consumers.
if ! ruby -ryaml -e '
  cat = YAML.load_file(ARGV[0]); bad = []
  walk = lambda do |pl|
    (pl || []).each do |p|
      next unless p.is_a?(Hash) && p["consumers"]
      c = p["consumers"]
      unless c.is_a?(Hash) && (c.keys - ["equals", "contains"]).empty?
        bad << p["id"]; next
      end
      ["equals", "contains"].each do |k|
        next unless c.key?(k)
        ok = c[k].is_a?(Array) && !c[k].empty? && c[k].all? { |x| x.is_a?(String) && !x.strip.empty? }
        bad << p["id"] unless ok
      end
    end
  end
  (cat["axes"] || []).each { |a| walk.call(a["params"]); (a["options"] || []).each { |o| walk.call(o["params"]) } }
  abort("bad consumers: #{bad.uniq.join(", ")}") unless bad.empty?
' "$CATALOG" 2>/dev/null; then
    fail "malformed consumers: metadata (equals/contains must be non-empty arrays of key names)"
fi

# Check 7 ([6]): if ANY option emits postgresql.spilo.*, at least one option must
# pin postgresql.kind: spilo. The chart default is spilo (values.yaml:623) but the
# wizard must emit it explicitly so a byo/external overlay layered on top is the
# ONLY thing that flips kind — never an implicit default.
if ! ruby -ryaml -e '
  cat = YAML.load_file(ARGV[0])
  spilo = false; pinned = false
  (cat["axes"] || []).each do |a|
    (a["options"] || []).each do |o|
      em = o["emits"]; next unless em.is_a?(Hash)
      pg = em["postgresql"]; next unless pg.is_a?(Hash)
      spilo = true if pg["spilo"]
      pinned = true if pg["kind"] == "spilo"
    end
  end
  abort("postgresql.spilo.* emitted but no option pins postgresql.kind: spilo") if spilo && !pinned
' "$CATALOG" 2>/dev/null; then
    fail "postgresql.spilo.* emitted but no option pins postgresql.kind: spilo"
fi

# Check 8 ([1]): the chart fail-fasts (templates/llm-gateway/configmap.yaml) when
# llmGateway.deploy=true and neither models[] nor configMapName is set. Enforce the
# XOR at emit time so no option can leave that latent hard-fail.
if ! ruby -ryaml -e '
  cat = YAML.load_file(ARGV[0]); bad = []
  (cat["axes"] || []).each do |a|
    (a["options"] || []).each do |o|
      em = o["emits"]; next unless em.is_a?(Hash)
      lg = em["llmGateway"]; next unless lg.is_a?(Hash) && lg["deploy"] == true
      has_models = lg["models"].is_a?(Array) && !lg["models"].empty?
      has_cmn    = lg["configMapName"].is_a?(String) && !lg["configMapName"].strip.empty?
      bad << o["id"] unless has_models ^ has_cmn
    end
  end
  abort("llmGateway.deploy:true requires models[] XOR configMapName: #{bad.join(", ")}") unless bad.empty?
' "$CATALOG" 2>/dev/null; then
    fail "an option sets llmGateway.deploy:true without exactly one of models[] / configMapName"
fi

exit "$problems"
