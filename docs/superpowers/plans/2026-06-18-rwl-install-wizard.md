# rwl-install-wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `rwl-install-wizard`, a generate-only Claude Code plugin that interviews a RunWhen-platform operator and emits layered `values` overlays + a tailored user guide + a tailored debug guide, driven by a structured knob catalog.

**Architecture:** Approach C (hybrid). A `data/knob-catalog.yaml` is the source of truth for axes → questions → exact `values` fragments → guide/known-issue ids. Three skills (`/rwl-install`, `/rwl-install-show`, `/rwl-install-explain`) read the catalog and assemble the kit; Claude renders prose, but always from exact catalog fragments. Two bash-3.2 guard scripts (`secret-guard.sh`, `catalog-lint.sh`) enforce the secret-free invariant and catalog integrity deterministically and are the TDD'd core.

**Tech Stack:** Bash 3.2 (scripts/tests, matching the marketplace convention — no `declare -A`, `${var,,}`, `|&`, `local` outside functions, no `yq`/`python`/`jq` dependency), YAML (catalog + generated overlays), Markdown (skills + guide data). Plugin packaged in the existing `rohit-claude-plugins` marketplace.

**Reference spec:** `docs/superpowers/specs/2026-06-17-rwl-install-wizard-design.md`

**Chart compatibility target (V1):** `chartCompat: ">=0.2.30 <0.3"` (current chart is `0.2.34`).

**Authoring constraint (required for lint to work without a YAML parser):** in `knob-catalog.yaml`, the `guide_sections:` and `known_issues:` fields MUST be written as single-line inline arrays, e.g. `guide_sections: [networking-non-rfc1918]`. The `emits:` block is normal multi-line YAML.

**Source material for content tasks (paths in the `runwhen/rwlight-helm` repo — not this repo):**
- `charts/runwhen-platform/values-example-*.yaml` — 7 overlays that seed axis fragments
- `charts/runwhen-platform/docs/install/INSTALL-CHECKLIST.md` — Phase 0→10 + conditional blocks (user-guide structure)
- `charts/runwhen-platform/INSTALL-FRICTIONS.md` — ~36 dated known issues (debug-guide content)
- `charts/runwhen-platform/docs/install/{registry-routing,security-hardening,airgap,customer-access}.md`

> **Note on content tasks (12–20):** these distill existing prose from the source files above into the catalog/guide/known-issue formats proven in Tasks 8–11. The plan pins the exact output files and exact source sections for each; the English prose is authored at execution time from those pinned sources. Acceptance for every content task is identical and mechanical: `./tests/test-catalog-lint.sh` and `./tests/test-secret-guard.sh` pass, and the new axis's golden fixture (added in the same task) regenerates with the expected overlay keys + guide/issue ids.

---

## File Structure

Created under `rwl-install-wizard/` in this repo (`rohit-claude-plugins`):

```
rwl-install-wizard/
├── .claude-plugin/plugin.json          # name, version, chartCompat
├── README.md
├── .gitignore                          # ignores nothing in-plugin; documents generated paths
├── lib/
│   ├── secret-guard.sh                 # scan a dir/file for secret-shaped content (exit 2 if found)
│   └── catalog-lint.sh                 # validate knob-catalog.yaml + data/ integrity
├── skills/
│   ├── rwl-install/SKILL.md
│   ├── rwl-install-show/SKILL.md
│   └── rwl-install-explain/SKILL.md
├── data/
│   ├── knob-catalog.yaml
│   ├── guide-sections/<id>.md
│   └── known-issues/<id>.md
└── tests/
    ├── test-secret-guard.sh
    ├── test-catalog-lint.sh
    └── fixtures/
        ├── profiles/<name>.yaml            # golden input profiles
        ├── secret-dirty/                   # files containing secrets (guard must flag)
        └── secret-clean/                   # files with existingSecret refs (guard must pass)
```

Modified:
- `.claude-plugin/marketplace.json` — register the new plugin.

---

## Task 1: Plugin scaffold + marketplace registration

**Files:**
- Create: `rwl-install-wizard/.claude-plugin/plugin.json`
- Create: `rwl-install-wizard/README.md`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Create `plugin.json`**

```json
{
  "name": "rwl-install-wizard",
  "description": "Guided installer for the RunWhen platform Helm chart: interviews the operator and generates layered values overlays plus tailored user and debug guides. Generate-only, self-contained, never handles secrets.",
  "version": "0.1.0",
  "author": {
    "name": "Rohit Ekbote"
  },
  "homepage": "https://github.com/Rohit-Ekbote/claude-plugins",
  "repository": "https://github.com/Rohit-Ekbote/claude-plugins",
  "license": "MIT",
  "keywords": ["helm", "runwhen", "install", "wizard", "values", "kubernetes", "generate-only"],
  "metadata": {
    "chartCompat": ">=0.2.30 <0.3"
  }
}
```

- [ ] **Step 2: Create a short `README.md`**

```markdown
# rwl-install-wizard

Guided installer for the RunWhen platform Helm chart. Answer an interview about
your cluster's constraints; the wizard generates layered `values` overlays and a
tailored user guide + debug guide for your exact install shape.

- **Generate-only** — never touches a cluster, never runs `helm`/`kubectl`.
- **Self-contained** — needs no chart source repo at runtime.
- **Secret-free** — never asks for or stores any credential. Secrets are wired
  via `existingSecret` references; the user guide hands you `kubectl create
  secret` templates to fill at your own terminal.

## Skills

- `/rwl-install` — run or resume the interview, then generate the kit.
- `/rwl-install-show` — show the saved profile and what's been generated.
- `/rwl-install-explain <topic>` — explain one install decision in depth.

## Output (in your working dir, gitignored)

- `.claude/rwl-install-profile.yaml` — your saved answers (re-runnable).
- `rwl-install-out/values-*.yaml` — layered overlays.
- `rwl-install-out/USER-GUIDE.md`, `rwl-install-out/DEBUG-GUIDE.md`.

Targets chart versions `>=0.2.30 <0.3`. See
`docs/superpowers/specs/2026-06-17-rwl-install-wizard-design.md` for design.
```

- [ ] **Step 3: Register in `marketplace.json`**

Add this object to the `plugins` array in `.claude-plugin/marketplace.json` (after the `rwl-env` entry):

