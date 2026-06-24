# fde-tools Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `fde-tools` Claude Code plugin in this marketplace repo — packaging the FDE engagement workflow as five slash commands with date-anchored outputs and an interactive `/qna` interrogate-and-edit loop.

**Architecture:** Prompt-only plugin (no scripts, fully offline). Five markdown command specs under `commands/` plus three underscore-prefixed shared "include" convention files referenced via `${CLAUDE_PLUGIN_ROOT}`. Guide assets (CSS + HTML template) are ported into the plugin. Automated tests are static structural-lint assertions in bash (the existing repo style); behavioral verification of the commands is manual against a fixture engagement directory, since running a slash command needs the Claude runtime.

**Tech Stack:** Markdown command/skill specs, Claude Code plugin manifest (`plugin.json` / `marketplace.json`), bash 3.2 assertion scripts, offline HTML/CSS for the guide.

## Global Constraints

- Plugin name: `fde-tools`; version `0.1.0`.
- Bash scripts must run on bash 3.2 (macOS default): no `declare -A`, no `${var,,}`, no `|&`.
- Commands reference includes/assets via `${CLAUDE_PLUGIN_ROOT}/commands/...` and `${CLAUDE_PLUGIN_ROOT}/assets/...` — never `~/.claude/commands/...`.
- Underscore-prefixed files in `commands/` are shared includes, NOT slash commands.
- `slack/`, `granola/`, `raw/` are strictly read-only — no command may write to them.
- All dates normalized to `YYYY-MM-DD`.
- Guide must work fully offline: no CDN links, no web fonts, no JavaScript.
- Date-anchoring (dated `## <YYYY-MM-DD>` sections) applies ONLY to `progress.md` and `requirements.md`; `summary.md` and the guide stay current-truth.
- `changelog.md` is append-only and written ONLY by `/qna`.
- Spec of record: `docs/superpowers/specs/2026-06-24-fde-tools-plugin-design.md`.
- Source files being ported live at `~/.claude/commands/`: `_engagement-context.md`, `build-fde-guide.md`, `summarize-engagement.md`, `update-engagement-progress.md`, and `assets/{fde-guide.css,fde-guide-page.html.tmpl}`.

---

## File Structure

```
fde-tools/
├── .claude-plugin/plugin.json          # Task 1
├── commands/
│   ├── _engagement-context.md          # Task 2 (ported)
│   ├── _date-parsing.md                # Task 3 (new)
│   ├── build-guide.md                  # Task 5 (ported)
│   ├── summarize-engagement.md         # Task 6 (ported)
│   ├── update-progress.md              # Task 7 (ported + refactor)
│   ├── update-requirements.md          # Task 8 (new)
│   ├── _qna-engine.md                  # Task 9 (new)
│   └── qna.md                          # Task 9 (new)
├── assets/
│   ├── fde-guide.css                   # Task 4 (ported)
│   └── fde-guide-page.html.tmpl        # Task 4 (ported)
├── tests/
│   ├── run-all.sh                      # Task 1
│   ├── test-structure.sh               # Task 1, grown each task
│   └── fixtures/sample-engagement/     # Task 10
└── README.md                           # Task 11
```

`tests/test-structure.sh` is the spine: each task appends assertions for the file(s) it creates, so the suite grows monotonically and a task's assertions fail before its file exists (the TDD red→green cycle for a content plugin).

---

## Task 1: Scaffold plugin manifest + test harness

**Files:**
- Create: `fde-tools/.claude-plugin/plugin.json`
- Create: `fde-tools/tests/test-structure.sh`
- Create: `fde-tools/tests/run-all.sh`

**Interfaces:**
- Produces: `test-structure.sh` defines bash helpers `assert_file(path, label)`, `assert_grep(pattern, file, label)`, `assert_no_grep(pattern, file, label)`, and a `PLUGIN_DIR` variable resolving to `fde-tools/`. All later tasks append assertions using these helpers. Exit code is non-zero if any assertion fails.

- [ ] **Step 1: Write the failing test harness**

Create `fde-tools/tests/test-structure.sh`:

```bash
#!/usr/bin/env bash
# test-structure.sh - Static structural lint for the fde-tools plugin.
# Grows one assertion block per implementation task.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CMD="$PLUGIN_DIR/commands"

PASS=0; FAIL=0
assert_file() {
    if [ -f "$1" ]; then printf "  PASS: %s\n" "$2"; PASS=$((PASS+1));
    else printf "  FAIL: %s (missing: %s)\n" "$2" "$1"; FAIL=$((FAIL+1)); fi
}
assert_grep() {
    if grep -qE "$1" "$2" 2>/dev/null; then printf "  PASS: %s\n" "$3"; PASS=$((PASS+1));
    else printf "  FAIL: %s (pattern '%s' not in %s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1)); fi
}
assert_no_grep() {
    if grep -qE "$1" "$2" 2>/dev/null; then printf "  FAIL: %s (forbidden '%s' found in %s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1));
    else printf "  PASS: %s\n" "$3"; PASS=$((PASS+1)); fi
}

echo "== Task 1: plugin manifest =="
assert_file "$PLUGIN_DIR/.claude-plugin/plugin.json" "plugin.json exists"
grep -q '"name": *"fde-tools"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null \
  && { echo "  PASS: plugin.json names fde-tools"; PASS=$((PASS+1)); } \
  || { echo "  FAIL: plugin.json does not name fde-tools"; FAIL=$((FAIL+1)); }

# --- later tasks append assertion blocks below this line ---

echo ""
echo "TOTAL: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `plugin.json exists (missing: ...)`, final line `TOTAL: 0 passed, 2 failed`, non-zero exit.

- [ ] **Step 3: Create the plugin manifest**

Create `fde-tools/.claude-plugin/plugin.json`:

```json
{
  "name": "fde-tools",
  "description": "Forward Deployed Engineer engagement toolkit: builds an offline field guide, summary, dated progress timeline, and dated requirements log from read-only engagement notes, with an interactive /qna command to interrogate and edit the generated data.",
  "version": "0.1.0",
  "author": {
    "name": "Rohit Ekbote"
  },
  "homepage": "https://github.com/Rohit-Ekbote/claude-plugins",
  "repository": "https://github.com/Rohit-Ekbote/claude-plugins",
  "license": "MIT",
  "keywords": ["fde", "engagement", "field-guide", "summary", "progress", "requirements", "offline", "generate-only"]
}
```

- [ ] **Step 4: Create the suite runner**

Create `fde-tools/tests/run-all.sh`:

```bash
#!/usr/bin/env bash
# run-all.sh - Run every fde-tools test suite.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$SCRIPT_DIR"/test-*.sh; do
    echo "### $t"
    bash "$t" || rc=1
done
exit "$rc"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash fde-tools/tests/run-all.sh`
Expected: PASS — `TOTAL: 2 passed, 0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add fde-tools/.claude-plugin/plugin.json fde-tools/tests/test-structure.sh fde-tools/tests/run-all.sh
git commit -m "feat(fde-tools): scaffold plugin manifest and structure test harness"
```

---

## Task 2: Port the `_engagement-context.md` shared include

**Files:**
- Create: `fde-tools/commands/_engagement-context.md`
- Modify: `fde-tools/tests/test-structure.sh` (append assertions)

**Interfaces:**
- Produces: the shared engagement convention referenced by every command via `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md`. Defines: read-only loading of `slack/`/`granola/`/`raw/`; the `corrections.md` overlay; the latest-wins-by-topic resolver; customer-identity inference; the contradiction-handling flow and the `> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.` callout format.

- [ ] **Step 1: Append failing assertions**

In `fde-tools/tests/test-structure.sh`, immediately above the `# --- later tasks append` line, insert:

