# /rwl-catalog-update — inline-`fail` detection (design)

**Date:** 2026-07-09
**Status:** approved (design), pending spec review → writing-plans
**Scope:** the maintainer skill `.claude/skills/rwl-catalog-update/` only —
`detect-drift.sh`, a new `fails.baseline`, `SKILL.md`, and
`tests/test-detect-drift.sh`. Does NOT touch the operator runtime
(`rwl-install-wizard/`) and NEVER commits (the maintainer reviews + commits).

## Problem

The whole STOXX/0.2.59 install failure traced to a chart **inline `{{ fail }}`**
invariant (the llm-gateway configmap fail) that the wizard's output did not
satisfy. But `/rwl-catalog-update`'s drift detector is structurally blind to
inline fails: `check_validators` tracks only the **2 named**
`runwhen.*.validate` helpers, while the chart carries **~22 inline `{{ fail }}`
guards across ~9 files**. When a future chart bump adds or tightens an inline
fail, the detector reports "no drift" while the wizard's generated overlays
silently become uninstallable. The render check does not save you: it *disables*
`llmGateway` to work around that very fail, and it cannot see runtime-only
breakage ([4] snippet admission, [5] readonly-rootfs) or implicit-default
reliance ([6]).

## Goal

When the maintainer refreshes the catalog against a newer chart,
`/rwl-catalog-update` surfaces every **new** install-blocking inline `fail` as a
needs-decision finding, so the maintainer models a question/param/emit (or
confirms the catalog already satisfies it) rather than shipping output that
fails `helm template`. Plus a judgment-layer note in `SKILL.md` for the friction
classes the render check cannot catch.

## Decisions (locked in brainstorming)

- **Fail identity = normalized message text.** Simplest; mirrors the existing
  flat-list `validators.baseline`. Accepted cost: a chart maintainer rewording a
  message re-surfaces it once as "new" — the maintainer glances and re-baselines.
  For an occasional, human-supervised tool, a dismissable false-positive is far
  cheaper than a silent miss (bias to recall).
- **New-only**, like `check_validators` (no removed-fail / stale-baseline
  handling). A stale baseline entry is low-risk; the existing tool already made
  this call for validators.
- **Extraction/normalization in an embedded ruby snippet** inside `check_fails`
  (not awk), for reliable quote/printf handling — consistent with the existing
  `catalog_pinned` ruby usage in the same file.

## Architecture

### Identity & normalization
For each inline `fail`, the signature is its **normalized message**:
1. Extract the first double-quoted string after `fail` — covers both
   `fail "MSG"` and `fail (printf "FMT" $args)` (the `FMT` is the signature).
2. Replace printf verbs (`%q`, `%s`, `%d`, `%v`, and the `%!…` error forms) with
   a single `%` placeholder.
3. Collapse all runs of whitespace (including embedded newlines) to one space;
   trim leading/trailing space.
The signature is that resulting string. Signatures form a flat, sorted,
one-per-line baseline file `fails.baseline`, seeded from the chart's current
fails (see Seeding).

### `detect-drift.sh` — new `check_fails`
A new function, invoked in the existing `check_*` sequence (after
`check_validators`), mirroring `check_validators`'s shape:
1. Scan `"$CHART/templates"` recursively (which includes `_helpers.tpl`) for the
   Go-template `fail` **builtin invocation** — matched on the template-action form
   (`fail` preceded by `{{`/`{{-`/`(`, i.e. `fail "…"` or `fail (printf "…"`), NOT
   the bare word "fail" appearing inside prose or a comment.
2. For each, extract + normalize the message via a ruby one-liner; record
   `signature \t relative-file` pairs. Write the sorted-unique signatures to
   `"$OUT/fails.chart"`.
3. `comm -13 <(sort -u fails.baseline) fails.chart` → signatures present in the
   chart but not the baseline = **new**.
4. For each new signature, emit ONE finding (deduped by signature):
   `emit_finding decide fail "" "<message excerpt ≤160 chars>" "<file>" "" ""`.
   The finding flows through the existing `emit_finding` / `assemble-report.rb`
   pipeline into `needsDecision[]`.

`check_fails` returns early (no findings) if the chart has no `templates/` dir,
matching the defensive style of the other checks.

**Complementary to `check_validators` (by design):** the `objectStorage.validate`
/ `postgresql.validate` helpers *contain* several of these fails, so those
messages are in `fails.baseline`. If a future chart adds a **new fail branch
inside** an existing validate helper, `check_validators` won't notice (helper
name unchanged) but `check_fails` will — closing a gap the named-validator check
structurally cannot cover.

### Seeding `fails.baseline`
The initial baseline is the normalized signature set of the CURRENT reference
chart (0.2.59), captured by running the same extractor the detector uses, so the
first real run against 0.2.59 reports zero new fails. The plan generates it
mechanically (run the extractor, sort -u, write the file) — not hand-typed — so
it exactly matches what `check_fails` produces.

## `SKILL.md` additions

1. **New section "Friction classes the render check cannot catch"** (read before
   trusting a "no drift" result), each with the 0.2.59 example that taught it:
   - Inline `{{ fail }}` invariants — now surfaced by `check_fails`, but the
     maintainer must still model each new one.
   - Implicit chart defaults (e.g. `postgresql.kind`) — render succeeds but is
     fragile; pin explicitly (finding [6]).
   - Runtime-only failures invisible to `helm template` — `readOnlyRootFilesystem`
     breaking Spilo/Patroni ([5]); ingress snippet-annotation admission rejection
     ([4]).
   - Posture applied to stateful subcharts — global security context reaching
     Spilo ([5]).
2. **`kind: fail` in the needs-decision walk (step 3):** "a new inline chart fail
   — the chart added an install-blocking guard. Confirm the catalog satisfies it
   (model a question/param/emit if not), then add its normalized signature to
   `fails.baseline`." Mirrors the existing `kind: validator` handling.

## Testing (`tests/test-detect-drift.sh`)

Mirror the existing validator test:
1. **New fail flagged:** a fixture chart whose `_helpers.tpl` (or a template)
   carries an inline `fail` with a message NOT in `fails.baseline` → assert a
   `decide\tfail\t…` row is emitted.
2. **Baselined fail not re-flagged (non-vacuity):** a fail whose normalized
   message IS in the baseline is NOT reported — proving the check isn't just
   "flag every fail."
3. **Normalization unit check:** two messages differing only in a `%q` arg and
   in whitespace collapse to the SAME signature (so a cosmetic chart change does
   not create noise).

The maintainer verification gate is unchanged: `detect-drift.sh` still writes
`findings.tsv` and never edits sources.

## Non-goals

- No change to the operator runtime (`rwl-install-wizard/`), its catalog, or its
  tests.
- No auto-fix: `check_fails` only *surfaces* new fails; modeling them into the
  catalog stays a human-approved step (the maintainer contract).
- No removed-fail / baseline-staleness detection (new-only, per decision).
- No value-path parsing of fail conditions (message-text identity, per decision).

## What this reuses (keep consistent)

The `emit_finding` TSV contract, the `auto`/`decide` bucketing, `assemble-report.rb`,
the `comm -13 baseline chart` diff pattern from `check_validators`, and the
baseline-as-flat-sorted-list convention from `validators.baseline`.
