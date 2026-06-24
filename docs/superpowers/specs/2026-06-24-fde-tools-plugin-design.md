# fde-tools Plugin — Design

**Date:** 2026-06-24
**Status:** Approved design, pending implementation plan
**Author:** Rohit Ekbote (with Claude Code)

## Summary

`fde-tools` is a new Claude Code plugin in this marketplace repo that packages the
Forward Deployed Engineer (FDE) engagement workflow currently implemented as global
slash commands in `~/.claude/commands/`. It ports the three existing commands
(`build-fde-guide`, `summarize-engagement`, `update-engagement-progress`), adds
date-anchoring to the timeline-style outputs, introduces a new `update-requirements`
command, and replaces the one-shot `correct-engagement-data` command with a single
interactive `/qna` command that can interrogate **and edit** the generated data.

Unlike the original design — which kept `corrections.md` strictly append-only and all
generated docs regenerate-only — this plugin allows changing, correcting, and deleting
existing generated data and corrections entries, while preserving history through a new
append-only `changelog.md` audit trail. The raw input directories remain strictly
read-only.

## Goals

- Package the FDE engagement workflow as an installable, shareable plugin.
- Retire the global `~/.claude/commands/` engagement commands (no coexistence).
- Add date parsing/attribution to `update-progress` and the new `update-requirements`.
- Provide one `/qna` command to ask questions about, clarify, correct, and surgically
  edit the generated engagement docs.
- Allow mutation (edit/delete) of generated docs and `corrections.md`, with an
  append-only audit trail so history is never silently lost.
- Keep `slack/`, `granola/`, `raw/` strictly read-only.
- Stay prompt-only and fully offline — no helper scripts, no runtime dependencies.

## Non-Goals

- Deterministic timestamp-parsing scripts (rejected Approach B). Date extraction is done
  by the model from freeform notes, as `update-engagement-progress` already does today.
- Date sectioning for `summary.md` and the guide — these stay current-truth.
- Modifying raw inputs under `slack/`, `granola/`, `raw/`.
- A single mega-command with subcommands (rejected Approach C). The plugin exposes
  discrete slash commands matching the user-requested names.

## Architecture

### Approach

Approach A — a prompt-only plugin with shared "include" convention files, mirroring the
proven structure of the existing global commands. Each command is a markdown spec under
`commands/`; underscore-prefixed files are shared includes referenced via
`${CLAUDE_PLUGIN_ROOT}`, not directly invocable as slash commands.

### File layout

```
fde-tools/
├── .claude-plugin/
│   └── plugin.json                    # name: fde-tools, version 0.1.0
├── commands/
│   ├── build-guide.md                 # /build-guide
│   ├── summarize-engagement.md        # /summarize-engagement
│   ├── update-progress.md             # /update-progress
│   ├── update-requirements.md         # /update-requirements   (new)
│   ├── qna.md                         # /qna                   (new)
│   ├── _engagement-context.md         # shared include (ported)
│   ├── _date-parsing.md               # shared include (new)
│   └── _qna-engine.md                 # shared include (new)
├── assets/
│   ├── fde-guide.css                  # ported from ~/.claude/commands/assets/
│   └── fde-guide-page.html.tmpl       # ported
├── tests/
│   ├── run-all.sh
│   └── fixtures/<engagement-dir>/     # slack/ granola/ raw/ with planted data
└── README.md
```

- Commands reference includes and assets via `${CLAUDE_PLUGIN_ROOT}/commands/…` and
  `${CLAUDE_PLUGIN_ROOT}/assets/…` rather than `~/.claude/commands/…`.
- `fde-tools` is registered as a 4th plugin entry in `.claude-plugin/marketplace.json`.

### Working-directory model

Commands run inside an **engagement directory** containing read-only `slack/`,
`granola/`, `raw/` source material. They produce and maintain `summary.md`,
`progress.md`, `requirements.md`, `guide/`, the `corrections.md` overlay, and the new
`changelog.md`. This is unchanged from the existing commands.

## Components

### Shared includes

**`_engagement-context.md`** — ported essentially unchanged from the current global
include. Defines: recursive read-only loading of `slack/`/`granola/`/`raw/` (absent dirs
skipped silently); the dated `corrections.md` overlay; the latest-wins-by-topic resolver
(most recent dated statement per topic is current truth; on a date tie a `corrections.md`
entry wins); customer-identity inference (fall back to `[Customer]`); and the
contradiction-handling flow (pause on material contradictions → show both quotes with
file paths → ask which is correct → record a resolution block). Only change: paths become
plugin-relative.

**`_date-parsing.md` (new)** — shared timestamp convention used by `update-progress` and
`update-requirements`:

- **Date sources, in priority order:** (1) explicit dates in body text, (2) Slack message
  timestamps, (3) Granola meeting dates/headers, (4) dates embedded in filenames
  (e.g. `granola/2026-03-12-kickoff.md`), (5) fallback to the run date only when nothing
  else applies.
- **Normalization:** all dates to `YYYY-MM-DD`. Relative phrases ("yesterday",
  "last Tuesday") resolve against the nearest anchoring date in the same source, not the
  run date.
- **Attribution rule:** every development/ask is attributed to the date it actually
  occurred — never piled under the run date.
- **Ambiguity:** if a date can't be determined for an item, tag it `(date unknown)`
  rather than guessing.

This factors date logic out of `update-progress` (which currently inlines it) so progress
and requirements share one source of truth.

**`_qna-engine.md` (new)** — the `/qna` behavior spec (see command below).

### Commands

