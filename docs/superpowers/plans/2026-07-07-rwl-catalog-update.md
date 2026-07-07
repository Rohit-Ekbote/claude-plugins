# /rwl-catalog-update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A maintainer-only `/rwl-catalog-update` command that detects drift between `rwl-install-wizard`'s hand-authored catalog and a newer chart checkout, auto-fixes mechanical drift, and flags structural changes for the maintainer.

**Architecture:** Hybrid. A deterministic detector (`detect-drift.sh` + `gen-overlays.rb`) renders every catalog option via `helm template` against a maintainer-supplied chart and writes a structured drift report. A skill layer (`SKILL.md`) reads the report, applies mechanical fixes, flags structural ones, and re-runs the plugin's existing guards until green. It lives at repo root (`.claude/skills/…`), outside the shipped plugin package.

**Tech Stack:** Bash 3.2 (macOS default), Ruby (stdlib `yaml`/`json` — already used by the plugin), Helm 3, the existing `rwl-install-wizard/` catalog, `lib/catalog-lint.sh`, and `tests/`.

## Global Constraints

- **Runtime plugin stays decoupled.** Nothing under `rwl-install-wizard/skills/` or the operator experience may gain a chart dependency. All chart contact is in `.claude/skills/rwl-catalog-update/` only.
- **Not shipped to operators.** The command lives at repo root `.claude/skills/rwl-catalog-update/`; the marketplace publishes only `./rwl-install-wizard`, so it must never be referenced from inside `rwl-install-wizard/`.
- **Bash 3.2 compatible:** no `declare -A`, no `${var,,}`, no `|&`.
- **No new runtime deps:** only bash, ruby (stdlib), helm. No `jq`, no gems.
- **Deterministic detection, judgment application:** the detector never edits files; only the skill layer edits, and only after the detector's report says what changed.
- **The command never commits.** It stages a reviewed working tree and hands back a diff.
- **Reuse, don't duplicate, the plugin's verification:** `rwl-install-wizard/lib/catalog-lint.sh` and `rwl-install-wizard/tests/run-all.sh` are the acceptance gate.
- Paths are relative to the repo/worktree root (where `rwl-install-wizard/` and `.claude/` live).

## File Structure

```
.claude/skills/rwl-catalog-update/
  SKILL.md                     # judgment layer (Task 8)
  gen-overlays.rb              # catalog option → dummy-substituted overlay YAML (Task 1)
  detect-drift.sh              # deterministic detector; orchestrates checks (Tasks 2-6)
  assemble-report.rb           # findings TSV → drift-report.md + drift-report.json (Task 6)
  validators.baseline          # snapshot of chart fail-fast validators (Task 3)
  tests/
    run-all.sh                 # runs every test-*.sh here (Task 7)
    test-gen-overlays.sh       # Task 1
    test-detect-drift.sh       # Tasks 2-6
    fixtures/
      chart-compat/Chart.yaml        # fake newer Chart.yaml (Task 2)
      helpers-extra-validator.tpl    # fake _helpers with one new fail (Task 3)
      example-bumped-tag.yaml        # fake values-example with a bumped tag (Task 4)
docs/superpowers/plans/2026-07-07-rwl-catalog-update.md   # this file
```

Runtime outputs (`drift-report.md`, `drift-report.json`, `findings.tsv`) are written to a `--out` dir (default `./.rwl-catalog-drift/`) and are NOT committed.

---

### Task 1: `gen-overlays.rb` — render one catalog option to overlay YAML

Pure transform (no helm): given the catalog and an option id, substitute each of that option's params with a heuristic dummy value and print the option's `emits:` as overlay YAML. This is the per-option input to the render check.

**Files:**
- Create: `.claude/skills/rwl-catalog-update/gen-overlays.rb`
- Create: `.claude/skills/rwl-catalog-update/tests/test-gen-overlays.sh`

