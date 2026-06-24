---
description: Generate (or regenerate) summary.md for the current FDE engagement directory.
---

Read and follow all conventions defined in `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` before proceeding.

Follow these steps in order:

## Step 1 — Load corrections overlay

If `corrections.md` exists in the current working directory, read it first. Resolutions recorded there are applied via the latest-wins-by-topic resolver — the most recent dated statement about a topic is current truth, so a later correction can supersede an earlier one. Also check for a legacy `side-notes.md` if present; it will be merged using the same latest-wins-by-topic resolver.

## Step 2 — Load engagement context

Read every readable text file found recursively under `slack/`, `granola/`, and `raw/` in the current working directory. Skip any directory that is absent — do not error. Never modify any file under `slack/`, `granola/`, or `raw/`; they are read-only inputs.

## Step 3 — Infer customer identity

From the combined engagement context, infer the customer name (company or org) as defined in `_engagement-context.md`. If the name cannot be confidently inferred, use `[Customer]` and note the ambiguity at the top of `summary.md`.

## Step 4 — Run contradiction handling

Apply the contradiction-handling flow from `_engagement-context.md`:
- Only flag material, factual contradictions (incompatible claims that affect decisions).
- When a contradiction is found: pause, show both sources with file path and exact quote, ask which is correct.
- On user confirmation: append a resolution block to `corrections.md` (creating it if absent) using the format specified in `_engagement-context.md`.
- If the contradiction is unresolved (user defers, skips, or the command runs non-interactively), surface it inline in `summary.md` using this exact callout format:

  `> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`

## Step 5 — Write summary.md

Fully regenerate `summary.md` in the current working directory (overwrite on every run). The file must contain a top-level title followed by exactly these seven H2 sections, in this order:

```
# <Customer> — Engagement Summary

## Customer profile

## Infrastructure (as-is)

## Requirements / goals

## How we solve each requirement

## Solution options with trade-offs

## Blockers / risks

## Open questions
```

Populate each section from the engagement context, `corrections.md`, and legacy `side-notes.md` if present. Apply the latest-wins-by-topic resolver from the convention to determine current truth for each topic (most recent dated statement across notes and `corrections.md` wins). Place any unresolved-contradiction callouts inline within the relevant section. Do not add, remove, or rename sections.

## Outputs

- Always write: `summary.md` (fully regenerated).
- Write `corrections.md` only when the user confirms a contradiction resolution during this run (append the resolution block, creating the file if absent). Never write new entries to the legacy `side-notes.md`.
- Never modify any file under `slack/`, `granola/`, or `raw/`.
