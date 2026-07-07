#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$DIR")"
REPO="$(cd "$SKILL/../../.." && pwd)"
CATALOG="$REPO/rwl-install-wizard/data/knob-catalog.yaml"
PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
out="$(ruby "$SKILL/gen-overlays.rb" "$CATALOG" "$TMP" mirrored-per-upstream)"
echo "== gen-overlays renders mirrored-per-upstream =="
[ "$out" = "values-registry.yaml" ] && ok "prints overlay filename" || no "overlay filename (got '$out')"
f="$TMP/values-registry.yaml"
grep -q 'docker-dockerhub' "$f" && ok "substitutes registry host" || no "registry host not substituted"
grep -q '<REGISTRY_HOST>' "$f" && no "placeholder survived" || ok "no placeholder survived"
ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f" && ok "overlay parses as YAML" || no "overlay invalid YAML"

echo "== options with empty emits produce nothing =="
out2="$(ruby "$SKILL/gen-overlays.rb" "$CATALOG" "$TMP" connected)"
[ -z "$out2" ] && ok "connected (empty emits) prints nothing" || no "connected printed '$out2'"
rm -rf "$TMP"
echo ""; echo "gen-overlays: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
