# Value-at-consumer check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mechanically assert that each operator input reaches EVERY rendered consumer that should reflect it (VAULT_URL, DATABASE_URL, api_base, …), so a shape mismatch that drops the value to a chart fallback fails a test.

**Architecture:** Per-param `consumers: {equals, contains}` metadata in `knob-catalog.yaml` (single source of truth). A shared Ruby extractor (`consumer-values.rb`) reads a rendered manifest and returns every value of a given env key (handles configmap-data and pod-env forms). A shared Ruby driver (`check-consumers.rb`) ties a profile's answers × the catalog declarations × the rendered manifest into pass/fail assertions. The plugin render guard runs it per full profile (airgap + a new byo profile); the `rwl-catalog-update` detector runs it opportunistically per option.

**Tech Stack:** Bash 3.2 (macOS default), Ruby stdlib (`yaml`), Helm 3. No new deps.

## Global Constraints

- Bash 3.2 / macOS portable: no `declare -A`, no `${var,,}`, no `|&`, no `grep -P`.
- Ruby stdlib only (`yaml`). No gems, no `jq`.
- The value-at-consumer check MUST use the two-part semantics: (1) at least one of a param's consumer keys appears in the render, AND (2) every rendered occurrence of every listed key satisfies equals/contains the param value. A mere "value appears somewhere" check is forbidden — that is the weak oracle this replaces.
- Render assertions never pass `--set` values the plugin does not emit (established in v0.1.4).
- Verified v1 declarations (do not invent others): `vaultAddress→equals:[VAULT_URL,RUNNER_VAULT_URL,VAULT_ADDR]`, `neo4jUri→equals:[NEO4J_URI,GRAPH_DB_URI]`, `redisHost→equals:[REDIS_HOST]`, `pgHost→contains:[DATABASE_URL]`, `llmBaseUrl→equals:[api_base]`.
- Paths are relative to the repo/worktree root (where `rwl-install-wizard/` and `.claude/` live).

## File Structure

```
rwl-install-wizard/
  lib/consumer-values.rb          # extractor: (manifest, key) -> [values]           (Task 1)
  lib/check-consumers.rb          # driver: (catalog, answers, render) -> pass/fail   (Task 3)
  data/knob-catalog.yaml          # + consumers: on 5 params                          (Task 2)
  lib/catalog-lint.sh             # + consumers-shape validation                      (Task 2)
  tests/test-consumer-values.sh   # extractor unit test                               (Task 1)
  tests/test-check-consumers.sh   # driver non-vacuity test                           (Task 3)
  tests/fixtures/profiles/byo.yaml# new byo profile answers                           (Task 4)
  tests/test-airgap-registry.sh   # call check-consumers per profile                  (Task 4)
.claude/skills/rwl-catalog-update/
  gen-overlays.rb                 # + optional --answers output                       (Task 5)
  detect-drift.sh                 # opportunistic consumerMismatch finding            (Task 5)
```

---

### Task 1: `consumer-values.rb` — extract every rendered value of an env key

**Files:**
- Create: `rwl-install-wizard/lib/consumer-values.rb`
- Create: `rwl-install-wizard/tests/test-consumer-values.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: Ruby module `ConsumerValues` with `ConsumerValues.values(text, key) -> Array<String>`. CLI: `ruby lib/consumer-values.rb <manifest-file> <KEY>` prints one value per line. Handles two render forms — configmap data (`  KEY: "value"` / `  KEY: value`) and pod env (`- name: KEY` immediately followed by `value: "value"`). Values are unquoted.

- [ ] **Step 1: Write the failing test**

Create `rwl-install-wizard/tests/test-consumer-values.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash rwl-install-wizard/tests/test-consumer-values.sh`
Expected: FAIL — `consumer-values.rb` does not exist (ruby load error / empty output).

- [ ] **Step 3: Write minimal implementation**

Create `rwl-install-wizard/lib/consumer-values.rb`:

```ruby
#!/usr/bin/env ruby
# consumer-values.rb — extract every rendered value of an env KEY from a helm
# manifest. Two forms: configmap data (`  KEY: "v"` / `  KEY: v`) and pod env
# (`- name: KEY` immediately followed by `value: "v"`). Values are unquoted.
module ConsumerValues
  def self.unquote(s)
    s = s.strip
    s = s[1..-2] if s.length >= 2 && ((s[0] == '"' && s[-1] == '"') || (s[0] == "'" && s[-1] == "'"))
    s
  end

  def self.values(text, key)
    lines = text.lines
    esc = Regexp.escape(key)
    out = []
    lines.each_with_index do |ln, i|
      # configmap-data form: <ws>KEY: <value>   (the token before ':' is exactly KEY)
      if ln =~ /^\s*#{esc}:\s*(\S.*?)\s*$/
        out << unquote($1)
      # pod-env form: <ws>- name: KEY  then next line  value: <value>
      elsif ln =~ /^\s*-?\s*name:\s*#{esc}\s*$/
        nxt = lines[i + 1]
        out << unquote($1) if nxt && nxt =~ /^\s*value:\s*(\S.*?)\s*$/
      end
    end
    out
  end