```json
{
  "name": "rwl-install-wizard",
  "description": "Guided installer for the RunWhen platform Helm chart: interview-driven generation of values overlays and tailored install/debug guides",
  "version": "0.1.0",
  "source": "./rwl-install-wizard",
  "author": {
    "name": "Rohit Ekbote"
  },
  "tags": ["helm", "runwhen", "install", "wizard", "values", "kubernetes"],
  "homepage": "https://github.com/Rohit-Ekbote/claude-plugins"
}
```

- [ ] **Step 4: Validate JSON parses**

Run: `python3 -c "import json,sys; json.load(open('.claude-plugin/marketplace.json')); json.load(open('rwl-install-wizard/.claude-plugin/plugin.json')); print('OK')"`
Expected: `OK`

(Note: `python3` is used here only as a JSON syntax checker in the test harness, not as a plugin runtime dependency.)

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/.claude-plugin/plugin.json rwl-install-wizard/README.md .claude-plugin/marketplace.json
git commit -m "feat(rwl-install-wizard): scaffold plugin + register in marketplace"
```

---

## Task 2: secret-guard test harness (failing)

**Files:**
- Create: `rwl-install-wizard/tests/test-secret-guard.sh`
- Create: `rwl-install-wizard/tests/fixtures/secret-clean/values-posture.yaml`
- Create: `rwl-install-wizard/tests/fixtures/secret-dirty/values-bad.yaml`

- [ ] **Step 1: Create the clean fixture (must PASS the guard)**

`rwl-install-wizard/tests/fixtures/secret-clean/values-posture.yaml`:

```yaml
# Clean: secrets referenced by name only, never inline.
global:
  imagePullSecrets: []
ccCatalog:
  auth:
    existingSecret: cc-catalog-svc-auth
seaweedfs:
  s3:
    existingConfigSecret: rw-seaweedfs-identities
papi:
  oidc:
    clientSecretRef:
      name: papi-oidc
      key: clientSecret
domain: rw.example.com
```

- [ ] **Step 2: Create the dirty fixture (must be FLAGGED)**

`rwl-install-wizard/tests/fixtures/secret-dirty/values-bad.yaml`:

```yaml
postgresql:
  auth:
    password: hunter2supersecret
vault:
  token: hvs.CAESIJabcdef0123456789tokenmaterial
aws:
  accessKey: AKIAIOSFODNN7EXAMPLE
tls:
  key: |
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSk
    -----END PRIVATE KEY-----
```

- [ ] **Step 3: Write the failing test**

`rwl-install-wizard/tests/test-secret-guard.sh`:

```bash
#!/usr/bin/env bash
# test-secret-guard.sh - Unit tests for lib/secret-guard.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
GUARD="$PLUGIN_DIR/lib/secret-guard.sh"

PASS=0; FAIL=0
assert_rc() {
    if [ "$1" = "$2" ]; then
        printf "  PASS: %s\n" "$3"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, expected=%s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1))
    fi
}

echo "== secret-guard: clean dir passes =="
bash "$GUARD" "$SCRIPT_DIR/fixtures/secret-clean" >/dev/null 2>&1
assert_rc "$?" "0" "clean fixture dir exits 0"

echo "== secret-guard: dirty dir is flagged =="
bash "$GUARD" "$SCRIPT_DIR/fixtures/secret-dirty" >/dev/null 2>&1
assert_rc "$?" "2" "dirty fixture dir exits 2"

echo "== secret-guard: dirty output names the offending file =="
out="$(bash "$GUARD" "$SCRIPT_DIR/fixtures/secret-dirty" 2>&1)"
case "$out" in
  *values-bad.yaml*) printf "  PASS: %s\n" "names offending file"; PASS=$((PASS+1)) ;;
  *) printf "  FAIL: %s\n" "names offending file"; FAIL=$((FAIL+1)) ;;
esac

echo ""
echo "secret-guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bash rwl-install-wizard/tests/test-secret-guard.sh`
Expected: FAIL — `secret-guard.sh` does not exist yet, all asserts fail / script errors.

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/tests/test-secret-guard.sh rwl-install-wizard/tests/fixtures/secret-clean rwl-install-wizard/tests/fixtures/secret-dirty
git commit -m "test(rwl-install-wizard): failing tests + fixtures for secret-guard"
```

---

## Task 3: secret-guard.sh implementation

**Files:**
- Create: `rwl-install-wizard/lib/secret-guard.sh`

- [ ] **Step 1: Implement the guard**

`rwl-install-wizard/lib/secret-guard.sh`:

```bash
#!/usr/bin/env bash
# secret-guard.sh - Scan a file or directory for secret-shaped content.
#
# Usage: secret-guard.sh <path> [<path>...]
# Exit:  0 = clean, 2 = secret-shaped content found (locations printed to stderr)
#
# The wizard is secret-free: generated overlays reference secrets by name
# (existingSecret / *Ref), never inline. This guard fails the build if a literal
# secret slips into the profile or generated kit. Bash 3.2 compatible.
set -uo pipefail

# Keys that must never carry an inline literal value. A line is OK if its value
# is empty, a placeholder, or an existingSecret-style reference handled below.
SECRET_KEY_RE='(pass(word|wd)?|token|api[_-]?key|secret[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret|credential)'

# Obvious secret material regardless of key.
MATERIAL_RE='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|hvs\.[0-9A-Za-z]{15,})'

# Values that are allowed even on a secret-ish key (references / placeholders / empty).
is_allowed_value() {
    # $1 = the raw value (everything after the first colon)
    v="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/#.*$//')"
    [ -z "$v" ] && return 0
    case "$v" in
        '""'|"''"|'|'|'>'|'{}'|'[]') return 0 ;;
        '<'*'>'|*CHANGEME*|*REPLACE*|*PLACEHOLDER*|*YOUR_*) return 0 ;;
        \"*existingSecret*|*existingSecret*|*Ref*|*secretKeyRef*|*valueFrom*) return 0 ;;
    esac
    return 1
}

found=0
report() { printf 'secret-guard: %s:%s: %s\n' "$1" "$2" "$3" >&2; found=1; }

scan_file() {
    f="$1"
    lineno=0
    # Read raw lines (preserve content); IFS= and -r keep it verbatim.
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno+1))
        # 1) Obvious secret material anywhere.
        if printf '%s' "$line" | grep -Eiq "$MATERIAL_RE"; then
            report "$f" "$lineno" "secret material detected"
            continue
        fi
        # 2) secret-ish key with an inline literal value.
        key="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*\([A-Za-z0-9_-]*\)[[:space:]]*:.*$/\1/p')"
        [ -z "$key" ] && continue
        if printf '%s' "$key" | grep -Eiq "^$SECRET_KEY_RE$"; then
            val="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*[A-Za-z0-9_-]*[[:space:]]*:\(.*\)$/\1/p')"
            if ! is_allowed_value "$val"; then
                report "$f" "$lineno" "inline value for secret-ish key '$key'"
            fi
        fi
    done < "$f"
}