```bash
echo "== Task 2: _engagement-context include =="
assert_file "$CMD/_engagement-context.md" "_engagement-context.md exists"
assert_no_grep "~/.claude/commands" "$CMD/_engagement-context.md" "no home-path refs in context include"
assert_grep "latest-wins-by-topic" "$CMD/_engagement-context.md" "context include defines resolver"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `_engagement-context.md exists (missing ...)`.

- [ ] **Step 3: Port the file**

Copy the source, then apply the path rewrite:

```bash
cp ~/.claude/commands/_engagement-context.md fde-tools/commands/_engagement-context.md
```

Then edit `fde-tools/commands/_engagement-context.md`:
- Replace the header note line (line 3) that reads
  `> This file is a shared include referenced by `build-fde-guide`, `summarize-engagement`, and `update-engagement-progress`. It is **not** a slash command and is not run directly.`
  with:
  `> This file is a shared include referenced by the fde-tools commands (`build-guide`, `summarize-engagement`, `update-progress`, `update-requirements`, `qna`). It is **not** a slash command and is not run directly.`
- Search the file for any `~/.claude/commands` occurrences and replace each with `${CLAUDE_PLUGIN_ROOT}/commands`. (The source currently has none in the body, but verify after copy.)

Leave all other content — corrections overlay, resolver rules, correction/resolution block formats, customer identity, contradiction handling — verbatim.

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 2 assertions pass; `TOTAL: 5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/_engagement-context.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): port _engagement-context shared include"
```

---

## Task 3: Write the `_date-parsing.md` shared include (new)

**Files:**
- Create: `fde-tools/commands/_date-parsing.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Produces: the shared timestamp convention referenced by `update-progress` and `update-requirements` via `${CLAUDE_PLUGIN_ROOT}/commands/_date-parsing.md`. Defines the ordered date-source priority, normalization, attribution, and ambiguity rules.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line:

```bash
echo "== Task 3: _date-parsing include =="
assert_file "$CMD/_date-parsing.md" "_date-parsing.md exists"
assert_grep "date sources" "$CMD/_date-parsing.md" "date-parsing lists source priority"
assert_grep "date unknown" "$CMD/_date-parsing.md" "date-parsing defines ambiguity fallback"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `_date-parsing.md exists (missing ...)`.

- [ ] **Step 3: Write the file**

Create `fde-tools/commands/_date-parsing.md`:

```markdown
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
```

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 3 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/_date-parsing.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): add _date-parsing shared include"
```

---

## Task 4: Port the guide assets

**Files:**
- Create: `fde-tools/assets/fde-guide.css`
- Create: `fde-tools/assets/fde-guide-page.html.tmpl`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Produces: the offline stylesheet and the five-token page template (`{{PAGE_TITLE}}`, `{{SIDEBAR_NAV}}`, `{{KICKER}}`, `{{PAGE_BODY}}`, `{{PAGER}}`) consumed by `build-guide` at `${CLAUDE_PLUGIN_ROOT}/assets/`.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line:

```bash
echo "== Task 4: guide assets =="
assert_file "$PLUGIN_DIR/assets/fde-guide.css" "fde-guide.css exists"
assert_file "$PLUGIN_DIR/assets/fde-guide-page.html.tmpl" "page template exists"
assert_grep "\\{\\{PAGE_BODY\\}\\}" "$PLUGIN_DIR/assets/fde-guide-page.html.tmpl" "template has PAGE_BODY token"
assert_grep "\\{\\{PAGER\\}\\}" "$PLUGIN_DIR/assets/fde-guide-page.html.tmpl" "template has PAGER token"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `fde-guide.css exists (missing ...)`.

- [ ] **Step 3: Copy the assets verbatim**

```bash
mkdir -p fde-tools/assets
cp ~/.claude/commands/assets/fde-guide.css fde-tools/assets/fde-guide.css
cp ~/.claude/commands/assets/fde-guide-page.html.tmpl fde-tools/assets/fde-guide-page.html.tmpl
```

Do not modify the asset contents — the template already references `assets/style.css` relatively, which is correct (the guide copies the CSS to `guide/assets/style.css` at build time).

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 4 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/assets/ fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): port offline guide assets (css + page template)"
```

---

## Task 5: Port the `/build-guide` command

**Files:**
- Create: `fde-tools/commands/build-guide.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: `_engagement-context.md` (Task 2), `assets/fde-guide.css` + `assets/fde-guide-page.html.tmpl` (Task 4).
- Produces: the `/build-guide` slash command. Writes the multi-page offline guide into `guide/`.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line:

```bash
echo "== Task 5: build-guide command =="
assert_file "$CMD/build-guide.md" "build-guide.md exists"
assert_no_grep "~/.claude/commands" "$CMD/build-guide.md" "no home-path refs in build-guide"
assert_grep "CLAUDE_PLUGIN_ROOT" "$CMD/build-guide.md" "build-guide uses plugin-root refs"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `build-guide.md exists (missing ...)`.

- [ ] **Step 3: Port and rewrite paths**

```bash
cp ~/.claude/commands/build-fde-guide.md fde-tools/commands/build-guide.md
```