**Interfaces:**
- Consumes: `rwl-install-wizard/data/knob-catalog.yaml` (existing).
- Produces: `ruby gen-overlays.rb <catalog> <out-dir> <option-id>` — writes `<out-dir>/<overlay-file>` (the option's `overlay:` value) and prints the overlay filename to stdout; prints nothing and exits 0 if the option has no overlay/emits. Helper functions `snake(id)`, `dummy(id)` used by later reasoning but not called cross-file.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/rwl-catalog-update/tests/test-gen-overlays.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-gen-overlays.sh`
Expected: FAIL — `gen-overlays.rb` does not exist (ruby error / no output).

- [ ] **Step 3: Write minimal implementation**

Create `.claude/skills/rwl-catalog-update/gen-overlays.rb`:

```ruby
#!/usr/bin/env ruby
# gen-overlays.rb <catalog.yaml> <out-dir> <option-id>
# Render ONE catalog option's emits to an overlay file, substituting each of the
# option's params (axis-level + option-level) with a render-valid DUMMY value.
# Dummies need only make `helm template` succeed — never semantically correct.
require 'yaml'
catalog, outdir, want = ARGV
abort "usage: gen-overlays.rb <catalog> <out-dir> <option-id>" unless want

def snake(id); id.gsub(/([a-z0-9])([A-Z])/, '\1_\2').upcase; end

def dummy(id)
  case id
  when /Url$/          then "https://dummy.example/v1"
  when /Host$/, /Endpoint$/ then "mirror.example"
  when /Secret/        then "dummy-secret"
  when /Class$/        then "dummy-sc"
  when /Uid$/, /Gid$/, /Dimension$/, /Port$/ then "1000"
  when "releaseName"   then "rw"          # must match the detector's helm release name
  when "domain"        then "ex.example.com"
  when "bundleFile"    then "ca.crt"
  else "dummy-#{id.gsub(/([A-Z])/){ "-#{$1.downcase}" }}"
  end
end

def subst(o, m)
  case o
  when String then r = o; m.each { |k, v| r = r.gsub("<#{k}>", v.to_s) }; r
  when Array  then o.map { |e| subst(e, m) }
  when Hash   then o.each_with_object({}) { |(k, v), h| h[subst(k, m)] = subst(v, m) }
  else o
  end
end

cat = YAML.load_file(catalog)
cat["axes"].each do |axis|
  (axis["options"] || []).each do |opt|
    next unless opt["id"] == want
    ov = opt["overlay"]; em = opt["emits"]
    next if ov.nil? || em.nil? || em == {}
    pids = []
    (axis["params"] || []).each { |p| pids << p["id"] }
    (opt["params"]  || []).each { |p| pids << p["id"] }
    pmap = {}; pids.each { |id| pmap[snake(id)] = dummy(id) }
    data = subst(Marshal.load(Marshal.dump(em)), pmap)
    File.write(File.join(outdir, ov), data.to_yaml)
    puts ov
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-gen-overlays.sh`
Expected: PASS — `gen-overlays: 6 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/gen-overlays.rb .claude/skills/rwl-catalog-update/tests/test-gen-overlays.sh
git commit -m "feat(rwl-catalog-update): gen-overlays.rb renders one option to overlay YAML"
```

---

### Task 2: `detect-drift.sh` scaffold — args, findings emitter, chartCompat check

Create the detector skeleton: argument parsing, a `emit_finding` helper that appends a TSV row to a findings file, and the first real check (chart version vs catalog `chartCompat`).

**Files:**
- Create: `.claude/skills/rwl-catalog-update/detect-drift.sh`
- Create: `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
- Create: `.claude/skills/rwl-catalog-update/tests/fixtures/chart-compat/Chart.yaml`

**Interfaces:**
- Consumes: `rwl-install-wizard/data/knob-catalog.yaml`, a `--chart <dir>` containing `Chart.yaml`.
- Produces: `detect-drift.sh --chart <dir> [--catalog <f>] [--out <dir>]`. Writes `<out>/findings.tsv` (tab-separated: `bucket  kind  option  detail  evidence  current  chart`). `emit_finding <bucket> <kind> <option> <detail> <evidence> <current> <chart>` appends one row. Exit 0 on success, 2 on usage error.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/rwl-catalog-update/tests/fixtures/chart-compat/Chart.yaml`:

```yaml
apiVersion: v2
name: runwhen-platform
version: 0.3.7
```

Create `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$DIR")"
DET="$SKILL/detect-drift.sh"
FIX="$DIR/fixtures"
PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }
field(){ awk -F'\t' -v k="$1" '$2==k{print; exit}' "$2"; }   # first row with kind==k

echo "== chartCompat drift: chart 0.3.7 is outside >=0.2.37 <0.3 =="
OUT="$(mktemp -d)"
bash "$DET" --chart "$FIX/chart-compat" --out "$OUT" >/dev/null 2>&1
row="$(field chartCompat "$OUT/findings.tsv")"
[ -n "$row" ] && ok "emits a chartCompat finding" || no "no chartCompat finding"
echo "$row" | grep -q "0.3.7" && ok "records detected version 0.3.7" || no "version not recorded"
echo "$row" | grep -q "^decide" && ok "chartCompat out-of-range is needs-decision" || no "wrong bucket"
rm -rf "$OUT"

echo "== usage error without --chart =="
bash "$DET" --out /tmp/x >/dev/null 2>&1; [ "$?" = "2" ] && ok "exit 2 without --chart" || no "wrong exit"

echo ""; echo "detect-drift: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: FAIL — `detect-drift.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `.claude/skills/rwl-catalog-update/detect-drift.sh`:

```bash
#!/usr/bin/env bash
# detect-drift.sh --chart <dir> [--catalog <f>] [--out <dir>]
# Deterministic drift detector. Writes <out>/findings.tsv; never edits sources.
set -uo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SKILL_DIR/../../.." && pwd)"
CATALOG="$REPO/rwl-install-wizard/data/knob-catalog.yaml"
CHART=""; OUT="./.rwl-catalog-drift"

while [ $# -gt 0 ]; do
  case "$1" in
    --chart)   CHART="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$CHART" ] && [ -f "$CHART/Chart.yaml" ] || { echo "usage: --chart <dir with Chart.yaml>" >&2; exit 2; }
mkdir -p "$OUT"; FINDINGS="$OUT/findings.tsv"; : > "$FINDINGS"

# emit_finding <bucket:auto|decide> <kind> <option> <detail> <evidence> <current> <chart>
emit_finding() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$FINDINGS"
}

check_chartcompat() {
  local ver compat
  ver="$(awk '/^version:/{print $2; exit}' "$CHART/Chart.yaml")"
  compat="$(awk -F'"' '/^chartCompat:/{print $2; exit}' "$CATALOG")"
  # crude range check: extract the "<X.Y" upper bound and compare major.minor.
  local upper; upper="$(printf '%s' "$compat" | sed -nE 's/.*<([0-9]+\.[0-9]+).*/\1/p')"
  local vmm; vmm="$(printf '%s' "$ver" | sed -nE 's/^([0-9]+\.[0-9]+).*/\1/p')"
  if [ -n "$upper" ] && [ -n "$vmm" ] && [ "$(printf '%s\n%s\n' "$vmm" "$upper" | sort -V | tail -1)" = "$vmm" ] && [ "$vmm" != "$upper" ]; then
    emit_finding decide chartCompat "" "chart $ver is outside catalog range $compat" "$CHART/Chart.yaml" "$compat" "$ver"
  else
    emit_finding auto chartCompat "" "chart $ver within/at catalog range $compat" "$CHART/Chart.yaml" "$compat" "$ver"
  fi
}

check_chartcompat
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: PASS — `detect-drift: 4 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/detect-drift.sh .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh .claude/skills/rwl-catalog-update/tests/fixtures/chart-compat/Chart.yaml
git commit -m "feat(rwl-catalog-update): detect-drift scaffold + chartCompat check"
```

---

### Task 3: Validator-inventory check + baseline

Detect newly-added fail-fast validators in the chart's `_helpers.tpl` (a new one usually means a new required knob → needs a question). Compares the chart's `fail` guards against a committed baseline snapshot.

**Files:**
- Create: `.claude/skills/rwl-catalog-update/validators.baseline`
- Modify: `.claude/skills/rwl-catalog-update/detect-drift.sh` (add `check_validators`, call it)
- Create: `.claude/skills/rwl-catalog-update/tests/fixtures/helpers-extra-validator.tpl`
- Modify: `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh` (add a case)

**Interfaces:**
- Consumes: `<chart>/templates/_helpers.tpl`, `validators.baseline`.
- Produces: `check_validators` appends a `validator` finding (bucket `decide`) per `define "runwhen.*.validate"` present in the chart but absent from the baseline.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/rwl-catalog-update/validators.baseline` with the current chart's validator names (one per line — generate now):

```
runwhen.objectStorage.validate
runwhen.postgresql.validate
```

(Populate the full list in Step 3 from the real chart; the two above are the minimum the test relies on.)

Create `.claude/skills/rwl-catalog-update/tests/fixtures/helpers-extra-validator.tpl`:

```
{{- define "runwhen.objectStorage.validate" -}}{{- end }}
{{- define "runwhen.postgresql.validate" -}}{{- end }}
{{- define "runwhen.workspaceBootstrap.validate" -}}{{ fail "needs staffUser.email" }}{{- end }}
```

Append to `test-detect-drift.sh` (before the final summary):

```bash
echo "== validator inventory: a new validate helper is flagged =="
OUT2="$(mktemp -d)"; CH="$OUT2/chart"; mkdir -p "$CH/templates"
printf 'apiVersion: v2\nname: runwhen-platform\nversion: 0.2.54\n' > "$CH/Chart.yaml"
cp "$FIX/helpers-extra-validator.tpl" "$CH/templates/_helpers.tpl"
bash "$DET" --chart "$CH" --out "$OUT2" >/dev/null 2>&1
if grep -q $'\tvalidator\t.*workspaceBootstrap' "$OUT2/findings.tsv"; then ok "new validator workspaceBootstrap flagged"; else no "new validator not flagged"; fi
grep -q $'\tvalidator\t.*objectStorage' "$OUT2/findings.tsv" && no "baseline validator wrongly flagged" || ok "baseline validators not re-flagged"
rm -rf "$OUT2"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: FAIL — "new validator not flagged" (no `check_validators` yet).

- [ ] **Step 3: Write minimal implementation**

First regenerate the real baseline from the chart (run once, commit the result):

```bash
grep -oE 'define "runwhen\.[a-zA-Z.]*validate"' \
  /Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform/templates/_helpers.tpl \
  | sed -E 's/define "(.*)"/\1/' | sort -u > .claude/skills/rwl-catalog-update/validators.baseline
```

Add to `detect-drift.sh` (after `check_chartcompat` definition, and add the call at the bottom):

```bash
check_validators() {
  local helpers="$CHART/templates/_helpers.tpl"; [ -f "$helpers" ] || return 0
  local baseline="$SKILL_DIR/validators.baseline"
  grep -oE 'define "runwhen\.[a-zA-Z.]*validate"' "$helpers" \
    | sed -E 's/define "(.*)"/\1/' | sort -u > "$OUT/validators.chart"
  # names in chart but not in baseline = newly added
  comm -13 <(sort -u "$baseline") "$OUT/validators.chart" | while IFS= read -r v; do
    [ -n "$v" ] || continue
    emit_finding decide validator "" "new fail-fast validator '$v' — may require a new question/param" "$helpers" "" "$v"
  done
}
```

Change the bottom of the file from:

```bash
check_chartcompat
```
to:
```bash
check_chartcompat
check_validators
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: PASS — validator cases green.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/detect-drift.sh .claude/skills/rwl-catalog-update/validators.baseline .claude/skills/rwl-catalog-update/tests/
git commit -m "feat(rwl-catalog-update): flag newly-added chart validators vs baseline"
```

---

### Task 4: Pinned-tag drift check

Compare the catalog's pinned subchart tags (`x-airgap-pinned-tags-notice.pinnedTags` — neo4j/vault/bciBaseHelmTest) against the tags the chart's `values-example-airgap-jcr.yaml` pins for the same images. A mismatch is auto-fixable tag drift.

**Files:**
- Modify: `.claude/skills/rwl-catalog-update/detect-drift.sh` (add `check_tags`, call it)
- Create: `.claude/skills/rwl-catalog-update/tests/fixtures/example-bumped-tag.yaml`
- Modify: `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`

**Interfaces:**
- Consumes: `<chart>/values-example-airgap-jcr.yaml`, catalog `pinnedTags`.
- Produces: `check_tags` appends an `auto`/`tag` finding per pinned tag whose chart value differs, with `current`=catalog tag, `chart`=chart tag.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/rwl-catalog-update/tests/fixtures/example-bumped-tag.yaml`:

```yaml
neo4j:
  image:
    customImage: "<host>/docker-dockerhub/library/neo4j:5.26.99"
vault:
  server:
    image:
      repository: "<host>/docker-dockerhub/hashicorp/vault"
      tag: "1.21.2"
```

Append to `test-detect-drift.sh`:

```bash
echo "== tag drift: neo4j bumped in chart example is flagged auto-fixable =="
OUT3="$(mktemp -d)"; CH3="$OUT3/chart"; mkdir -p "$CH3"
printf 'apiVersion: v2\nname: runwhen-platform\nversion: 0.2.54\n' > "$CH3/Chart.yaml"
cp "$FIX/example-bumped-tag.yaml" "$CH3/values-example-airgap-jcr.yaml"
bash "$DET" --chart "$CH3" --out "$OUT3" >/dev/null 2>&1
row="$(field tag "$OUT3/findings.tsv")"
echo "$row" | grep -q "neo4j" && ok "neo4j tag drift detected" || no "neo4j tag drift missing"
echo "$row" | grep -q "5.26.99" && ok "records chart tag 5.26.99" || no "chart tag not recorded"
echo "$row" | grep -q "^auto" && ok "tag drift is auto-fixable" || no "wrong bucket for tag"
# vault unchanged (1.21.2 == catalog) must NOT be flagged
grep -P '\ttag\t.*vault' "$OUT3/findings.tsv" >/dev/null 2>&1 && no "unchanged vault flagged" || ok "unchanged vault not flagged"
rm -rf "$OUT3"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: FAIL — no `tag` findings yet.

- [ ] **Step 3: Write minimal implementation**

Add to `detect-drift.sh` and call it at the bottom:

```bash
# Read catalog pinnedTags via ruby (neo4j/vault/bciBaseHelmTest -> version string).
catalog_pinned() {
  ruby -ryaml -e '
    c=YAML.load_file(ARGV[0])
    c["axes"].each{|a| (a["options"]||[]).each{|o|
      n=((o["emits"]||{})["x-airgap-pinned-tags-notice"]||{})["pinnedTags"]
      next unless n
      n.each{|k,v| puts "#{k}\t#{v}"}
    }}' "$CATALOG" | sort -u
}

check_tags() {
  local ex="$CHART/values-example-airgap-jcr.yaml"; [ -f "$ex" ] || return 0
  # chart tags for the three pinned images, parsed from the example.
  local c_neo4j c_vault c_bci
  c_neo4j="$(grep -oE 'library/neo4j:[^"[:space:]]+' "$ex" | head -1 | sed 's#.*:##')"
  c_vault="$(awk '/hashicorp\/vault/{f=1} f&&/tag:/{gsub(/[",]/,"",$2);print $2;exit}' "$ex")"
  c_bci="$(grep -oE 'bci/bci-base:[^"[:space:]]+' "$ex" | head -1 | sed 's#.*:##')"
  catalog_pinned | while IFS="$(printf '\t')" read -r name ver; do
    local chart_ver=""
    case "$name" in
      neo4j) chart_ver="$c_neo4j" ;;
      vault) chart_ver="$c_vault" ;;
      bciBaseHelmTest) chart_ver="$c_bci" ;;
    esac
    [ -n "$chart_ver" ] || continue
    if [ "$chart_ver" != "$ver" ]; then
      emit_finding auto tag "$name" "pinned $name tag $ver != chart example $chart_ver" "$ex" "$ver" "$chart_ver"
    fi
  done
}
```

Add `check_tags` to the call list at the bottom.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: PASS — tag cases green.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/detect-drift.sh .claude/skills/rwl-catalog-update/tests/
git commit -m "feat(rwl-catalog-update): pinned-tag drift check vs chart example"
```

