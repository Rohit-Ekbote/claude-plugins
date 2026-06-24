# Date Parsing — Shared Include

> Shared include referenced by `update-progress` and `update-requirements`. It is **not** a slash command. It defines how to extract and attribute timestamps from the engagement material so the two timeline outputs anchor each item to the date it actually occurred.

## Date sources (priority order)

When attributing an item (a development, decision, blocker, ask) to a date, use the first source that yields a confident date:

1. **Explicit dates in body text** — a date written into the note or message content itself ("On 2026-03-12 we decided…").
2. **Slack message timestamps** — the timestamp attached to the message in the export.
3. **Granola meeting dates / headers** — the meeting date in the note header or title.
4. **Dates embedded in filenames** — e.g. `granola/2026-03-12-kickoff.md`, `raw/2026-04-01-notes.txt`.
5. **Run date (fallback only)** — today's date, used **only** when none of the above applies (e.g. a conclusion reached during this run that is not tied to any dated source).

## Normalization

- Normalize every date to `YYYY-MM-DD`.
- Resolve relative phrases ("yesterday", "last Tuesday", "next week") against the **nearest anchoring date in the same source** (e.g. the meeting date of the note they appear in), NOT against the run date.

## Attribution rule

Attribute each item to the date it actually occurred. Never pile everything under the run date. A single fact is recorded once, under the date it happened — not duplicated across multiple dates.

## Ambiguity

If a date cannot be confidently determined for an item, tag it `(date unknown)` and group such items under a trailing `## (date unknown)` section in the output. Do not guess a date.