[ "$#" -ge 1 ] || { echo "usage: secret-guard.sh <path> [<path>...]" >&2; exit 64; }

for target in "$@"; do
    [ -e "$target" ] || continue
    if [ -d "$target" ]; then
        # -print0 not portable to all `read`; use a newline loop (paths w/o newlines).
        find "$target" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.md' \) | while IFS= read -r f; do
            scan_file "$f"
        done
        # `found` set in subshell above is lost; re-scan via grep summary for exit code.
        if find "$target" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.md' \) -print0 \
            | xargs -0 grep -EilZ "$MATERIAL_RE" 2>/dev/null | grep -q .; then
            found=1
        fi
    else
        scan_file "$target"
    fi
done

[ "$found" -eq 0 ] || exit 2
exit 0
```

> Implementation note: the `find | while` loop runs in a subshell, so `found`
> set inside it does not propagate. Step 2 fixes this with a robust
> single-pass design — do not skip it.

- [ ] **Step 2: Make the directory scan exit-code-correct (single process, no subshell)**

Replace the `for target` loop with a subshell-free version that collects files first:

```bash
[ "$#" -ge 1 ] || { echo "usage: secret-guard.sh <path> [<path>...]" >&2; exit 64; }

# Collect target files into the positional list without a pipe-to-while subshell.
files=""
for target in "$@"; do
    [ -e "$target" ] || continue
    if [ -d "$target" ]; then
        while IFS= read -r f; do
            files="$files
$f"
        done <<EOF
