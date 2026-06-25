---
description: Mine the engagement inputs for customer problems and propose RunWhen solution designs (assistants, tasks, rules, workflows, KBs) in solutions.md — a priority-ordered backlog that feeds the POC scope-definition and tool-building phases.
---

# design-solutions

Produce `solutions.md` — a backlog of **problem → proposed RunWhen solution** entries. Unlike the other fde-tools commands, this one **actively designs**: it elaborates problems from hints and proposes concrete solutions for the FDE to refine. Every proposed solution is a first draft, not a commitment.

## Step 1 — Load shared conventions

Read and follow in full:

1. `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` — input loading from `slack/`/`granola/`/`raw/` (absent dirs skipped silently), the `corrections.md` overlay, the latest-wins-by-topic resolver, customer-identity inference, and contradiction handling (pause on material contradictions; record resolutions to `corrections.md`; otherwise surface inline using `> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`).
2. `${CLAUDE_PLUGIN_ROOT}/commands/_runwhen-primitives.md` — the RunWhen vocabulary every solution is expressed in.

## Step 2 — Read all inputs

Read in this order (skip absent items silently):

1. `corrections.md` (and a legacy `side-notes.md` if present) — authoritative corrections/resolutions, read first.
2. All readable files under `slack/`, `granola/`, `raw/` recursively — never modify them; they are read-only.
3. `solutions.md` (if present) — this command's own memory of prior runs.

Apply the latest-wins-by-topic resolver: for each problem/topic, the most recent dated statement across notes and `corrections.md` is current truth (e.g. a problem reframed, or a status advanced by a correction).

## Step 3 — Mine for problems

Identify the **customer's problems toward RunWhen as a product** — operational pain, SME dependencies, recurring failure modes, friction points, and value drivers — NOT deployment/integration asks (those belong in `requirements.md`). A problem may come from a thin hint: a single line about a recurring pain is enough to elaborate into a full problem statement. Build on the hints; do not merely quote them.

## Step 4 — Design a solution for each problem

For each problem, design a concrete RunWhen solution mapped onto the primitives in `_runwhen-primitives.md`. Propose specific assistants (and their risk profile), tasks/CodeBundles, SLX/SLIs/SLOs, workflows, scheduled commands, rules, and knowledge — including only the primitives that solution actually needs. The design is a recommendation the FDE will validate.

## Step 5 — Write solutions.md

Fully regenerate `solutions.md` (overwrite each run). Open with a title and a one-line framing note:

```
# <Customer> — RunWhen Solution Design

_Proposed solution designs derived from the engagement inputs. Each is a first-draft recommendation — refine via `/qna`._
```

Use the inferred customer name (or `[Customer]` if ambiguous, noting the ambiguity).

Then one entry per problem, **ordered by POC value** (core value drivers first), in exactly this shape:

```
### <Problem title>

**Problem:** <elaborated problem statement — the operational pain, who feels it, why it matters for the POC. Synthesized/expanded from the hints, not just quoted.>

**Solution (proposed):**
- **Assistants:** <persona(s) + risk profile>
- **Tasks/CodeBundles:** <diagnostics/remediation to build>
- **SLX / SLIs / SLOs:** <monitoring units>
- **Workflows:** <event triggers>
- **Scheduled Commands:** <cron investigations>
- **Rules:** <interpretation guidance>
- **Knowledge:** <KB to encode>
- **How it fits:** <one or two lines tying the pieces into the workflow that solves the problem>

**Source:** <which inputs hinted it — file + who, e.g. `raw/notes.txt`; `Slack day-1 status — GR`>
**Status:** proposed
```

Rules for entries:

- Omit any primitive line the solution does not use (do not write empty `Assistants:` lines).
- Keep the `**Solution (proposed):**` heading on every entry — these are recommendations, not commitments.
- **Status** defaults to `proposed`; set it to `scoping`, `building`, or `built` only when an input or a `corrections.md` entry explicitly says so.
- Place any unresolved-contradiction callouts inline in the relevant entry using `> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`

## Step 6 — Idempotency

- Entries are keyed by problem title/slug. Re-running updates an existing entry in place rather than adding a duplicate; a problem whose source material is unchanged comes out the same.
- Insert new problems in their correct priority position.
- A correction recorded in `corrections.md` (to a problem statement, a chosen primitive, or a status) is current truth and is reflected on the next regeneration.

## Step 7 — Outputs

- **Always write:** `solutions.md` (fully regenerated).
- **Write only on a confirmed resolution:** append a resolution block to `corrections.md` (creating it if absent) when the user confirms a contradiction during this run. Do not write to a legacy `side-notes.md`.
- **Never modify** any file under `slack/`, `granola/`, or `raw/`.