end

if __FILE__ == $0
  vals = ConsumerValues.values(File.read(ARGV[0]), ARGV[1])
  puts vals.join("\n")
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash rwl-install-wizard/tests/test-consumer-values.sh`
Expected: PASS — `consumer-values: 6 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/lib/consumer-values.rb rwl-install-wizard/tests/test-consumer-values.sh
git commit -m "feat(rwl-install-wizard): consumer-values.rb env-key value extractor"
```

---

### Task 2: `consumers:` catalog metadata + lint rule

**Files:**
- Modify: `rwl-install-wizard/data/knob-catalog.yaml` (add `consumers:` to 5 params)
- Modify: `rwl-install-wizard/lib/catalog-lint.sh` (add `check_consumers_shape`)
- Modify: `rwl-install-wizard/tests/test-catalog-lint.sh` (add a bad-shape case)

**Interfaces:**
- Consumes: nothing new.
- Produces: catalog params `vaultAddress`, `neo4jUri`, `redisHost`, `pgHost`, `llmBaseUrl` each carry a `consumers:` block. `catalog-lint.sh` exits 1 if any `consumers:` block is malformed.

- [ ] **Step 1: Add the declarations (edit `knob-catalog.yaml`)**

Find each param line and append `consumers:`. The params are inline `{ id: … }` maps — add the key inside the braces. Exact edits:

`{ id: vaultAddress, prompt: "…" }` → append `, consumers: { equals: [VAULT_URL, RUNNER_VAULT_URL, VAULT_ADDR] }` before the closing `}`.
`{ id: neo4jUri, prompt: "…" }` → `, consumers: { equals: [NEO4J_URI, GRAPH_DB_URI] }`
`{ id: redisHost, prompt: "…" }` → `, consumers: { equals: [REDIS_HOST] }`
`{ id: pgHost, prompt: "…" }` → `, consumers: { contains: [DATABASE_URL] }`
`{ id: llmBaseUrl, prompt: "…" }` → `, consumers: { equals: [api_base] }`

(Use the Edit tool per param, matching the existing full line and inserting before the final ` }`.)

- [ ] **Step 2: Write the failing lint test**

Append to `rwl-install-wizard/tests/test-catalog-lint.sh` (before the final summary lines):

```bash
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash rwl-install-wizard/tests/test-catalog-lint.sh`
Expected: FAIL — "malformed consumers … is rejected" fails (rc 0, expected 1), because the rule doesn't exist yet.

- [ ] **Step 4: Add the lint rule (edit `catalog-lint.sh`)**

Insert before the final `exit "$problems"` line:

```bash
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash rwl-install-wizard/tests/test-catalog-lint.sh`
Expected: PASS — all cases green, including the two new ones.
Run: `bash rwl-install-wizard/lib/catalog-lint.sh rwl-install-wizard/data/knob-catalog.yaml rwl-install-wizard/data`
Expected: exit 0 (the 5 real declarations are well-formed).

- [ ] **Step 6: Commit**

```bash
git add rwl-install-wizard/data/knob-catalog.yaml rwl-install-wizard/lib/catalog-lint.sh rwl-install-wizard/tests/test-catalog-lint.sh
git commit -m "feat(rwl-install-wizard): consumers: metadata + lint shape rule"
```

---

### Task 3: `check-consumers.rb` — assert answers reach consumers

**Files:**
- Create: `rwl-install-wizard/lib/check-consumers.rb`
- Create: `rwl-install-wizard/tests/test-check-consumers.sh`

**Interfaces:**
- Consumes: `ConsumerValues.values` from `lib/consumer-values.rb` (same dir, `require_relative`).
- Produces: CLI `ruby lib/check-consumers.rb <catalog> <answers.yaml> <render.yaml>`. For each answered param that declares `consumers`, prints `  PASS: <param> …` or `  FAIL: <param> …`. Exit 0 iff every declared consumer check passes. Two-part semantics: (a) ≥1 of the param's consumer keys occurs in the render, (b) every occurrence equals/contains the answer value.

- [ ] **Step 1: Write the failing test**

Create `rwl-install-wizard/tests/test-check-consumers.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash rwl-install-wizard/tests/test-check-consumers.sh`
Expected: FAIL — `check-consumers.rb` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `rwl-install-wizard/lib/check-consumers.rb`:

```ruby
#!/usr/bin/env ruby
# check-consumers.rb <catalog> <answers.yaml> <render.yaml>
# For each answered param that declares consumers, assert its value reaches every
# rendered consumer. Two-part semantics: (a) >=1 of the param's consumer keys must
# occur in the render; (b) every occurrence of every listed key must equal (equals)
# or include (contains) the answer value.
require 'yaml'
require_relative 'consumer-values'