---

### Task 5: Per-option render check (integration; real chart, skip-if-absent)

For every option with an overlay, render it (via `gen-overlays.rb`) against the chart with `helm template` (release `rw`). A render failure ⇒ `decide` (removed/renamed key or new validator); a surviving public image ref ⇒ `decide` (mirror invariant broken).

**Files:**
- Modify: `.claude/skills/rwl-catalog-update/detect-drift.sh` (add `check_render`, call it)
- Modify: `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`

**Interfaces:**
- Consumes: `gen-overlays.rb`, `helm`, `<chart>` (a real runwhen-platform chart).
- Produces: `check_render` appends `render`/`publicRef` findings (bucket `decide`). If `helm` is absent or `<chart>/values.yaml` missing, it appends one `auto`/`renderSkipped` note and returns (never fails the detector).

- [ ] **Step 1: Write the failing test**

Append to `test-detect-drift.sh`:

```bash
echo "== render check: runs against real chart if available, else skips cleanly =="
OUT4="$(mktemp -d)"
REALCHART="${RWL_CHART_PATH:-/Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform}"
if command -v helm >/dev/null 2>&1 && [ -f "$REALCHART/values.yaml" ]; then
  bash "$DET" --chart "$REALCHART" --out "$OUT4" >/dev/null 2>&1
  # mirrored-per-upstream must render clean against the current chart -> no render/publicRef finding for it
  if grep -P '\t(render|publicRef)\tmirrored-per-upstream' "$OUT4/findings.tsv" >/dev/null 2>&1; then
    no "mirrored-per-upstream unexpectedly flagged against current chart"
  else ok "mirrored-per-upstream renders clean against current chart"; fi
else
  bash "$DET" --chart "$FIX/chart-compat" --out "$OUT4" >/dev/null 2>&1
  grep -q $'\trenderSkipped\t' "$OUT4/findings.tsv" && ok "render check skips cleanly without chart/helm" || no "no renderSkipped note"
fi
rm -rf "$OUT4"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: FAIL — no `render`/`renderSkipped` handling yet.

- [ ] **Step 3: Write minimal implementation**

Add to `detect-drift.sh` and call at bottom:

```bash
PUBLIC_HOSTS='us-docker\.pkg\.dev|ghcr\.io|quay\.io|registry-1\.docker\.io|docker\.io|registry\.k8s\.io|registry\.suse\.com'

