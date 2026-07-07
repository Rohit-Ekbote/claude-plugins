# Design: `/rwl-catalog-update` — chart-drift maintainer command

**Date:** 2026-07-07
**Status:** Approved (brainstorming) — pending spec review → implementation plan
**Owner:** Rohit Ekbote

## Problem

`rwl-install-wizard` generates a RunWhen-platform install kit from a hand-authored
source of truth, `rwl-install-wizard/data/knob-catalog.yaml`, pinned to
`chartCompat: ">=0.2.37 <0.3"` (effectively authored against ~0.2.40). The chart
(`rwlight-helm/charts/runwhen-platform`) ships fast and chunky — 0.2.54 today,
with jumps like `0.2.42 → 0.2.49` in a single sync. The catalog drifts: image
tags, value key-paths, fail-fast validators, and available options fall out of
sync with the chart, producing kits that fail or degrade a real install (see the
v0.1.1–v0.1.3 fix rounds).

## Goal & non-goals

**Goal (ranked):** (1) correctness of generated output against the current chart,
(2) work across a range of chart versions, (3) reduce the manual toil of keeping
the catalog current — served by a periodic, maintainer-run refresh.

**Explicit non-goal — no runtime chart dependency.** The operator-facing plugin
stays fully self-contained: it never reads, parses, or renders the chart at
`/rwl-install` time. All chart contact happens only in the maintainer command,
during a supervised refresh. This preserves the plugin's "generate-only,
self-contained" contract.

## Solution overview

A **maintainer-only** command, `/rwl-catalog-update`, that lives at repo root
(`.claude/skills/rwl-catalog-update/`), is **not** part of the published plugin
package (the marketplace publishes only `./rwl-install-wizard`), and refreshes the
catalog + `data/` to match a chart the maintainer points it at.

It automates the process performed by hand across v0.1.1–v0.1.3:
read chart → detect drift → apply mechanical fixes → flag structural changes →
re-run lint + the helm-render guard → bump version → hand back a reviewed diff.

### Inputs

- `--chart <path>`: a local `rwlight-helm/charts/runwhen-platform` checkout or a
  chart `.tgz`. Source of truth for the newer chart (thorough: `values.yaml`,
  `values-example-*.yaml`, `templates/_helpers.tpl`).

### Components (hybrid: deterministic detection + judgment application)

1. **Detector — `detect-drift.sh` (deterministic).** Generalizes the existing
   regression guard (`rwl-install-wizard/tests/test-airgap-registry.sh`) to every
   option in the catalog. For each option: substitute placeholder params with
   dummy values, deep-merge its `emits:` into overlays (reuse the `gen.rb`
   approach), `helm template` against the provided chart, and record findings. No
   edits; fully reproducible. Emits a structured `drift-report.md` (+ JSON).
2. **Skill layer — `SKILL.md` (judgment).** Reads the report, auto-applies
   mechanical fixes, flags structural changes for the maintainer one at a time,
   regenerates fixtures, bumps the plugin version, and re-runs the verification
   gate until green. Presents a git diff + summary. Never commits.

## Detector checks

Per catalog option, rendered against `--chart`:

| Check | Signal |
|---|---|
| Render succeeds | emit still valid; failure ⇒ removed/renamed key or new required validator |
| No public/unresolved image refs | air-gap invariant still holds against this chart |
| Pinned tag vs chart tag | catalog literal (e.g. `neo4j:5.26.0`) vs chart-resolved tag ⇒ tag drift |
| Emit key-paths recognized | every value-path the emit sets is one the chart still accepts (render + `values.yaml` key sweep) ⇒ renames/removals |
| Validator inventory | list `fail` guards in `_helpers.tpl`; diff vs last run ⇒ new required knob |
| Example-overlay reconciliation | diff `values-example-*.yaml` shapes vs the matching option's emit ⇒ new recommended pattern |
| chartCompat | detected chart `version:` vs catalog `chartCompat` range |

Findings are grouped into **auto-fixable** and **needs-decision**.

## Auto-fix vs. flag

**Auto-applied** (mechanically checkable, then verified by re-render):
- Image-tag refresh, kept in lockstep across the three places tags live:
  catalog emits, `x-airgap-pinned-tags-notice.pinnedTags`, and the
  `airgap-image-manifest.md` baseline (the render guard already asserts these match).
- `chartCompat` bump.
- Unambiguous 1:1 key renames the chart makes obvious.
- Regenerated `tests/fixtures/`, plugin `version` bump.

**Flagged for the maintainer** (interview *design* — never auto-invented), each
with evidence (`file:line`) and a recommended action:
- A new fail-fast validator requiring a new question/param.
- An option the chart deprecated or removed.
- A new knob/axis with no obvious interview question.
- Any ambiguous key move.

## Verification gate

Before presenting, the command must leave green:
`catalog-lint.sh` (exit 0), `secret-guard` (exit 0), `tests/run-all.sh` including
the helm-render guard **against the provided chart**, and the air-gap fixture
re-render (non-`rw` release, zero public refs, no validate fail-fast). If a
flagged item is left unresolved, the run stops at "needs your decision" rather
than committing partial work.

## Workflow

1. `/rwl-catalog-update --chart <path>`
2. Detector renders every option → `drift-report.md` ("Chart 0.2.54 vs catalog 0.2.40. N auto-fixable, M need you.")
3. Skill applies the N auto-fixes (tags, chartCompat, notice/manifest sync, fixtures).
4. Skill presents each of the M flags with evidence + recommendation, one at a time; maintainer decides (`apply` / `edit` / `skip`).
5. Runs lint + secret-guard + render guard → all green (or loops).
6. Prints the git diff + per-change summary. Maintainer reviews, commits, and bumps `marketplace.json`.

The command never commits; it stages a reviewed working tree.

## Testing the command

- **Self-test against the current chart:** run the detector against 0.2.54 with the
  current catalog; assert it produces a report and that auto-fixable items are a
  bounded, expected set (e.g. the known `neo4j` tag drift) — proving it isn't
  hallucinating drift.
- **Synthetic drift fixture:** a tiny stub/patched chart with one renamed key, one
  bumped tag, one new validator; assert the detector reports exactly those three in
  the right buckets. Regression test for detector precision.
- Reuses the plugin's existing `tests/` as the verification gate — no parallel
  test infrastructure.

## File layout

```
.claude/skills/rwl-catalog-update/
  SKILL.md            # judgment layer: read report, apply, flag, verify, summarize
  detect-drift.sh     # deterministic detector (render every option vs --chart)
  gen-overlays.rb     # shared: profile/emit → overlays (generalized from session's gen.rb)
docs/superpowers/specs/2026-07-07-rwl-catalog-update-design.md
```

(Detector reuses `rwl-install-wizard/data/knob-catalog.yaml`,
`rwl-install-wizard/lib/catalog-lint.sh`, and `rwl-install-wizard/tests/` via
repo-relative paths. Nothing is added to the shipped `rwl-install-wizard/`
package except normal catalog/data edits the command produces.)

## Risks / open items for implementation

- **No `values.schema.json`:** key-existence detection relies on render success +
  a `values.yaml` key sweep, which is heuristic. Renders are the trustworthy
  signal; the key sweep is a hint. Ambiguous moves are flagged, not auto-applied.
- **Placeholder param substitution** for rendering options needs a dummy-value map
  per param type (host, secret name, storage class, URL) so every option renders.
- **Detector precision** (false "drift") is bounded by the self-test + synthetic
  fixture above.
