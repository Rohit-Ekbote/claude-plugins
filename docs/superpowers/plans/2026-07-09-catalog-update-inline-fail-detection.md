# /rwl-catalog-update inline-`fail` detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `/rwl-catalog-update` drift detector surface every *new* chart inline `{{ fail }}` invariant as a needs-decision finding, so a chart bump that adds an install-blocking guard can't slip past unseen (the class that caused finding [1]).

**Architecture:** A standalone `extract-fails.rb` scans the chart's templates for Go-template `fail` builtins and prints a normalized message signature per unique fail. A new `check_fails` in `detect-drift.sh` diffs those signatures against a committed `fails.baseline` (`comm -13`, exactly like `check_validators`) and emits a `decide fail` finding per new signature. A `SKILL.md` judgment-layer documents the friction classes the render check can't catch.

**Tech Stack:** bash 3.2 (macOS-compatible), embedded/standalone Ruby (no gems beyond stdlib), the existing `emit_finding`/`assemble-report.rb` TSV pipeline.

## Global Constraints

- **Scope: the maintainer skill only** — `.claude/skills/rwl-catalog-update/`. Do NOT touch `rwl-install-wizard/` (operator runtime), its catalog, or its tests. This work never bumps `plugin.json`.
- **Never commit inside the skill's own flow** — but THIS plan's tasks DO commit (they build the tool). The skill's runtime still never commits.
- **bash 3.2 compatible**: no `declare -A`, no `${var,,}`, no `|&`. (Substring `${var:0:N}` and `${var:0:N}` are fine.)
- **Fail identity = normalized message text** (locked decision): the first double-quoted string after a `fail` builtin, with printf verbs (`%q %s %d %v %t %f`) collapsed to `%` and all whitespace runs collapsed to a single space, trimmed. Rewording a message re-surfaces it once — accepted.
- **New-only** (like `check_validators`): no removed-fail / baseline-staleness handling.
- **Reference chart** for baseline seeding + render tests: `RWL_CHART_PATH` / the path `/Users/rohitekbote/emdash/worktrees/rwlight-helm/emdash/for-qna-3tl69/charts/runwhen-platform` (version 0.2.59).
- **Maintainer test gate**: `bash .claude/skills/rwl-catalog-update/tests/run-all.sh` (globs `test-*.sh`) must exit 0 after each task.
- Follow existing patterns: standalone `.rb` helpers (`gen-overlays.rb`, `assemble-report.rb`); `emit_finding <bucket> <kind> <option> <detail> <evidence> <current> <chart>`; baseline as a flat sorted one-per-line file (`validators.baseline`).

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `.claude/skills/rwl-catalog-update/extract-fails.rb` (new) | Scan a templates dir, print `signature\tfile` per unique normalized fail | 1 |
| `.claude/skills/rwl-catalog-update/tests/test-extract-fails.sh` (new) | Unit-test extraction + normalization | 1 |
| `.claude/skills/rwl-catalog-update/fails.baseline` (new) | Committed signatures of the current (0.2.59) chart fails | 2 |
| `.claude/skills/rwl-catalog-update/detect-drift.sh` (modify) | New `check_fails`, wired after `check_validators` | 2 |
| `.claude/skills/rwl-catalog-update/tests/fixtures/helpers-extra-fail.tpl` (new) | Fixture: one new + one baselined fail | 2 |
| `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh` (modify) | Assert new-fail flagged / baselined-fail not | 2 |
| `.claude/skills/rwl-catalog-update/SKILL.md` (modify) | Judgment-layer section + `kind: fail` needs-decision handling | 3 |

---

### Task 1: `extract-fails.rb` — extractor + normalizer (standalone, unit-tested)

**Files:**
- Create: `.claude/skills/rwl-catalog-update/extract-fails.rb`
- Create: `.claude/skills/rwl-catalog-update/tests/test-extract-fails.sh`

**Interfaces:**
- Produces: `extract-fails.rb <templates-dir>` → stdout, one line per UNIQUE normalized signature, format `<signature>\t<relative-file>`, sorted by signature. `check_fails` (Task 2) consumes this: `cut -f1` for the `comm` diff, and looks up the file column for a finding's evidence.

