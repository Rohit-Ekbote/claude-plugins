---
description: Create or update requirements.md — a newest-first dated timeline of feature asks and requirements raised across engagement forums.
---

# update-requirements

Build a **date-wise timeline of asks** — every new feature, request, or requirement raised in any engagement forum (Slack, Granola meetings, raw notes), attributed to the date it was raised.

## Step 1 — Load shared conventions

Read and follow `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` in full before proceeding. It defines input loading from `slack/`/`granola/`/`raw/` (absent dirs skipped silently), the `corrections.md` overlay, the latest-wins-by-topic resolver, customer-identity inference, and contradiction handling (pause on material contradictions; record resolutions to `corrections.md`; otherwise surface inline using `> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`).

## Step 2 — Determine the dates for each ask

Follow `${CLAUDE_PLUGIN_ROOT}/commands/_date-parsing.md` for all date extraction, normalization, and attribution. Attribute each ask to the date it was **raised** (per the date-source priority: body dates, Slack timestamps, Granola headers, filename dates; run date only as the documented fallback). Asks whose date cannot be determined go under a trailing `## (date unknown)` section.

## Step 3 — Read all inputs

Read in this order:

1. `corrections.md` (if present) — authoritative corrections/resolutions. Also read a legacy `side-notes.md` if present.
2. All readable files under `slack/`, `granola/`, `raw/` recursively — skip absent dirs silently. Never modify them; they are read-only.
3. `requirements.md` (if present) — this command's own memory of what was reported on previous runs.

Apply the latest-wins-by-topic resolver: for each ask/topic, the most recent dated statement across notes and `corrections.md` is current truth (e.g. an ask later marked delivered or withdrawn).

## Step 4 — Identify the asks

An **ask** is any new feature request, capability request, or requirement raised by the customer or team — distinct from a development or decision (those belong in `progress.md`). For each ask, capture:

- **Ask** — a one-line statement of what is being requested.
- **Source** — the forum and who raised it (e.g. `Slack #eng — Priya`, `Granola 2026-03-12 kickoff — customer lead`, `raw/field-notes.txt`).
- **Status** — default to `requested`; override it only when the source explicitly states a different status (e.g. `in-progress`, `delivered`, `declined`).

## Step 5 — Write requirements.md

The file must open with a top-level title on its first line:

```
# <Customer> — Engagement Requirements
```

Use the inferred customer name (or `[Customer]` if ambiguous).

Below the title, write dated sections **newest date first**. Compose each section as:

```
## <YYYY-MM-DD>

- **<ask>** — _<source forum + who>_ — status: <status>
- **<ask>** — _<source forum + who>_ — status: <status>
```

Place any unresolved-contradiction callouts inline within the relevant dated section using the exact format `> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`

## Step 6 — Idempotency

- **Never produce two sections with the same date.** If a `## <YYYY-MM-DD>` section already exists, **replace it in place** with the freshly composed one — re-running on the same day updates that day's section rather than appending a duplicate.
- Insert any new date in its correct newest-first position.
- A dated section whose source material is unchanged since the last run comes out identical — re-running with no new input leaves `requirements.md` effectively unchanged.
- When a later statement supersedes an ask recorded in an **earlier** dated section (e.g. it was delivered or withdrawn), insert this exact marker immediately under that earlier entry, without rewriting the original line:

  `> ⚠️ Later updated (YYYY-MM-DD): <what is now true>.`

  (This marker reads **Later updated** — distinct on purpose from the `> ⚠️ Later corrected` marker `update-progress` uses. An ask being delivered or withdrawn is a status update, not a correction of an earlier mistake.)

## Step 7 — Outputs

- **Always write:** `requirements.md` (created or updated as above).
- **Write only on a confirmed resolution:** append a resolution block to `corrections.md` (creating it if absent) when the user confirms an answer to a contradiction during this run. Do not write to the legacy `side-notes.md`.
- **Never modify** any file under `slack/`, `granola/`, or `raw/`.
