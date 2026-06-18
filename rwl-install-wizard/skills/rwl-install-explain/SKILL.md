---
name: rwl-install-explain
description: Explain one RunWhen-platform install decision (axis or knob) in depth, without running the interview
triggers:
  - /rwl-install-explain
  - explain install option
  - what does this install knob do
---

# Explain an install decision

Read-only, conversational. No cluster access, no secrets.

## Instructions

1. Read `${CLAUDE_PLUGIN_ROOT}/data/knob-catalog.yaml`.

2. Match the user's argument (`/rwl-install-explain <topic>`) to an axis `id`,
   axis `title`, or an option `id`/`label`. If no argument is given, list all
   axes (id + title) and ask which to explain.

3. For the matched axis, explain in plain language:
   - **What it controls** (from the axis `title`/`question`).
   - **Each option** and the concrete `values` it emits (summarize the `emits:`
     fragment — show the keys, not as something to copy-paste blindly).
   - **Why it matters / what breaks without it** — pull the linked
     `known_issues` entries from `${CLAUDE_PLUGIN_ROOT}/data/known-issues/<id>.md`
     and summarize the symptom→cause→fix.
   - **Related guide sections** by name.

4. If the user asks about a raw chart knob not modeled as an axis, say so plainly
   and point them to the chart's `values.yaml` and `INSTALL-FRICTIONS.md`; do not
   fabricate an answer.

5. Never ask for or display any secret value.
