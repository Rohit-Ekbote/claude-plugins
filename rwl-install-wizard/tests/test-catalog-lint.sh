#!/usr/bin/env bash
# test-catalog-lint.sh - Unit tests for lib/catalog-lint.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
LINT="$PLUGIN_DIR/lib/catalog-lint.sh"
DATA="$PLUGIN_DIR/data"

PASS=0; FAIL=0
assert_rc() {
    if [ "$1" = "$2" ]; then printf "  PASS: %s\n" "$3"; PASS=$((PASS+1));
    else printf "  FAIL: %s (rc=%s, expected=%s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1)); fi
}

# NOTE: this first case only passes once a later task creates data/knob-catalog.yaml
# and the data/ dir. Until then it FAILS by design (lint exits 1: "data dir not found").
echo "== catalog-lint: real catalog is clean =="
bash "$LINT" "$DATA/knob-catalog.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "0" "shipped catalog passes lint"

echo "== catalog-lint: missing known-issue ref fails =="
bash "$LINT" "$SCRIPT_DIR/fixtures/catalog-bad-missing-ref.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "1" "missing id reference is rejected"

echo "== catalog-lint: inline secret in emits fails =="
bash "$LINT" "$SCRIPT_DIR/fixtures/catalog-bad-inline-secret.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "1" "inline secret in emits is rejected"

echo "== catalog-lint: emits block with nested '- id:' is NOT a false positive =="
TMPL="$(mktemp -d)"
mkdir -p "$TMPL/data/guide-sections" "$TMPL/data/known-issues"
cat > "$TMPL/cat.yaml" <<'YML'
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: on
        label: "On"
        overlay: values-cluster.yaml
        emits:
          someList:
            - id: item1
              value: x
        guide_sections: []
        known_issues: []
YML
bash "$LINT" "$TMPL/cat.yaml" "$TMPL/data" >/dev/null 2>&1
assert_rc "$?" "0" "nested emits '- id:' does not trip label check"
rm -rf "$TMPL"

echo "== catalog-lint: orphan data file is rejected =="
TMPO="$(mktemp -d)"
mkdir -p "$TMPO/data/guide-sections" "$TMPO/data/known-issues"
echo "# orphan" > "$TMPO/data/guide-sections/unused.md"
cat > "$TMPO/cat.yaml" <<'YML'
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: on
        label: "On"
        overlay: values-cluster.yaml
        emits: {}
        guide_sections: []
        known_issues: []
YML
bash "$LINT" "$TMPO/cat.yaml" "$TMPO/data" >/dev/null 2>&1
assert_rc "$?" "1" "orphan unreferenced file is rejected"
rm -rf "$TMPO"

echo "== catalog-lint: option without label/title/question is rejected =="
TMPN="$(mktemp -d)"
mkdir -p "$TMPN/data/guide-sections" "$TMPN/data/known-issues"
cat > "$TMPN/cat.yaml" <<'YML'
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: on
        overlay: values-cluster.yaml
        emits: {}
        guide_sections: []
        known_issues: []
YML
bash "$LINT" "$TMPN/cat.yaml" "$TMPN/data" >/dev/null 2>&1
assert_rc "$?" "1" "option without label is rejected"
rm -rf "$TMPN"

echo "== catalog-lint: malformed consumers: is rejected =="
TMPC="$(mktemp -d)"; mkdir -p "$TMPC/data/guide-sections" "$TMPC/data/known-issues"
cat > "$TMPC/cat.yaml" <<'YML'
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: on
        label: "On"
        overlay: values-cluster.yaml
        params:
          - { id: badp, prompt: "x", consumers: { equals: "VAULT_URL" } }
        emits: { foo: bar }
        guide_sections: []
        known_issues: []
YML
bash "$LINT" "$TMPC/cat.yaml" "$TMPC/data" >/dev/null 2>&1
assert_rc "$?" "1" "malformed consumers (equals not a list) is rejected"
rm -rf "$TMPC"

echo "== catalog-lint: well-formed consumers passes =="
TMPD="$(mktemp -d)"; mkdir -p "$TMPD/data/guide-sections" "$TMPD/data/known-issues"
cat > "$TMPD/cat.yaml" <<'YML'
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: on
        label: "On"
        overlay: values-cluster.yaml
        params:
          - { id: goodp, prompt: "x", consumers: { equals: [VAULT_URL], contains: [DATABASE_URL] } }
        emits: { foo: bar }
        guide_sections: []
        known_issues: []
YML
bash "$LINT" "$TMPD/cat.yaml" "$TMPD/data" >/dev/null 2>&1
assert_rc "$?" "0" "well-formed consumers passes"
rm -rf "$TMPD"

echo "== catalog-lint: postgresql.spilo.* without a kind:spilo pin is rejected =="
TMPS="$(mktemp -d)"; mkdir -p "$TMPS/data/guide-sections" "$TMPS/data/known-issues"
cat > "$TMPS/cat.yaml" <<'YML'
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: on
        label: "On"
        overlay: values-storage.yaml
        emits:
          postgresql:
            spilo:
              persistence:
                kind: pvc
        guide_sections: []
        known_issues: []
YML
bash "$LINT" "$TMPS/cat.yaml" "$TMPS/data" >/dev/null 2>&1
assert_rc "$?" "1" "spilo.* emitted with no option pinning postgresql.kind: spilo is rejected"
rm -rf "$TMPS"

echo ""
echo "catalog-lint: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