catalog, answers_file, render_file = ARGV
cat = YAML.load_file(catalog)

# param id -> {"equals"=>[...], "contains"=>[...]}
consumers = {}
collect = lambda do |pl|
  (pl || []).each { |p| consumers[p["id"]] = p["consumers"] if p.is_a?(Hash) && p["consumers"] }
end
(cat["axes"] || []).each { |a| collect.call(a["params"]); (a["options"] || []).each { |o| collect.call(o["params"]) } }

# flatten answers: axis -> {option, <pid>: <val>} into pid -> val
answers = {}
(YAML.load_file(answers_file)["answers"] || {}).each do |_axis, m|
  next unless m.is_a?(Hash)
  m.each { |k, v| answers[k] = v unless k == "option" }
end

render = File.read(render_file)
fails = 0
answers.each do |pid, val|
  c = consumers[pid]
  next unless c
  val = val.to_s
  total = 0
  bad = []
  (c["equals"] || []).each do |key|
    vs = ConsumerValues.values(render, key)
    total += vs.size
    vs.each { |rv| bad << "#{key}=#{rv} (!= #{val})" unless rv == val }
  end
  (c["contains"] || []).each do |key|
    vs = ConsumerValues.values(render, key)
    total += vs.size
    vs.each { |rv| bad << "#{key}=#{rv} (!~ #{val})" unless rv.include?(val) }
  end
  keys = ((c["equals"] || []) + (c["contains"] || [])).join(",")
  if total == 0
    puts "  FAIL: #{pid}: value #{val} reached NO consumer [#{keys}]"; fails += 1
  elsif !bad.empty?
    puts "  FAIL: #{pid}: #{bad.join('; ')}"; fails += 1
  else
    puts "  PASS: #{pid} -> [#{keys}] all resolve to #{val}"
  end
