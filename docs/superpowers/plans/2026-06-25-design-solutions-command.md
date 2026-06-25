# /design-solutions Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/design-solutions` command (and a `_runwhen-primitives.md` shared include) to the existing `fde-tools` plugin that mines engagement inputs for customer problems and proposes RunWhen solution designs, plus wire it into `/qna`, the fixture, tests, and packaging.

**Architecture:** Prompt-only, extends the existing `fde-tools/` plugin. One new command file + one new shared include (the RunWhen primitive vocabulary, grounded in the RunWhen docs), both referenced via `${CLAUDE_PLUGIN_ROOT}`. The active-design behavior is contained entirely in the new command. Existing commands (`build-guide`, `summarize-engagement`, `update-progress`, `update-requirements`) are untouched; `/qna` is extended to also read/correct `solutions.md`.

**Tech Stack:** Markdown command/include specs, Claude Code plugin manifest, bash 3.2 structural-lint assertions (existing `tests/test-structure.sh` + `tests/test-fixtures.sh`).

## Global Constraints

- Plugin name `fde-tools`; bump version `0.1.0` → `0.2.0` in `fde-tools/.claude-plugin/plugin.json`.
- Bash scripts must run on bash 3.2 (macOS default): no `declare -A`, no `${var,,}`, no `|&`.
- Commands/includes reference paths via `${CLAUDE_PLUGIN_ROOT}/commands/...` and `/assets/...` — never `~/.claude/commands/...`.
- Underscore-prefixed files in `commands/` are shared includes, NOT slash commands.
- `slack/`, `granola/`, `raw/` are strictly read-only — no command may write to them.
- New `test-structure.sh` assertions are inserted immediately ABOVE the line `# --- later tasks append assertion blocks below this line ---` (preserve that marker).
- `/update-requirements` is NOT modified by this plan.
- `solutions.md` is regenerated each run (not append-only, not a dated timeline); entries keyed by problem title/slug; `_date-parsing.md` is NOT used.
- Every solution carries a `(proposed)` label; `Status` defaults to `proposed` and advances only when an input/correction explicitly says so.
- `/qna` regeneration order including the new doc: summarize → progress → requirements → solutions → guide.
- Spec of record: `docs/superpowers/specs/2026-06-25-design-solutions-command-design.md`.
- RunWhen primitive definitions are grounded in `https://docs.runwhen.com/docs/use/common-user-journeys/` and the `learn/` concept pages (assistants, rules, workflows).

---

## File Structure

```
fde-tools/
├── .claude-plugin/plugin.json          # Task 5 (version bump)
├── commands/
│   ├── _runwhen-primitives.md          # Task 1 (new include)
│   ├── design-solutions.md             # Task 2 (new command)
│   ├── _qna-engine.md                  # Task 3 (add solutions.md to scope + regen table)
│   └── qna.md                          # Task 3 (load solutions.md)
├── tests/
│   ├── test-structure.sh               # Tasks 1,2,3,5 (assertions)
│   ├── test-fixtures.sh                # Task 4 (product-hint assertion)
│   └── fixtures/sample-engagement/raw/field-notes.txt   # Task 4 (planted hint)
└── README.md                           # Task 5 (command row + note)
.claude-plugin/marketplace.json         # Task 5 (description/tags)
```

`tests/test-structure.sh` is the spine: each task appends assertions for the file(s) it creates/changes, above the marker, so a task's assertions fail before its change exists (the red→green cycle for a content plugin).

---

## Task 1: Write the `_runwhen-primitives.md` shared include

**Files:**
- Create: `fde-tools/commands/_runwhen-primitives.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Produces: the RunWhen solution vocabulary referenced by `design-solutions.md` via `${CLAUDE_PLUGIN_ROOT}/commands/_runwhen-primitives.md`. Names the primitives `AI Assistant`, `Workflow`, `Rule`, `Scheduled Command`, `Knowledge` (asserted by tests) plus Workspace, SLX/SLI/SLO, Task/CodeBundle, CodeCollection, Runner, MCP.

- [ ] **Step 1: Append failing assertions**

In `fde-tools/tests/test-structure.sh`, immediately ABOVE the line `# --- later tasks append assertion blocks below this line ---`, insert:

```bash
echo "== design-solutions: _runwhen-primitives include =="
assert_file "$CMD/_runwhen-primitives.md" "_runwhen-primitives.md exists"
assert_grep "AI Assistant" "$CMD/_runwhen-primitives.md" "primitives names AI Assistant"
assert_grep "Workflow" "$CMD/_runwhen-primitives.md" "primitives names Workflow"
assert_grep "Rule" "$CMD/_runwhen-primitives.md" "primitives names Rule"
assert_grep "Scheduled Command" "$CMD/_runwhen-primitives.md" "primitives names Scheduled Command"
assert_grep "Knowledge" "$CMD/_runwhen-primitives.md" "primitives names Knowledge"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `_runwhen-primitives.md exists (missing ...)`, non-zero exit.

- [ ] **Step 3: Write the include**

Create `fde-tools/commands/_runwhen-primitives.md`:

```markdown
# RunWhen Primitives — Shared Include

> Shared include referenced by `design-solutions`. It is **not** a slash command. It is a concise vocabulary of RunWhen's building blocks — not a tutorial — used to express each proposed solution in real RunWhen terms.

> **Accuracy note:** this encodes a point-in-time understanding of RunWhen, grounded in the RunWhen docs (`https://docs.runwhen.com/docs/use/common-user-journeys/` and the `learn/` concept pages). Review it for correctness over time. Because it ships with the plugin, corrections to it are plugin edits — not engagement-data edits via `/qna`.

## Primitives

- **Workspace** — a collaborative tenant/scope boundary; contains SLXs, assistants, and shared knowledge.
- **SLX (Service Level Experience)** — bundles a service/resource's health indicators and objectives; triggers investigation when thresholds are breached.
- **SLI (Service Level Indicator)** — a health-check task defining what healthy operation looks like, used within an SLX.
- **SLO (Service Level Objective)** — an alerting threshold within an SLX that determines when an Issue is raised.
- **Task / CodeBundle (Runbook)** — an executable diagnostic or remediation procedure; the investigative backbone and the main artifact built during tool-building.
- **CodeCollection** — a git repo packaging reusable tasks.
- **AI Assistant (Digital Assistant)** — an intelligent agent in Workspace Chat and integrations (e.g. Slack) that answers questions and runs diagnostic tasks. Tuned by **access level** (read-only / read-write) and **confidence thresholds** (filter confidence = which tasks it considers; run confidence = which it executes), plus task-tag filters. Draws context from Rules, Commands, and Knowledge. Create different personas for different risk profiles — e.g. an interactive-thorough assistant vs. an autonomous-conservative one for webhooks (low run confidence keeps scale/COGS down).
- **Workflow** — event-driven automation: an external alert/webhook/SLO-trip launches an assistant investigation and routes the result (Slack, PagerDuty, etc.). The incident-integration path.
- **Scheduled Command** — a cron-triggered recurring investigation/briefing that runs an assistant's instructions and delivers to Slack or email.
- **Rule** — standing interpretive guidance (de-noise / re-prioritize / reframe) that shapes how an assistant **interprets** findings. It does NOT change which tasks run (confidence thresholds do that) or which procedures users invoke (Commands do that). Configured in Workspace Studio, scoped workspace / per-assistant / per-user.
- **Knowledge (KB)** — curated narrative context (ownership, architecture, environment specifics) attached at resource/SLX level; how SME knowledge is encoded. There is no central KB registry.
- **RunSession / Issue** — a RunSession is the record of one investigation; an Issue is a detected problem flagged when an SLX health check fails.
- **Runner / RunWhen Local** — discovers resources and executes tasks.
- **MCP Server** — the interface an LLM client (e.g. Claude) uses to craft tasks, scheduled commands, rules, and KBs.

## Using these in a solution design

Map each proposed solution onto only the primitives it needs. Common shapes:

- **Reduce SME dependency** → an **AI Assistant** (the "SME simulator") + **Knowledge** encoding the SME's domain expertise + the **Tasks** it runs.
- **Incident triage at scale without COGS blowup** → a **Workflow** (alert/incident integration) → a conservative **autonomous Assistant** (low run confidence) + **Rules** to de-noise expected events.
- **Recurring scheduled checks** (e.g. pre-market prep-job health) → a **Scheduled Command** running a **Task**, with a **Rule** to reframe expected churn and pair failures with rerun guidance.
- **Custom resource troubleshooting** (e.g. a bespoke CRD) → a custom **Task/CodeBundle** (authored via the **MCP**) + **Knowledge** describing the resource.
```

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — the six new assertions pass; `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/_runwhen-primitives.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): add _runwhen-primitives shared include (docs-grounded vocabulary)"
```

---

## Task 2: Write the `/design-solutions` command

**Files:**
- Create: `fde-tools/commands/design-solutions.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: `_engagement-context.md` (existing), `_runwhen-primitives.md` (Task 1).
- Produces: the `/design-solutions` slash command. Writes `solutions.md` — a priority-ordered backlog of `### <Problem title>` entries, each with `**Problem:**`, `**Solution (proposed):**` (structured by primitive), `**Source:**`, `**Status:**`.

- [ ] **Step 1: Append failing assertions**

Insert above the marker line in `test-structure.sh`:

```bash
echo "== design-solutions: command =="
assert_file "$CMD/design-solutions.md" "design-solutions.md exists"
assert_no_grep "~/.claude/commands" "$CMD/design-solutions.md" "no home-path refs in design-solutions"
assert_grep "_engagement-context.md" "$CMD/design-solutions.md" "design-solutions references engagement-context"
assert_grep "_runwhen-primitives.md" "$CMD/design-solutions.md" "design-solutions references runwhen-primitives"
assert_grep "solutions.md" "$CMD/design-solutions.md" "design-solutions writes solutions.md"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `design-solutions.md exists (missing ...)`.

- [ ] **Step 3: Write the command**

Create `fde-tools/commands/design-solutions.md`:

```markdown
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
```

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — the five new assertions pass; `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/design-solutions.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): add design-solutions command (problem->RunWhen solution backlog)"
```

---

## Task 3: Wire `solutions.md` into `/qna`

**Files:**
- Modify: `fde-tools/commands/_qna-engine.md`
- Modify: `fde-tools/commands/qna.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: `solutions.md` (produced by Task 2) and `design-solutions.md` (the regeneration target).
- Produces: `/qna` now reads/answers-about/corrects/edits `solutions.md`, and offers `solutions` as a regeneration option.

- [ ] **Step 1: Append failing assertions**

Insert above the marker line in `test-structure.sh`:

```bash
echo "== design-solutions: qna integration =="
assert_grep "solutions.md" "$CMD/_qna-engine.md" "qna-engine scope includes solutions.md"
assert_grep "design-solutions.md" "$CMD/_qna-engine.md" "qna-engine regen table includes design-solutions"
assert_grep "solutions.md" "$CMD/qna.md" "qna loads solutions.md"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `qna-engine scope includes solutions.md (pattern ... not in ...)`.

- [ ] **Step 3: Add solutions.md to the qna-engine scope**

In `fde-tools/commands/_qna-engine.md`, replace this exact line:

```
`/qna` operates over the generated docs in the working directory: `summary.md`, `progress.md`, `requirements.md`, and the `guide/` pages, plus the `corrections.md` overlay. It also reads the read-only source material (`slack/`, `granola/`, `raw/`) and `changelog.md` for provenance.
```

with:

```
`/qna` operates over the generated docs in the working directory: `summary.md`, `progress.md`, `requirements.md`, `solutions.md`, and the `guide/` pages, plus the `corrections.md` overlay. It also reads the read-only source material (`slack/`, `granola/`, `raw/`) and `changelog.md` for provenance.
```

- [ ] **Step 4: Add solutions to the regeneration prompt and table**

In `fde-tools/commands/_qna-engine.md`, replace this exact line:

```
> Regenerate now? — summary / progress / requirements / guide / all / none
```

with:

```
> Regenerate now? — summary / progress / requirements / solutions / guide / all / none
```

Then replace this exact table row:

```
| `requirements` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/update-requirements.md`. |
| `guide` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/build-guide.md`. |
| `all` | Follow all four in order: summarize → progress → requirements → guide. |
```

with:

```
| `requirements` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/update-requirements.md`. |
| `solutions` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/design-solutions.md`. |
| `guide` | Follow `${CLAUDE_PLUGIN_ROOT}/commands/build-guide.md`. |
| `all` | Follow all five in order: summarize → progress → requirements → solutions → guide. |
```

- [ ] **Step 5: Load solutions.md in qna.md**

In `fde-tools/commands/qna.md`, replace this exact line:

```
- `summary.md`, `progress.md`, `requirements.md`, and the `guide/` pages — the generated docs under discussion.
```

with:

```
- `summary.md`, `progress.md`, `requirements.md`, `solutions.md`, and the `guide/` pages — the generated docs under discussion.
```

- [ ] **Step 6: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — the three new assertions pass; `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add fde-tools/commands/_qna-engine.md fde-tools/commands/qna.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): wire solutions.md into /qna scope and regeneration"
```

---

## Task 4: Enrich the fixture with a product-problem hint

**Files:**
- Modify: `fde-tools/tests/fixtures/sample-engagement/raw/field-notes.txt`
- Modify: `fde-tools/tests/test-fixtures.sh`

**Interfaces:**
- Produces: a planted product-problem hint so the `/design-solutions` manual smoke has something to design from; a guard assertion that the hint is present.

- [ ] **Step 1: Append failing assertion**

In `fde-tools/tests/test-fixtures.sh`, immediately ABOVE these lines:

```bash
echo ""
echo "TOTAL: $PASS passed, $FAIL failed"
```

insert:

```bash
# Product-problem hints for design-solutions (SME dependency + recurring prep-job failure).
grep -qi "SME" "$FX/raw/field-notes.txt" && grep -qi "prep job" "$FX/raw/field-notes.txt" \
  && ok "product-problem hints present (SME dependency + prep-job failure)" || no "product-problem hints missing"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-fixtures.sh`
Expected: FAIL — `product-problem hints missing`, non-zero exit.

- [ ] **Step 3: Plant the hints in the fixture**

In `fde-tools/tests/fixtures/sample-engagement/raw/field-notes.txt`, append these lines to the end of the file:

```
- Users lean heavily on a handful of SMEs to keep pipelines healthy and to triage incidents; GR wants RunWhen to reduce that SME dependency (the core POC value driver).
- Every morning before market open, prep jobs run for each component; when one fails the on-call has to RCA it by hand and decide whether to rerun — a recurring, time-sensitive pain.
```

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/run-all.sh`
Expected: PASS — both suites end `0 failed`; the new fixture assertion passes; exit 0.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/tests/fixtures/sample-engagement/raw/field-notes.txt fde-tools/tests/test-fixtures.sh
git commit -m "test(fde-tools): plant product-problem hints in fixture for design-solutions"
```

---

## Task 5: Packaging — version bump, README, marketplace, fixture README

**Files:**
- Modify: `fde-tools/.claude-plugin/plugin.json`
- Modify: `fde-tools/README.md`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `fde-tools/tests/fixtures/README.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a `0.2.0` plugin that documents `/design-solutions`, and a manual-smoke step for it.

- [ ] **Step 1: Append failing assertion**

Insert above the marker line in `test-structure.sh`:

```bash
echo "== design-solutions: packaging =="
assert_grep '"version": *"0.2.0"' "$PLUGIN_DIR/.claude-plugin/plugin.json" "plugin version bumped to 0.2.0"
assert_grep "design-solutions" "$PLUGIN_DIR/README.md" "README documents design-solutions"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `plugin version bumped to 0.2.0 (pattern ... not in ...)`.

- [ ] **Step 3: Bump the plugin version**

In `fde-tools/.claude-plugin/plugin.json`, change:

```
  "version": "0.1.0",
```

to:

```
  "version": "0.2.0",
```

- [ ] **Step 4: Update the README command table and add a note**

In `fde-tools/README.md`, replace this exact table row:

```
| `/update-requirements` | `requirements.md` — newest-first dated timeline of feature asks | **yes** |
| `/qna` | answers, corrections, and surgical edits over the generated docs | — |
```

with:

```
| `/update-requirements` | `requirements.md` — newest-first dated timeline of deployment/integration asks | **yes** |
| `/design-solutions` | `solutions.md` — backlog of customer problems → proposed RunWhen solution designs | no (priority-ordered) |
| `/qna` | answers, corrections, and surgical edits over the generated docs | — |
```

Then, immediately below the closing line of the `## /qna — interrogate and edit` section (the line `` `slack/`, `granola/`, and `raw/` are never modified by any command. ``), add this new section:

```markdown

## solutions vs requirements

Two different artifacts for two different audiences:

- **`/update-requirements` → `requirements.md`** — *deployment/integration asks*: what GR needs to install and run the RunWhen platform (chart knobs, air-gap, auth, storage, SSO). A dated timeline.
- **`/design-solutions` → `solutions.md`** — *product solution design*: the customer's operational problems and proposed RunWhen solutions (assistants, tasks, rules, workflows, KBs) that drive the POC's scope-definition and tool-building phases. A priority-ordered backlog. Unlike the other commands, it actively designs — every solution is a first-draft proposal you refine via `/qna`.
```

- [ ] **Step 5: Update the marketplace description and tags**

In `.claude-plugin/marketplace.json`, in the `fde-tools` entry, replace the `description` and `tags` values. Find the `fde-tools` block's description line:

```
      "description": "Forward Deployed Engineer engagement toolkit: offline field guide, summary, dated progress timeline, dated requirements log, and an interactive /qna command to interrogate and edit the generated data",
```

replace with:

```
      "description": "Forward Deployed Engineer engagement toolkit: offline field guide, summary, dated progress timeline, dated requirements log, RunWhen solution-design backlog, and an interactive /qna command to interrogate and edit the generated data",
```

and find the `fde-tools` block's tags line:

```
      "tags": ["fde", "engagement", "field-guide", "summary", "progress", "requirements", "offline"],
```

replace with:

```
      "tags": ["fde", "engagement", "field-guide", "summary", "progress", "requirements", "solutions", "runwhen", "offline"],
```

Validate JSON: `node -e "require('./.claude-plugin/marketplace.json'); console.log('OK')"`
Expected: `OK`.

- [ ] **Step 6: Add the design-solutions manual-smoke step to the fixture README**

In `fde-tools/tests/fixtures/README.md`, find the manual-smoke block that lists the `claude "/..."` commands and add, immediately after the `claude "/update-requirements"` line, this line (matching the surrounding indentation/format):

```
    claude "/design-solutions"         # -> solutions.md, >=1 problem->solution entry, status: proposed
```

Then add this sentence to the planted-material description list (the bullet list near the top of the README), as a new bullet:

```
- **Product-problem hints:** an SME-dependency line and a recurring prep-job-failure line in `raw/field-notes.txt` — exercises `/design-solutions`.
```

- [ ] **Step 7: Run the full suite to verify pass**

Run: `bash fde-tools/tests/run-all.sh`
Expected: PASS — both suites end `0 failed`; the two new packaging assertions pass; exit 0.

- [ ] **Step 8: Commit**

```bash
git add fde-tools/.claude-plugin/plugin.json fde-tools/README.md .claude-plugin/marketplace.json fde-tools/tests/fixtures/README.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): v0.2.0 packaging for design-solutions (README, marketplace, fixture smoke)"
```

---

## Manual Verification (post-implementation)

Automated tests cover structure only. Verify behavior manually against the fixture (needs the Claude runtime):

```bash
cd fde-tools/tests/fixtures/sample-engagement
claude "/design-solutions"
# Confirm solutions.md: title "# <Customer> — RunWhen Solution Design"; at least one
# ### entry built from the planted SME-dependency and prep-job hints; each entry has
# **Problem:**, **Solution (proposed):** with only the relevant primitive lines, **Source:**,
# and **Status:** proposed. Entries ordered by POC value (SME simulator first).
claude "/qna the prep-job solution should use a Scheduled Command, not a Workflow"
# Confirm /qna treats this as a correction (writes corrections.md) or a direct edit
# (logs changelog.md), then re-run /design-solutions and confirm the correction persists.
rm -rf solutions.md corrections.md changelog.md   # cleanup throwaway output
```

Confirm the read-only guarantee held: `git status` shows no changes under `tests/fixtures/sample-engagement/{slack,granola,raw}/` beyond the intentionally-committed `raw/field-notes.txt` hints.