list_options() {
  ruby -ryaml -e '
    YAML.load_file(ARGV[0])["axes"].each{|a| (a["options"]||[]).each{|o|
      puts o["id"] if o["overlay"] && o["emits"] && o["emits"]!={} }}' "$CATALOG"
}

check_render() {
  if ! command -v helm >/dev/null 2>&1 || [ ! -f "$CHART/values.yaml" ]; then
    emit_finding auto renderSkipped "" "helm or chart values.yaml unavailable — render checks skipped" "$CHART" "" ""
    return 0
  fi
  local opt tmp ov
  for opt in $(list_options); do
    tmp="$(mktemp -d)"
    ov="$(ruby "$SKILL_DIR/gen-overlays.rb" "$CATALOG" "$tmp" "$opt")"
    [ -n "$ov" ] || { rm -rf "$tmp"; continue; }
    if helm template rw "$CHART" -f "$CHART/values.yaml" -f "$tmp/$ov" \
         --set neo4j.disableLookups=true --set qdrant.disableLookups=true \
         > "$tmp/render.yaml" 2> "$tmp/err"; then
      if grep -Eo '(image|customImage): *"?[^" }]+' "$tmp/render.yaml" \
           | grep -vE 'git_url|github\.com' | grep -Eq "$PUBLIC_HOSTS"; then
        emit_finding decide publicRef "$opt" "option renders a public image ref against this chart" "$CHART" "" ""
      fi
    else
      emit_finding decide render "$opt" "option fails to render: $(head -1 "$tmp/err" | cut -c1-160)" "$CHART" "" ""
    fi
    rm -rf "$tmp"
  done
}
```

Add `check_render` to the call list.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: PASS — render case green (renders clean, or skips cleanly).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/detect-drift.sh .claude/skills/rwl-catalog-update/tests/
git commit -m "feat(rwl-catalog-update): per-option render check (skip-if-no-chart)"
```

