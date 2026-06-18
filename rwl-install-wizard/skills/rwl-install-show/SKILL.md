---
name: rwl-install-show
description: Show the saved rwl-install profile and the generated install kit for this project
triggers:
  - /rwl-install-show
  - show install profile
  - what has the install wizard generated
---

# Show rwl-install profile + kit

Read-only. Never modifies anything, never runs cluster commands.

## Instructions

1. Look for `.claude/rwl-install-profile.yaml` in `$PWD`.

   **If missing**, print:
   ```
   No install profile found in this directory.
   Run /rwl-install to start the interview.
   ```
   Then stop.

2. **If present**, print the profile's `chartCompat`, `generatedAt`, and a
   human-readable summary of each answered axis (one line per axis: axis id →
   chosen option(s) and key parameters).

3. List the contents of `rwl-install-out/` if it exists, grouped as:
   - Overlays: every `values-*.yaml` present, with a one-line note of which axis
     produced each (from the overlay file header).
   - Guides: `USER-GUIDE.md`, `DEBUG-GUIDE.md` (with their section counts).

   If `rwl-install-out/` is missing, note that the kit has not been generated yet
   and suggest running `/rwl-install`.

4. Print the exact install command line the kit implies, reading the ordered
   `-f` overlay list from `USER-GUIDE.md`'s "Install day" section. Do NOT invent
   secret values; show secret creation only as the `<PLACEHOLDER>` templates
   already in the guide.

5. Never print the contents of any secret. This skill only reads non-sensitive
   profile + generated files (which are themselves secret-free by construction).
