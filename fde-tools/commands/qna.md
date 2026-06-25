---
description: Interactively ask about, clarify, correct, and edit the generated engagement docs (summary, progress, requirements, guide). Routes corrections to corrections.md and logs direct edits to an append-only changelog.md.
---

# qna

**Usage:** `/qna [optional opening question or instruction]`

Interrogate and edit the engagement data the other fde-tools commands generated.

## Step 1 — Load conventions

Read and follow in full:

1. `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` — input loading, corrections overlay, latest-wins-by-topic resolver, customer identity, contradiction handling.
2. `${CLAUDE_PLUGIN_ROOT}/commands/_qna-engine.md` — the QNA loop: the three intents, the `changelog.md` audit trail, and the regeneration offer.

## Step 2 — Load the data

Read (skip any that are absent):

- `corrections.md` and a legacy `side-notes.md` if present (read first).
- `summary.md`, `progress.md`, `requirements.md`, `solutions.md`, and the `guide/` pages — the generated docs under discussion.
- `changelog.md` if present — prior audit history.
- All readable files under `slack/`, `granola/`, `raw/` recursively — read-only source material for provenance.

## Step 3 — Run the loop

For each user turn, follow `_qna-engine.md`: detect the intent (question / correction / direct edit-delete), act on it, write `corrections.md` or `changelog.md` as specified, and offer regeneration after corrections. Continue until the user ends the session.

If `$ARGUMENTS` contains an opening question or instruction, treat it as the first turn.

## Guarantees

- Never modify any file under `slack/`, `granola/`, or `raw/`.
- `changelog.md` is append-only and written only for direct edit/delete mutations.