**`/build-guide`** — ported from `build-fde-guide.md`. Builds the multi-page offline HTML
field guide into `guide/`. Current-truth, no date sectioning. Behavior unchanged beyond
plugin-relative paths (CSS/template copied from `${CLAUDE_PLUGIN_ROOT}/assets/`).

**`/summarize-engagement`** — ported from `summarize-engagement.md`. Regenerates
`summary.md` with its fixed seven H2 sections. Current-truth, no date sectioning.
Unchanged beyond path refactor.

**`/update-progress`** — ported from `update-engagement-progress.md`. Newest-first dated
timeline with `Developments / Decisions / New blockers / Resolved` per `## <YYYY-MM-DD>`
section and same-date idempotent replacement. Its inline date logic is replaced by a
reference to `_date-parsing.md`.

**`/update-requirements` (new)** — newest-first **dated timeline of asks**. Each
`## <YYYY-MM-DD>` section lists feature requests / asks raised that day. Each entry
captures: the ask, the source forum + who raised it, and status if stated in the source.
Same idempotency as progress (re-running replaces a date's section in place). Uses
`_date-parsing.md` to attribute each ask to the date it was raised. Writes
`requirements.md`.

**`/qna` (new)** — interactive loop over all generated docs (`summary.md`,
`progress.md`, `requirements.md`, `guide/`) plus `corrections.md`. Three intents,
auto-detected per user turn:

1. **Question / clarification** — answer from the docs and engagement context, citing
   provenance (which source file/date a fact came from). Read-only.
2. **Correction** — record the corrected truth as a dated correction in `corrections.md`,
   then offer regeneration (`summary / progress / requirements / guide / all / none`).
   This absorbs the retired `correct-engagement-data` command.
3. **Direct edit / delete** — surgically amend a line in a generated doc in place, or
   amend/delete a `corrections.md` entry, when the user requests a specific change. Every
   such mutation appends a `changelog.md` audit entry. `/qna` warns that a direct edit to
   a generated doc may be overwritten by a later regeneration, and suggests recording it
   as a correction (intent 2) instead if it should persist.

`/qna` never modifies `slack/`/`granola/`/`raw/`.

## Data Flow & Artifacts

| File / dir | Writer | Mutability |
|---|---|---|
| `slack/` `granola/` `raw/` | — | **Read-only** (never written) |
| `corrections.md` | qna; any generate cmd resolving a contradiction | Append + **editable/deletable** via qna |
| `summary.md` | summarize-engagement; qna direct-edit | Regenerated or edited in place |
| `progress.md` | update-progress; qna direct-edit | Regenerated or edited in place |
| `requirements.md` | update-requirements; qna direct-edit | Regenerated or edited in place |
| `guide/` | build-guide; qna direct-edit | Regenerated or edited in place |
| `changelog.md` | **qna only (new)** | **Append-only** audit trail |

### `changelog.md` (new, append-only)

The immutable history that protects provenance now that other stores are mutable. Every
`/qna` mutation (a direct edit, or a `corrections.md` amend/delete) appends one dated
block:

```
### Change: <short-topic>
Date: YYYY-MM-DD

**Action:** edited | deleted
**Target:** <file + what changed, e.g. progress.md § 2026-03-12 / corrections.md "storage-backend" entry>
**Before:** <prior text or quote>
**After:** <new text, or "(removed)">
**Reason:** <user's stated reason, if given>
```

Corrections (intent 2) flow into `corrections.md` as today and do **not** require a
changelog entry — only mutations of existing data (intent 3) do, since that is where
history would otherwise be lost.

### Resolution precedence (unchanged)

Latest-wins-by-topic across `slack`/`granola`/`raw` + `corrections.md`. Generate commands
always rebuild from sources + `corrections.md`. A manual direct-edit to a generated doc is
a surgical override that a later regeneration may overwrite; `/qna` surfaces this when it
makes a direct edit.

## Migration & Retiring the Globals

1. **Port assets:** copy `~/.claude/commands/assets/fde-guide.css` and
   `fde-guide-page.html.tmpl` into `fde-tools/assets/`.
2. **Port the three command specs + the context include**, rewriting every
   `~/.claude/commands/...` path to `${CLAUDE_PLUGIN_ROOT}/commands/...` or `/assets/...`.
3. **Register** `fde-tools` in `.claude-plugin/marketplace.json` and add
   `fde-tools/.claude-plugin/plugin.json`.
4. **Retire the globals:** the global files live in `~/.claude/commands/`, outside this
   repo. Retirement is a documented manual step — the implementation plan lists the
   `~/.claude/commands/*engagement*` / `*fde-guide*` files plus `assets/` to delete after
   the plugin is installed and verified. The plugin will not auto-delete files outside the
   repo.
5. **README** for the plugin: the five commands, the engagement-directory model, and the
   mutability/audit behavior.

## Testing

Following the repo's existing style (`rwl-install-wizard/tests/` with shell assertions
over fixtures):

- A **fixture engagement dir** under `tests/fixtures/` with small `slack/`, `granola/`,
  `raw/` files containing known dates, a planted material contradiction, and a couple of
  feature-asks.
- **Assertion checks** (bash, run via `run-all.sh`): after running each command against
  the fixture, assert e.g. `progress.md` has the expected dated sections newest-first;
  `requirements.md` attributes an ask to the right date; `changelog.md` gets an append on
  a qna edit; raw inputs are byte-identical (read-only guarantee held).
- Manual smoke per `CLAUDE.md`: `claude "/update-requirements"` etc. in the fixture dir.

## Open Questions

None outstanding — all design decisions resolved during brainstorming.