---

### Task 6: Report assembly — findings TSV → drift-report.md + drift-report.json

Turn `findings.tsv` into a human report (grouped auto-fixable vs needs-decision) and a machine JSON the skill layer consumes.

**Files:**
- Create: `.claude/skills/rwl-catalog-update/assemble-report.rb`
- Modify: `.claude/skills/rwl-catalog-update/detect-drift.sh` (call assembler at end; print summary line)
- Modify: `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`

**Interfaces:**
- Consumes: `<out>/findings.tsv`.
- Produces: `assemble-report.rb <findings.tsv> <out-dir>` writes `<out-dir>/drift-report.md` and `<out-dir>/drift-report.json`. JSON shape: `{"autoFixable":[{kind,option,detail,evidence,current,chart}...],"needsDecision":[...]}`. `detect-drift.sh` prints `drift: <A> auto-fixable, <D> need decision -> <out>/drift-report.md`.

- [ ] **Step 1: Write the failing test**

Append to `test-detect-drift.sh`:

```bash
echo "== report assembly: md + json grouped by bucket =="
OUT5="$(mktemp -d)"
bash "$DET" --chart "$FIX/chart-compat" --out "$OUT5" >/dev/null 2>&1
[ -f "$OUT5/drift-report.md" ] && ok "writes drift-report.md" || no "no drift-report.md"
[ -f "$OUT5/drift-report.json" ] && ok "writes drift-report.json" || no "no drift-report.json"
ruby -rjson -e 'j=JSON.parse(File.read(ARGV[0])); abort unless j.key?("autoFixable")&&j.key?("needsDecision")' "$OUT5/drift-report.json" && ok "json has both buckets" || no "json shape wrong"
grep -q "Needs decision" "$OUT5/drift-report.md" && ok "md has needs-decision section" || no "md missing section"
rm -rf "$OUT5"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: FAIL — no report files yet.

- [ ] **Step 3: Write minimal implementation**

Create `.claude/skills/rwl-catalog-update/assemble-report.rb`:

```ruby
#!/usr/bin/env ruby
# assemble-report.rb <findings.tsv> <out-dir>
require 'json'
tsv, outdir = ARGV
cols = %w[bucket kind option detail evidence current chart]
auto = []; decide = []
File.readlines(tsv).each do |line|
  f = line.chomp.split("\t", -1)
  next if f.length < 7
  row = Hash[cols.zip(f)]
  (row["bucket"] == "auto" ? auto : decide) << row.reject { |k, _| k == "bucket" }