Then in `fde-tools/commands/build-guide.md` apply these exact replacements (every occurrence):

| Find | Replace |
|------|---------|
| `~/.claude/commands/_engagement-context.md` | `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` |
| `~/.claude/commands/assets/fde-guide.css` | `${CLAUDE_PLUGIN_ROOT}/assets/fde-guide.css` |
| `~/.claude/commands/assets/fde-guide-page.html.tmpl` | `${CLAUDE_PLUGIN_ROOT}/assets/fde-guide-page.html.tmpl` |
| `running <code>/build-fde-guide</code>` | `running <code>/build-guide</code>` |

Leave all step logic, the CSS component vocabulary, and the checklist otherwise verbatim. The output directory remains `guide/` and the source dirs remain read-only.

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 5 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/build-guide.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): port build-guide command"
```

---

## Task 6: Port the `/summarize-engagement` command

**Files:**
- Create: `fde-tools/commands/summarize-engagement.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: `_engagement-context.md` (Task 2).
- Produces: the `/summarize-engagement` slash command. Writes `summary.md` with its fixed seven H2 sections. Current-truth, no date sectioning.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line:

```bash
echo "== Task 6: summarize-engagement command =="
assert_file "$CMD/summarize-engagement.md" "summarize-engagement.md exists"
assert_no_grep "~/.claude/commands" "$CMD/summarize-engagement.md" "no home-path refs in summarize"
assert_grep "How we solve each requirement" "$CMD/summarize-engagement.md" "summary keeps fixed sections"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `summarize-engagement.md exists (missing ...)`.

- [ ] **Step 3: Port and rewrite paths**

```bash
cp ~/.claude/commands/summarize-engagement.md fde-tools/commands/summarize-engagement.md
```

Then replace every occurrence of `~/.claude/commands/_engagement-context.md` with `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md`. Leave the seven-section structure and all other content verbatim.

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 6 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/summarize-engagement.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): port summarize-engagement command"
```

---

## Task 7: Port `/update-progress` and refactor date logic to the shared include

**Files:**
- Create: `fde-tools/commands/update-progress.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: `_engagement-context.md` (Task 2), `_date-parsing.md` (Task 3).
- Produces: the `/update-progress` slash command. Writes `progress.md` as a newest-first dated timeline with `Developments / Decisions / New blockers / Resolved` per `## <YYYY-MM-DD>` section, same-date idempotent replacement.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line:

```bash
echo "== Task 7: update-progress command =="
assert_file "$CMD/update-progress.md" "update-progress.md exists"
assert_no_grep "~/.claude/commands" "$CMD/update-progress.md" "no home-path refs in update-progress"
assert_grep "_date-parsing.md" "$CMD/update-progress.md" "update-progress references date-parsing include"
assert_grep "New blockers" "$CMD/update-progress.md" "update-progress keeps section structure"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `update-progress.md exists (missing ...)`.

- [ ] **Step 3: Port and rewrite**

```bash
cp ~/.claude/commands/update-engagement-progress.md fde-tools/commands/update-progress.md
```

Then in `fde-tools/commands/update-progress.md`:

1. Replace every `~/.claude/commands/_engagement-context.md` with `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md`.
2. Replace the entirety of `## Step 2 — Determine the timeline dates` (its heading and body paragraphs, through just before `## Step 3 — Read all inputs`) with this refactored version that delegates date rules to the shared include:

```markdown
## Step 2 — Determine the timeline dates

Follow `${CLAUDE_PLUGIN_ROOT}/commands/_date-parsing.md` for all date extraction, normalization, and attribution. In summary, the progress log is a **date-wise timeline, newest date first**, where each item is attributed to the date it actually occurred:

1. **Event dates found inside the engagement material** — per the date-source priority in `_date-parsing.md` (body dates, Slack timestamps, Granola headers, filename dates). Each distinct date with material activity gets its own `## <YYYY-MM-DD>` section. Backfilling historical dates is intended.
2. **The run date** — used only as the fallback per `_date-parsing.md`, for anything observed or concluded during this run that is not tied to a specific source date.

Items whose date cannot be determined go under a trailing `## (date unknown)` section per the include. Never pile everything under the run date.
```

Leave Steps 3–7 (idempotency rules, section structure, superseded-section markers, outputs) verbatim aside from the path rewrite in step 1 above.

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 7 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/update-progress.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): port update-progress and delegate date logic to shared include"
```