end
exit(fails == 0 ? 0 : 1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash rwl-install-wizard/tests/test-check-consumers.sh`
Expected: PASS — `check-consumers: 3 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/lib/check-consumers.rb rwl-install-wizard/tests/test-check-consumers.sh
git commit -m "feat(rwl-install-wizard): check-consumers.rb value-at-consumer driver"
```

---

### Task 4: Wire the check into the plugin render guard (airgap + byo profiles)

**Files:**
- Create: `rwl-install-wizard/tests/fixtures/profiles/byo.yaml`
- Modify: `rwl-install-wizard/tests/test-airgap-registry.sh` (call check-consumers per rendered profile)

**Interfaces:**
- Consumes: `lib/check-consumers.rb`, the existing `airgap.yaml` profile, the new `byo.yaml`, the existing airgap + byo-datastores fixtures.
- Produces: two new guard assertions — the airgap render's `llmBaseUrl→api_base`, and the byo render's `vaultAddress/pgHost/redisHost/neo4jUri/llmBaseUrl` consumers — driven entirely by catalog declarations.

- [ ] **Step 1: Create the byo profile answers**

Create `rwl-install-wizard/tests/fixtures/profiles/byo.yaml`:

```yaml
schemaVersion: 1
chartCompat: ">=0.2.37 <0.3"
generatedAt: "2026-07-07"
# byo-datastores profile: external Vault/PG/Redis/Neo4j. Rendered by layering the
# airgap registry+storage+cluster fixtures with the byo-datastores fixture (see the
# guard's byo render). These answer values MUST match the byo-datastores fixture so
# the value-at-consumer check has the correct operator inputs.
answers:
  llm-endpoint: { option: internal-openai, llmBaseUrl: "https://llm.internal/v1" }
  subcharts:
    option: byo-datastores
    pgHost: pg.example.com
    pgPort: "5432"
    pgDatabase: core
    pgUsername: runwhen
    redisHost: redis.example.com
    redisPort: "6379"
    neo4jUri: "bolt://neo4j.example.com:7687"
    neo4jUsername: neo4j
    vaultAddress: "https://vault.example.com"
    qdrantUrl: "http://qdrant.example.com:6333"
```

- [ ] **Step 2: Add the guard assertions (edit `test-airgap-registry.sh`)**

In the RENDER block, right after the existing airgap render's image-ref check
(after the line `no "rendered manifests contain a public image ref"; else ok …; fi`
and before the byo section), add the airgap consumer check:

```bash
    # value-at-consumer: airgap profile (only llmBaseUrl -> api_base applies; datastores are bundled)
    if ruby "$PLUGIN_DIR/lib/check-consumers.rb" "$CATALOG" "$SCRIPT_DIR/fixtures/profiles/airgap.yaml" "$TMP" >/dev/null 2>&1; then
      ok "airgap: every operator input reaches its consumer"
    else no "airgap: an operator input did not reach its declared consumer"; fi
```

Then, inside the byo render block, right after the existing
`ok "byo-datastores: VAULT_URL + RUNNER_VAULT_URL resolve to the external Vault"`
line pair (i.e. after the `vok` check, still inside the `if helm template … byo …; then`
success branch), add the data-driven byo consumer check:

```bash
    if ruby "$PLUGIN_DIR/lib/check-consumers.rb" "$CATALOG" "$(dirname "$AIRGAP")/../profiles/byo.yaml" "$TMP" >/dev/null 2>&1; then
      ok "byo: every operator input (vault/pg/redis/neo4j/llm) reaches its consumer"
    else no "byo: an operator input did not reach its declared consumer"; fi
```

(Note: `$CATALOG`, `$PLUGIN_DIR`, `$SCRIPT_DIR`, `$AIRGAP`, `$TMP` are already defined earlier in this test. `fixtures/profiles/byo.yaml` resolves via `$SCRIPT_DIR/fixtures/profiles/byo.yaml`; use that exact form if `$(dirname "$AIRGAP")/../profiles/byo.yaml` is awkward — both point at the same file.)

- [ ] **Step 3: Run the guard to verify the new assertions pass**

Run: `RWL_CHART_PATH=/Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform bash rwl-install-wizard/tests/test-airgap-registry.sh`
Expected: PASS — includes `airgap: every operator input reaches its consumer` and `byo: every operator input (vault/pg/redis/neo4j/llm) reaches its consumer`; final line `airgap-registry: N passed, 0 failed` (N = previous + 2).

- [ ] **Step 4: Prove non-vacuity (revert the v0.1.6 fix, expect the new byo assertion to fail)**

Run:
```bash
cp rwl-install-wizard/tests/fixtures/expected/byo-datastores/values-cluster.yaml /tmp/byo.bak
ruby -ryaml -e 's=YAML.load_file(ARGV[0]); s["vault"]={"deploy"=>false,"external"=>{"address"=>"https://vault.example.com","authMountPoint"=>"kubernetes"}}; File.write(ARGV[0], s.to_yaml)' rwl-install-wizard/tests/fixtures/expected/byo-datastores/values-cluster.yaml
RWL_CHART_PATH=/Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform bash rwl-install-wizard/tests/test-airgap-registry.sh 2>&1 | grep -E "byo:|failed"
cp /tmp/byo.bak rwl-install-wizard/tests/fixtures/expected/byo-datastores/values-cluster.yaml
```
Expected: the `byo: …` assertion FAILS (proving the new check catches the flat-vs-nested shape gap), then the fixture is restored. (Do NOT commit the reverted fixture.)

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/tests/fixtures/profiles/byo.yaml rwl-install-wizard/tests/test-airgap-registry.sh
git commit -m "test(rwl-install-wizard): value-at-consumer assertions for airgap + byo profiles"
```

---

### Task 5: Opportunistic detector integration (`consumerMismatch`)

**Files:**
- Modify: `.claude/skills/rwl-catalog-update/gen-overlays.rb` (optional answers output)
- Modify: `.claude/skills/rwl-catalog-update/detect-drift.sh` (`check_render` calls check-consumers)
- Modify: `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh` (assert no consumerMismatch on the current chart)

**Interfaces:**
- Consumes: `rwl-install-wizard/lib/check-consumers.rb` (repo-relative), `gen-overlays.rb`.
- Produces: `gen-overlays.rb <catalog> <out-dir> <option-id> --answers` also writes `<out-dir>/answers.yaml` (the option's dummy param values in profile-answers shape). `check_render` runs check-consumers against each option's render and emits a `decide/consumerMismatch` finding when a declared consumer resolves to the wrong value.

- [ ] **Step 1: Add `--answers` to `gen-overlays.rb`**

In `gen-overlays.rb`, after the block that writes the overlay (`File.write(...); puts ov`), and using the already-computed `pids` and `dummy`, add answers output. Replace the option loop body's tail so that when `ARGV[3] == "--answers"` it also writes an answers file. Concretely, after `puts ov` inside the matched-option block, add:

```ruby
    if ARGV[3] == "--answers"
      ans = { "option" => want }
      pids.each { |pid| ans[pid] = dummy(pid) }
      File.write(File.join(outdir, "answers.yaml"), { "answers" => { "x" => ans } }.to_yaml)
    end
```

(`pids` and `dummy` already exist in that scope from Task-1-era gen-overlays. `want` is the option id arg.)

- [ ] **Step 2: Write the failing detector test**

Append to `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh` before the final summary:

```bash
echo "== consumer check: only the KNOWN byo-datastores neo4j mismatch, nothing else =="
REALCHART="${RWL_CHART_PATH:-/Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform}"
if command -v helm >/dev/null 2>&1 && [ -f "$REALCHART/values.yaml" ]; then
  OUTC="$(mktemp -d)"
  bash "$DET" --chart "$REALCHART" --out "$OUTC" >/dev/null 2>&1
  # byo-datastores + external Neo4j is a KNOWN chart bug (agentfarm/usearch hardcode
  # the bundled neo4j host) — see data/known-issues/neo4j-external-agentfarm-usearch.md.
  # The detector is EXPECTED to flag exactly that option and no other.
  if awk -F'\t' '$2=="consumerMismatch" && $3=="byo-datastores"' "$OUTC/findings.tsv" | grep -q .; then
    ok "detector flags the known byo-datastores neo4j consumerMismatch"
  else no "detector did not flag byo-datastores (consumer check not running?)"; fi
  unexpected="$(awk -F'\t' '$2=="consumerMismatch" && $3!="byo-datastores"{print $3}' "$OUTC/findings.tsv" | sort -u | tr '\n' ' ')"
  [ -z "$unexpected" ] && ok "no unexpected consumerMismatch" || no "unexpected consumerMismatch: $unexpected"
  rm -rf "$OUTC"
else
  ok "SKIP consumer check (no chart/helm)"
fi
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: FAIL — `check_render` does not yet emit/clear consumerMismatch (the assertion errors or the finding logic is absent). If it happens to pass because nothing is emitted, proceed — Step 5 will confirm real coverage.

- [ ] **Step 4: Wire check-consumers into `check_render`**

In `detect-drift.sh` `check_render`, change the `gen-overlays.rb` call to also request answers, and after a successful render add the consumer check. Replace:

```bash
    ov="$(ruby "$SKILL_DIR/gen-overlays.rb" "$CATALOG" "$tmp" "$opt")"
```
with:
```bash
    ov="$(ruby "$SKILL_DIR/gen-overlays.rb" "$CATALOG" "$tmp" "$opt" --answers)"
```

Then, inside the `if helm template … ; then` success branch, after the existing
publicRef block, add:

```bash
      # value-at-consumer: does any declared consumer resolve to the wrong value?
      if [ -f "$tmp/answers.yaml" ] && \
         ! ruby "$REPO/rwl-install-wizard/lib/check-consumers.rb" "$CATALOG" "$tmp/answers.yaml" "$tmp/render.yaml" >/dev/null 2>&1; then
        emit_finding decide consumerMismatch "$opt" "an operator input does not reach its declared consumer" "$CHART" "" ""
      fi
```

(`$REPO` is defined at the top of `detect-drift.sh`. `check-consumers.rb` returns non-zero only when a declared consumer for one of THIS option's params is present-but-wrong or missing-after-being-declared; options whose params declare no consumers produce no finding.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash .claude/skills/rwl-catalog-update/tests/run-all.sh`
Expected: both suites green. The detector run against the current (correct) chart emits **no** consumerMismatch.
Then confirm real coverage — the check actually runs for at least the internal-openai option:
```bash
bash .claude/skills/rwl-catalog-update/detect-drift.sh --chart /Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform --out /tmp/dc
test -f /tmp/dc/../*/answers.yaml 2>/dev/null; ruby .claude/skills/rwl-catalog-update/gen-overlays.rb rwl-install-wizard/data/knob-catalog.yaml /tmp/ans internal-openai --answers && grep -q llmBaseUrl /tmp/ans/answers.yaml && echo "answers emitted for internal-openai ✅"; rm -rf /tmp/dc /tmp/ans
```
Expected: `answers emitted for internal-openai ✅`.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/rwl-catalog-update/gen-overlays.rb .claude/skills/rwl-catalog-update/detect-drift.sh .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh
git commit -m "feat(rwl-catalog-update): opportunistic consumerMismatch via shared check-consumers"
```

---

## Self-Review

**1. Spec coverage:**
- Declaration `consumers: {equals, contains}` per-param → Task 2. ✓
- Two-part semantics (≥1 present; all occurrences match) → Task 3 impl + Global Constraints. ✓
- Shared extractor `consumer-values.rb` → Task 1. ✓
- Shared driver → Task 3 (`check-consumers.rb`; spec named it `.sh` — implemented as Ruby for YAML parsing, a stated deviation, same responsibility). ✓
- Plugin guard primary, full profiles incl. new byo profile → Task 4. ✓
- Detector opportunistic `consumerMismatch` → Task 5. ✓
- `catalog-lint` shape rule → Task 2. ✓
- Testing: extractor unit (Task 1), driver non-vacuity (Task 3), guard non-vacuity (Task 4 Step 4), detector coverage (Task 5 Step 5). ✓
- **Deviation from spec:** the byo scenario reuses the existing airgap + byo-datastores fixtures layered together (no new `expected/byo/` overlays); only a `profiles/byo.yaml` answers file is added. This is simpler and covers the same consumers — noted in Task 4.

**2. Placeholder scan:** No TBD/TODO. Every code step has complete code. The catalog edits in Task 2 Step 1 reference the existing param lines (matched via Edit); the exact strings to append are given verbatim.

**3. Type/name consistency:** `ConsumerValues.values(text, key) -> Array` defined in Task 1, consumed by `require_relative 'consumer-values'` in Task 3 (same `lib/` dir). `check-consumers.rb <catalog> <answers.yaml> <render.yaml>` signature identical in Task 3, Task 4, Task 5. `consumers: {equals, contains}` shape identical across Tasks 2/3. `emit_finding decide consumerMismatch <opt> …` uses the 7-field signature from the detector's existing `emit_finding`. gen-overlays `--answers` writes `answers.yaml` (Task 5 Step 1) consumed at Task 5 Step 4.