end
File.write(File.join(outdir, "drift-report.json"),
           JSON.pretty_generate("autoFixable" => auto, "needsDecision" => decide))
md = +"# Catalog drift report\n\n"
render = lambda do |title, rows|
  md << "## #{title} (#{rows.length})\n\n"
  if rows.empty? then md << "_none_\n\n"
  else rows.each { |r| md << "- **#{r['kind']}** #{r['option'].empty? ? '' : "[#{r['option']}] "}— #{r['detail']}" \
                          "#{r['current'].to_s.empty? ? '' : " (`#{r['current']}` → `#{r['chart']}`)"}" \
                          "#{r['evidence'].to_s.empty? ? '' : "  \n  _#{r['evidence']}_"}\n" }
       md << "\n"
  end
end
render.call("Auto-fixable", auto)
render.call("Needs decision", decide)
File.write(File.join(outdir, "drift-report.md"), md)
```

Append to the bottom of `detect-drift.sh` (after all `check_*` calls):

```bash
ruby "$SKILL_DIR/assemble-report.rb" "$FINDINGS" "$OUT"
A="$(awk -F'\t' '$1=="auto"' "$FINDINGS" | wc -l | tr -d ' ')"
D="$(awk -F'\t' '$1=="decide"' "$FINDINGS" | wc -l | tr -d ' ')"
echo "drift: $A auto-fixable, $D need decision -> $OUT/drift-report.md"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`
Expected: PASS — `detect-drift: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/assemble-report.rb .claude/skills/rwl-catalog-update/detect-drift.sh .claude/skills/rwl-catalog-update/tests/
git commit -m "feat(rwl-catalog-update): assemble drift-report.md + .json"
```

---

### Task 7: Test runner + `.gitignore` for outputs

Add a runner for the skill's own tests and ignore the runtime output dir.

**Files:**
- Create: `.claude/skills/rwl-catalog-update/tests/run-all.sh`
- Modify: `.gitignore` (repo root)

**Interfaces:**
- Produces: `bash .claude/skills/rwl-catalog-update/tests/run-all.sh` runs every `test-*.sh` and exits non-zero if any fail.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/rwl-catalog-update/tests/run-all.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$DIR"/test-*.sh; do echo "### $t"; bash "$t" || rc=1; done
exit "$rc"
```

- [ ] **Step 2: Run to verify current state**

Run: `bash .claude/skills/rwl-catalog-update/tests/run-all.sh`
Expected: both suites print `N passed, 0 failed`; exit 0.

- [ ] **Step 3: Ignore runtime outputs**

Append to repo-root `.gitignore`:

```
# rwl-catalog-update runtime drift reports
.rwl-catalog-drift/
```

- [ ] **Step 4: Verify**

Run: `git status --porcelain .rwl-catalog-drift 2>/dev/null; echo "ignored-ok"`
Expected: no output for the dir; `ignored-ok`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/tests/run-all.sh .gitignore
git commit -m "test(rwl-catalog-update): test runner + ignore runtime reports"
```

---

### Task 8: `SKILL.md` — the judgment layer

The maintainer-facing skill. Prose + exact commands: run the detector, apply auto-fixes deterministically, walk the maintainer through each needs-decision item, keep the three tag-sync locations in lockstep, and gate on the plugin's existing verification before handing back a diff.

**Files:**
- Create: `.claude/skills/rwl-catalog-update/SKILL.md`

**Interfaces:**
- Consumes: `detect-drift.sh`, `drift-report.json`, the plugin's `lib/catalog-lint.sh` and `tests/run-all.sh`.
- Produces: an edited working tree (catalog + `data/` + `tests/fixtures/` + version bumps) + a printed summary. Never commits.

- [ ] **Step 1: Write the skill**

Create `.claude/skills/rwl-catalog-update/SKILL.md`:

```markdown
---
name: rwl-catalog-update
description: Maintainer command — refresh rwl-install-wizard's knob-catalog to a newer chart. Reads a local chart checkout, auto-fixes mechanical drift (tags, chartCompat), flags structural changes, and gates on the plugin's lint + render guard. Never commits.
triggers:
  - /rwl-catalog-update
  - update rwl catalog to chart
---

# rwl-catalog-update (maintainer only)

Refresh `rwl-install-wizard/data/knob-catalog.yaml` + `data/` to match a newer
chart. Maintainer-run, human-supervised. Does NOT touch the operator runtime and
NEVER commits — you review the diff and commit.

## Inputs
- A local chart checkout: `<chart>` = a `runwhen-platform` chart dir (has `Chart.yaml`, `values.yaml`, `templates/_helpers.tpl`, `values-example-*.yaml`).

## Steps

1. **Detect.** Run:
   `bash ${CLAUDE_PLUGIN_ROOT}/detect-drift.sh --chart <chart> --out ./.rwl-catalog-drift`
   Read `./.rwl-catalog-drift/drift-report.json`. Summarise counts to the operator.

2. **Apply auto-fixable items** (from `autoFixable[]`), each verified by re-running the detector or the render guard after:
   - `kind: tag` — update the pinned tag in ALL THREE lockstep locations: the option `emits:` (`neo4j.image.customImage` / `vault.server.image.tag` / qdrant `chartTests…bci-base`), the `x-airgap-pinned-tags-notice.pinnedTags`, and the `airgap-image-manifest.md` baseline line. They must stay identical (the render guard asserts it).
   - `kind: chartCompat` — bump `chartCompat:` in `knob-catalog.yaml` (and the note in the header) to include the detected version.
   - Regenerate affected `tests/fixtures/expected/` overlays and bump `rwl-install-wizard/.claude-plugin/plugin.json` version (patch).

3. **Walk each needs-decision item** (`needsDecision[]`) ONE AT A TIME. For each, show the evidence (`evidence` file), your recommendation, and ask `apply / edit / skip`:
   - `kind: validator` — a new fail-fast. Propose the question/param + emit to satisfy it (model it on the chart's `values-example-*.yaml`). Only add after the maintainer approves.
   - `kind: render` — an option no longer renders. Likely a renamed/removed key; propose the mapping from the chart, or propose deprecating the option.
   - `kind: publicRef` — an option leaks a public ref against this chart; propose the per-upstream override that fixes it.

4. **Verify (gate — must be green before you present):**
   - `bash rwl-install-wizard/lib/catalog-lint.sh rwl-install-wizard/data/knob-catalog.yaml rwl-install-wizard/data`
   - `RWL_CHART_PATH=<chart> bash rwl-install-wizard/tests/run-all.sh`
   If anything is red, keep fixing; if a needs-decision item is unresolved, STOP and report — do not present a partial refresh as done.

5. **Summarize & hand off.** Print the `git status` + a per-change summary grouped by MISSED-style reason. Tell the maintainer to review, commit, and bump `.claude-plugin/marketplace.json` to match `plugin.json`. Do NOT commit.

## Hard rules
- Never edit `rwl-install-wizard/skills/`.
- Never auto-invent an interview question — structural changes are maintainer-approved.
- Keep the three tag locations identical.
- Never commit.
```

- [ ] **Step 2: Dry-run the detector end-to-end against the real chart**

Run:
```bash
bash .claude/skills/rwl-catalog-update/detect-drift.sh \
  --chart /Users/rohitekbote/wd/code/github.com/runwhen/rwlight-helm/charts/runwhen-platform \
  --out ./.rwl-catalog-drift
cat ./.rwl-catalog-drift/drift-report.md
```
Expected: a report renders; `mirrored-per-upstream` is NOT under render/publicRef; any real tag drift (e.g. neo4j) appears under Auto-fixable. Confirms the skill's step 1 works against the true chart.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/rwl-catalog-update/SKILL.md
git commit -m "feat(rwl-catalog-update): SKILL.md judgment layer + verification gate"
```

---

## Self-Review

**1. Spec coverage:**
- Maintainer-only, repo-level, not shipped → File Structure + Global Constraints + Task 8 frontmatter. ✓
- No runtime chart dependency → Global Constraints; all chart contact in `.claude/skills/…`. ✓
- Hybrid detector + skill → Tasks 1-6 (detector) + Task 8 (skill). ✓
- Input = local chart checkout → `--chart` arg, Task 2. ✓
- Detector checks (render, public refs, tag drift, key-paths, validators, example reconcile, chartCompat) → chartCompat T2, validators T3, tags T4, render+publicRef+key-paths(via render failure) T5. **Gap:** explicit `values-example-*` reconciliation beyond tags and standalone key-path sweep are folded into the render check (a renamed key surfaces as a render failure). Documented as intentional in Task 5 (render is the trustworthy signal); no separate task needed.
- Auto-fix vs flag → drift-report buckets (T6) + SKILL step 2/3. ✓
- Verification gate (lint + render guard, non-rw) → SKILL step 4 + Task 8 dry-run. ✓
- Tag lockstep across 3 locations → SKILL step 2. ✓
- Testing: self-test against current chart (Task 5 + Task 8 Step 2) + synthetic precision (Tasks 3/4 fixtures). ✓
- Never commits → Global Constraints + SKILL hard rules. ✓

**2. Placeholder scan:** No TBD/TODO; every code step has complete code. The `validators.baseline` seed in Task 3 Step 1 is explicitly regenerated from the real chart in Step 3. ✓

**3. Type/name consistency:** `emit_finding <bucket> <kind> <option> <detail> <evidence> <current> <chart>` — 7 fields, matches the TSV columns in `assemble-report.rb` (`bucket kind option detail evidence current chart`) and every `emit_finding` call. `gen-overlays.rb <catalog> <out-dir> <option-id>` signature consistent across Task 1 + Task 5 `check_render`. Report JSON keys `autoFixable`/`needsDecision` consistent between Task 6 impl and its test. ✓