$(find "$target" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.md' \))
EOF
    else
        files="$files
$target"
    fi
done

OLDIFS="$IFS"; IFS='
'
for f in $files; do
    [ -n "$f" ] || continue
    scan_file "$f"
done
IFS="$OLDIFS"

[ "$found" -eq 0 ] || exit 2
exit 0
```

(Delete the earlier `for target ... done` block from Step 1 so only this version remains.)

- [ ] **Step 3: Make executable**

Run: `chmod +x rwl-install-wizard/lib/secret-guard.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash rwl-install-wizard/tests/test-secret-guard.sh`
Expected: `secret-guard: 3 passed, 0 failed`

- [ ] **Step 5: Lint for bash 3.2 / shellcheck**

Run: `shellcheck -s bash rwl-install-wizard/lib/secret-guard.sh || true`
Expected: no errors that block (warnings acceptable). Confirm no `declare -A`, `${var,,}`, `|&`, or `local` outside functions.

- [ ] **Step 6: Commit**

```bash
git add rwl-install-wizard/lib/secret-guard.sh
git commit -m "feat(rwl-install-wizard): secret-guard scanner (secret-free invariant)"
```

---

## Task 4: catalog-lint test harness (failing)

**Files:**
- Create: `rwl-install-wizard/tests/test-catalog-lint.sh`
- Create: `rwl-install-wizard/tests/fixtures/catalog-bad-missing-ref.yaml`
- Create: `rwl-install-wizard/tests/fixtures/catalog-bad-inline-secret.yaml`

- [ ] **Step 1: Bad fixture — references a known-issue id with no file**

`rwl-install-wizard/tests/fixtures/catalog-bad-missing-ref.yaml`:

```yaml
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: yes
        label: "Yes"
        overlay: values-cluster.yaml
        emits:
          demo: { enabled: true }
        guide_sections: [demo-section]
        known_issues: [this-id-has-no-file]
```

- [ ] **Step 2: Bad fixture — inline secret in `emits:`**

`rwl-install-wizard/tests/fixtures/catalog-bad-inline-secret.yaml`:

```yaml
axes:
  - id: demo
    title: Demo
    question: "Demo?"
    options:
      - id: yes
        label: "Yes"
        overlay: values-cluster.yaml
        emits:
          postgresql:
            auth:
              password: literalvalue
        guide_sections: []
        known_issues: []
```

- [ ] **Step 3: Write the failing test**

`rwl-install-wizard/tests/test-catalog-lint.sh`:

```bash
#!/usr/bin/env bash
# test-catalog-lint.sh - Unit tests for lib/catalog-lint.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
LINT="$PLUGIN_DIR/lib/catalog-lint.sh"
DATA="$PLUGIN_DIR/data"

PASS=0; FAIL=0
assert_rc() {
    if [ "$1" = "$2" ]; then printf "  PASS: %s\n" "$3"; PASS=$((PASS+1));
    else printf "  FAIL: %s (rc=%s, expected=%s)\n" "$3" "$1" "$2"; FAIL=$((FAIL+1)); fi
}

echo "== catalog-lint: real catalog is clean =="
bash "$LINT" "$DATA/knob-catalog.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "0" "shipped catalog passes lint"

echo "== catalog-lint: missing known-issue ref fails =="
bash "$LINT" "$SCRIPT_DIR/fixtures/catalog-bad-missing-ref.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "1" "missing id reference is rejected"

echo "== catalog-lint: inline secret in emits fails =="
bash "$LINT" "$SCRIPT_DIR/fixtures/catalog-bad-inline-secret.yaml" "$DATA" >/dev/null 2>&1
assert_rc "$?" "1" "inline secret in emits is rejected"

echo ""
echo "catalog-lint: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bash rwl-install-wizard/tests/test-catalog-lint.sh`
Expected: FAIL — `catalog-lint.sh` and the real catalog don't exist yet.

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/tests/test-catalog-lint.sh rwl-install-wizard/tests/fixtures/catalog-bad-missing-ref.yaml rwl-install-wizard/tests/fixtures/catalog-bad-inline-secret.yaml
git commit -m "test(rwl-install-wizard): failing tests + fixtures for catalog-lint"
```

---

## Task 5: catalog-lint.sh implementation

**Files:**
- Create: `rwl-install-wizard/lib/catalog-lint.sh`

> Depends on the inline-array authoring constraint (top of plan) so `grep` can
> extract `guide_sections`/`known_issues` ids without a YAML parser.

- [ ] **Step 1: Implement the linter**

`rwl-install-wizard/lib/catalog-lint.sh`:

```bash
#!/usr/bin/env bash
# catalog-lint.sh - Validate knob-catalog.yaml + data/ integrity.
#
# Usage: catalog-lint.sh <knob-catalog.yaml> <data-dir>
# Exit:  0 = clean, 1 = problems found (printed to stderr)
#
# Checks (heuristic, line-oriented — bash 3.2, no YAML parser):
#   1. Every id in `guide_sections: [...]` has data/guide-sections/<id>.md
#   2. Every id in `known_issues: [...]`  has data/known-issues/<id>.md
#   3. No orphan files in those dirs (every file is referenced at least once)
#   4. No inline literal secret under an `emits:` block (reuses secret-guard rules)
#   5. Every `- id:` option block has a `label:` within the catalog
set -uo pipefail

CATALOG="${1:-}"; DATA="${2:-}"
[ -f "$CATALOG" ] || { echo "catalog-lint: catalog not found: $CATALOG" >&2; exit 1; }
[ -d "$DATA" ]    || { echo "catalog-lint: data dir not found: $DATA" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/secret-guard.sh"

problems=0
fail() { printf 'catalog-lint: %s\n' "$1" >&2; problems=1; }

# Extract ids from inline arrays for a given field name. Prints one id per line.
extract_ids() {
    field="$1"
    grep -Eo "${field}:[[:space:]]*\[[^]]*\]" "$CATALOG" \
        | sed -E "s/${field}:[[:space:]]*\[//; s/\]//" \
        | tr ',' '\n' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | grep -v '^$'
}

# 1 & 2: referenced ids must have files.
check_refs() {
    field="$1"; subdir="$2"
    extract_ids "$field" | sort -u | while IFS= read -r id; do
        [ -n "$id" ] || continue
        [ -f "$DATA/$subdir/$id.md" ] || echo "MISSING $subdir/$id.md"
    done
}
miss="$(check_refs guide_sections guide-sections; check_refs known_issues known-issues)"
if [ -n "$miss" ]; then
    printf '%s\n' "$miss" | while IFS= read -r m; do fail "referenced file not found: $m"; done
    problems=1
fi

# 3: orphan files.
check_orphans() {
    field="$1"; subdir="$2"
    [ -d "$DATA/$subdir" ] || return 0
    refs="$(extract_ids "$field" | sort -u)"
    for path in "$DATA/$subdir"/*.md; do
        [ -e "$path" ] || continue
        base="$(basename "$path" .md)"
        case "
$refs
" in
            *"
$base
"*) : ;;
            *) fail "orphan (unreferenced) file: $subdir/$base.md" ;;
        esac
    done
}
check_orphans guide_sections guide-sections
check_orphans known_issues known-issues

# 4: no inline secrets in emits — reuse secret-guard against the catalog itself.
if ! bash "$GUARD" "$CATALOG" >/dev/null 2>&1; then
    fail "secret-guard flagged inline secret-shaped content in catalog"
fi

# 5: every option block (- id:) is followed by a label: before the next - id:.
#    Awk state machine: after seeing a list item that starts an option, require label.
awk '
  /^[[:space:]]*-[[:space:]]+id:/ { if (in_opt && !seen_label) { print "NOLABEL " optline } in_opt=1; seen_label=0; optline=$0; next }
  /^[[:space:]]*label:/ { if (in_opt) seen_label=1 }
  END { if (in_opt && !seen_label) print "NOLABEL " optline }
' "$CATALOG" | while IFS= read -r nl; do
    fail "option without label: ${nl#NOLABEL }"
done
# Propagate awk-detected failures (subshell): re-run to set problems.
if awk '
  /^[[:space:]]*-[[:space:]]+id:/ { if (in_opt && !seen_label) c++; in_opt=1; seen_label=0; next }
  /^[[:space:]]*label:/ { if (in_opt) seen_label=1 }
  END { if (in_opt && !seen_label) c++; exit (c>0)?1:0 }
' "$CATALOG"; then : ; else problems=1; fi

exit "$problems"
```

> Note: the `- id:` / `label:` heuristic treats every list item with an `id:` as
> an option. That is acceptable because the only `- id:` list items in the
> catalog are axes and options, and axes also carry sibling fields; to avoid
> false positives on axes, author each axis with its `title:` line and each
> option with its `label:` line. Axis-level `- id:` blocks have a `title:` not a
> `label:` — see Step 2.

- [ ] **Step 2: Adjust the label check to ignore axis-level blocks**

Axis blocks use `title:`; option blocks use `label:`. Update both awk programs to
only require a label when the block has neither a `title:` nor a `question:`
(i.e. it is an option, not an axis). Replace both awk invocations' middle rule
set with:

```awk
  /^[[:space:]]*-[[:space:]]+id:/ { if (in_opt && !ok) FLAG; in_opt=1; ok=0; next }
  /^[[:space:]]*(label|title|question):/ { if (in_opt) ok=1 }
```

where `FLAG` is `{ print "NOLABEL " optline }` (first awk) and `c++` (second awk),
and keep `optline=$0` capture on the `- id:` rule. This makes the rule "every
`- id:` block must declare at least one of label/title/question", which holds for
both axes and options and removes false positives.

- [ ] **Step 3: Make executable**

Run: `chmod +x rwl-install-wizard/lib/catalog-lint.sh`

- [ ] **Step 4: Run tests — clean-catalog case will still fail (no real catalog yet)**

Run: `bash rwl-install-wizard/tests/test-catalog-lint.sh`
Expected: the two "bad fixture" asserts PASS (exit 1 correctly); the "real catalog is clean" assert FAILS because `data/knob-catalog.yaml` doesn't exist yet. This is expected — the real catalog arrives in Task 8.

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/lib/catalog-lint.sh
git commit -m "feat(rwl-install-wizard): catalog-lint validator"
```

---

## Task 6: `/rwl-install-show` skill

**Files:**
- Create: `rwl-install-wizard/skills/rwl-install-show/SKILL.md`

(Built before the wizard itself because it is the simplest read-only skill and
defines the profile/output contract the other skills reuse.)

- [ ] **Step 1: Write the skill**

`rwl-install-wizard/skills/rwl-install-show/SKILL.md`:

````markdown
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
````

- [ ] **Step 2: Validate frontmatter parses**

Run: `python3 -c "import yaml,sys; d=open('rwl-install-wizard/skills/rwl-install-show/SKILL.md').read().split('---')[1]; yaml.safe_load(d); print('OK')"`
Expected: `OK` (python3 used only as a YAML syntax checker in the harness).

- [ ] **Step 3: Commit**

```bash
git add rwl-install-wizard/skills/rwl-install-show/SKILL.md
git commit -m "feat(rwl-install-wizard): /rwl-install-show read-only skill"
```

---

## Task 7: `/rwl-install-explain` skill

**Files:**
- Create: `rwl-install-wizard/skills/rwl-install-explain/SKILL.md`

- [ ] **Step 1: Write the skill**

`rwl-install-wizard/skills/rwl-install-explain/SKILL.md`:

````markdown
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
````

- [ ] **Step 2: Validate frontmatter parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('rwl-install-wizard/skills/rwl-install-explain/SKILL.md').read().split('---')[1]); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add rwl-install-wizard/skills/rwl-install-explain/SKILL.md
git commit -m "feat(rwl-install-wizard): /rwl-install-explain skill"
```

---

## Task 8: First catalog axis (`networking`) + data files — makes catalog-lint green

**Files:**
- Create: `rwl-install-wizard/data/knob-catalog.yaml`
- Create: `rwl-install-wizard/data/guide-sections/networking-non-rfc1918.md`
- Create: `rwl-install-wizard/data/known-issues/mimir-memberlist-no-private-ip.md`

- [ ] **Step 1: Create the catalog with the catalog header + the `networking` axis**

`rwl-install-wizard/data/knob-catalog.yaml`:

```yaml
# knob-catalog.yaml — SOURCE OF TRUTH for rwl-install-wizard.
#
# MAINTENANCE CONTRACT: a new chart knob or a newly logged friction is an edit
# to THIS file (and a data/ file), never a change to the skills.
#
# chartCompat: ">=0.2.30 <0.3"
#
# AUTHORING RULES (enforced by lib/catalog-lint.sh):
#   - guide_sections / known_issues MUST be single-line inline arrays:
#       guide_sections: [some-id, other-id]
#   - emits: MUST NOT contain an inline secret literal. Wire secrets by name
#     (existingSecret / *Ref) only.
#   - Every option block (- id:) carries a label:. Axes carry title: + question:.
chartCompat: ">=0.2.30 <0.3"
axes:
  - id: networking
    title: Pod network CIDR
    question: "Is your cluster's pod network in standard private (RFC1918) ranges?"
    options:
      - id: rfc1918
        label: "Yes — 10.x / 172.16–31.x / 192.168.x (default)"
        emits: {}
        guide_sections: []
        known_issues: []
      - id: non-rfc1918
        label: "No — non-RFC1918 space (e.g. carrier/DoD 21.121.x)"
        overlay: values-cluster.yaml
        emits:
          metricstore:
            config:
              memberlist:
                bind_addr: ["127.0.0.1"]
                advertise_addr: "127.0.0.1"
        guide_sections: [networking-non-rfc1918]
        known_issues: [mimir-memberlist-no-private-ip]
```

- [ ] **Step 2: Create the guide section**

`rwl-install-wizard/data/guide-sections/networking-non-rfc1918.md`:

```markdown
### Networking — non-RFC1918 pod CIDR

Your pods run on a non-RFC1918 CIDR. Mimir's memberlist autodetects a "private"
IP and fails to start otherwise. The generated `values-cluster.yaml` pins
`metricstore.config.memberlist.bind_addr`/`advertise_addr` to `127.0.0.1`
(correct for the single-replica monolithic Mimir this chart ships).

After install, if Mimir still misbehaves, also raise its log level off `warn` so
you get diagnostic output.
```

- [ ] **Step 3: Create the known-issue entry**

`rwl-install-wizard/data/known-issues/mimir-memberlist-no-private-ip.md`:

```markdown
## Mimir crashloops: `no private IP address found`

**Symptom:** `metricstore`/mimir pod crashloops; logs (once `log_level` is above
`warn`) show `no private IP address found` and `memberlist-kv invalid service
state: Stopping`.

**Cause:** the pod CIDR is non-RFC1918 (e.g. 21.121.x). Mimir's memberlist
private-IP autodetection only accepts RFC1918 ranges.

**Fix:** set `metricstore.config.memberlist.bind_addr: ["127.0.0.1"]` and
`advertise_addr: "127.0.0.1"`. Safe for single-replica monolithic Mimir. The
wizard's `values-cluster.yaml` already contains this when you answered
"non-RFC1918". Also bump Mimir `log_level` off `warn` or you get zero logs.

_Source: INSTALL-FRICTIONS.md §23 / 2026-06-15 entry._
```

- [ ] **Step 4: Run catalog-lint test — now fully green**

Run: `bash rwl-install-wizard/tests/test-catalog-lint.sh`
Expected: `catalog-lint: 3 passed, 0 failed`

- [ ] **Step 5: Run secret-guard over the catalog + data**

Run: `bash rwl-install-wizard/lib/secret-guard.sh rwl-install-wizard/data`
Expected: exit 0 (no output).

- [ ] **Step 6: Commit**

```bash
git add rwl-install-wizard/data
git commit -m "feat(rwl-install-wizard): knob-catalog + networking axis end-to-end"
```

---

## Task 9: `/rwl-install` wizard skill (interview + GENERATE)

**Files:**
- Create: `rwl-install-wizard/skills/rwl-install/SKILL.md`

- [ ] **Step 1: Write the skill**

`rwl-install-wizard/skills/rwl-install/SKILL.md`:

````markdown
---
name: rwl-install
description: Interview the operator about their cluster and generate a tailored RunWhen-platform install kit (layered values overlays + user guide + debug guide). Generate-only; never touches a cluster; never asks for or stores secrets.
triggers:
  - /rwl-install
  - install runwhen platform
  - generate runwhen values
  - runwhen install wizard
---

# RunWhen platform install wizard

Generate-only. **Never** run `helm`, `kubectl`, or any cluster command. **Never**
ask for, echo, or store a secret (password, token, key, PAT, kubeconfig, cert
material). Secrets are wired by name (`existingSecret`/`*Ref`) only.

## Inputs
- Catalog: `${CLAUDE_PLUGIN_ROOT}/data/knob-catalog.yaml`
- Guide sections: `${CLAUDE_PLUGIN_ROOT}/data/guide-sections/`
- Known issues: `${CLAUDE_PLUGIN_ROOT}/data/known-issues/`
- Guard: `${CLAUDE_PLUGIN_ROOT}/lib/secret-guard.sh`

## State + output (in `$PWD`)
- Profile: `.claude/rwl-install-profile.yaml` (the ONLY state; secret-free)
- Kit: `rwl-install-out/{values-*.yaml, USER-GUIDE.md, DEBUG-GUIDE.md}`

## Flow

1. **Chart-version gate.** State the targeted range (`chartCompat` from the
   catalog). Ask the operator which chart version they have. If out of range,
   warn and continue, and stamp generated files "unverified for chart <X>".

2. **Load or start profile.**
   - If `.claude/rwl-install-profile.yaml` exists: summarize saved answers and
     ask whether to (a) review all, (b) change a specific axis, or (c)
     regenerate as-is. Preload answers accordingly.
   - Else: start a fresh interview.

3. **Interview** — walk axes from the catalog **one question at a time** using
   the AskUserQuestion tool. For each axis:
   - Present the `question` and its `options` (label each from the catalog).
   - Skip an axis whose `dependsOn` precondition is unmet, or auto-resolve it
     when an earlier answer moots it (note the auto-resolution to the operator).
   - If a chosen option triggers a `conflictsWith` pair already selected,
     surface the conflict and ask the operator to resolve before continuing.
   - **Only collect non-sensitive shape facts** (domain, StorageClass,
     ingressClass, UID/GID, registry hostname/path, endpoint URLs, CA-bundle
     source reference). If a value would be a secret, do NOT collect it — instead
     record that a named secret is required and surface it in the guide.

4. **Write the profile** to `.claude/rwl-install-profile.yaml` (schemaVersion: 1,
   chartCompat, generatedAt = today, answers map). Save even a partial profile
   if the operator stops early.

5. **GENERATE** (always fully rewrite `rwl-install-out/`):
   1. For each answered option, take its `emits:` fragment and target `overlay:`.
      Deep-merge fragments per overlay file. Write only overlays that received
      content. Prepend each overlay with a header: chartCompat, generatedAt,
      and the axis answers that produced it.
   2. Collect the de-duplicated union of `guide_sections` ids → assemble
      `USER-GUIDE.md` in INSTALL-CHECKLIST Phase 0→10 order, with command blocks
      that name the generated overlays in `-f` flags and substitute the
      operator's domain/namespace. Secret creation appears only as
      `kubectl create secret ... <PLACEHOLDER>` templates.
   3. Collect the de-duplicated union of `known_issues` ids → assemble
      `DEBUG-GUIDE.md` from the matching `data/known-issues/<id>.md` files.
   4. Both guides end with a short "verify it's running / when you're stuck"
      pointer (checklist Phases 6/8); note that live-cluster debugging is out of
      scope for this wizard.

6. **Secret-guard gate.** Run
   `bash ${CLAUDE_PLUGIN_ROOT}/lib/secret-guard.sh .claude/rwl-install-profile.yaml rwl-install-out`.
   If it exits non-zero, DELETE the offending generated content, tell the
   operator exactly which file/line tripped it, and stop — do not present a kit
   that contains secret-shaped content.

7. **Summary.** Print which overlays + guides were written and the first command
   from the user guide. Suggest `/rwl-install-show` to review.

## Hard rules
- Generate-only. No cluster calls. No `helm`/`kubectl` execution.
- Secret-free. No secret is ever requested, echoed, or written.
- Output is a pure function of (profile + catalog): always regenerate wholesale.
````

- [ ] **Step 2: Validate frontmatter parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('rwl-install-wizard/skills/rwl-install/SKILL.md').read().split('---')[1]); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add rwl-install-wizard/skills/rwl-install/SKILL.md
git commit -m "feat(rwl-install-wizard): /rwl-install interview + generate skill"
```

---

## Task 10: Golden fixture for the `networking` vertical slice + end-to-end test doc

**Files:**
- Create: `rwl-install-wizard/tests/fixtures/profiles/networking-only.yaml`
- Create: `rwl-install-wizard/tests/fixtures/expected/networking-only/values-cluster.yaml`
- Create: `rwl-install-wizard/tests/README.md`

- [ ] **Step 1: Golden input profile**

`rwl-install-wizard/tests/fixtures/profiles/networking-only.yaml`:

```yaml
schemaVersion: 1
chartCompat: ">=0.2.30 <0.3"
generatedAt: "2026-06-18"
answers:
  networking: { cidr: non-rfc1918 }
```

- [ ] **Step 2: Expected overlay (structural golden)**

`rwl-install-wizard/tests/fixtures/expected/networking-only/values-cluster.yaml`:

```yaml
metricstore:
  config:
    memberlist:
      bind_addr: ["127.0.0.1"]
      advertise_addr: "127.0.0.1"
```

- [ ] **Step 3: Document the golden-equivalence procedure**

`rwl-install-wizard/tests/README.md`:

```markdown
# rwl-install-wizard tests

## Automated (run directly, bash 3.2)

    bash tests/test-secret-guard.sh
    bash tests/test-catalog-lint.sh

Both must print `N passed, 0 failed`. CI runs them on every change.

## Golden fixtures (semantic equivalence)

Generation is Claude-assembled (Approach C), so golden checks assert
STRUCTURAL/SEMANTIC equivalence, not byte-for-byte:

- `fixtures/profiles/<name>.yaml` — an input profile.
- `fixtures/expected/<name>/` — the expected `values-*.yaml` overlays (the
  merged key/value tree) and the expected list of guide_section / known_issue
  ids in the guides.

To verify a slice: run `/rwl-install` (or regenerate from the fixture profile),
then confirm the generated overlay parses to the same key/value tree as the
expected file (`diff <(yaml-normalize a) <(yaml-normalize b)` where available),
and that the guides contain exactly the expected ids. The deterministic core —
which fragments and ids a profile selects — is exact; only rendered prose varies.
```

- [ ] **Step 4: Verify secret-guard passes on the expected fixtures**

Run: `bash rwl-install-wizard/lib/secret-guard.sh rwl-install-wizard/tests/fixtures/profiles rwl-install-wizard/tests/fixtures/expected`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add rwl-install-wizard/tests/fixtures/profiles rwl-install-wizard/tests/fixtures/expected rwl-install-wizard/tests/README.md
git commit -m "test(rwl-install-wizard): golden fixture for networking slice + test docs"
```

---

## Task 11: CI wiring + full machine-test run

**Files:**
- Create: `rwl-install-wizard/tests/run-all.sh`
- Modify: `.github/workflows/*` (only if a CI workflow already exists in this repo; otherwise create `rwl-install-wizard/tests/run-all.sh` and document manual runs)

- [ ] **Step 1: Aggregate test runner**

`rwl-install-wizard/tests/run-all.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$SCRIPT_DIR"/test-*.sh; do
    echo "### $t"
    bash "$t" || rc=1
done
# Catalog + data must be secret-clean.
echo "### secret-guard over data/"
bash "$SCRIPT_DIR/../lib/secret-guard.sh" "$SCRIPT_DIR/../data" || rc=1
exit "$rc"
```

- [ ] **Step 2: Make executable + run everything**

Run: `chmod +x rwl-install-wizard/tests/run-all.sh && bash rwl-install-wizard/tests/run-all.sh`
Expected: every test prints `0 failed`, secret-guard over `data/` exits 0, overall exit 0.

- [ ] **Step 3: Check for an existing CI workflow**

Run: `ls .github/workflows/ 2>/dev/null || echo "no workflows"`
- If a workflow exists, add a step invoking `bash rwl-install-wizard/tests/run-all.sh`.
- If none exists, skip CI wiring (the runner is documented in `tests/README.md`).

- [ ] **Step 4: Commit**

```bash
git add rwl-install-wizard/tests/run-all.sh
git add .github/workflows 2>/dev/null || true
git commit -m "test(rwl-install-wizard): aggregate test runner + CI wiring"
```

> **Milestone:** the plugin now installs, runs all three skills, and generates a
> correct, secret-free kit for the `networking` axis. Tasks 12–20 widen catalog
> coverage using the exact same patterns and the mechanical acceptance criteria
> noted at the top of the plan.

---

## Task 12: `cluster-shape` axis

**Files:**
- Modify: `rwl-install-wizard/data/knob-catalog.yaml` (add axis)
- Create: `rwl-install-wizard/data/guide-sections/{cluster-domain,storageclass,ingress-tls}.md`
- Create: `rwl-install-wizard/data/known-issues/{papi-cors-csrf-custom-hosts,ingress-not-rendered,tls-clusterissuer-vs-issuer}.md`
- Create: `rwl-install-wizard/tests/fixtures/profiles/cluster-basic.yaml` + `fixtures/expected/cluster-basic/`

**Source:** `values-example-cluster.yaml`, `values-example-internal-ca.yaml` (TLS modes), INSTALL-FRICTIONS §3 (CORS/CSRF), the "ingress.enabled" note (Jun 11), and the Issuer-vs-ClusterIssuer note (Jun 15).

**Axis:** options for `domain` (string param), `storageClass` (GKE `standard-rwo` / EKS `gp3` / AKS `managed-csi` / on-prem CSI name / NFS), `ingressClass` (string), `tls` (3 modes: cert-manager ClusterIssuer / cert-manager Issuer / bring-your-own secret). `emits:` into `values-cluster.yaml` under `global`, `ingress`, and per-service host keys. CORS/CSRF/login-allowed-hosts derive from `domain`.

- [ ] **Step 1:** Add the axis to the catalog (inline arrays for guide_sections/known_issues; no inline secrets — TLS BYO uses `ingress.tls.existingSecret`).
- [ ] **Step 2:** Author the three guide-section files and three known-issue files from the cited sources.
- [ ] **Step 3:** Add the golden fixture profile + expected overlay tree.
- [ ] **Step 4:** Run `bash rwl-install-wizard/tests/run-all.sh` → all `0 failed`, secret-guard exit 0.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): cluster-shape axis`.

---

## Task 13: `registry-routing` axis

**Files:**
- Modify: catalog; Create: `data/guide-sections/{registry-connected,registry-flat-mirror,registry-jfrog-per-upstream,subchart-alias-mirroring}.md`; `data/known-issues/{hardcoded-image-refs,embedder-airgap-hang,thin-chart-subchart-aliases,seaweedfs-image-chrislusf}.md`; golden fixture `profiles/airgap-jfrog.yaml` + expected.

**Source:** `values-example-airgap-jcr.yaml`, `docs/install/registry-routing.md`, `docs/install/airgap*.md`, INSTALL-FRICTIONS §29/§30/§31/§33.

**Axis:** `mode` = connected (no override) / flat `registryOverride` / per-upstream JFrog `registry:` map. `emits:` into `values-registry.yaml`. Image pull is wired via `images.pullSecrets[0].name` **by name only** (no credential).

- [ ] **Step 1:** Add axis (registry **hostname/repo path** params only — never a credential).
- [ ] **Step 2:** Author guide-sections + known-issues from cited sources.
- [ ] **Step 3:** Golden fixture + expected.
- [ ] **Step 4:** `run-all.sh` green.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): registry-routing axis`.

---

## Task 14: `storage` axis

**Files:**
- Modify: catalog; Create: `data/guide-sections/{storage-pvc,storage-nfs,storage-emptydir,object-storage-seaweedfs,object-storage-external-s3}.md`; `data/known-issues/{postgres-storage-kind,mimir-wal-ephemeral,seaweedfs-s3-access-denied,qdrant-no-nfs}.md`; golden fixture `profiles/nfs-single-node.yaml` + expected.

**Source:** `values-example-storage-nfs.yaml`, `values-example-single-node.yaml`, `STORAGE.md`, INSTALL-FRICTIONS §20/§20a/§22/§23/§36.

**Axis:** storage tier (`pvc`/`nfs`/`emptyDir`), object storage backend (bundled SeaweedFS vs external S3). `conflictsWith`: `storage:emptyDir` ⟷ `object-storage:external-s3-durable` where appropriate. External S3 endpoint is a **URL/bucket** only; credentials via `existingConfigSecret`/`platform-secrets` by name.

- [ ] **Step 1:** Add axis with the `conflictsWith` pair (declared symmetrically).
- [ ] **Step 2:** Author guide-sections + known-issues.
- [ ] **Step 3:** Golden fixture + expected.
- [ ] **Step 4:** `run-all.sh` green.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): storage axis`.

---

## Task 15: `security-posture` axis

**Files:**
- Modify: catalog; Create: `data/guide-sections/{nonroot-uid,readonly-rootfs,webhook-labels-securitycontext}.md`; `data/known-issues/{vault-init-home-perms,llm-gateway-nonroot-prisma,mass-run-as-root-failures}.md`; golden fixture `profiles/hardened.yaml` + expected.

**Source:** `docs/install/security-hardening.md`, `values-example-enterprise-byo-sa.yaml` (securityContext bits), INSTALL-FRICTIONS Jun 11/12 entries (run-as-root mass failures, vault-init regression, llm-gateway prisma).

**Axis:** `runAsNonRoot` + `uid`/`gid` params, `readOnlyRootfs` (with scratch volumes), admission-webhook `commonLabels`/`podSecurityContext`/`containerSecurityContext`. `emits:` into `values-posture.yaml` under `global.*`.

- [ ] **Step 1:** Add axis (UID/GID are non-sensitive integers).
- [ ] **Step 2:** Author guide-sections + known-issues (note the litellm-non_root image + UID 65534 vs 1000 webhook constraint).
- [ ] **Step 3:** Golden fixture + expected.
- [ ] **Step 4:** `run-all.sh` green.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): security-posture axis`.

---

## Task 16: `rbac-identity` axis

**Files:**
- Modify: catalog; Create: `data/guide-sections/{byo-serviceaccounts,no-clusterrolebindings,vault-injector-authdelegator,no-imagepullsecrets}.md`; `data/known-issues/{vault-clusterrolebinding-blocked,sa-rolebinding-reserved}.md`; golden fixture `profiles/byo-sa.yaml` + expected.

**Source:** `values-example-enterprise-byo-sa.yaml`, INSTALL-FRICTIONS §N (2026-06-09 enterprise entry), customer-access BYO-SA docs.

**Axis:** `byoServiceAccounts` (omit chart SA/RoleBindings; reference existing SA names), `clusterRoleBindings` off, Vault injector + authDelegator off, `imagePullSecrets` off. `emits:` into `values-posture.yaml`. All SA references are **names**, not tokens.

- [ ] **Step 1:** Add axis.
- [ ] **Step 2:** Author guide-sections + known-issues (note `system:auth-delegator` caveat).
- [ ] **Step 3:** Golden fixture + expected.
- [ ] **Step 4:** `run-all.sh` green.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): rbac-identity axis`.

---

## Task 17: `internal-ca` axis

**Files:**
- Modify: catalog; Create: `data/guide-sections/internal-ca-trust-bundle.md`; `data/known-issues/mcp-server-ssl-verify-failed.md`; golden fixture `profiles/internal-ca.yaml` + expected.

**Source:** `values-example-internal-ca.yaml`.

**Axis:** inject a private/corporate CA trust bundle. The CA bundle is referenced by **ConfigMap/Secret name** (the operator creates it out-of-band); the wizard never ingests cert material. `emits:` into `values-cluster.yaml`.

- [ ] **Step 1:** Add axis (CA bundle referenced by name only).
- [ ] **Step 2:** Author guide-section + known-issue.
- [ ] **Step 3:** Golden fixture + expected.
- [ ] **Step 4:** `run-all.sh` green.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): internal-ca axis`.

---

## Task 18: `subcharts` axis

**Files:**
- Modify: catalog; Create: `data/guide-sections/{subchart-bundled,subchart-byo-external}.md`; `data/known-issues/{postgres-bundled-single-pod,vault-order-of-operations,neo4j-workload-name}.md`; golden fixture `profiles/byo-datastores.yaml` + expected.

**Source:** `Chart.yaml` dependency conditions, `values-example-subchart-extensions.yaml`, INSTALL-FRICTIONS §11/§12/§20/§32/§34 (order-of-operations: Vault → DB migrations → workloads).

**Axis:** for each of postgres/redis/neo4j/vault/qdrant: bundled (`<name>.deploy: true`) vs BYO-external (`deploy: false` + connection host/port + `existingSecret` for creds). `emits:` into `values-cluster.yaml`.

- [ ] **Step 1:** Add axis (external connection params are host/port; creds by `existingSecret` name).
- [ ] **Step 2:** Author guide-sections + known-issues (emphasize the Vault→migrations→workloads dependency chain).
- [ ] **Step 3:** Golden fixture + expected.
- [ ] **Step 4:** `run-all.sh` green.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): subcharts axis`.

---

## Task 19: `llm-endpoint` axis

**Files:**
- Modify: catalog; Create: `data/guide-sections/llm-endpoint.md`; `data/known-issues/{llm-bootstrap-egress,tiktoken-dns-benign,litellm-configmap-placeholder}.md`; golden fixture `profiles/internal-llm.yaml` + expected.

**Source:** INSTALL-FRICTIONS §15 (llmBootstrap), Jun 12 llm-gateway entries, customer-access LLM notes.

**Axis:** internal OpenAI-compatible endpoint **URL** wiring; API key referenced via `existingSecret` name only. `emits:` into `values-cluster.yaml` (llm-gateway/litellm config) — endpoint URL is a non-secret.

- [ ] **Step 1:** Add axis (URL only; key by `existingSecret`).
- [ ] **Step 2:** Author guide-section + known-issues (note tiktoken DNS failure is benign).
- [ ] **Step 3:** Golden fixture + expected.
- [ ] **Step 4:** `run-all.sh` green.
- [ ] **Step 5:** Commit `feat(rwl-install-wizard): llm-endpoint axis`.

---

## Task 20: `optional-components` axis + full-shape golden fixture + final review

**Files:**
- Modify: catalog; Create: `data/guide-sections/{slack,alert-ingestor,redis-toggle}.md`; `data/known-issues/{slackbot-selfhosted,alert-ingestor-snippet-annotation,redis-deploy-switch}.md`; golden fixture `profiles/full-enterprise.yaml` (non-root + non-RFC1918 + air-gap + BYO-SA) + expected.

**Source:** `docs/install/slack-setup.md`, INSTALL-FRICTIONS §5 (slackbot), the alert-ingestor snippet-annotation note (Jun 11), the Redis open question (Jun 15).

**Axis:** toggles for Slack, alert-ingestor, redis. Slack tokens are referenced via `secrets.values.slack*` `existingSecret` names only — never collected. `emits:` into `values-cluster.yaml`.

- [ ] **Step 1:** Add axis.
- [ ] **Step 2:** Author guide-sections + known-issues.
- [ ] **Step 3:** Add the combined `full-enterprise` golden fixture exercising multiple axes at once; expected tree spans `values-cluster.yaml`, `values-registry.yaml`, `values-posture.yaml`.
- [ ] **Step 4:** `bash rwl-install-wizard/tests/run-all.sh` → all green; `secret-guard` over `data/` and over all expected fixtures exits 0.
- [ ] **Step 5:** Final self-check: every spec axis has a catalog entry; README skill list matches shipped skills; bump nothing else.
- [ ] **Step 6:** Commit `feat(rwl-install-wizard): optional-components axis + full-enterprise golden fixture`.

---

## Done criteria

- `bash rwl-install-wizard/tests/run-all.sh` exits 0 (both unit suites green; secret-guard clean over `data/` and fixtures).
- All 10 spec axes present in `knob-catalog.yaml`, each with guide-sections + known-issues files and a golden fixture.
- Three skills present and frontmatter-valid; plugin registered in `marketplace.json`.
- No skill ever runs a cluster command; no secret is ever requested or written (enforced by secret-guard gate inside `/rwl-install`).
