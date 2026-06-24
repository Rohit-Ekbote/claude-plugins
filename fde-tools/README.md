# fde-tools

A Claude Code plugin packaging the Forward Deployed Engineer (FDE) engagement workflow. It turns read-only engagement notes into living docs and lets you interrogate and edit them conversationally.

## The engagement directory

Run the commands from inside an engagement directory containing read-only source material:

- `slack/` — Slack exports
- `granola/` — Granola meeting notes
- `raw/` — raw field notes

These are **never modified**. Commands produce and maintain: `summary.md`, `progress.md`, `requirements.md`, `guide/`, the `corrections.md` overlay, and an append-only `changelog.md`.

## Commands

| Command | Output | Dated? |
|---------|--------|--------|
| `/build-guide` | `guide/` — multi-page offline HTML field guide | no (current-truth) |
| `/summarize-engagement` | `summary.md` — profile, infra, goals, solutions, risks | no (current-truth) |
| `/update-progress` | `progress.md` — newest-first dated timeline of developments/decisions/blockers | **yes** |
| `/update-requirements` | `requirements.md` — newest-first dated timeline of feature asks | **yes** |
| `/qna` | answers, corrections, and surgical edits over the generated docs | — |

## How data flows

- All commands read `slack/`/`granola/`/`raw/` plus the `corrections.md` overlay and resolve facts by **latest-wins-by-topic** (the most recent dated statement about a topic is current truth).
- `/update-progress` and `/update-requirements` parse timestamps from the notes (body dates, Slack stamps, Granola headers, filename dates) and attribute each item to the date it occurred.
- Material contradictions pause the run and ask you to resolve them; resolutions are recorded in `corrections.md`.

## /qna — interrogate and edit

`/qna` works over every generated doc and has three modes, auto-detected per message:

1. **Ask / clarify** — answers with provenance (which source file and date a fact came from). Read-only.
2. **Correct** — you state the corrected truth; it writes a dated entry to `corrections.md` and offers to regenerate.
3. **Direct edit / delete** — surgical in-place edits to a generated doc, or amend/delete of a `corrections.md` entry. Every such change is logged to the append-only `changelog.md`. Direct edits to generated docs may be overwritten by a later regeneration — `/qna` warns you and suggests recording a correction instead if it should persist.

`slack/`, `granola/`, and `raw/` are never modified by any command.
