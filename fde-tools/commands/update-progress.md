---
description: Create or update progress.md with a dated delta section for today's run.
---

## Step 1 — Load shared conventions

Read and follow `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` in full before proceeding. That file defines:

- How to load inputs from `slack/`, `granola/`, and `raw/` (absent dirs silently skipped).
- Corrections overlay: read `corrections.md` first (and a legacy `side-notes.md` if present); confirmed resolutions and corrections recorded there are authoritative over raw inputs.
- Latest-wins-by-topic resolver: apply the convention's latest-wins-by-topic resolver across all notes and `corrections.md` — the most recent dated statement about a topic is current truth; on a date tie, the `corrections.md` entry wins; corrections are never deleted.
- Customer identity: infer the customer name from the engagement context; fall back to `[Customer]` if ambiguous.
- Contradiction handling: pause on material contradictions, ask the user to resolve, record to `corrections.md`, or surface inline using the exact callout format `> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`

## Step 2 — Determine the timeline dates

Follow `${CLAUDE_PLUGIN_ROOT}/commands/_date-parsing.md` for all date extraction, normalization, and attribution. In summary, the progress log is a **date-wise timeline, newest date first**, where each item is attributed to the date it actually occurred:

1. **Event dates found inside the engagement material** — per the date-source priority in `_date-parsing.md` (body dates, Slack timestamps, Granola headers, filename dates). Each distinct date with material activity gets its own `## <YYYY-MM-DD>` section. Backfilling historical dates is intended.
2. **The run date** — used only as the fallback per `_date-parsing.md`, for anything observed or concluded during this run that is not tied to a specific source date.

Items whose date cannot be determined go under a trailing `## (date unknown)` section per the include. Never pile everything under the run date.

## Step 3 — Read all inputs

Read in this order:

1. `corrections.md` (if present) — authoritative corrections and resolutions. Also read a legacy `side-notes.md` if present.
2. All readable files under `slack/`, `granola/`, `raw/` recursively — skip absent dirs silently.
3. `progress.md` (if present) — this is the command's own memory of what was reported on previous runs.

After reading all inputs, apply the latest-wins-by-topic resolver defined in `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md`: for each topic, the most recent dated statement across notes and `corrections.md` is current truth; on a date tie, the `corrections.md` entry wins.

## Step 4 — Attribute activity to dates

Build the timeline by attributing each development, decision, blocker, and resolution to the date it occurred (per Step 2).

- On the **first run** (no existing `progress.md`), construct the full back-dated timeline from the engagement material: one section per date that has activity, newest first.
- On **subsequent runs**, refresh the timeline from current inputs: add sections for any new dates, and update existing dated sections in place where their source material has changed. Do not duplicate a fact across multiple dates — record it once, under the date it happened.

Resolved contradictions and corrections recorded in `corrections.md` should be treated as settled and need not be flagged again unless new contradictory evidence has appeared.

A Correction block in `corrections.md` (with its own `Date:` field) is itself a dated development event: attribute it to its own `Date:` in the timeline, not to the run date.

### Annotating superseded past sections

When a correction (or a newer note) supersedes a claim recorded in an **earlier** dated section, insert this exact marker line into that earlier section, immediately under the superseded claim:

`> ⚠️ Later corrected (YYYY-MM-DD): <what is actually true>.`

(YYYY-MM-DD is the date of the superseding statement.)

Do not alter the original wording of the earlier claim — only add the marker. Earlier sections are never rewritten, only annotated.

## Step 5 — Write each dated section

Compose every dated section with this exact structure:

```
## <YYYY-MM-DD>

### Developments
<Facts, progress updates, notable events, and any Correction: events sourced from corrections.md on this date. Bullet list.>

### Decisions
<Decisions made or confirmed on this date. Bullet list.>

### New blockers
<Blockers that emerged or were identified on this date. If none, write "None.">

### Resolved
<Items (blockers, open questions, contradictions) resolved on this date. If none, write "None.">
```

Surface any unresolved contradictions inline within the relevant sub-section using the exact callout format:

`> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`

Resolved contradictions belong in `corrections.md` per the convention, not in `progress.md`.

## Step 6 — Write progress.md with idempotency

The file must open with a top-level title on its very first line:

```
# <Customer> — Engagement Progress
```

Use the inferred customer name (or `[Customer]` if ambiguous).

Dated sections appear below the title, **newest date first**.

**Idempotency rules:**

- **Never produce two sections with the same date.** If a `## <YYYY-MM-DD>` section already exists, **replace it in place** with the freshly composed one — do not append a duplicate. This is what makes re-running on the same day update that day's section rather than adding another.
- Insert any new date in its correct newest-first position (the run date's section, when present, sits at the very top, immediately after the title line).
- A dated section whose source material is unchanged since the last run should come out identical — re-running with no new input leaves `progress.md` effectively unchanged.

## Step 7 — Write outputs

- **Always write:** `progress.md` (created or updated as above).
- **Write only on a confirmed resolution:** append the resolution block to `corrections.md` (creating it if absent) when the user confirms an answer to a contradiction during this run. Do not write to the legacy `side-notes.md` for new resolutions.
- **Never modify** any file under `slack/`, `granola/`, or `raw/`. Those are read-only inputs.
