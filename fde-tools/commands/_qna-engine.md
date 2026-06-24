# QNA Engine — Shared Include

> Shared include referenced by the `qna` command. It is **not** a slash command. It defines the interactive loop for interrogating and editing the generated engagement docs.

## Scope of data

`/qna` operates over the generated docs in the working directory: `summary.md`, `progress.md`, `requirements.md`, and the `guide/` pages, plus the `corrections.md` overlay. It also reads the read-only source material (`slack/`, `granola/`, `raw/`) and `changelog.md` for provenance.

**Read-only guarantee:** `/qna` never modifies any file under `slack/`, `granola/`, or `raw/` under any circumstance.

## Intent detection

For each user turn, classify into exactly one of three intents and act accordingly.

### Intent 1 — Question / clarification (read-only)

The user asks about the generated data ("why does the summary say storage is NFS?", "where did the March ask come from?").

- Answer from the generated docs and the engagement context.
- **Cite provenance**: name the source file and date a fact came from (e.g. "from `granola/2026-03-12-kickoff.md`, stated 2026-03-12"), and note if it was set by a `corrections.md` entry.
- Write nothing.

### Intent 2 — Correction (writes corrections.md)

The user states that something recorded is wrong and gives the corrected truth ("setup isn't ready yet").

- Infer the correction fields: `topic` (short semantic slug), `Correction` (what is actually true), `Corrects` (the mistaken claim and where it appeared), `Date` (today, `YYYY-MM-DD`).
- If any field is too ambiguous to infer confidently, ask ONE brief clarifying question before writing.
- Prepend a Correction block (insert it at the top of) `corrections.md` (immediately under the title line if present; create the file with title `# Corrections` if absent), using the format from `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md`:

  ```
  ### Correction: <short-topic>
  Date: YYYY-MM-DD

  **Correction:** <what is actually true>
  **Corrects:** <the mistaken claim / where it appeared>
  ```

- This writes only to `corrections.md` (a new prepended block) and does NOT require a `changelog.md` entry.
- Then offer regeneration (see "Offer to regenerate" below).

### Intent 3 — Direct edit / delete (writes the target + changelog.md)

The user requests a specific surgical change to existing generated data, or to amend/delete a `corrections.md` entry ("delete the duplicate ingress line in progress.md for 2026-04-01", "remove the storage-backend correction I added by mistake").

- Make the precise edit in place to the target file (`summary.md` / `progress.md` / `requirements.md` / a `guide/` page), OR amend/delete the named `corrections.md` entry.
- **Append a `changelog.md` audit entry** (see below) for every such mutation.
- **Warn about regeneration overwrite:** if the target is a generated doc, tell the user that a later `/update-progress`, `/update-requirements`, `/summarize-engagement`, or `/build-guide` run may overwrite this in-place edit, and suggest recording it as a correction (Intent 2) instead if it should persist. Amend/delete of a `corrections.md` entry is durable and carries no such warning.

## changelog.md (append-only audit trail)

`changelog.md` is written ONLY by `/qna`, ONLY for Intent 3 mutations, and is **append-only** — never rewrite or delete earlier entries. Prepend each new block (insert it at the top of the file, newest first), immediately under the title line if present. Create the file with title `# Changelog` if absent.

Block format:

```
### Change: <short-topic>
Date: YYYY-MM-DD

**Action:** edited | deleted
**Target:** <file + what changed, e.g. progress.md § 2026-03-12 / corrections.md "storage-backend" entry>
**Before:** <prior text or quote>
**After:** <new text, or "(removed)">
**Reason:** <user's stated reason, if given; else omit this line>
```

## Offer to regenerate

After an Intent 2 correction (and optionally after an Intent 3 edit), ask exactly:

> Regenerate now? — summary / progress / requirements / guide / all / none

| Answer | Action |
|--------|--------|
| `summary` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/summarize-engagement.md`. |
| `progress` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/update-progress.md`. |
| `requirements` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/update-requirements.md`. |
| `guide` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/build-guide.md`. |
| `all` | Follow all four in order: summarize → progress → requirements → guide. |
| `none` | Leave generated docs as-is; the next manual run picks up corrections via the overlay. |

Write only the outputs the user opts to regenerate. Never write to `slack/`, `granola/`, or `raw/`.
