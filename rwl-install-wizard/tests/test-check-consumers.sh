#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(dirname "$DIR")"; LIB="$PLUGIN/lib"
PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

CAT="$(mktemp)"; cat > "$CAT" <<'YML'
axes:
  - id: subcharts
    options:
      - id: byo
        params:
          - { id: vaultAddress, prompt: "x", consumers: { equals: [VAULT_URL, VAULT_ADDR] } }
          - { id: pgHost, prompt: "x", consumers: { contains: [DATABASE_URL] } }
YML
ANS="$(mktemp)"; cat > "$ANS" <<'YML'
answers:
  subcharts: { option: byo, vaultAddress: "https://vault.example.com", pgHost: "pg.example.com" }
YML
GOOD="$(mktemp)"; cat > "$GOOD" <<'YML'
data:
  VAULT_URL: "https://vault.example.com"
spec:
  env:
    - name: VAULT_ADDR
      value: "https://vault.example.com"
    - name: DATABASE_URL
      value: "postgresql://u:$(PW)@pg.example.com:5432/db"
YML
BAD="$(mktemp)"; cat > "$BAD" <<'YML'
data:
  VAULT_URL: "https://vault.airgap.example.com"
spec:
  env:
    - name: VAULT_ADDR
      value: "https://vault.airgap.example.com"
    - name: DATABASE_URL
      value: "postgresql://u:$(PW)@pg.example.com:5432/db"
YML

echo "== correct render: all consumers satisfied (exit 0) =="
ruby "$LIB/check-consumers.rb" "$CAT" "$ANS" "$GOOD" >/dev/null 2>&1
assert(){ [ "$1" = "$2" ] && ok "$3" || no "$3 (got $1)"; }
assert "$?" "0" "good render passes"

echo "== fallback render: VAULT_URL wrong host (exit non-zero) =="
ruby "$LIB/check-consumers.rb" "$CAT" "$ANS" "$BAD" >/dev/null 2>&1
[ "$?" != "0" ] && ok "bad render fails (catches MISSED-11 shape)" || no "bad render should fail"

echo "== dropped consumer: key absent entirely (exit non-zero) =="
EMPTY="$(mktemp)"; echo 'data: {}' > "$EMPTY"
ruby "$LIB/check-consumers.rb" "$CAT" "$ANS" "$EMPTY" >/dev/null 2>&1
[ "$?" != "0" ] && ok "absent consumer fails (input reached nothing)" || no "absent consumer should fail"

rm -f "$CAT" "$ANS" "$GOOD" "$BAD" "$EMPTY"
echo ""; echo "check-consumers: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