---

## Task 8: Write the `/update-requirements` command (new)

**Files:**
- Create: `fde-tools/commands/update-requirements.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: `_engagement-context.md` (Task 2), `_date-parsing.md` (Task 3).
- Produces: the `/update-requirements` slash command. Writes `requirements.md` as a newest-first dated timeline of asks, each `## <YYYY-MM-DD>` section listing asks raised that day with `ask / source forum + who / status`. Same idempotency as progress.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line:

```bash
echo "== Task 8: update-requirements command =="
assert_file "$CMD/update-requirements.md" "update-requirements.md exists"
assert_no_grep "~/.claude/commands" "$CMD/update-requirements.md" "no home-path refs in update-requirements"
assert_grep "_date-parsing.md" "$CMD/update-requirements.md" "requirements references date-parsing include"
assert_grep "requirements.md" "$CMD/update-requirements.md" "requirements writes requirements.md"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `update-requirements.md exists (missing ...)`.

- [ ] **Step 3: Write the command**

Create `fde-tools/commands/update-requirements.md`:

```markdown
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
- **Status** — only if explicitly stated in the source (e.g. `requested`, `in-progress`, `delivered`, `declined`). If no status is stated, write `requested`.

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

## Step 7 — Outputs

- **Always write:** `requirements.md` (created or updated as above).
- **Write only on a confirmed resolution:** append a resolution block to `corrections.md` (creating it if absent) when the user confirms an answer to a contradiction during this run. Do not write to the legacy `side-notes.md`.
- **Never modify** any file under `slack/`, `granola/`, or `raw/`.
```

- [ ] **Step 4: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 8 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add fde-tools/commands/update-requirements.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): add update-requirements command (dated timeline of asks)"
```

---

## Task 9: Write the `_qna-engine.md` include and `/qna` command (new)

**Files:**
- Create: `fde-tools/commands/_qna-engine.md`
- Create: `fde-tools/commands/qna.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: `_engagement-context.md` (Task 2). References regeneration via the other four commands by name.
- Produces: the `/qna` slash command and its `_qna-engine.md` spec. Three auto-detected intents (question/clarify, correction, direct edit/delete). Writes `corrections.md` (intent 2 and contradiction resolutions) and the new append-only `changelog.md` (intent 3 mutations). Never modifies `slack/`/`granola/`/`raw/`.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line:

```bash
echo "== Task 9: qna command + engine =="
assert_file "$CMD/_qna-engine.md" "_qna-engine.md exists"
assert_file "$CMD/qna.md" "qna.md exists"
assert_no_grep "~/.claude/commands" "$CMD/qna.md" "no home-path refs in qna"
assert_grep "changelog.md" "$CMD/_qna-engine.md" "qna-engine defines changelog audit trail"
assert_grep "append-only" "$CMD/_qna-engine.md" "qna-engine marks changelog append-only"
assert_grep "read-only" "$CMD/_qna-engine.md" "qna-engine keeps raw inputs read-only"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `_qna-engine.md exists (missing ...)`.

- [ ] **Step 3: Write the `_qna-engine.md` include**

Create `fde-tools/commands/_qna-engine.md`:

```markdown
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
- Append a Correction block to the TOP of `corrections.md` (immediately under the title line if present; create the file with title `# Corrections` if absent), using the format from `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md`:

  ```
  ### Correction: <short-topic>
  Date: YYYY-MM-DD

  **Correction:** <what is actually true>
  **Corrects:** <the mistaken claim / where it appeared>
  ```

- This is append-only to `corrections.md` and does NOT require a `changelog.md` entry.
- Then offer regeneration (see "Offer to regenerate" below).

### Intent 3 — Direct edit / delete (writes the target + changelog.md)

The user requests a specific surgical change to existing generated data, or to amend/delete a `corrections.md` entry ("delete the duplicate ingress line in progress.md for 2026-04-01", "remove the storage-backend correction I added by mistake").

- Make the precise edit in place to the target file (`summary.md` / `progress.md` / `requirements.md` / a `guide/` page), OR amend/delete the named `corrections.md` entry.
- **Append a `changelog.md` audit entry** (see below) for every such mutation.
- **Warn about regeneration overwrite:** if the target is a generated doc, tell the user that a later `/update-progress`, `/update-requirements`, `/summarize-engagement`, or `/build-guide` run may overwrite this in-place edit, and suggest recording it as a correction (Intent 2) instead if it should persist. Amend/delete of a `corrections.md` entry is durable and carries no such warning.

