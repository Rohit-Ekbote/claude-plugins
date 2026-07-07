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
   `bash .claude/skills/rwl-catalog-update/detect-drift.sh --chart <chart> --out ./.rwl-catalog-drift`
   Read `./.rwl-catalog-drift/drift-report.json`. Summarise counts to the operator.

2. **Apply auto-fixable items** (from `autoFixable[]`), each verified by re-running the detector or the render guard after:
   - `kind: tag` — update the pinned tag in ALL THREE lockstep locations: the option `emits:` (`neo4j.image.customImage` / `vault.server.image.tag` / qdrant `chartTests…bci-base`), the `x-airgap-pinned-tags-notice.pinnedTags`, and the `airgap-image-manifest.md` baseline line. They must stay identical (the render guard asserts it).
   - `kind: chartCompat` (auto bucket) — chart is WITHIN the catalog range; informational, no action.
   - `kind: renderSkipped` (auto bucket) — the detector could not render (no `helm`, or no chart at `--chart`). Not a fix: re-run with a valid `--chart` and `helm` installed to get render coverage.
   - Regenerate affected `tests/fixtures/expected/` overlays and bump `rwl-install-wizard/.claude-plugin/plugin.json` version (patch).

3. **Walk each needs-decision item** (`needsDecision[]`) ONE AT A TIME. For each, show the evidence (`evidence` file), your recommendation, and ask `apply / edit / skip`:
   - `kind: validator` — a new fail-fast. Propose the question/param + emit to satisfy it (model it on the chart's `values-example-*.yaml`). Only add after the maintainer approves.
   - `kind: render` — an option no longer renders. Likely a renamed/removed key; propose the mapping from the chart, or propose deprecating the option.
   - `kind: publicRef` — an option leaks a public ref against this chart; propose the per-upstream override that fixes it.
   - `kind: chartCompat` (decide bucket) — the chart version is OUTSIDE the catalog's `chartCompat` range. Do NOT bump the range as a reflex: first reconcile all other drift and confirm the verification gate (step 4) is green, THEN widen `chartCompat:` in `knob-catalog.yaml` (and its header note) to include the new version — that assertion means "the catalog now supports this chart."

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
