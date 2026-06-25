# `/design-solutions` Command — Design

**Date:** 2026-06-25
**Status:** Approved design, pending implementation plan
**Author:** Rohit Ekbote (with Claude Code)
**Plugin:** `fde-tools` (extends the plugin shipped in PR #26)

## Summary

Add a new command, `/design-solutions`, to the `fde-tools` plugin. Unlike the
existing commands — which transcribe what is explicitly stated — this command
**actively designs**: it mines the engagement inputs for customer *problems*
(operational pain, SME dependencies, recurring failure modes), elaborates each
into a full problem statement, and proposes a concrete RunWhen solution mapped
onto real RunWhen product primitives (AI Assistants, Tasks/CodeBundles, SLX/SLI/SLO,
Workflows, Scheduled Commands, Rules, Knowledge). The output, `solutions.md`, is a
priority-ordered backlog of problem→solution entries that feeds the POC's
scope-definition and tool-building phases.

This was driven by feedback from a real engagement (`/Users/rohitekbote/wd/gr-fde-guide`):
the existing `/update-requirements` was capturing *deployment/integration asks*
(chart knobs, air-gap, kubeconfig, storage, SSO), while the genuine *product*
requirements — the SME-dependency-reduction value driver, incident triage at
scale, ControlledJob CRD troubleshooting, pre-market prep-job RCA — were buried as
a few lines and never elaborated into a solution design.

## Goals

- Capture **customer requirements toward RunWhen as a product**: problem
  statements and how RunWhen addresses them.
- **Actively design and propose** solutions from even thin hints — the command
  does the first-draft thinking; the FDE refines.
- Express solutions in **real RunWhen terms** (a docs-grounded primitive vocabulary).
- Produce a backlog that **feeds the POC scope-definition and tool-building phases**.
- Stay consistent with the plugin: prompt-only, offline, reuses the engagement
  conventions, refinable through `/qna` and the `corrections.md` overlay.

## Non-Goals

- **Do not change `/update-requirements`.** It remains the deployment/integration
  asks tracker, unchanged.
- Not a dated timeline (unlike `progress.md` / `requirements.md`). No date sections;
  `_date-parsing.md` is not used.
- Not a tutorial on RunWhen — `_runwhen-primitives.md` is a concise vocabulary, not docs.
- No automated execution of the designs; this produces a plan, not RunWhen config.

## Architecture

Approach A (chosen): a new command file plus a new shared "primitives" include,
factored exactly like the rest of the plugin (prompt-only, `${CLAUDE_PLUGIN_ROOT}`
references). The active-design behavior is contained entirely in the one command.

### File layout

```
fde-tools/
├── commands/
│   ├── design-solutions.md         # /design-solutions          (new)
│   ├── _runwhen-primitives.md      # shared include             (new)
│   ├── _engagement-context.md      # reused (unchanged)
│   ├── _qna-engine.md              # updated: solutions.md added to /qna scope + regen table
│   ├── qna.md                      # updated: loads solutions.md
│   └── build-guide.md, summarize-engagement.md,
│       update-progress.md, update-requirements.md   # unchanged
├── README.md                       # updated: new command row + "solutions vs requirements" note
└── tests/
    ├── test-structure.sh           # updated: new assertions
    ├── test-fixtures.sh            # updated: planted product-hint assertion
    └── fixtures/...                # enriched with a product-problem hint
```

- `/design-solutions` writes **`solutions.md`** in the engagement working directory.
- It reads the read-only inputs (`slack/`, `granola/`, `raw/`), the `corrections.md`
  overlay, and references `_runwhen-primitives.md`.
- `${CLAUDE_PLUGIN_ROOT}/commands/...` references throughout; no `~/.claude/commands` refs.

## Components

### `_runwhen-primitives.md` (new shared include)

A concise, **correctable** reference of the RunWhen building blocks the command
designs against — grounded in the RunWhen docs
(`https://docs.runwhen.com/docs/use/common-user-journeys/` and the `learn/`
concept pages for assistants, rules, and workflows). One short entry per primitive
(what it is, when to reach for it). It is **not** a tutorial.

Primitives (docs-grounded definitions):

- **Workspace** — tenant/scope boundary; contains SLXs, assistants, knowledge.
- **SLX (Service Level Experience)** — bundles a service/resource's health
  indicators and objectives; triggers investigation when thresholds breach.
- **SLI (Service Level Indicator)** — a health-check task defining healthy operation.
- **SLO (Service Level Objective)** — alerting threshold determining when an Issue is raised.
- **Task / CodeBundle (Runbook)** — executable diagnostic/remediation procedure;
  the investigative backbone and the main artifact built during tool-building.
- **CodeCollection** — git repo packaging reusable tasks.
- **AI Assistant (Digital Assistant)** — intelligent agent in Workspace Chat/Slack;
  tuned by **access level** (read-only / read-write) and **confidence thresholds**
  (filter confidence = which tasks considered; run confidence = which executed),
  plus task-tag filters; draws context from Rules, Commands, and Knowledge. Create
  different personas for different risk profiles (interactive-thorough vs.
  autonomous-conservative).
- **Workflow** — event-driven: an alert/webhook/SLO-trip launches an assistant
  investigation and routes the result (Slack/PagerDuty). The incident-integration path.
- **Scheduled Command** — cron-triggered recurring investigation/briefing delivered
  to Slack/email.
- **Rule** — standing interpretive guidance (de-noise / re-prioritize / reframe)
  shaping how an assistant *interprets* findings; does **not** change which tasks
  run; configured in Workspace Studio, scoped workspace/assistant/user.
- **Knowledge (KB)** — narrative context (ownership/architecture) attached at
  resource/SLX level; how SME knowledge is encoded. No central registry.
- **RunSession / Issue** — a recorded investigation; an Issue is a detected problem
  from a failed SLX health check.
- **Runner / RunWhen Local** — discovers resources and executes tasks.
- **MCP Server** — the interface Claude uses to craft tasks, scheduled commands,
  rules, and KBs.

**Accuracy note in the include itself:** it records that this content encodes a
point-in-time understanding of RunWhen and should be reviewed for correctness;
because it ships with the plugin, corrections to it are plugin edits (not
engagement-data edits via `/qna`).

### `/design-solutions` (new command)

Behavior:

1. Load `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` in full (read-only
   input loading; `corrections.md` overlay; latest-wins-by-topic resolver; customer
   identity; contradiction handling with the `> ⚠️ Contradiction: ...; unresolved.`
   callout) and `${CLAUDE_PLUGIN_ROOT}/commands/_runwhen-primitives.md` (vocabulary).
2. **Mine the inputs for problems**, not just stated asks — operational pain, SME
   dependencies, recurring failure modes, friction points. A problem may come from a
   thin hint.
3. For each problem, **actively design a RunWhen solution** mapped onto the primitives.
4. Write `solutions.md`, **regenerated each run**, entries **ordered by POC value**
   (core value drivers first, e.g. the SME simulator).

Output file `solutions.md`:

```markdown
# <Customer> — RunWhen Solution Design

<one-line note: proposed solution designs derived from engagement inputs; refine via /qna>

### <Problem title>

**Problem:** <elaborated problem statement — the operational pain, who feels it,
why it matters for the POC. Synthesized/expanded from the hints, not just quoted.>

**Solution (proposed):**
- **Assistants:** <persona(s) + risk profile, if any>
- **Tasks/CodeBundles:** <diagnostics/remediation to build>
- **SLX / SLIs / SLOs:** <monitoring units, if any>
- **Workflows:** <event triggers, if any>
- **Scheduled Commands:** <cron investigations, if any>
- **Rules:** <interpretation guidance, if any>
- **Knowledge:** <KB to encode, if any>
- **How it fits:** <one or two lines tying the pieces into the workflow that solves the problem>

**Source:** <which inputs hinted it — file + who>
**Status:** proposed | scoping | building | built
```

Rules:

- Only the relevant primitive lines appear per entry; omit primitives a solution
  does not use.
- Every solution carries the **"(proposed)"** label — it is a first-draft
  recommendation the FDE validates.
- **Status** defaults to `proposed`; advance it only when an input or a correction
  explicitly says so (mirrors the `update-requirements` default-then-override rule).
- **Idempotency:** entries keyed by problem title/slug — re-running updates an entry
  in place rather than duplicating. Customer name inferred per `_engagement-context.md`
  (fall back to `[Customer]`).
- The title line is `# <Customer> — RunWhen Solution Design`.
- Read-only inputs (`slack/`/`granola/`/`raw/`) are never modified. Contradiction
  resolutions, when confirmed, append to `corrections.md` per the convention.

### `/qna` integration (updates to `_qna-engine.md` and `qna.md`)

- `_qna-engine.md`: add `solutions.md` to the "Scope of data" `/qna` reads, answers
  about (with provenance), corrects, and directly edits. Add a `solutions` row to the
  "Offer to regenerate" table mapping to
  `${CLAUDE_PLUGIN_ROOT}/commands/design-solutions.md`, and include it in `all`
  (order: summarize → progress → requirements → solutions → guide).
- `qna.md`: add `solutions.md` to the Step 2 list of generated docs it loads.
- Mutability rules are unchanged: a direct edit to `solutions.md` is logged to the
  append-only `changelog.md` (Intent 3) and warned as overwritable by regeneration;
  a correction (Intent 2) routes to `corrections.md` and survives regeneration.

## Data Flow

- `/design-solutions` reads `slack`/`granola`/`raw` + `corrections.md`, designs, and
  (re)writes `solutions.md`. Latest-wins-by-topic from the overlay governs
  `solutions.md` like the other generated docs, so FDE corrections to a problem
  statement, a chosen primitive, or a status persist across regenerations.
- `/qna` reads `solutions.md` for Q&A and routes corrections/edits as above.
- Contradiction handling is inherited unchanged from `_engagement-context.md`.

## Packaging

- Bump `fde-tools` version `0.1.0` → `0.2.0` (new feature) in
  `fde-tools/.claude-plugin/plugin.json`.
- `README.md`: add the `/design-solutions` → `solutions.md` row and a short
  "solutions vs requirements" note distinguishing the two audiences (product
  solution design vs. deployment/integration asks).
- Marketplace `description`/tags refreshed if warranted. `RETIRE-GLOBALS.md`
  unaffected (no global equivalent existed).

## Testing

Same style as the plugin: static structural-lint assertions (automated) plus a
fixture-based manual smoke (behavioral, needs the Claude runtime).

- **`test-structure.sh` assertions:**
  - `commands/design-solutions.md` and `commands/_runwhen-primitives.md` exist.
  - `design-solutions.md` has no `~/.claude/commands` refs and references both
    `_engagement-context.md` and `_runwhen-primitives.md`.
  - `design-solutions.md` writes `solutions.md`.
  - `_runwhen-primitives.md` names the core primitives (greps for `AI Assistant`,
    `Workflow`, `Rule`, `Scheduled Command`, `Knowledge`).
  - `_qna-engine.md` includes `solutions.md` in its scope; `qna.md` loads it.
- **Fixture enrichment:** add a planted product-problem hint to `sample-engagement`
  (an SME-dependency line and a recurring prep-job-failure line). A `test-fixtures.sh`
  assertion confirms the planted product hint is present.
- **Manual smoke** (documented in the fixture README): run `/design-solutions` in the
  fixture dir; confirm `solutions.md` produces at least one problem→solution entry
  with the structured primitive breakdown and a `proposed` status; then exercise a
  `/qna` correction to a proposed solution and confirm it persists across a regen.

## Open Questions

None outstanding — all design decisions resolved during brainstorming. The RunWhen
primitive vocabulary is grounded in the published docs; the `_runwhen-primitives.md`
include carries a self-note to review its accuracy over time.