- [ ] **Step 1: Write the failing unit test** `tests/test-extract-fails.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$DIR")"
EX="$SKILL/extract-fails.rb"
PASS=0; FAIL=0
ok(){ printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== extract-fails: finds template fail builtins, ignores prose 'fail' =="
T="$(mktemp -d)"; mkdir -p "$T/sub"
cat > "$T/a.tpl" <<'TPL'
# this comment mentions fail but is not a builtin invocation
{{- if not .Values.foo }}{{ fail "foo is required: set foo.bar" }}{{- end }}
TPL
cat > "$T/sub/b.yaml" <<'YML'
{{- fail (printf "kind=%q is invalid, must be one of: a, b." $k) }}
YML
OUT="$(ruby "$EX" "$T")"
echo "$OUT" | grep -q 'foo is required: set foo.bar' && ok "captures fail \"...\" message" || no "missed direct fail message"
echo "$OUT" | grep -q 'kind=% is invalid, must be one of: a, b.' && ok "captures printf fail + normalizes %q" || no "missed/unnormalized printf fail"
[ "$(printf '%s\n' "$OUT" | grep -c .)" = "2" ] && ok "exactly two signatures (prose 'fail' ignored)" || no "wrong signature count: $(printf '%s' "$OUT" | grep -c .)"
rm -rf "$T"

echo "== extract-fails: %q/%s + whitespace collapse to ONE signature =="
T2="$(mktemp -d)"
cat > "$T2/c.tpl" <<'TPL'
{{ fail "x=%q  is    bad" }}
{{ fail (printf "x=%s is bad" $v) }}
TPL
OUT2="$(ruby "$EX" "$T2")"
[ "$(printf '%s\n' "$OUT2" | grep -c .)" = "1" ] && ok "%q and %s + whitespace normalize to one signature" || no "did not collapse to one"
printf '%s\n' "$OUT2" | cut -f1 | grep -qx 'x=% is bad' && ok "signature is 'x=% is bad'" || no "unexpected signature: $(printf '%s' "$OUT2" | cut -f1)"
rm -rf "$T2"

echo ""
echo "extract-fails: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it and confirm it FAILS** (script doesn't exist yet):

Run: `bash .claude/skills/rwl-catalog-update/tests/test-extract-fails.sh; echo rc=$?`
Expected: Ruby errors (`No such file or directory -- extract-fails.rb`) and `rc=1` / non-zero.

- [ ] **Step 3: Write `extract-fails.rb`:**

```ruby
#!/usr/bin/env ruby
# extract-fails.rb <templates-dir>
# Scan Helm template files under <dir> for Go-template `fail` BUILTIN calls and
# print one line per UNIQUE normalized message signature: "<signature>\t<relfile>",
# sorted by signature.
#
# Signature = the first double-quoted string after `fail` (covers `fail "MSG"` and
# `fail (printf "FMT" ...)`), with printf verbs (%q %s %d %v %t %f) collapsed to `%`
# and every run of whitespace collapsed to a single space, trimmed. Rewording a
# message changes the signature — the accepted identity tradeoff (see design spec).
require 'find'
dir = ARGV[0]
abort "usage: extract-fails.rb <templates-dir>" unless dir
seen = {}   # signature -> first relative file where seen
if File.directory?(dir)
  Find.find(dir) do |path|
    next unless File.file?(path) && path =~ /\.(ya?ml|tpl)\z/
    rel = path.sub(/\A#{Regexp.escape(dir)}\/?/, '')
    File.foreach(path) do |line|
      # `fail` builtin: preceded by `{{`, `{{-`, or `(` (a template action / pipeline),
      # then any non-quote chars (e.g. ` (printf `), then the first "..." string.
      # Not the bare word "fail" in prose/comments (no preceding `{{`/`(`).
      line.scan(/(?:\{\{-?\s*|\(\s*)fail\b[^"]*"((?:[^"\\]|\\.)*)"/) do |m|
        sig = m[0].gsub(/%[qsdvtf]/, '%').gsub(/\s+/, ' ').strip
        seen[sig] ||= rel unless sig.empty?
      end
    end
  end
end
seen.keys.sort.each { |sig| puts "#{sig}\t#{seen[sig]}" }
```

- [ ] **Step 4: Run the unit test — PASSES:**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-extract-fails.sh`
Expected: `extract-fails: 5 passed, 0 failed`

- [ ] **Step 5: Smoke-check against the real chart** (sanity — not an assertion):

Run: `ruby .claude/skills/rwl-catalog-update/extract-fails.rb /Users/rohitekbote/emdash/worktrees/rwlight-helm/emdash/for-qna-3tl69/charts/runwhen-platform/templates | wc -l`
Expected: a count in the high-teens/low-20s (the chart's distinct fail messages; ~22 fail lines collapse to that many unique signatures).

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/rwl-catalog-update/extract-fails.rb .claude/skills/rwl-catalog-update/tests/test-extract-fails.sh
git commit -m "feat(rwl-catalog-update): extract-fails.rb — normalized inline-fail signatures"
```

---

### Task 2: `fails.baseline` + `check_fails` in `detect-drift.sh`

**Files:**
- Create: `.claude/skills/rwl-catalog-update/fails.baseline` (generated, committed)
- Modify: `.claude/skills/rwl-catalog-update/detect-drift.sh` (add `check_fails`, wire after `check_validators`)
- Create: `.claude/skills/rwl-catalog-update/tests/fixtures/helpers-extra-fail.tpl`
- Modify: `.claude/skills/rwl-catalog-update/tests/test-detect-drift.sh`

**Interfaces:**
- Consumes: `extract-fails.rb <dir>` (Task 1) → `<signature>\t<relfile>` lines.
- Produces: a `decide\tfail\t\t<detail>\t<file>\t\t` row in `findings.tsv` per new signature (flows into `needsDecision[]` via `assemble-report.rb`).

- [ ] **Step 1: Add the fixture** `tests/fixtures/helpers-extra-fail.tpl` — one brand-new fail (must be flagged) and one real 0.2.59 fail (must be baselined, so NOT flagged):

```
{{- define "demo" -}}
{{ fail "BRAND NEW GUARD: set demo.widget.enabled or demo.widget.existingConfigMap." }}
{{ fail "objectStorage.kind=external requires objectStorage.external.host or objectStorage.external.internalHost." }}
{{- end }}
```

- [ ] **Step 2: Add the failing drift assertions** to `tests/test-detect-drift.sh`, before its final summary/`exit` block. Match the file's existing helpers (`ok`/`no`/`DET`/`FIX`):

```bash
echo "== inline-fail drift: a NEW fail is flagged, a baselined one is not =="
OUTF="$(mktemp -d)"; CHF="$OUTF/chart"; mkdir -p "$CHF/templates"
printf 'apiVersion: v2\nname: runwhen-platform\nversion: 0.2.59\n' > "$CHF/Chart.yaml"
cp "$FIX/helpers-extra-fail.tpl" "$CHF/templates/_helpers.tpl"
bash "$DET" --chart "$CHF" --out "$OUTF" >/dev/null 2>&1
if grep -q $'\tfail\t.*BRAND NEW GUARD' "$OUTF/findings.tsv"; then ok "new inline fail flagged"; else no "new inline fail not flagged"; fi
if grep -q 'objectStorage.kind=external requires' "$OUTF/findings.tsv"; then no "baselined fail wrongly re-flagged"; else ok "baselined fail not re-flagged"; fi
rm -rf "$OUTF"
```

- [ ] **Step 3: Run the drift test and confirm the new block FAILS** (`check_fails` + baseline don't exist yet, so no `fail` row is emitted):

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh 2>&1 | grep -E 'inline fail|baselined fail'`
Expected: `FAIL: new inline fail not flagged` (the baselined-not-reflagged line may PASS vacuously — that's fine; the new-fail line must FAIL).

- [ ] **Step 4: Generate the committed baseline** from the real 0.2.59 chart, using Task 1's extractor (mechanical — never hand-typed):

Run:
```bash
ruby .claude/skills/rwl-catalog-update/extract-fails.rb \
  /Users/rohitekbote/emdash/worktrees/rwlight-helm/emdash/for-qna-3tl69/charts/runwhen-platform/templates \
  | cut -f1 | sort -u > .claude/skills/rwl-catalog-update/fails.baseline
```
Then confirm it is non-empty and contains the objectStorage message the fixture relies on:

Run: `grep -c . .claude/skills/rwl-catalog-update/fails.baseline; grep -q 'objectStorage.kind=external requires objectStorage.external.host' .claude/skills/rwl-catalog-update/fails.baseline && echo HAVE_IT`
Expected: a count in the high-teens/low-20s, then `HAVE_IT`.

- [ ] **Step 5: Implement `check_fails`** in `detect-drift.sh`. Add this function right after the `check_validators` function definition:

```bash
check_fails() {
  local tdir="$CHART/templates"; [ -d "$tdir" ] || return 0
  local baseline="$SKILL_DIR/fails.baseline"
  ruby "$SKILL_DIR/extract-fails.rb" "$tdir" > "$OUT/fails.chart.full"
  cut -f1 "$OUT/fails.chart.full" > "$OUT/fails.chart"
  # signatures present in the chart but not the baseline = newly added invariants
  comm -13 <(sort -u "$baseline" 2>/dev/null) "$OUT/fails.chart" | while IFS= read -r sig; do
    [ -n "$sig" ] || continue
    local file; file="$(awk -F'\t' -v s="$sig" '$1==s{print $2; exit}' "$OUT/fails.chart.full")"
    emit_finding decide fail "" "new inline chart fail: ${sig:0:140}" "$tdir/$file" "" ""
  done
}
```

- [ ] **Step 6: Wire it into the check sequence.** In `detect-drift.sh`, in the run block near the bottom, add `check_fails` immediately after `check_validators`:

```bash
check_chartcompat
check_validators
check_fails
check_tags
check_render
```

- [ ] **Step 7: Run the drift test — the new block PASSES:**

Run: `bash .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh 2>&1 | tail -3`
Expected: final line `... passed, 0 failed` (both new assertions pass; all prior assertions still pass).

- [ ] **Step 8: Run the whole maintainer suite — green:**

Run: `bash .claude/skills/rwl-catalog-update/tests/run-all.sh 2>&1 | tail -6`
Expected: every `test-*.sh` reports `0 failed` (test-extract-fails, test-detect-drift, test-gen-overlays).

- [ ] **Step 9: Verify the real chart reports ZERO new fails** (baseline is self-consistent with the extractor):

Run:
```bash
ruby .claude/skills/rwl-catalog-update/extract-fails.rb \
  /Users/rohitekbote/emdash/worktrees/rwlight-helm/emdash/for-qna-3tl69/charts/runwhen-platform/templates \
  | cut -f1 | comm -13 <(sort -u .claude/skills/rwl-catalog-update/fails.baseline) - | grep -c .
```
Expected: `0` (running the detector against the chart the baseline was built from surfaces no new fails).

- [ ] **Step 10: Commit**

```bash
git add .claude/skills/rwl-catalog-update/fails.baseline .claude/skills/rwl-catalog-update/detect-drift.sh .claude/skills/rwl-catalog-update/tests/fixtures/helpers-extra-fail.tpl .claude/skills/rwl-catalog-update/tests/test-detect-drift.sh
git commit -m "feat(rwl-catalog-update): check_fails surfaces new inline chart fails as needs-decision"
```

---

### Task 3: `SKILL.md` — judgment layer + `kind: fail` handling

**Files:**
- Modify: `.claude/skills/rwl-catalog-update/SKILL.md`

**Interfaces:** none (prose). Documents the new `fail` finding kind and the friction classes the render check cannot catch.

- [ ] **Step 1: Add `kind: fail` to the needs-decision walk.** In `SKILL.md`, in the `## Steps` section's step 3 list (the one that walks `needsDecision[]` items — it already documents `kind: validator`, `kind: render`, `kind: publicRef`, `kind: chartCompat`), add a bullet immediately after the `kind: validator` bullet:

```markdown
   - `kind: fail` — a new inline chart `{{ fail }}` guard (an install-blocking
     invariant) the catalog may not satisfy. Confirm the catalog produces values
     that pass it — model a question/param/emit if not (mirror the chart's
     `values-example-*.yaml`). Only after the maintainer approves, append the
     finding's normalized signature to `fails.baseline` so it is not re-flagged.
     Like validators, structural changes are maintainer-approved.
```

- [ ] **Step 2: Add the friction-classes section.** In `SKILL.md`, insert this section immediately before the `## Hard rules` section:

```markdown
## Friction classes the render check cannot catch

`check_render` renders each option in isolation with dummy values; a green render
does NOT mean the option is install-safe. Before trusting a "no drift" result,
reason about these classes by hand (each learned from the 0.2.59 STOXX failure):

- **Inline `{{ fail }}` invariants.** `check_fails` now surfaces *new* ones as
  `kind: fail` findings — but you must still model each into the catalog (or
  confirm it is already satisfied). The render check actively hides some: it
  disables `llmGateway` to work around the llm-gateway model_list fail.
- **Implicit chart defaults.** An option can render only because it relies on a
  chart default (e.g. `postgresql.kind` defaulting to `spilo`). Pin the
  discriminator explicitly so a later overlay is the only thing that can change
  it. (Finding [6].)
- **Runtime-only failures — invisible to `helm template`.** `readOnlyRootFilesystem:
  true` renders fine but breaks Spilo/Patroni at runtime ([5]); a hardened
  ingress controller rejects `allowSnippetAnnotations` snippets at admission ([4]).
  Neither shows up in a template render.
- **Posture applied to stateful subcharts.** A global security context that is
  correct for first-party pods can be wrong for a subchart (Spilo needs a
  writable rootfs) — the chart may replace the global context per-subchart. ([5].)
```

- [ ] **Step 3: Verify the SKILL references resolve** (no broken kind/file names introduced):

Run: `grep -n 'kind: fail\|fails.baseline\|Friction classes' .claude/skills/rwl-catalog-update/SKILL.md`
Expected: the `kind: fail` bullet, the two `fails.baseline` mentions, and the new section heading all present.

- [ ] **Step 4: Confirm the maintainer suite is still green** (prose-only change, no behavior impact):

Run: `bash .claude/skills/rwl-catalog-update/tests/run-all.sh 2>&1 | tail -4`
Expected: all `test-*.sh` `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/rwl-catalog-update/SKILL.md
git commit -m "docs(rwl-catalog-update): kind:fail handling + friction-classes judgment layer"
```

---

## Self-Review

**Spec coverage:**
- Identity = normalized message (printf verbs → `%`, whitespace collapse) → Task 1 `extract-fails.rb` + unit test. ✔
- `check_fails` mirroring `check_validators` (`comm -13`, `decide fail` finding, file evidence) → Task 2. ✔
- `fails.baseline` seeded mechanically from 0.2.59 → Task 2 Step 4 (generation command, not hand-typed) + Step 9 self-consistency check. ✔
- Complementary-to-validators (new fail inside an existing validate helper) → satisfied structurally: `check_fails` scans all templates incl. `_helpers.tpl`, independent of validator names. ✔
- SKILL judgment layer + `kind: fail` needs-decision handling → Task 3. ✔
- Testing: new-fail flagged, baselined-not-reflagged (non-vacuity), normalization equality → Task 1 Steps 1/4 + Task 2 Steps 2/7. ✔
- New-only, no removed-fail handling → not implemented (per decision); `check_fails` only emits for `comm -13` new signatures. ✔
- Scope: maintainer skill only; no `rwl-install-wizard/` or `plugin.json` changes → every task path is under `.claude/skills/rwl-catalog-update/`. ✔

**Placeholder scan:** every step has concrete code/commands + expected output. The baseline's exact lines are intentionally generated (Task 2 Step 4 command) rather than transcribed — with a determinism check (Step 9) and a content check (Step 4) so it is verifiable, not a placeholder.

**Consistency:** `extract-fails.rb` output contract (`<signature>\t<relfile>`, sorted, unique-by-signature) is defined in Task 1 Interfaces and consumed exactly that way in Task 2 Step 5 (`cut -f1`, `awk -F'\t' … {print $2}`). The `decide fail` row shape asserted in Task 2 Step 2 (`\tfail\t.*BRAND NEW GUARD`) matches what `emit_finding decide fail "" "new inline chart fail: …"` produces. `SKILL.md`'s `kind: fail` label matches the `emit_finding` kind. `${sig:0:140}` is bash-3.2-safe.

**Note for the executor:** Task 2 depends on Task 1's `extract-fails.rb`. Run in order.