## changelog.md (append-only audit trail)

`changelog.md` is written ONLY by `/qna`, ONLY for Intent 3 mutations, and is **append-only** — never rewrite or delete earlier entries. Append each new block to the TOP of the file (newest first), immediately under the title line if present. Create the file with title `# Changelog` if absent.

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
```

- [ ] **Step 4: Write the `qna.md` command**

Create `fde-tools/commands/qna.md`:

```markdown
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
- `summary.md`, `progress.md`, `requirements.md`, and the `guide/` pages — the generated docs under discussion.
- `changelog.md` if present — prior audit history.
- All readable files under `slack/`, `granola/`, `raw/` recursively — read-only source material for provenance.

## Step 3 — Run the loop

For each user turn, follow `_qna-engine.md`: detect the intent (question / correction / direct edit-delete), act on it, write `corrections.md` or `changelog.md` as specified, and offer regeneration after corrections. Continue until the user ends the session.

If `$ARGUMENTS` contains an opening question or instruction, treat it as the first turn.

## Guarantees

- Never modify any file under `slack/`, `granola/`, or `raw/`.
- `changelog.md` is append-only and written only for direct edit/delete mutations.
```

- [ ] **Step 5: Run to verify pass**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: PASS — Task 9 assertions pass.

- [ ] **Step 6: Commit**

```bash
git add fde-tools/commands/_qna-engine.md fde-tools/commands/qna.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): add qna command and qna-engine with changelog audit trail"
```

---

## Task 10: Fixture engagement dir + read-only guarantee test

**Files:**
- Create: `fde-tools/tests/fixtures/sample-engagement/granola/2026-03-12-kickoff.md`
- Create: `fde-tools/tests/fixtures/sample-engagement/slack/eng-channel.txt`
- Create: `fde-tools/tests/fixtures/sample-engagement/raw/field-notes.txt`
- Create: `fde-tools/tests/fixtures/README.md`
- Create: `fde-tools/tests/test-fixtures.sh`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: nothing from prior tasks at runtime — this is a static fixture plus a guard test.
- Produces: a small engagement directory for manual smoke-testing the commands, with planted dates, a material contradiction, and feature-asks; plus an automated test asserting the fixture is well-formed and complete enough to exercise each command.

- [ ] **Step 1: Append failing assertions to the structure suite**

Insert above the `# --- later tasks append` line in `test-structure.sh`:

```bash
echo "== Task 10: fixtures =="
FX="$PLUGIN_DIR/tests/fixtures/sample-engagement"
assert_file "$FX/granola/2026-03-12-kickoff.md" "kickoff fixture exists"
assert_file "$FX/slack/eng-channel.txt" "slack fixture exists"
assert_file "$FX/raw/field-notes.txt" "raw fixture exists"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `kickoff fixture exists (missing ...)`.

- [ ] **Step 3: Create the fixture files**

`fde-tools/tests/fixtures/sample-engagement/granola/2026-03-12-kickoff.md`:

```markdown
# Acme Robotics — Kickoff
Date: 2026-03-12

Attendees: Priya (Acme infra lead), Dan (FDE).

- Acme runs a single on-prem k3s cluster. Storage is NFS-only today.
- Goal: deploy the RunWhen platform to give SREs runbook automation.
- Priya asked: can we get SSO via their Okta? (new ask)
- Dan to confirm storage requirements for Postgres next week.
```

`fde-tools/tests/fixtures/sample-engagement/slack/eng-channel.txt`:

```
[2026-03-19 09:14] priya: Postgres needs block storage — NFS won't work for our write patterns.
[2026-03-19 09:20] dan: noted, that conflicts with the NFS-only constraint from kickoff. will dig in.
[2026-03-25 16:02] priya: new ask — can the guide be available fully offline for our air-gapped site?
```

`fde-tools/tests/fixtures/sample-engagement/raw/field-notes.txt`:

```
2026-04-01
- Confirmed block storage available via local-path provisioner; NFS-only applied to the archive tier only.
- Installed platform; runner came up. Setup looks ready.
```

`fde-tools/tests/fixtures/README.md`:

```markdown
# sample-engagement fixture

