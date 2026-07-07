#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$(dirname "$DIR")/lib"
PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

M="$(mktemp)"
cat > "$M" <<'YML'
data:
  VAULT_URL: "https://vault.example.com"
  GRAPH_DB_URI: bolt://neo4j.example.com:7687
  DECOY_URL: "https://nope.example.com"
spec:
  containers:
    - env:
        - name: VAULT_ADDR
          value: "https://vault.example.com"
        - name: DATABASE_URL
          value: "postgresql://runwhen:$(PW)@pg.example.com:5432/litellm"
YML

echo "== configmap-data form (quoted) =="
[ "$(ruby "$LIB/consumer-values.rb" "$M" VAULT_URL)" = "https://vault.example.com" ] && ok "VAULT_URL quoted" || no "VAULT_URL quoted"
echo "== configmap-data form (unquoted) =="
[ "$(ruby "$LIB/consumer-values.rb" "$M" GRAPH_DB_URI)" = "bolt://neo4j.example.com:7687" ] && ok "GRAPH_DB_URI unquoted" || no "GRAPH_DB_URI unquoted"
echo "== pod-env form =="
[ "$(ruby "$LIB/consumer-values.rb" "$M" VAULT_ADDR)" = "https://vault.example.com" ] && ok "VAULT_ADDR env" || no "VAULT_ADDR env"
echo "== composite value returned whole =="
ruby "$LIB/consumer-values.rb" "$M" DATABASE_URL | grep -q 'pg.example.com:5432' && ok "DATABASE_URL composite" || no "DATABASE_URL composite"
echo "== absent key returns nothing =="
[ -z "$(ruby "$LIB/consumer-values.rb" "$M" NOPE_KEY)" ] && ok "absent key empty" || no "absent key empty"
echo "== decoy key not matched by VAULT_URL query =="
[ "$(ruby "$LIB/consumer-values.rb" "$M" VAULT_URL | wc -l | tr -d ' ')" = "1" ] && ok "no decoy bleed" || no "no decoy bleed"
rm -f "$M"
echo ""; echo "consumer-values: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