A minimal FDE engagement directory for manually smoke-testing the fde-tools commands.

Planted material:
- **Dates** across Granola (header + filename `2026-03-12`), Slack timestamps (`2026-03-19`, `2026-03-25`), and a raw note (`2026-04-01`) — exercises every date source in `_date-parsing.md`.
- **A material contradiction:** kickoff says "NFS-only" storage; Slack says "Postgres needs block storage"; the raw note (2026-04-01, latest) resolves it (block storage available; NFS-only is archive-tier only). Exercises contradiction handling and latest-wins resolution.
- **Two feature-asks:** Okta SSO (2026-03-12), offline guide (2026-03-25) — exercises `update-requirements`.

## Manual smoke (needs the Claude runtime — not run in CI)

From inside `tests/fixtures/sample-engagement/`:

    claude "/summarize-engagement"     # -> summary.md, 7 sections, current-truth
    claude "/update-progress"          # -> progress.md, dated sections newest-first
    claude "/update-requirements"      # -> requirements.md, asks under 2026-03-12 and 2026-03-25
    claude "/build-guide"              # -> guide/ offline HTML
    claude "/qna where did the storage decision come from?"   # cites provenance

Generated files (summary.md, progress.md, requirements.md, guide/, corrections.md, changelog.md)
are throwaway — do not commit them. They are covered by the repo .gitignore patterns or should be
removed after smoke-testing.
```

- [ ] **Step 4: Write the fixture guard test**

Create `fde-tools/tests/test-fixtures.sh`:

```bash
#!/usr/bin/env bash
# test-fixtures.sh - Assert the sample engagement fixture is complete and read-only-safe to use.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FX="$SCRIPT_DIR/fixtures/sample-engagement"
PASS=0; FAIL=0
ok() { printf "  PASS: %s\n" "$1"; PASS=$((PASS+1)); }
no() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== fixture completeness =="
[ -d "$FX/granola" ] && [ -d "$FX/slack" ] && [ -d "$FX/raw" ] && ok "all three source dirs present" || no "missing a source dir"

# Date sources: filename date, body date, slack timestamp, raw date.
grep -q "2026-03-12" "$FX/granola/2026-03-12-kickoff.md" && ok "granola body date present" || no "granola body date missing"
grep -q "2026-03-19" "$FX/slack/eng-channel.txt" && ok "slack timestamp present" || no "slack timestamp missing"
grep -q "2026-04-01" "$FX/raw/field-notes.txt" && ok "raw date present" || no "raw date missing"

# Planted contradiction: NFS-only vs block storage.
grep -qi "NFS-only" "$FX/granola/2026-03-12-kickoff.md" && grep -qi "block storage" "$FX/slack/eng-channel.txt" \
  && ok "material contradiction planted" || no "contradiction not planted"

# Feature asks for update-requirements.
grep -qi "ask" "$FX/granola/2026-03-12-kickoff.md" && grep -qi "ask" "$FX/slack/eng-channel.txt" \
  && ok "feature asks present in two forums" || no "feature asks missing"

echo ""
echo "TOTAL: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 5: Run the full suite to verify pass**

Run: `bash fde-tools/tests/run-all.sh`
Expected: PASS — both `test-structure.sh` and `test-fixtures.sh` end `TOTAL: N passed, 0 failed`; runner exit 0.

- [ ] **Step 6: Commit**

```bash
git add fde-tools/tests/fixtures/ fde-tools/tests/test-fixtures.sh fde-tools/tests/test-structure.sh
git commit -m "test(fde-tools): add sample engagement fixture and fixture guard test"
```

---

## Task 11: Marketplace registration, README, and globals-retirement doc

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Create: `fde-tools/README.md`
- Create: `fde-tools/RETIRE-GLOBALS.md`
- Modify: `fde-tools/tests/test-structure.sh`

**Interfaces:**
- Consumes: the completed `fde-tools/` plugin from Tasks 1–10.
- Produces: the plugin registered in the marketplace so it is installable; user-facing README; and a documented manual procedure to retire the old global commands.

- [ ] **Step 1: Append failing assertions**

Insert above the `# --- later tasks append` line in `test-structure.sh`:

```bash
echo "== Task 11: registration + docs =="
assert_file "$PLUGIN_DIR/README.md" "plugin README exists"
assert_file "$PLUGIN_DIR/RETIRE-GLOBALS.md" "retirement doc exists"
ROOT="$(dirname "$PLUGIN_DIR")"
assert_grep "\"name\": *\"fde-tools\"" "$ROOT/.claude-plugin/marketplace.json" "fde-tools registered in marketplace"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash fde-tools/tests/test-structure.sh`
Expected: FAIL — `plugin README exists (missing ...)` and the marketplace assertion fails.

- [ ] **Step 3: Register in the marketplace**

In `.claude-plugin/marketplace.json`, add this object to the `plugins` array (after the `rwl-install-wizard` entry; ensure the preceding entry has a trailing comma and the JSON stays valid):

```json
    {
      "name": "fde-tools",
      "description": "Forward Deployed Engineer engagement toolkit: offline field guide, summary, dated progress timeline, dated requirements log, and an interactive /qna command to interrogate and edit the generated data",
      "version": "0.1.0",
      "source": "./fde-tools",
      "author": {
        "name": "Rohit Ekbote"
      },
      "tags": ["fde", "engagement", "field-guide", "summary", "progress", "requirements", "offline"],
      "homepage": "https://github.com/Rohit-Ekbote/claude-plugins"
    }
```

Validate JSON: `python3 -c "import json,sys; json.load(open('.claude-plugin/marketplace.json'))" && echo OK`
Expected: `OK`.

- [ ] **Step 4: Write the plugin README**

Create `fde-tools/README.md`:

```markdown
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
```

- [ ] **Step 5: Write the globals-retirement doc**

Create `fde-tools/RETIRE-GLOBALS.md`:

```markdown
# Retiring the global engagement commands

`fde-tools` supersedes the global engagement slash commands in `~/.claude/commands/`. Those files live **outside this repository**, so this plugin does not (and cannot) delete them automatically. After installing `fde-tools` and verifying the commands work, remove the old globals manually:

```bash
rm ~/.claude/commands/build-fde-guide.md
rm ~/.claude/commands/summarize-engagement.md
rm ~/.claude/commands/update-engagement-progress.md
rm ~/.claude/commands/correct-engagement-data.md
rm ~/.claude/commands/_engagement-context.md
rm -rf ~/.claude/commands/assets   # only if no other global command uses it
```

Mapping from old to new:

| Old global command | New fde-tools command |
|--------------------|-----------------------|
| `/build-fde-guide` | `/build-guide` |
| `/summarize-engagement` | `/summarize-engagement` |
| `/update-engagement-progress` | `/update-progress` |
| `/correct-engagement-data` | folded into `/qna` (correction intent) |
| _(none)_ | `/update-requirements` (new) |

Verify `fde-tools` is installed and its commands appear before deleting the globals, so you are never left without the workflow.
```

- [ ] **Step 6: Run the full suite to verify pass**

Run: `bash fde-tools/tests/run-all.sh`
Expected: PASS — all assertions pass, exit 0.

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin/marketplace.json fde-tools/README.md fde-tools/RETIRE-GLOBALS.md fde-tools/tests/test-structure.sh
git commit -m "feat(fde-tools): register plugin in marketplace, add README and globals-retirement doc"
```

---

## Manual Verification (post-implementation)

Automated tests cover structure only. Verify behavior manually against the fixture (needs the Claude runtime):

```bash
cd fde-tools/tests/fixtures/sample-engagement
claude "/summarize-engagement"     # summary.md: 7 H2 sections, current-truth, no date sections
claude "/update-progress"          # progress.md: newest-first dated sections; the 2026-03-19 storage contradiction surfaces or resolves
claude "/update-requirements"      # requirements.md: Okta SSO under 2026-03-12, offline guide under 2026-03-25
claude "/build-guide"              # guide/: offline HTML, no CDN/JS; assets/style.css present
claude "/qna where did the storage decision come from?"   # cites granola/slack/raw provenance and the 2026-04-01 resolution
# Then exercise a direct edit and confirm changelog.md gets an append-only block.
# Finally confirm slack/ granola/ raw/ are byte-identical (git status clean for those dirs).
rm -rf summary.md progress.md requirements.md guide corrections.md changelog.md   # cleanup throwaway output
```

Confirm the read-only guarantee held: `git status` shows no changes under `tests/fixtures/sample-engagement/{slack,granola,raw}/`.
