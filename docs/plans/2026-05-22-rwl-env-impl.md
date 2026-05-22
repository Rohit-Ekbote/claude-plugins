# rwl-env Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `rwl-env` plugin as a sibling to `rwenv` in this marketplace — a local-only debugger for helm-deployed RunWhen platform installs, with mutations gated to `helm upgrade` / `helm rollback` for deterministic revert.

**Architecture:** Per-project `.claude/rwl-env-env` file is the single runtime source of truth. Three agents (`helm-ops`, `k8s-ops`, `db-ops`) construct commands with the right flags; a PreToolUse hook validates flags, enforces `readOnly`, and auto-approves. Static `data/services-catalog.json` + `data/workflows-index.json` carry the chart + app-source-derived knowledge.

**Tech Stack:** Bash 3.2 (macOS-compatible), jq, helm 3.x, kubectl, Claude Code hooks/skills/agents.

**Design doc:** `docs/plans/2026-05-22-rwl-env-design.md` (commit `76850e7`)

---

## Phases & Task Index

| Phase | Tasks | Purpose |
|---|---|---|
| 1. Foundation | T1–T5 | Plugin scaffold, library utilities, marketplace registration |
| 2. Safety hook | T6–T9 | PreToolUse hook with validation + decision matrix |
| 3. Env management | T10–T13 | `/rwl-env-{list,cur,set,add}` skills |
| 4. Data files | T14–T18 | `services-catalog.json` + `workflows-index.json` + schema tests |
| 5. Agents | T19–T21 | `helm-ops`, `k8s-ops`, `db-ops` |
| 6. Helm op skills | T22–T25 | image-tag, rollback, set-values, upgrade-chart |
| 7. Debug skills | T26–T27 | dispatcher + 7 topic skills |
| 8. Bug report | T28 | `/rwl-report-chart-bug` |
| 9. Docs + release | T29–T31 | Manual testing runbook, catalog authoring guide, marketplace bump |

Each task ends with a commit. Tests are written before implementation where applicable (TDD). Bash 3.2 compatibility is enforced throughout.

---

## Phase 1: Foundation

### Task 1: Plugin scaffold and marketplace registration

**Files:**
- Create: `rwl-env/.claude-plugin/plugin.json`
- Create: `rwl-env/README.md`
- Create: `rwl-env/LICENSE`
- Create: `rwl-env/.gitignore`
- Create: `rwl-env/agents/.gitkeep`, `rwl-env/hooks/.gitkeep`, `rwl-env/lib/.gitkeep`, `rwl-env/data/.gitkeep`, `rwl-env/skills/.gitkeep`, `rwl-env/scripts/.gitkeep`, `rwl-env/tests/.gitkeep`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Create plugin.json**

Write `rwl-env/.claude-plugin/plugin.json`:

```json
{
  "name": "rwl-env",
  "description": "Helm-deployed RunWhen platform local debugger with deterministic-revert safety",
  "version": "0.1.0",
  "author": {
    "name": "Rohit Ekbote"
  },
  "homepage": "https://github.com/Rohit-Ekbote/claude-plugins",
  "repository": "https://github.com/Rohit-Ekbote/claude-plugins",
  "license": "MIT",
  "keywords": ["kubernetes", "k8s", "helm", "runwhen", "debug", "single-cluster", "safety"]
}
```

- [ ] **Step 2: Create README.md**

Write `rwl-env/README.md`:

```markdown
# rwl-env

Local debugger for helm-deployed RunWhen platform installs. All mutations go through `helm upgrade` / `helm rollback` so cluster state stays fully describable by `helm history` — every change is deterministically revertible.

## Quick start

```bash
# Register your first deployment
/rwl-env-add helm-dev

# Activate it for the current project
/rwl-env-set helm-dev

# Check status
/rwl-env-cur

# Bump an image tag
/rwl-upgrade-image-tag papi 2026-05-22.3
```

## Safety invariants

- Only `helm upgrade` and `helm rollback` mutate cluster state.
- `kubectl` writes (`apply`, `delete`, `patch`, etc.) are blocked by the PreToolUse hook.
- Postgres access is always read-only (no DDL/DML), regardless of the rwl-env's `readOnly` flag.
- `helm install` / `helm uninstall` are out of scope — this plugin debugs existing installs.

## Design

See `docs/plans/2026-05-22-rwl-env-design.md`.

## Comparison with rwenv

| | rwenv | rwl-env |
|---|---|---|
| Topology | Multi-cluster GKE / k3s | Single helm release per entry |
| Execution | Dev container or local | Local only |
| Mutations | kubectl + helm (gated) | helm upgrade / rollback only |
| DB access | Read/write per env | Always read-only |
```

- [ ] **Step 3: Copy LICENSE from rwenv**

```bash
cp rwenv/LICENSE rwl-env/LICENSE
```

- [ ] **Step 4: Create .gitignore**

Write `rwl-env/.gitignore`:

```
# Local test fixtures
tests/fixtures/.kube/
*.tmp
```

- [ ] **Step 5: Create directory placeholders**

```bash
mkdir -p rwl-env/agents rwl-env/hooks rwl-env/lib rwl-env/data rwl-env/skills rwl-env/scripts rwl-env/tests
touch rwl-env/agents/.gitkeep rwl-env/hooks/.gitkeep rwl-env/lib/.gitkeep rwl-env/data/.gitkeep rwl-env/skills/.gitkeep rwl-env/scripts/.gitkeep rwl-env/tests/.gitkeep
```

- [ ] **Step 6: Register plugin in marketplace.json**

Modify `.claude-plugin/marketplace.json` — add a second entry to `plugins[]` after the rwenv entry:

```json
{
  "name": "rwl-env",
  "description": "Helm-deployed RunWhen platform local debugger with deterministic-revert safety",
  "version": "0.1.0",
  "source": "./rwl-env",
  "author": {
    "name": "Rohit Ekbote"
  },
  "tags": ["kubernetes", "k8s", "helm", "runwhen", "debug"],
  "homepage": "https://github.com/Rohit-Ekbote/claude-plugins"
}
```

- [ ] **Step 7: Verify plugin.json parses and marketplace contains both plugins**

Run:
```bash
jq . rwl-env/.claude-plugin/plugin.json >/dev/null && echo "plugin.json OK"
jq '.plugins | length' .claude-plugin/marketplace.json
```
Expected: `plugin.json OK`, then `2`.

- [ ] **Step 8: Commit**

```bash
git add rwl-env/ .claude-plugin/marketplace.json
git commit -m "feat(rwl-env): plugin scaffold and marketplace registration"
```

---

### Task 2: `lib/rwlenv-utils.sh` — config-loading basics

**Files:**
- Create: `rwl-env/lib/rwlenv-utils.sh`
- Create: `rwl-env/tests/test-utils.sh`
- Create: `rwl-env/tests/fixtures/envs.json`

- [ ] **Step 1: Create the test fixture**

Write `rwl-env/tests/fixtures/envs.json`:

```json
{
  "version": "1.0",
  "rwlenvs": {
    "helm-dev": {
      "description": "Local k3d test cluster",
      "kubeconfigPath": "/tmp/test-kubeconfig",
      "kubernetesContext": "k3d-rwl-dev",
      "namespace": "runwhen",
      "releaseName": "rwl",
      "chart": { "repo": "oci://registry.example.com/charts", "name": "runwhen-platform" },
      "readOnly": false
    },
    "helm-staging": {
      "description": "Staging read-only",
      "kubeconfigPath": "/tmp/staging-kubeconfig",
      "kubernetesContext": "staging-ctx",
      "namespace": "runwhen",
      "releaseName": "rwl",
      "chart": { "repo": "https://charts.example.com", "name": "runwhen-platform" },
      "readOnly": true
    }
  }
}
```

- [ ] **Step 2: Write the failing test for `get_config_dir`, `load_envs`, `get_rwlenv_by_name`, `list_rwlenv_names`, `is_readonly`**

Write `rwl-env/tests/test-utils.sh`:

```bash
#!/usr/bin/env bash
# test-utils.sh - Unit tests for rwlenv-utils.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Point at fixtures
export RWLENV_CONFIG_DIR="$SCRIPT_DIR/fixtures"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/lib/rwlenv-utils.sh"

PASS=0; FAIL=0

assert_eq() {
    local actual="$1" expected="$2" desc="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s\n    expected=%q\n    actual=%q\n" "$desc" "$expected" "$actual"
        FAIL=$((FAIL+1))
    fi
}

assert_rc() {
    local rc="$1" expected="$2" desc="$3"
    if [[ "$rc" == "$expected" ]]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, expected=%s)\n" "$desc" "$rc" "$expected"
        FAIL=$((FAIL+1))
    fi
}

# --- Tests ---

echo "== get_config_dir =="
assert_eq "$(get_config_dir)" "$SCRIPT_DIR/fixtures" "respects RWLENV_CONFIG_DIR"

echo "== load_envs =="
assert_eq "$(load_envs | jq -r '.version')" "1.0" "loads envs.json version"
assert_eq "$(load_envs | jq -r '.rwlenvs | keys | length')" "2" "loads 2 rwlenvs"

echo "== get_rwlenv_by_name =="
assert_eq "$(get_rwlenv_by_name helm-dev | jq -r '.namespace')" "runwhen" "fetches helm-dev"
out=$(get_rwlenv_by_name nonexistent 2>/dev/null); assert_rc $? 1 "missing rwlenv returns rc=1"

echo "== list_rwlenv_names =="
got=$(list_rwlenv_names | sort | tr '\n' ',' | sed 's/,$//')
assert_eq "$got" "helm-dev,helm-staging" "lists all names"

echo "== is_readonly =="
is_readonly helm-dev; assert_rc $? 1 "helm-dev is not readOnly (rc=1)"
is_readonly helm-staging; assert_rc $? 0 "helm-staging is readOnly (rc=0)"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
```

Make it executable:
```bash
chmod +x rwl-env/tests/test-utils.sh
```

- [ ] **Step 3: Run the test and confirm it fails**

```bash
rwl-env/tests/test-utils.sh
```
Expected: fails because `rwl-env/lib/rwlenv-utils.sh` doesn't exist yet.

- [ ] **Step 4: Implement the basic functions**

Write `rwl-env/lib/rwlenv-utils.sh`:

```bash
#!/usr/bin/env bash
# rwlenv-utils.sh - Shared utility functions for rwl-env plugin

set -euo pipefail

# Get the config directory (supports RWLENV_CONFIG_DIR override)
get_config_dir() {
    echo "${RWLENV_CONFIG_DIR:-$HOME/.claude/rwl-env}"
}

# Get the plugin directory
get_plugin_dir() {
    echo "${RWLENV_PLUGIN_DIR:-$HOME/.claude/plugins/cache/Rohit-Ekbote-rwl-env/rwl-env}"
}

# Load envs.json content. Echoes empty skeleton + rc=1 if missing.
load_envs() {
    local envs_file
    envs_file="$(get_config_dir)/envs.json"
    if [[ ! -f "$envs_file" ]]; then
        echo '{"version":"1.0","rwlenvs":{}}'
        return 1
    fi
    cat "$envs_file"
}

# Get rwlenv entry by name. rc=1 if not found.
get_rwlenv_by_name() {
    local name="$1"
    local envs
    envs="$(load_envs)"
    echo "$envs" | jq -e --arg name "$name" '.rwlenvs[$name]' 2>/dev/null
}

# List all rwlenv names.
list_rwlenv_names() {
    local envs
    envs="$(load_envs)"
    echo "$envs" | jq -r '.rwlenvs | keys[]'
}

# Get current rwlenv for a directory (defaults to PWD).
get_current_rwlenv() {
    local dir="${1:-$PWD}"
    local file="$dir/.claude/rwl-env"
    if [[ -f "$file" ]]; then
        tr -d '[:space:]' < "$file"
        return 0
    fi
    return 1
}

# Check if rwlenv is read-only. rc=0 if read-only, rc=1 otherwise.
is_readonly() {
    local name="$1"
    local rwlenv
    rwlenv="$(get_rwlenv_by_name "$name")" || return 1
    echo "$rwlenv" | jq -e '.readOnly == true' >/dev/null 2>&1
}
```

Make it executable:
```bash
chmod +x rwl-env/lib/rwlenv-utils.sh
```

- [ ] **Step 5: Run the test and confirm it passes**

```bash
rwl-env/tests/test-utils.sh
```
Expected: all PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add rwl-env/lib/rwlenv-utils.sh rwl-env/tests/test-utils.sh rwl-env/tests/fixtures/envs.json
git commit -m "feat(rwl-env): config-loading utilities with unit tests"
```

---

### Task 3: `lib/rwlenv-utils.sh` — kubeconfig discovery

**Files:**
- Modify: `rwl-env/lib/rwlenv-utils.sh`
- Modify: `rwl-env/tests/test-utils.sh`
- Create: `rwl-env/tests/fixtures/kube-a.yaml`
- Create: `rwl-env/tests/fixtures/kube-b.yaml`

- [ ] **Step 1: Create kubeconfig fixtures**

Write `rwl-env/tests/fixtures/kube-a.yaml`:

```yaml
apiVersion: v1
kind: Config
clusters:
- name: cluster-a
  cluster: { server: https://a.example.com }
contexts:
- name: ctx-shared
  context: { cluster: cluster-a, user: user-a }
- name: ctx-only-a
  context: { cluster: cluster-a, user: user-a }
users:
- name: user-a
  user: {}
current-context: ctx-shared
```

Write `rwl-env/tests/fixtures/kube-b.yaml`:

```yaml
apiVersion: v1
kind: Config
clusters:
- name: cluster-b
  cluster: { server: https://b.example.com }
contexts:
- name: ctx-shared
  context: { cluster: cluster-b, user: user-b }
- name: ctx-only-b
  context: { cluster: cluster-b, user: user-b }
users:
- name: user-b
  user: {}
current-context: ctx-shared
```

- [ ] **Step 2: Append failing tests**

Append to `rwl-env/tests/test-utils.sh` (before the final `[[ "$FAIL" -eq 0 ]]` line):

```bash
echo "== list_contexts_in_file =="
got=$(list_contexts_in_file "$SCRIPT_DIR/fixtures/kube-a.yaml" | sort | tr '\n' ',' | sed 's/,$//')
assert_eq "$got" "ctx-only-a,ctx-shared" "kube-a.yaml lists ctx-only-a + ctx-shared"

echo "== find_context_across_files =="
# Searches under a temporary KUBE_SEARCH_ROOT (env var, override of ~/.kube/)
export KUBE_SEARCH_ROOT="$SCRIPT_DIR/fixtures"
got=$(find_context_across_files ctx-only-a | tr '\n' '|' | sed 's/|$//')
# Format: "<file>\t<context>"
assert_eq "$got" "$SCRIPT_DIR/fixtures/kube-a.yaml	ctx-only-a" "ctx-only-a found in kube-a.yaml only"

got_count=$(find_context_across_files ctx-shared | wc -l | tr -d ' ')
assert_eq "$got_count" "2" "ctx-shared found in both files"

got=$(find_context_across_files ctx-missing | wc -l | tr -d ' ')
assert_eq "$got" "0" "ctx-missing returns no matches"
unset KUBE_SEARCH_ROOT
```

- [ ] **Step 3: Run the test and confirm new tests fail**

```bash
rwl-env/tests/test-utils.sh
```
Expected: new assertions FAIL (functions not defined).

- [ ] **Step 4: Append implementation to rwlenv-utils.sh**

Append to `rwl-env/lib/rwlenv-utils.sh`:

```bash
# --- Kubeconfig discovery ---

# List contexts in a single kubeconfig file. Returns rc=1 if file invalid.
list_contexts_in_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    kubectl --kubeconfig="$file" config get-contexts -o name 2>/dev/null || return 1
}

# Discover candidate kubeconfig files under KUBE_SEARCH_ROOT (defaults to ~/.kube/).
# Also includes $KUBECONFIG colon-split paths if set.
discover_kubeconfig_files() {
    local root="${KUBE_SEARCH_ROOT:-$HOME/.kube}"
    if [[ -d "$root" ]]; then
        # Match: config, *.yaml, *.yml, *-config, *.config
        find "$root" -maxdepth 1 -type f \
            \( -name 'config' -o -name '*.yaml' -o -name '*.yml' \
               -o -name '*-config' -o -name '*.config' \) 2>/dev/null
    fi
    if [[ -n "${KUBECONFIG:-}" ]]; then
        echo "$KUBECONFIG" | tr ':' '\n' | while read -r p; do
            [[ -f "$p" ]] && echo "$p"
        done
    fi
}

# Find (file, context) pairs matching context_name. Tab-separated lines.
# Exact match first, substring match fallback. rc=0 even if no matches.
find_context_across_files() {
    local target="$1"
    local files
    files=$(discover_kubeconfig_files)
    local found_exact=0
    local f ctx
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        while IFS= read -r ctx; do
            [[ -z "$ctx" ]] && continue
            if [[ "$ctx" == "$target" ]]; then
                printf "%s\t%s\n" "$f" "$ctx"
                found_exact=1
            fi
        done < <(list_contexts_in_file "$f" 2>/dev/null || true)
    done <<< "$files"

    # Substring fallback only if no exact matches
    if [[ "$found_exact" -eq 0 ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            while IFS= read -r ctx; do
                [[ -z "$ctx" ]] && continue
                if [[ "$ctx" == *"$target"* ]]; then
                    printf "%s\t%s\n" "$f" "$ctx"
                fi
            done < <(list_contexts_in_file "$f" 2>/dev/null || true)
        done <<< "$files"
    fi
}
```

- [ ] **Step 5: Run the test and confirm pass**

```bash
rwl-env/tests/test-utils.sh
```
Expected: all PASS.

Note: tests depend on `kubectl` being installed. If not present, document this in the task notes and skip — but `kubectl` is a hard runtime dep anyway.

- [ ] **Step 6: Commit**

```bash
git add rwl-env/lib/rwlenv-utils.sh rwl-env/tests/test-utils.sh rwl-env/tests/fixtures/kube-a.yaml rwl-env/tests/fixtures/kube-b.yaml
git commit -m "feat(rwl-env): kubeconfig discovery functions"
```

---

### Task 4: `lib/rwlenv-utils.sh` — write-detection helpers

**Files:**
- Modify: `rwl-env/lib/rwlenv-utils.sh`
- Modify: `rwl-env/tests/test-utils.sh`

- [ ] **Step 1: Append failing tests**

Append to `rwl-env/tests/test-utils.sh` (before final assertion):

```bash
echo "== is_helm_write_operation =="
is_helm_write_operation "upgrade"; assert_rc $? 0 "upgrade is a write"
is_helm_write_operation "rollback"; assert_rc $? 0 "rollback is a write"
is_helm_write_operation "install"; assert_rc $? 0 "install is a write (forbidden by allowlist later)"
is_helm_write_operation "uninstall"; assert_rc $? 0 "uninstall is a write"
is_helm_write_operation "get values"; assert_rc $? 1 "get values is not a write"
is_helm_write_operation "history"; assert_rc $? 1 "history is not a write"

echo "== is_helm_forbidden_operation =="
is_helm_forbidden_operation "install"; assert_rc $? 0 "install is forbidden"
is_helm_forbidden_operation "uninstall"; assert_rc $? 0 "uninstall is forbidden"
is_helm_forbidden_operation "delete"; assert_rc $? 0 "delete is forbidden"
is_helm_forbidden_operation "upgrade"; assert_rc $? 1 "upgrade is not forbidden"
is_helm_forbidden_operation "rollback"; assert_rc $? 1 "rollback is not forbidden"

echo "== is_kubectl_write_operation =="
is_kubectl_write_operation "apply"; assert_rc $? 0 "apply is a write"
is_kubectl_write_operation "delete"; assert_rc $? 0 "delete is a write"
is_kubectl_write_operation "patch"; assert_rc $? 0 "patch is a write"
is_kubectl_write_operation "scale"; assert_rc $? 0 "scale is a write"
is_kubectl_write_operation "set image"; assert_rc $? 0 "set image is a write"
is_kubectl_write_operation "get"; assert_rc $? 1 "get is not a write"
is_kubectl_write_operation "logs"; assert_rc $? 1 "logs is not a write"
is_kubectl_write_operation "rollout status"; assert_rc $? 1 "rollout status is not a write"
is_kubectl_write_operation "rollout restart"; assert_rc $? 0 "rollout restart is a write"

echo "== validate_psql_query =="
validate_psql_query "SELECT * FROM users"; assert_rc $? 0 "SELECT allowed"
validate_psql_query "EXPLAIN SELECT 1"; assert_rc $? 0 "EXPLAIN allowed"
validate_psql_query "INSERT INTO t VALUES (1)" 2>/dev/null; assert_rc $? 1 "INSERT blocked"
validate_psql_query "UPDATE t SET x=1" 2>/dev/null; assert_rc $? 1 "UPDATE blocked"
validate_psql_query "DELETE FROM t" 2>/dev/null; assert_rc $? 1 "DELETE blocked"
validate_psql_query "CREATE TABLE x (a int)" 2>/dev/null; assert_rc $? 1 "CREATE blocked"
validate_psql_query "DROP TABLE x" 2>/dev/null; assert_rc $? 1 "DROP blocked"
validate_psql_query "TRUNCATE x" 2>/dev/null; assert_rc $? 1 "TRUNCATE blocked"
validate_psql_query "COPY x TO '/tmp/f'" 2>/dev/null; assert_rc $? 1 "COPY TO blocked"
validate_psql_query "SELECT 1; DROP TABLE x" 2>/dev/null; assert_rc $? 1 "multi-stmt with DDL blocked"
```

- [ ] **Step 2: Run and confirm failures**

```bash
rwl-env/tests/test-utils.sh
```
Expected: new assertions FAIL.

- [ ] **Step 3: Append implementation**

Append to `rwl-env/lib/rwlenv-utils.sh`:

```bash
# --- Write detection ---

# Returns 0 if the helm subcommand is a write (upgrade/rollback/install/uninstall/etc).
is_helm_write_operation() {
    local cmd="$1"
    local write_ops="install|upgrade|uninstall|rollback|delete|repo add|repo remove|dependency"
    echo "$cmd" | grep -qE "^($write_ops)(\s|$)"
}

# Returns 0 if the helm subcommand is FORBIDDEN by rwl-env (out of scope for this plugin).
# This is a stricter subset than write_operation — upgrade/rollback are writes but allowed.
is_helm_forbidden_operation() {
    local cmd="$1"
    local forbidden="install|uninstall|delete|repo add|repo remove|dependency"
    echo "$cmd" | grep -qE "^($forbidden)(\s|$)"
}

# Returns 0 if the kubectl subcommand is a write.
# NOTE: "rollout status" and "rollout history" are reads; "rollout restart" is a write.
is_kubectl_write_operation() {
    local cmd="$1"
    # Match "rollout restart" explicitly before generic single-word "rollout" check
    if echo "$cmd" | grep -qE "^rollout\s+restart(\s|$)"; then return 0; fi
    if echo "$cmd" | grep -qE "^rollout\s+(status|history)(\s|$)"; then return 1; fi
    local write_ops="apply|delete|patch|create|edit|replace|scale|set\s+image|set\s+resources|set\s+env|label|annotate|taint|cordon|uncordon|drain|exec"
    # Note: "exec" included so callers can decide separately (we allow exec under extra checks).
    echo "$cmd" | grep -qE "^($write_ops)(\s|$)"
}

# Validate a SQL query for read-only safety. rc=0 if safe, rc=1 with stderr if blocked.
# Always blocks DDL, DML, COPY ... TO regardless of any readOnly flag.
validate_psql_query() {
    local query="$1"
    local query_upper
    query_upper=$(echo "$query" | tr '[:lower:]' '[:upper:]')

    local ddl="CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|VACUUM|REINDEX|CLUSTER"
    local dml="INSERT|UPDATE|DELETE|MERGE|UPSERT"

    if echo "$query_upper" | grep -qE "(^|[^A-Z])($ddl)([^A-Z]|$)"; then
        echo "ERROR: DDL blocked. rwl-env db access is read-only. Query: $query" >&2
        return 1
    fi
    if echo "$query_upper" | grep -qE "(^|[^A-Z])($dml)([^A-Z]|$)"; then
        echo "ERROR: DML blocked. rwl-env db access is read-only. Query: $query" >&2
        return 1
    fi
    if echo "$query_upper" | grep -qE "COPY.*TO"; then
        echo "ERROR: COPY TO blocked. File writes not allowed." >&2
        return 1
    fi
    return 0
}
```

- [ ] **Step 4: Run and confirm pass**

```bash
rwl-env/tests/test-utils.sh
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add rwl-env/lib/rwlenv-utils.sh rwl-env/tests/test-utils.sh
git commit -m "feat(rwl-env): helm/kubectl write detection and psql validation"
```

---

### Task 5: `lib/rwlenv-utils.sh` — runtime env file writers

**Files:**
- Modify: `rwl-env/lib/rwlenv-utils.sh`
- Modify: `rwl-env/tests/test-utils.sh`

- [ ] **Step 1: Append failing tests**

Append to `rwl-env/tests/test-utils.sh` (before final assertion):

```bash
echo "== set_rwlenv_for_dir + write_rwlenv_env =="
TMPDIR_TEST=$(mktemp -d)
trap "rm -rf $TMPDIR_TEST" EXIT

set_rwlenv_for_dir "$TMPDIR_TEST" "helm-dev"
assert_eq "$(cat $TMPDIR_TEST/.claude/rwl-env)" "helm-dev" "writes .claude/rwl-env"

write_rwlenv_env "$TMPDIR_TEST" "helm-dev"
assert_eq "$(grep '^RWLENV_NAME=' $TMPDIR_TEST/.claude/rwl-env-env | cut -d= -f2)" "helm-dev" "RWLENV_NAME set"
assert_eq "$(grep '^RWLENV_NAMESPACE=' $TMPDIR_TEST/.claude/rwl-env-env | cut -d= -f2)" "runwhen" "RWLENV_NAMESPACE set"
assert_eq "$(grep '^RWLENV_RELEASE=' $TMPDIR_TEST/.claude/rwl-env-env | cut -d= -f2)" "rwl" "RWLENV_RELEASE set"
assert_eq "$(grep '^RWLENV_READ_ONLY=' $TMPDIR_TEST/.claude/rwl-env-env | cut -d= -f2)" "false" "RWLENV_READ_ONLY false"
assert_eq "$(grep '^RWLENV_CHART_REPO=' $TMPDIR_TEST/.claude/rwl-env-env | cut -d= -f2)" "oci://registry.example.com/charts" "RWLENV_CHART_REPO set"

write_rwlenv_env "$TMPDIR_TEST" "helm-staging"
assert_eq "$(grep '^RWLENV_READ_ONLY=' $TMPDIR_TEST/.claude/rwl-env-env | cut -d= -f2)" "true" "RWLENV_READ_ONLY true for staging"

# Verify unknown entry fails
write_rwlenv_env "$TMPDIR_TEST" "nonexistent" 2>/dev/null; assert_rc $? 1 "unknown rwlenv fails"
```

- [ ] **Step 2: Run and confirm failures**

```bash
rwl-env/tests/test-utils.sh
```
Expected: new assertions FAIL.

- [ ] **Step 3: Append implementation**

Append to `rwl-env/lib/rwlenv-utils.sh`:

```bash
# --- Per-project file writers ---

# Set the active rwl-env for a directory. Writes <dir>/.claude/rwl-env and auto-gitignores.
set_rwlenv_for_dir() {
    local dir="${1:-$PWD}"
    local name="$2"
    local file="$dir/.claude/rwl-env"
    local gitignore="$dir/.gitignore"

    get_rwlenv_by_name "$name" >/dev/null || {
        echo "ERROR: Unknown rwl-env '$name'" >&2
        return 1
    }

    mkdir -p "$dir/.claude"
    echo "$name" > "$file"

    if [[ -d "$dir/.git" ]] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        if ! grep -qxF '.claude/rwl-env' "$gitignore" 2>/dev/null; then
            if [[ -f "$gitignore" ]] && [[ -s "$gitignore" ]] && [[ "$(tail -c 1 "$gitignore" | wc -l)" -eq 0 ]]; then
                echo >> "$gitignore"
            fi
            echo '.claude/rwl-env' >> "$gitignore"
        fi
    fi
}

# Generate <dir>/.claude/rwl-env-env from the named rwl-env entry.
write_rwlenv_env() {
    local dir="${1:-$PWD}"
    local name="$2"

    if [[ -z "$name" ]]; then
        echo "ERROR: rwl-env name required" >&2
        return 1
    fi

    local cfg
    cfg=$(get_rwlenv_by_name "$name") || {
        echo "ERROR: rwl-env '$name' not found" >&2
        return 1
    }

    local kubeconfig context namespace release chart_repo chart_name read_only
    kubeconfig=$(echo "$cfg" | jq -r '.kubeconfigPath')
    context=$(echo "$cfg" | jq -r '.kubernetesContext')
    namespace=$(echo "$cfg" | jq -r '.namespace')
    release=$(echo "$cfg" | jq -r '.releaseName')
    chart_repo=$(echo "$cfg" | jq -r '.chart.repo')
    chart_name=$(echo "$cfg" | jq -r '.chart.name')
    read_only=$(echo "$cfg" | jq -r '.readOnly')

    mkdir -p "$dir/.claude"
    local file="$dir/.claude/rwl-env-env"
    cat > "$file" <<ENVEOF
# Generated by /rwl-env-set. Do not edit manually.
RWLENV_NAME=$name
RWLENV_KUBECONFIG=$kubeconfig
RWLENV_CONTEXT=$context
RWLENV_NAMESPACE=$namespace
RWLENV_RELEASE=$release
RWLENV_CHART_REPO=$chart_repo
RWLENV_CHART_NAME=$chart_name
RWLENV_READ_ONLY=$read_only
ENVEOF

    # Auto-gitignore
    local gitignore="$dir/.gitignore"
    if [[ -d "$dir/.git" ]] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        if ! grep -qxF '.claude/rwl-env-env' "$gitignore" 2>/dev/null; then
            if [[ -f "$gitignore" ]] && [[ -s "$gitignore" ]] && [[ "$(tail -c 1 "$gitignore" | wc -l)" -eq 0 ]]; then
                echo >> "$gitignore"
            fi
            echo '.claude/rwl-env-env' >> "$gitignore"
        fi
    fi
}

# Format details of an rwl-env for display (used by /rwl-env-cur).
format_rwlenv_details() {
    local name="$1"
    local cfg
    cfg=$(get_rwlenv_by_name "$name") || return 1
    cat <<EOF
Name:        $name
Description: $(echo "$cfg" | jq -r '.description // "No description"')
Kubeconfig:  $(echo "$cfg" | jq -r '.kubeconfigPath')
Context:     $(echo "$cfg" | jq -r '.kubernetesContext')
Namespace:   $(echo "$cfg" | jq -r '.namespace')
Release:     $(echo "$cfg" | jq -r '.releaseName')
Chart:       $(echo "$cfg" | jq -r '.chart.repo')/$(echo "$cfg" | jq -r '.chart.name')
Read-Only:   $(echo "$cfg" | jq -r '.readOnly')
EOF
}
```

- [ ] **Step 4: Run and confirm pass**

```bash
rwl-env/tests/test-utils.sh
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add rwl-env/lib/rwlenv-utils.sh rwl-env/tests/test-utils.sh
git commit -m "feat(rwl-env): per-project runtime env file writer and details formatter"
```

---

## Phase 2: Safety Hook

### Task 6: Hook scaffold + engagement logic

**Files:**
- Create: `rwl-env/hooks/hooks.json`
- Create: `rwl-env/hooks/transform-commands.sh`
- Create: `rwl-env/tests/test-hooks.sh`
- Create: `rwl-env/tests/fixtures/rwl-env-env-helm-dev`
- Create: `rwl-env/tests/fixtures/rwl-env-env-helm-staging`

- [ ] **Step 1: Create hooks.json**

Write `rwl-env/hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/transform-commands.sh" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Create runtime env file fixtures**

Write `rwl-env/tests/fixtures/rwl-env-env-helm-dev`:

```bash
RWLENV_NAME=helm-dev
RWLENV_KUBECONFIG=/tmp/test-kubeconfig
RWLENV_CONTEXT=k3d-rwl-dev
RWLENV_NAMESPACE=runwhen
RWLENV_RELEASE=rwl
RWLENV_CHART_REPO=oci://registry.example.com/charts
RWLENV_CHART_NAME=runwhen-platform
RWLENV_READ_ONLY=false
```

Write `rwl-env/tests/fixtures/rwl-env-env-helm-staging`:

```bash
RWLENV_NAME=helm-staging
RWLENV_KUBECONFIG=/tmp/staging-kubeconfig
RWLENV_CONTEXT=staging-ctx
RWLENV_NAMESPACE=runwhen
RWLENV_RELEASE=rwl
RWLENV_CHART_REPO=https://charts.example.com
RWLENV_CHART_NAME=runwhen-platform
RWLENV_READ_ONLY=true
```

- [ ] **Step 3: Write the test harness skeleton (failing tests for engagement)**

Write `rwl-env/tests/test-hooks.sh`:

```bash
#!/usr/bin/env bash
# test-hooks.sh - Decision-matrix tests for transform-commands.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$PLUGIN_DIR/hooks/transform-commands.sh"

PASS=0; FAIL=0

# Set up a temp project dir with a fixture .claude/rwl-env-env
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/.claude"
trap "rm -rf $TMPDIR_TEST" EXIT

use_fixture() {
    cp "$SCRIPT_DIR/fixtures/rwl-env-env-$1" "$TMPDIR_TEST/.claude/rwl-env-env"
}
clear_fixture() {
    rm -f "$TMPDIR_TEST/.claude/rwl-env-env"
}

# Run hook with a given Bash command. Returns "<rc>|<stdout>".
run_hook() {
    local cmd="$1"
    local input
    input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
    local out rc
    out=$(cd "$TMPDIR_TEST" && echo "$input" | bash "$HOOK" 2>/dev/null) && rc=$? || rc=$?
    printf "%d|%s" "$rc" "$out"
}

assert_allow() {
    local cmd="$1" desc="$2"
    local result; result=$(run_hook "$cmd")
    local rc="${result%%|*}" out="${result#*|}"
    if [[ "$rc" == "0" ]] && echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, out=%s)\n" "$desc" "$rc" "$out"
        FAIL=$((FAIL+1))
    fi
}

assert_block() {
    local cmd="$1" desc="$2"
    local result; result=$(run_hook "$cmd")
    local rc="${result%%|*}"
    if [[ "$rc" == "2" ]]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (rc=%s, expected 2)\n" "$desc" "$rc"
        FAIL=$((FAIL+1))
    fi
}

# --- Engagement tests ---

echo "== No rwl-env-env: pass through =="
clear_fixture
assert_allow "echo hello" "echo passes through without env file"
assert_allow "kubectl get pods" "kubectl passes through without env file (no opinion)"

echo "== Non-managed binaries with env file =="
use_fixture helm-dev
assert_allow "ls -la" "ls always allowed"
assert_allow "git status" "git always allowed"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
```

Make executable:
```bash
chmod +x rwl-env/tests/test-hooks.sh
```

- [ ] **Step 4: Run, confirm failure (hook doesn't exist yet)**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: fails (hook missing).

- [ ] **Step 5: Implement scaffold of transform-commands.sh**

Write `rwl-env/hooks/transform-commands.sh`:

```bash
#!/usr/bin/env bash
# transform-commands.sh - Validation, safety enforcement, and auto-approval for rwl-env
#
# Sources $PWD/.claude/rwl-env-env. If missing, passes through silently.
# Validates kubectl/helm/psql commands against the active rwl-env:
#   - flags must match (kubeconfig, context, namespace, release)
#   - readOnly blocks helm writes
#   - kubectl writes always blocked
#   - psql DDL/DML always blocked

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/lib/rwlenv-utils.sh"

# Commands rwl-env opines on
RWLENV_BINARIES="kubectl|helm|psql"

# Read stdin
INPUT_JSON=$(cat)
ORIGINAL_CMD=$(echo "$INPUT_JSON" | jq -r '.tool_input.command // empty')

allow() {
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
}

block() {
    echo "BLOCKED by rwl-env: $1" >&2
    exit 2
}

# No command, nothing to inspect
if [[ -z "$ORIGINAL_CMD" ]]; then
    allow
fi

# Source the runtime env file
ENV_FILE="${PWD}/.claude/rwl-env-env"

# Determine if command involves an rwl-env-managed binary
CONTAINS_MANAGED=false
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z0-9_-])($RWLENV_BINARIES)(\s|$)"; then
    CONTAINS_MANAGED=true
fi

# If no env file: pass through everything (no opinion).
# (Unlike rwenv, we deliberately do NOT block kubectl/helm here — user may be working
#  on multiple non-rwl projects in this terminal.)
if [[ ! -f "$ENV_FILE" ]]; then
    allow
fi

# If env file exists but command doesn't involve managed binaries, allow.
if [[ "$CONTAINS_MANAGED" == "false" ]]; then
    allow
fi

# Source env vars for decision-making
# shellcheck source=/dev/null
source "$ENV_FILE"

# Validation + classification logic added in subsequent tasks
# For now, allow everything matched so the engagement tests pass.
allow
```

Make executable:
```bash
chmod +x rwl-env/hooks/transform-commands.sh
```

- [ ] **Step 6: Run tests, confirm pass**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: PASS=4 FAIL=0.

- [ ] **Step 7: Commit**

```bash
git add rwl-env/hooks/ rwl-env/tests/test-hooks.sh rwl-env/tests/fixtures/rwl-env-env-helm-dev rwl-env/tests/fixtures/rwl-env-env-helm-staging
git commit -m "feat(rwl-env): hook scaffold with engagement logic"
```

---

### Task 7: Hook — helm flag validation + decision

**Files:**
- Modify: `rwl-env/hooks/transform-commands.sh`
- Modify: `rwl-env/tests/test-hooks.sh`

- [ ] **Step 1: Append failing tests for helm validation**

Append to `rwl-env/tests/test-hooks.sh` (before `[[ "$FAIL" -eq 0 ]]`):

```bash
echo "== Helm validation (helm-dev, read-write) =="
use_fixture helm-dev

# Allowed reads
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev get values rwl -n runwhen" "helm get values allowed"
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev history rwl -n runwhen" "helm history allowed"
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev status rwl -n runwhen" "helm status allowed"

# Allowed writes (read-write env)
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev upgrade rwl oci://registry.example.com/charts/runwhen-platform --reuse-values -n runwhen" "helm upgrade allowed when not readOnly"
assert_allow "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev rollback rwl 7 -n runwhen" "helm rollback allowed when not readOnly"

# Forbidden operations
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev install rwl chart -n runwhen" "helm install forbidden (out of scope)"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev uninstall rwl -n runwhen" "helm uninstall forbidden"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev delete rwl -n runwhen" "helm delete forbidden"

# Flag mismatches
assert_block "helm --kubeconfig=/tmp/wrong --kube-context=k3d-rwl-dev get values rwl -n runwhen" "wrong kubeconfig blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=wrong-ctx get values rwl -n runwhen" "wrong context blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev get values rwl -n other-ns" "wrong namespace blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig --kube-context=k3d-rwl-dev upgrade other-release chart --reuse-values -n runwhen" "wrong release name blocked"

# Missing required flags
assert_block "helm get values rwl -n runwhen" "missing --kubeconfig and --kube-context blocked"
assert_block "helm --kubeconfig=/tmp/test-kubeconfig get values rwl -n runwhen" "missing --kube-context blocked"

echo "== Helm validation (helm-staging, read-only) =="
use_fixture helm-staging
assert_allow "helm --kubeconfig=/tmp/staging-kubeconfig --kube-context=staging-ctx get values rwl -n runwhen" "read on readOnly env allowed"
assert_block "helm --kubeconfig=/tmp/staging-kubeconfig --kube-context=staging-ctx upgrade rwl chart --reuse-values -n runwhen" "helm upgrade on readOnly blocked"
assert_block "helm --kubeconfig=/tmp/staging-kubeconfig --kube-context=staging-ctx rollback rwl 7 -n runwhen" "helm rollback on readOnly blocked"
```

- [ ] **Step 2: Run, confirm failures**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: helm validation tests FAIL (logic not implemented).

- [ ] **Step 3: Implement helm validation in transform-commands.sh**

In `rwl-env/hooks/transform-commands.sh`, replace the final `allow` line (after `source "$ENV_FILE"`) with this block:

```bash
# --- Helm decision ---
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z0-9_-])helm(\s|$)"; then
    # Extract helm subcommand. Anything after `helm` and any flags up to first non-flag token.
    helm_sub=$(echo "$ORIGINAL_CMD" \
        | sed 's/.*[^a-zA-Z0-9_-]helm/helm/' \
        | sed 's/^helm\s*//' \
        | awk '{
            for (i=1; i<=NF; i++) {
                if ($i ~ /^-/) {
                    # skip flag; eat next token if --foo without =
                    if ($i !~ /=/) i++
                    continue
                }
                # First non-flag token is the subcommand
                sub = $i
                if (NF >= i+1 && $(i+1) !~ /^-/) sub = sub " " $(i+1)
                print sub
                exit
            }
        }')

    # Forbidden operations (install, uninstall, delete, repo add/remove, dependency)
    if is_helm_forbidden_operation "$helm_sub"; then
        block "helm '$helm_sub' is out of scope for this plugin; use the helm CLI directly outside Claude Code."
    fi

    # Required flags
    echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=$RWLENV_KUBECONFIG(\s|$)" \
        || block "helm command missing or wrong --kubeconfig (expected $RWLENV_KUBECONFIG)."
    echo "$ORIGINAL_CMD" | grep -qE -- "--kube-context=$RWLENV_CONTEXT(\s|$)" \
        || block "helm command missing or wrong --kube-context (expected $RWLENV_CONTEXT)."
    echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)\s+$RWLENV_NAMESPACE(\s|$)" \
        || block "helm command missing or wrong -n/--namespace (expected $RWLENV_NAMESPACE)."

    # Release name must equal $RWLENV_RELEASE for upgrade/rollback/get/status/history
    # Extract first positional argument after subcommand
    rel_arg=$(echo "$ORIGINAL_CMD" \
        | sed 's/.*[^a-zA-Z0-9_-]helm/helm/' \
        | awk -v sub="$helm_sub" '{
            for (i=1; i<=NF; i++) {
                if ($i == "helm") continue
                if ($i ~ /^-/) {
                    if ($i !~ /=/) i++
                    continue
                }
                # consume subcommand tokens
                if (split(sub, parts, " ") >= 1 && $i == parts[1]) {
                    if (length(parts) > 1 && $(i+1) == parts[2]) i++
                    continue
                }
                print $i; exit
            }
        }')
    case "$helm_sub" in
        upgrade|rollback|"get values"|"get manifest"|"get metadata"|"get notes"|"get hooks"|history|status)
            if [[ -n "$rel_arg" && "$rel_arg" != "$RWLENV_RELEASE" ]]; then
                block "helm command targets release '$rel_arg' but active rwl-env release is '$RWLENV_RELEASE'."
            fi
            ;;
    esac

    # readOnly enforcement
    if [[ "$RWLENV_READ_ONLY" == "true" ]] && is_helm_write_operation "$helm_sub"; then
        block "helm '$helm_sub' not allowed; rwl-env '$RWLENV_NAME' is read-only."
    fi

    allow
fi

# --- Kubectl decision (added in Task 8) ---
# --- Psql decision (added in Task 9) ---

allow
```

- [ ] **Step 4: Run tests, confirm helm tests pass**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: helm validation tests PASS.

- [ ] **Step 5: Commit**

```bash
git add rwl-env/hooks/transform-commands.sh rwl-env/tests/test-hooks.sh
git commit -m "feat(rwl-env): hook validates helm commands and enforces readOnly"
```

---

### Task 8: Hook — kubectl validation + decision

**Files:**
- Modify: `rwl-env/hooks/transform-commands.sh`
- Modify: `rwl-env/tests/test-hooks.sh`

- [ ] **Step 1: Append failing kubectl tests**

Append to `rwl-env/tests/test-hooks.sh` (before `[[ "$FAIL" -eq 0 ]]`):

```bash
echo "== Kubectl validation (helm-dev) =="
use_fixture helm-dev

# Reads allowed
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev get pods -n runwhen" "kubectl get pods allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev logs my-pod -n runwhen" "kubectl logs allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev describe deploy/papi -n runwhen" "kubectl describe allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev get events -n runwhen --sort-by=.lastTimestamp" "kubectl get events allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev rollout status deploy/papi -n runwhen" "kubectl rollout status allowed"

# Writes always blocked (even when not readOnly)
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev apply -f x.yaml -n runwhen" "kubectl apply blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev delete pod my-pod -n runwhen" "kubectl delete blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev patch deploy/papi --patch='{}' -n runwhen" "kubectl patch blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev edit deploy/papi -n runwhen" "kubectl edit blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev scale deploy/papi --replicas=3 -n runwhen" "kubectl scale blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev rollout restart deploy/papi -n runwhen" "kubectl rollout restart blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev set image deploy/papi papi=newtag -n runwhen" "kubectl set image blocked"

# Exec and port-forward allowed (reads from rwl-env perspective)
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec my-pod -n runwhen -- ls" "kubectl exec interactive allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev port-forward svc/papi 8080:8080 -n runwhen" "kubectl port-forward allowed"

# Flag mismatches
assert_block "kubectl --kubeconfig=/tmp/wrong --context=k3d-rwl-dev get pods -n runwhen" "wrong kubeconfig blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=wrong get pods -n runwhen" "wrong context blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev get pods -n elsewhere" "wrong namespace blocked"
```

- [ ] **Step 2: Run, confirm failures**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: new kubectl tests FAIL.

- [ ] **Step 3: Replace the placeholder kubectl block in transform-commands.sh**

In `rwl-env/hooks/transform-commands.sh`, replace `# --- Kubectl decision (added in Task 8) ---` with:

```bash
# --- Kubectl decision ---
if echo "$ORIGINAL_CMD" | grep -qE "(^|[^a-zA-Z0-9_-])kubectl(\s|$)"; then
    # Required flags
    echo "$ORIGINAL_CMD" | grep -qE -- "--kubeconfig=$RWLENV_KUBECONFIG(\s|$)" \
        || block "kubectl command missing or wrong --kubeconfig (expected $RWLENV_KUBECONFIG)."
    echo "$ORIGINAL_CMD" | grep -qE -- "--context=$RWLENV_CONTEXT(\s|$)" \
        || block "kubectl command missing or wrong --context (expected $RWLENV_CONTEXT)."
    echo "$ORIGINAL_CMD" | grep -qE -- "(-n|--namespace)\s+$RWLENV_NAMESPACE(\s|$)" \
        || block "kubectl command missing or wrong -n/--namespace (expected $RWLENV_NAMESPACE)."

    # Extract kubectl subcommand (first non-flag token after kubectl)
    kubectl_sub=$(echo "$ORIGINAL_CMD" \
        | sed 's/.*[^a-zA-Z0-9_-]kubectl/kubectl/' \
        | awk '{
            for (i=2; i<=NF; i++) {
                if ($i ~ /^-/) {
                    if ($i !~ /=/) i++
                    continue
                }
                sub = $i
                if (NF >= i+1 && $(i+1) !~ /^-/) sub = sub " " $(i+1)
                print sub; exit
            }
        }')

    # Writes always blocked (only helm-ops can mutate)
    if is_kubectl_write_operation "$kubectl_sub"; then
        # Special case: exec is a "write-able" subcommand but rwl-env allows interactive shells
        case "$kubectl_sub" in
            exec*)
                : # exec extras handled in Task 9
                ;;
            *)
                block "kubectl '$kubectl_sub' not allowed; mutations must go through helm-ops (helm upgrade / rollback)."
                ;;
        esac
    fi

    allow
fi
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add rwl-env/hooks/transform-commands.sh rwl-env/tests/test-hooks.sh
git commit -m "feat(rwl-env): hook validates kubectl flags and blocks writes"
```

---

### Task 9: Hook — psql validation + exec extras

**Files:**
- Modify: `rwl-env/hooks/transform-commands.sh`
- Modify: `rwl-env/tests/test-hooks.sh`

- [ ] **Step 1: Append failing psql tests**

Append to `rwl-env/tests/test-hooks.sh` (before `[[ "$FAIL" -eq 0 ]]`):

```bash
echo "== psql validation =="
use_fixture helm-dev

assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'SELECT 1'" "exec + psql SELECT allowed"
assert_allow "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'EXPLAIN SELECT 1'" "exec + psql EXPLAIN allowed"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'INSERT INTO t VALUES (1)'" "exec + psql INSERT blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'DROP TABLE x'" "exec + psql DROP blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'TRUNCATE x'" "exec + psql TRUNCATE blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -f /tmp/file.sql" "psql -f file form blocked"
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core" "psql with no -c blocked (would start interactive)"

# Multi-statement
assert_block "kubectl --kubeconfig=/tmp/test-kubeconfig --context=k3d-rwl-dev exec -n runwhen core-pg-0 -- env PGPASSWORD=x psql -h 127.0.0.1 -U core -d core -c 'SELECT 1; DROP TABLE x'" "multi-stmt with DDL blocked"
```

- [ ] **Step 2: Run, confirm failures**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: new psql tests FAIL.

- [ ] **Step 3: Replace the exec stub and add psql validation**

In `rwl-env/hooks/transform-commands.sh`, expand the `exec*)` case in the kubectl block:

```bash
        case "$kubectl_sub" in
            exec*)
                # If the inner command invokes psql, validate it.
                if echo "$ORIGINAL_CMD" | grep -qE "[^a-zA-Z0-9_-]psql(\s|$)"; then
                    # Only -c '<query>' form is supported
                    if ! echo "$ORIGINAL_CMD" | grep -qE -- "psql\s+([^|;&]*?\s+)?-c\s+['\"]"; then
                        block "psql via kubectl exec must use -c '<query>' form; -f/stdin/interactive psql are not auto-approvable."
                    fi
                    # Extract query between first matching pair of quotes after -c
                    query=$(echo "$ORIGINAL_CMD" \
                        | sed -n "s/.*psql[^|;&]*-c[[:space:]]*'\\([^']*\\)'.*/\\1/p")
                    if [[ -z "$query" ]]; then
                        # Try double quotes
                        query=$(echo "$ORIGINAL_CMD" \
                            | sed -n 's/.*psql[^|;&]*-c[[:space:]]*"\([^"]*\)".*/\1/p')
                    fi
                    if [[ -z "$query" ]]; then
                        block "could not extract psql -c query for validation; reformulate with single-quoted -c '<query>'."
                    fi
                    # Validate read-only safety
                    validate_psql_query "$query" 2>/tmp/rwl-env-psql-err.$$ || {
                        msg=$(cat /tmp/rwl-env-psql-err.$$)
                        rm -f /tmp/rwl-env-psql-err.$$
                        block "$msg"
                    }
                    rm -f /tmp/rwl-env-psql-err.$$
                fi
                # Interactive shells (sh/bash without psql) pass through
                ;;
            *)
                block "kubectl '$kubectl_sub' not allowed; mutations must go through helm-ops (helm upgrade / rollback)."
                ;;
        esac
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
rwl-env/tests/test-hooks.sh
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add rwl-env/hooks/transform-commands.sh rwl-env/tests/test-hooks.sh
git commit -m "feat(rwl-env): hook validates psql queries via kubectl exec"
```

---

## Phase 3: Env Management Skills

These are markdown SKILL.md files. Verification is jq-validated frontmatter + a manual `claude /<skill-name>` smoke test against a populated `envs.json`.

### Task 10: `/rwl-env-list` skill

**Files:**
- Create: `rwl-env/skills/rwl-env-list/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-env-list/SKILL.md`:

```markdown
---
name: rwl-env-list
description: List all configured rwl-env entries
triggers:
  - /rwl-env-list
  - list rwl-envs
  - show rwl-envs
  - what rwl-envs are available
---

# List rwl-env Entries

List all configured rwl-env entries from `~/.claude/rwl-env/envs.json`.

## Instructions

1. Source the plugin utilities and read envs.json:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
   ```

2. Check the active rwl-env for the current project by reading `.claude/rwl-env`.

3. If `~/.claude/rwl-env/envs.json` doesn't exist, show:
   ```
   No rwl-env entries configured.

   Run /rwl-env-add to register your first deployment.
   ```

4. Otherwise, render a table:

   ```
   rwl-env Entries:

     NAME          CONTEXT             NAMESPACE   RELEASE   READ-ONLY   DESCRIPTION
   * helm-dev      k3d-rwl-dev         runwhen     rwl       No          Local k3d
     helm-staging  gke_..._staging     runwhen     rwl       Yes         Customer staging

   * = active for current directory (<pwd>)

   Use /rwl-env-set <name> to switch.
   Use /rwl-env-cur to see full details.
   ```

5. Mark the active entry with `*`. If no active entry, no marker.

## Implementation

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"

if ! load_envs >/dev/null 2>&1; then
    echo "No rwl-env entries configured."
    echo "Run /rwl-env-add to register your first deployment."
    exit 0
fi

active=""
if get_current_rwlenv >/dev/null 2>&1; then
    active=$(get_current_rwlenv)
fi

printf "rwl-env Entries:\n\n"
printf "  %-14s %-22s %-12s %-10s %-11s %s\n" NAME CONTEXT NAMESPACE RELEASE READ-ONLY DESCRIPTION
load_envs | jq -r '.rwlenvs | to_entries[] |
    [.key, .value.kubernetesContext, .value.namespace, .value.releaseName,
     (if .value.readOnly then "Yes" else "No" end),
     (.value.description // "")] | @tsv' | while IFS=$'\t' read -r name ctx ns rel ro desc; do
    marker=" "; [[ "$name" == "$active" ]] && marker="*"
    printf "%s %-14s %-22s %-12s %-10s %-11s %s\n" "$marker" "$name" "$ctx" "$ns" "$rel" "$ro" "$desc"
done

echo
[[ -n "$active" ]] && echo "* = active for current directory ($PWD)" || echo "(no active rwl-env for $PWD)"
echo "Use /rwl-env-set <name> to switch."
```

## Error Handling

- `envs.json` malformed: surface jq parse error, suggest manual fix.
- Empty `.rwlenvs`: show "No entries yet. Run /rwl-env-add."
```

- [ ] **Step 2: Validate frontmatter parses**

```bash
head -8 rwl-env/skills/rwl-env-list/SKILL.md
```
Expected: `---\nname: rwl-env-list\n...\n---` block.

- [ ] **Step 3: Commit**

```bash
git add rwl-env/skills/rwl-env-list/SKILL.md
git commit -m "feat(rwl-env): /rwl-env-list skill"
```

---

### Task 11: `/rwl-env-cur` skill

**Files:**
- Create: `rwl-env/skills/rwl-env-cur/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-env-cur/SKILL.md`:

```markdown
---
name: rwl-env-cur
description: Show the current rwl-env for this project directory
triggers:
  - /rwl-env-cur
  - current rwl-env
  - which rwl-env
  - show current rwl-env
---

# Show Current rwl-env

Display full details of the rwl-env configured for the current project directory.

## Instructions

1. Check for `.claude/rwl-env-env` in `$PWD`:

   **If missing:** print an error and offer setup:
   ```
   No rwl-env set for this project.
   Current directory: <pwd>

   Run /rwl-env-set <name> or /rwl-env-add to configure one.
   ```
   Then list available entries by reading `${RWLENV_CONFIG_DIR:-~/.claude/rwl-env}/envs.json` (same format as /rwl-env-list).

2. **If present:** source it and display:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
   source .claude/rwl-env-env
   ```

3. Print:
   ```
   Current rwl-env: $RWLENV_NAME

   Kubeconfig:   $RWLENV_KUBECONFIG
   Context:      $RWLENV_CONTEXT
   Namespace:    $RWLENV_NAMESPACE
   Release:      $RWLENV_RELEASE
   Chart:        $RWLENV_CHART_REPO/$RWLENV_CHART_NAME
   Read-Only:    $RWLENV_READ_ONLY
   ```

4. Augment with live helm metadata when reachable:
   ```bash
   helm --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
        get metadata "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" 2>/dev/null
   ```
   Then show:
   ```
   Live Release State:
     Chart version:  <chart>
     App version:    <appVersion>
     Last upgraded:  <timestamp>
     Revision:       <n>
   ```
   If the helm command fails, print "Cluster unreachable (offline?) — cannot show live state."

5. Stale-catalog check:
   ```bash
   catalog_av=$(jq -r '.chartAppVersion' "${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json")
   ```
   If `catalog_av != <live appVersion>`, print:
   ```
   WARNING: Catalog appVersion ($catalog_av) does not match live release. Debug recommendations may be stale.
   ```

6. Read-only warning:
   ```
   WARNING: This rwl-env is READ-ONLY. helm upgrade and helm rollback are blocked.
   ```

## Error Handling

- Missing `envs.json` is fine — runtime env file is self-contained.
- helm/kubectl errors are non-fatal: report and continue.
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/skills/rwl-env-cur/SKILL.md
git commit -m "feat(rwl-env): /rwl-env-cur skill"
```

---

### Task 12: `/rwl-env-set` skill

**Files:**
- Create: `rwl-env/skills/rwl-env-set/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-env-set/SKILL.md`:

```markdown
---
name: rwl-env-set
description: Set the active rwl-env for the current project directory
triggers:
  - /rwl-env-set
  - switch rwl-env
  - use rwl-env
  - set rwl-env
args:
  - name: rwlenv_name
    description: Name of the rwl-env to activate (prompted if omitted)
    required: false
---

# Set Active rwl-env

Switch the active rwl-env for `$PWD`. Writes `.claude/rwl-env` (plain text) and `.claude/rwl-env-env` (resolved KV). Both auto-gitignored.

## Instructions

1. **Determine target name:**
   - If user passed a name: validate it exists in `envs.json`.
   - Otherwise: list entries via `list_rwlenv_names` and prompt with `AskUserQuestion`.

2. **Check current state:**
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
   current=$(get_current_rwlenv 2>/dev/null) || current=""
   ```
   - If `current == target`: report "Already active." and exit.
   - If different: AskUserQuestion to confirm switch.

3. **Write files:**
   ```bash
   set_rwlenv_for_dir "$PWD" "$target"
   write_rwlenv_env "$PWD" "$target"
   ```

4. **Display confirmation** using `format_rwlenv_details`:
   ```bash
   format_rwlenv_details "$target"
   ```

5. **Read-only warning** (if applicable):
   ```
   WARNING: This rwl-env is READ-ONLY. The following are blocked:
     - helm upgrade, helm rollback
   Reads (helm get/history/status, kubectl get/logs/events, psql SELECT) remain allowed.
   ```

## Error Handling

**Unknown name:**
```
ERROR: rwl-env '<name>' not found.

Available:
  - helm-dev
  - helm-staging

Use /rwl-env-set <name> with one of the above, or /rwl-env-add to create a new entry.
```

**envs.json missing:**
```
ERROR: rwl-env config not found at ~/.claude/rwl-env/envs.json.
Run /rwl-env-add to create your first entry.
```

**`set_rwlenv_for_dir` returns non-zero:** surface the stderr message; do not proceed to `write_rwlenv_env`.

## Natural Language

- "switch to helm-staging" → `target=helm-staging`
- "use helm-dev for this project" → `target=helm-dev`
- "set rwl-env to production" → if exact match fails, suggest closest by substring.
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/skills/rwl-env-set/SKILL.md
git commit -m "feat(rwl-env): /rwl-env-set skill"
```

---

### Task 13: `/rwl-env-add` skill (interactive add with kubeconfig discovery)

**Files:**
- Create: `rwl-env/skills/rwl-env-add/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-env-add/SKILL.md`:

```markdown
---
name: rwl-env-add
description: Interactively register a new rwl-env entry
triggers:
  - /rwl-env-add
  - add rwl-env
  - register helm deployment
  - new rwl-env
args:
  - name: rwlenv_name
    description: Optional name; prompted if omitted
    required: false
  - name: kubeconfig
    description: Optional --kubeconfig path
    required: false
  - name: context
    description: Optional --context name
    required: false
---

# Add rwl-env Entry

Interactively register a new helm-deployed RunWhen platform install. Walks through name, kubeconfig discovery, context, namespace, release name, chart source, read-only mode.

## Instructions

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/rwlenv-utils.sh"
```

### Step 1: Name

If not provided, prompt:
```
What name for this rwl-env? (alphanumeric + hyphens)
Examples: helm-dev, helm-staging, customer-acme
```

Validate:
- Format: `^[a-z0-9-]+$`
- Not already in `envs.json` (error: "rwl-env '<name>' already exists.")

### Step 2: Description

Prompt:
```
Short description (e.g., 'Local k3d', 'Customer staging install'):
```

### Step 3: Kubeconfig resolution

**If `--kubeconfig` was passed:** validate the file exists, then use it.

**If `--context` was passed but no `--kubeconfig`:**
1. First, probe `~/.kube/config`:
   ```bash
   if list_contexts_in_file ~/.kube/config | grep -qxF "$context"; then
       kubeconfig=~/.kube/config
   fi
   ```
2. If not found, scan with `find_context_across_files`:
   ```bash
   matches=$(find_context_across_files "$context")
   match_count=$(echo "$matches" | grep -c '.')
   ```
3. Branch on count:
   - **1 match:** record (file, context). Show:
     ```
     Found context '<ctx>' in <file>
     ```
   - **>1:** AskUserQuestion with each `(file, context)` pair as an option.
   - **0:** error and list all contexts seen across scanned files:
     ```
     ERROR: Context '<ctx>' not found in any kubeconfig under ~/.kube/.

     Contexts seen:
       - ~/.kube/config: ctx-a, ctx-b
       - ~/.kube/staging.yaml: ctx-c

     Pass --kubeconfig <path> explicitly or use a different --context.
     ```

**If neither was passed:**
1. Default kubeconfig to `~/.kube/config` (or error if missing).
2. List contexts via `list_contexts_in_file ~/.kube/config`.
3. AskUserQuestion to pick.

**Validation (soft):**
```bash
kubectl --kubeconfig="$kubeconfig" --context="$context" auth can-i get pods 2>/dev/null \
    || echo "WARNING: Could not reach cluster (offline?). Continuing anyway."
```

### Step 4: Namespace

Prompt:
```
Which namespace is the helm release in?
```

Validate:
```bash
kubectl --kubeconfig="$kubeconfig" --context="$context" get ns "$ns" 2>/dev/null \
    || echo "WARNING: Namespace '$ns' not found via current credentials. Continuing anyway."
```

### Step 5: Release name

```bash
releases=$(helm --kubeconfig="$kubeconfig" --kube-context="$context" list -n "$ns" -o json 2>/dev/null | jq -r '.[].name')
count=$(echo "$releases" | grep -c '.')
```

Branch:
- **1:** auto-fill, show: `Using release '<name>' (only release in namespace).`
- **>1:** AskUserQuestion with each release name as an option.
- **0:** error: `No helm releases in namespace <ns> on context <ctx>. Is the chart installed?`

### Step 6: Chart repo + name

`chartName` is inferred from `helm get metadata`:
```bash
chartName=$(helm --kubeconfig="$kubeconfig" --kube-context="$context" \
    get metadata "$release" -n "$ns" 2>/dev/null | grep -E '^CHART:' | awk '{print $2}' | sed 's/-[0-9].*//')
```

Show inferred `chartName` and ask to confirm or override.

For `chartRepo`, AskUserQuestion with options:
- "OCI registry (oci://...)"
- "HTTPS chart museum (https://...)"

Then prompt for the URL.

Soft-validate:
```bash
helm show chart "$chartRepo/$chartName" 2>/dev/null \
    || echo "WARNING: Could not fetch chart from $chartRepo. Recording anyway."
```

### Step 7: Read-only mode

AskUserQuestion:
- "No (read-write) — allow helm upgrade/rollback" (default for dev)
- "Yes (read-only) — block all mutations" (recommended for shared/staging)

### Step 8: Set as active for current directory?

AskUserQuestion:
- "Yes, activate for $PWD"
- "No, just save the entry"

If yes:
```bash
set_rwlenv_for_dir "$PWD" "$name"
write_rwlenv_env "$PWD" "$name"
```

### Step 9: Save

Atomic jq merge into `envs.json`:

```bash
envs_file="${RWLENV_CONFIG_DIR:-$HOME/.claude/rwl-env}/envs.json"
mkdir -p "$(dirname "$envs_file")"
[[ -f "$envs_file" ]] || echo '{"version":"1.0","rwlenvs":{}}' > "$envs_file"

new_entry=$(jq -n \
    --arg desc "$description" \
    --arg kp "$kubeconfig" \
    --arg ctx "$context" \
    --arg ns "$ns" \
    --arg rel "$release" \
    --arg cr "$chartRepo" \
    --arg cn "$chartName" \
    --argjson ro $readOnly \
    '{description:$desc, kubeconfigPath:$kp, kubernetesContext:$ctx, namespace:$ns, releaseName:$rel, chart:{repo:$cr, name:$cn}, readOnly:$ro}')

jq --arg name "$name" --argjson entry "$new_entry" '.rwlenvs[$name] = $entry' "$envs_file" \
    > "${envs_file}.tmp" && mv "${envs_file}.tmp" "$envs_file"
```

### Step 10: Confirm

```
rwl-env 'helm-dev' created.

  Description:  Local k3d cluster
  Kubeconfig:   /Users/rohitekbote/.kube/config
  Context:      k3d-rwl-dev
  Namespace:    runwhen
  Release:      rwl
  Chart:        oci://registry.example.com/charts/runwhen-platform
  Read-Only:    No
  Active for:   /Users/rohitekbote/wd/myproject

Use /rwl-env-cur for full details (including live helm metadata).
Use /rwl-env-list to see all entries.
```

## Error Handling

- `~/.kube/` missing → "No kubeconfig found. Create `~/.kube/config` or pass `--kubeconfig`."
- Kubeconfig file unreadable/malformed → skip during scan, warn to stderr, continue.
- `$KUBECONFIG` set with multiple files → split on `:`, include each.
- User aborts (Ctrl-C) → no partial write; the jq merge in Step 9 is the last write.
- Name collision: refuse with "rwl-env '<name>' already exists. Use a different name or edit envs.json manually."
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/skills/rwl-env-add/SKILL.md
git commit -m "feat(rwl-env): /rwl-env-add skill with kubeconfig discovery"
```

---

## Phase 4: Data Files

These tasks author the static knowledge files referenced by debug skills and the bug-report flow. They require reading the helm chart at `/Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/` and the application source repos listed in the design doc's "Reference Material" section.

### Task 14: `data/services-catalog.json` — skeleton + deployment-graph fields

Goal: author the catalog with every first-party service + every subchart, with `imageTagKey`, `namespace`, `podSelector`, `containerName`, `internalPort`, `probes`, and `deploymentWaitFor`. No `runtime` blocks yet — that's Task 15.

**Files:**
- Create: `rwl-env/data/services-catalog.json`

**Reference sources** (read-only):
- Helm templates: `/Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/templates/`
- Values file: `/Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/values.yaml`
- Chart metadata: `/Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/Chart.yaml`

- [ ] **Step 1: Read Chart.yaml and capture appVersion + chartName**

```bash
yq '.appVersion' /Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/Chart.yaml
yq '.name' /Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/Chart.yaml
```

Record both for the catalog header.

- [ ] **Step 2: Enumerate first-party services from templates/**

```bash
ls /Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/templates/
```

The directory entries that contain a `deployment.yaml` or `statefulset.yaml` are first-party services. Expect ~25 entries: activities, agentfarm, alert-ingestor, alert-query, alert-worker, alerts, cc-catalog-svc, embedder, llm-bootstrap, llm-gateway, mcp-server, metricstore, migration-controller, papi, runner-control, runner-metric-proxy, slackbot, sobow-index, sobow-search, sobrain, taskiq-scheduler, taskiq-worker, usearch, user-pages, webhooks.

- [ ] **Step 3: For each service, extract fields from its template**

For each `templates/<svc>/deployment.yaml` (or `statefulset.yaml`), read:
- `metadata.labels` → derive `podSelector` (e.g., `app=<svc>`)
- `spec.template.spec.containers[0].name` → `containerName`
- `spec.template.spec.containers[0].image` → derive the `imageTagKey` by cross-referencing `values.yaml` (find which `images.<svcKey>.tag` substitutes into that template line)
- `spec.template.spec.containers[0].ports` → `internalPort`
- `spec.template.spec.containers[0].readinessProbe.httpGet.path` → `probes.readiness`
- `spec.template.spec.containers[0].livenessProbe.httpGet.path` → `probes.liveness`
- `spec.template.spec.initContainers[*].name` → `deploymentWaitFor` (names of wait-for-X init containers)

Use this script as a starting point (run from the helm chart dir):
```bash
cd /Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform
for svc_dir in templates/*/; do
    svc=$(basename "$svc_dir")
    for f in "$svc_dir"deployment.yaml "$svc_dir"statefulset.yaml; do
        [[ -f "$f" ]] || continue
        echo "--- $svc ($f) ---"
        grep -E 'image:|containerPort:|path:|readinessProbe|livenessProbe|initContainers:|- name:' "$f" | head -30
    done
done
```

This output guides hand-authoring. Many fields use helm templating (e.g., `{{ .Values.images.backendServices.tag }}`) — record the value-path, not the rendered output.

- [ ] **Step 4: Build the catalog with deployment-graph fields**

Write `rwl-env/data/services-catalog.json`. Structure:

```json
{
  "version": "1.0",
  "chartAppVersion": "1.0.0",
  "chartName": "runwhen-platform",
  "services": {
    "papi": {
      "description": "Public REST API",
      "namespace": "<rwl-env-ns>",
      "imageTagKey": "images.backendServices.tag",
      "podSelector": "app=papi",
      "containerName": "papi",
      "internalPort": 8080,
      "probes": { "readiness": "/healthz", "liveness": "/healthz" },
      "deploymentWaitFor": ["db-init", "vault-init", "migration-controller"]
    },
    "agentfarm": {
      "description": "Agent farm runtime",
      "namespace": "<rwl-env-ns>",
      "imageTagKey": "images.agentfarm.tag",
      "podSelector": "app=agentfarm",
      "containerName": "agentfarm",
      "internalPort": 8000,
      "probes": { "readiness": "/healthz", "liveness": "/healthz" },
      "deploymentWaitFor": ["vault-init", "migration-controller"]
    },
    "embedder":            { "_TODO_": "fill from templates/embedder/deployment.yaml" },
    "llm-gateway":         { "_TODO_": "fill from templates/llm-gateway/deployment.yaml" },
    "mcp-server":          { "_TODO_": "fill from templates/mcp-server/deployment.yaml" },
    "migration-controller":{ "_TODO_": "fill from templates/migration-controller/statefulset.yaml" },
    "taskiq-scheduler":    { "_TODO_": "fill" },
    "taskiq-worker":       { "_TODO_": "fill" },
    "sobow-search":        { "_TODO_": "fill" },
    "sobow-index":         { "_TODO_": "fill" },
    "sobrain":             { "_TODO_": "fill" },
    "alerts":              { "_TODO_": "fill" },
    "alert-ingestor":      { "_TODO_": "fill" },
    "alert-query":         { "_TODO_": "fill" },
    "alert-worker":        { "_TODO_": "fill" },
    "activities":          { "_TODO_": "fill" },
    "user-pages":          { "_TODO_": "fill" },
    "webhooks":            { "_TODO_": "fill" },
    "cc-catalog-svc":      { "_TODO_": "fill" },
    "runner-control":      { "_TODO_": "fill" },
    "runner-metric-proxy": { "_TODO_": "fill" },
    "usearch":             { "_TODO_": "fill" },
    "metricstore":         { "_TODO_": "fill" },
    "llm-bootstrap":       { "_TODO_": "fill" },
    "slackbot":            { "_TODO_": "fill" }
  },
  "databases": {},
  "subcharts": {}
}
```

Replace every `_TODO_` entry with real fields. Use the same shape as `papi`. **The `_TODO_` markers MUST all be removed before the commit.** Verify with:
```bash
! grep -q '_TODO_' rwl-env/data/services-catalog.json && echo "no TODOs remaining"
```

- [ ] **Step 5: Validate JSON parses**

```bash
jq . rwl-env/data/services-catalog.json >/dev/null && echo "JSON OK"
jq '.services | keys | length' rwl-env/data/services-catalog.json
```
Expected: `JSON OK`, then ~25 service keys.

- [ ] **Step 6: Commit**

```bash
git add rwl-env/data/services-catalog.json
git commit -m "feat(rwl-env): services-catalog.json deployment-graph fields"
```

---

### Task 15: `services-catalog.json` — runtime blocks for priority services

Add the `runtime` block (summary, callsOut, calledBy, knownFailureChains) to the 7 priority services by reading their application source code.

**Files:**
- Modify: `rwl-env/data/services-catalog.json`

**Source repos** (read-only references):

| Service | Repo |
|---|---|
| papi | `/Users/rohitekbote/wd/code/github.com/project-468/468-platform/backend-services-v2` |
| agentfarm | `/Users/rohitekbote/wd/code/github.com/runwhen/agentfarm` |
| migration-controller | `/Users/rohitekbote/wd/code/github.com/runwhen/agentfarm` (shares the same image; runs `webapp/migration_controller.py`) |
| taskiq-worker | `/Users/rohitekbote/wd/code/github.com/runwhen/agentfarm` (or backend-services-v2; confirm by tag-key in values.yaml) |
| sobow-search | `/Users/rohitekbote/wd/code/github.com/project-468/468-platform/backend-services-v2` |
| sobrain | `/Users/rohitekbote/wd/code/github.com/project-468/468-platform/backend-services-v2` |
| embedder | Repo path **TBD** — if not provided, skip the `runtime` block and leave a comment in the catalog. |
| llm-gateway | Third-party (litellm). Use chart values.yaml comments + INSTALL-FRICTIONS only — no source read. |

- [ ] **Step 1: For each priority service, identify outbound calls in the source**

For each repo, grep for service URL patterns. Examples:
```bash
# In backend-services-v2 (papi)
grep -RnEi 'http(s)?://[a-z-]+(\.|:)|grpc://|service\.' /Users/rohitekbote/wd/code/github.com/project-468/468-platform/backend-services-v2/papi/ | head -40

# In agentfarm
grep -RnEi 'requests\.(get|post)|httpx\.|grpc\.|VAULT_ADDR|LLM_GATEWAY' /Users/rohitekbote/wd/code/github.com/runwhen/agentfarm/ | head -40
```

Identify the service names called (papi → alert-query, papi → usearch, etc.). Cross-reference with the K8s `Service` objects in `templates/<other-svc>/service.yaml` to confirm names.

- [ ] **Step 2: For each priority service, add the runtime block**

Edit `rwl-env/data/services-catalog.json`. For each priority service, append:

```json
"runtime": {
  "summary": "<one sentence — what does this service do at runtime>",
  "callsOut": ["<svc1>", "<svc2>", "postgres:<db>", "redis", "vault"],
  "calledBy": ["<who calls it>"],
  "knownFailureChains": [
    {
      "symptom": "<short symptom>",
      "checkOrder": ["<first thing to check>", "<next>", "<...>"],
      "skill": "rwl-debug-<topic>"
    }
  ]
}
```

Example (papi, fully filled):

```json
"papi": {
  "description": "Public REST API",
  "namespace": "<rwl-env-ns>",
  "imageTagKey": "images.backendServices.tag",
  "podSelector": "app=papi",
  "containerName": "papi",
  "internalPort": 8080,
  "probes": { "readiness": "/healthz", "liveness": "/healthz" },
  "deploymentWaitFor": ["db-init", "vault-init", "migration-controller"],
  "runtime": {
    "summary": "REST entrypoint; fans out to alert-* services, usearch, and core DB.",
    "callsOut": ["alert-query", "alert-worker", "usearch", "vault", "redis", "postgres:core"],
    "calledBy": ["user-pages", "external clients via ingress"],
    "knownFailureChains": [
      {
        "symptom": "5xx on /api/v1/alerts",
        "checkOrder": ["alert-query pod ready", "redis reachable", "postgres core writable"],
        "skill": "rwl-debug-papi"
      }
    ]
  }
}
```

For **embedder**, if the source repo is unavailable, leave a JSON comment-free placeholder:
```json
"embedder": {
  "description": "Embedding service (shared-services image)",
  "namespace": "<rwl-env-ns>",
  "imageTagKey": "images.embedder.tag",
  "podSelector": "app=embedder",
  "containerName": "embedder",
  "internalPort": 8080,
  "probes": { "readiness": "/healthz", "liveness": "/healthz" },
  "deploymentWaitFor": []
}
```
(No `runtime` block.)

- [ ] **Step 3: Validate and commit**

```bash
jq '.services | to_entries | map(select(.value.runtime != null)) | length' rwl-env/data/services-catalog.json
```
Expected: 6 or 7 (depending on whether embedder source was available).

```bash
git add rwl-env/data/services-catalog.json
git commit -m "feat(rwl-env): runtime blocks for priority services"
```

---

### Task 16: `services-catalog.json` — databases + subcharts

**Files:**
- Modify: `rwl-env/data/services-catalog.json`

- [ ] **Step 1: Identify Postgres databases from chart templates**

```bash
ls /Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/templates/postgresql/
grep -rE 'database|secretName|pgbouncer' /Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/templates/postgresql/ | head -40
```

Identify Postgres clusters (e.g., `core`, `usearch`, `agentfarm`) and for each:
- secret name pattern (`<release>-pguser-<db>` typical for Spilo)
- service selector / fallback service name
- database name + username
- which services consume it (cross-reference `consumedBy`)

- [ ] **Step 2: Add `databases` section**

In `rwl-env/data/services-catalog.json`, replace `"databases": {}` with:

```json
"databases": {
  "core": {
    "description": "Core platform DB (papi, alerts, taskiq)",
    "secretNamePattern": "<release>-pguser-core",
    "serviceLabelSelector": "app.kubernetes.io/instance=<release>,application=spilo,cluster-name=<release>-core",
    "fallbackServiceName": "<release>-core-pgbouncer",
    "database": "core",
    "username": "core",
    "consumedBy": ["papi", "alerts", "taskiq-worker", "taskiq-scheduler", "activities"]
  },
  "usearch": {
    "description": "Search index DB",
    "secretNamePattern": "<release>-pguser-usearch",
    "serviceLabelSelector": "app.kubernetes.io/instance=<release>,application=spilo,cluster-name=<release>-usearch",
    "fallbackServiceName": "<release>-usearch-pgbouncer",
    "database": "usearch",
    "username": "usearch",
    "consumedBy": ["usearch"]
  },
  "agentfarm": {
    "description": "Agent farm DB",
    "secretNamePattern": "<release>-pguser-agentfarm",
    "serviceLabelSelector": "app.kubernetes.io/instance=<release>,application=spilo,cluster-name=<release>-agentfarm",
    "fallbackServiceName": "<release>-agentfarm-pgbouncer",
    "database": "app_users",
    "username": "agentfarm",
    "consumedBy": ["agentfarm", "migration-controller"]
  }
}
```

**Verify each value against the actual rendered Spilo templates before committing.** The patterns above are illustrative; correct names come from the chart.

- [ ] **Step 3: Add `subcharts` section**

Replace `"subcharts": {}` with:

```json
"subcharts": {
  "vault":      { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=vault",      "knownIssues": ["sealed after restart", "unsealer crashloop"] },
  "redis":      { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=redis",      "knownIssues": [] },
  "neo4j":      { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=neo4j",      "knownIssues": [] },
  "qdrant":     { "namespace": "<rwl-env-ns>", "selector": "app=qdrant",                        "knownIssues": ["does not support NFS for main data volume"] },
  "seaweedfs":  { "namespace": "<rwl-env-ns>", "selector": "app.kubernetes.io/name=seaweedfs",  "knownIssues": [] },
  "postgresql": { "namespace": "<rwl-env-ns>", "selector": "application=spilo",                 "knownIssues": [] }
}
```

- [ ] **Step 4: Validate and commit**

```bash
jq . rwl-env/data/services-catalog.json >/dev/null && echo "JSON OK"
jq '.databases | keys | length' rwl-env/data/services-catalog.json   # expect 3
jq '.subcharts | keys | length' rwl-env/data/services-catalog.json   # expect 6
```

```bash
git add rwl-env/data/services-catalog.json
git commit -m "feat(rwl-env): databases and subcharts sections"
```

---

### Task 17: `data/workflows-index.json`

Author the symptom-to-skill mapping from `INSTALL-FRICTIONS.md`.

**Files:**
- Create: `rwl-env/data/workflows-index.json`

- [ ] **Step 1: Read INSTALL-FRICTIONS.md and enumerate friction sections**

```bash
grep -E '^##|^###' /Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/INSTALL-FRICTIONS.md | head -80
```

Each numbered/named friction is a candidate symptom entry. Cluster them by topic into the 7 debug skills:
- `rwl-debug-pod` (generic crashloop / pending)
- `rwl-debug-image-pull` (ImagePullBackOff)
- `rwl-debug-migrations` (db-init / migration-controller hangs)
- `rwl-debug-vault` (vault sealed, unsealer issues)
- `rwl-debug-papi` (papi runtime failures)
- `rwl-debug-agentfarm` (agentfarm runtime)
- `rwl-debug-llm` (llm-bootstrap / llm-gateway / provider config)

- [ ] **Step 2: Write workflows-index.json**

Write `rwl-env/data/workflows-index.json` with at least 8 symptom entries spread across the 7 skills:

```json
{
  "version": "1.0",
  "chartAppVersion": "1.0.0",
  "symptoms": {
    "pod-stuck-init-wait-for-migrations": {
      "matchHints": ["initContainer wait-for-migrations", "migration-controller CrashLoop"],
      "skill": "rwl-debug-migrations",
      "likelyCauses": [
        "agentfarm image predates webapp/migration_controller.py",
        "db-init-job failed",
        "core DB not reachable from migration-controller"
      ],
      "firstChecks": [
        "kubectl logs <release>-migration-controller-0 -c migration-controller",
        "helm get values <release> | yq .images.agentfarm.tag",
        "kubectl get job <release>-db-init -o yaml"
      ]
    },
    "image-pull-backoff": {
      "matchHints": ["ImagePullBackOff", "ErrImagePull"],
      "skill": "rwl-debug-image-pull",
      "likelyCauses": [
        "missing or wrong imagePullSecrets",
        "registry override misconfigured",
        "airgap mirror not populated for this tag",
        "bitnami subchart pointed at retired free-tier tag"
      ],
      "firstChecks": [
        "kubectl describe pod <pod> | grep -A5 Events",
        "kubectl get secret <pull-secret> -o yaml",
        "helm get values <release> | yq '.global.imagePullSecrets, .registryOverride'"
      ]
    },
    "vault-sealed": {
      "matchHints": ["vault: Vault is sealed", "503 service unavailable from vault"],
      "skill": "rwl-debug-vault",
      "likelyCauses": ["vault-unsealer CrashLoopBackOff", "vault-init-job never completed", "unseal key secret missing"],
      "firstChecks": [
        "kubectl get pod -l app.kubernetes.io/name=vault",
        "kubectl logs deploy/vault-unsealer",
        "kubectl get job <release>-vault-init -o yaml"
      ]
    },
    "papi-5xx-alerts": {
      "matchHints": ["papi", "5xx", "/api/v1/alerts"],
      "skill": "rwl-debug-papi",
      "likelyCauses": ["alert-query pod down", "redis unreachable", "core DB read failure"],
      "firstChecks": [
        "kubectl get pod -l app=alert-query",
        "kubectl logs deploy/papi --tail=100",
        "kubectl logs deploy/alert-query --tail=100"
      ]
    },
    "agentfarm-llm-failures": {
      "matchHints": ["agentfarm", "llm timeout", "provider error"],
      "skill": "rwl-debug-agentfarm",
      "likelyCauses": ["llm-gateway misconfigured", "vault path missing provider key", "llm-bootstrap did not seed config"],
      "firstChecks": [
        "kubectl logs deploy/agentfarm --tail=200",
        "kubectl logs deploy/llm-gateway --tail=100",
        "kubectl get cm llmconfig -o yaml"
      ]
    },
    "llm-bootstrap-failure": {
      "matchHints": ["llm-bootstrap", "CrashLoop", "vault path"],
      "skill": "rwl-debug-llm",
      "likelyCauses": ["vault sealed", "missing provider key in llmconfig", "vault policy denies write"],
      "firstChecks": [
        "kubectl logs job/<release>-llm-bootstrap",
        "kubectl get cm llmconfig -o yaml",
        "kubectl exec vault-0 -- vault status"
      ]
    },
    "generic-crashloop": {
      "matchHints": ["CrashLoopBackOff", "Error", "OOMKilled"],
      "skill": "rwl-debug-pod",
      "likelyCauses": ["misconfigured env var", "OOM", "missing secret", "init container failed"],
      "firstChecks": [
        "kubectl describe pod <pod>",
        "kubectl logs <pod> --previous",
        "kubectl get events --field-selector involvedObject.name=<pod>"
      ]
    },
    "pending-pod": {
      "matchHints": ["Pending", "FailedScheduling", "0/N nodes available"],
      "skill": "rwl-debug-pod",
      "likelyCauses": ["resource pressure", "nodeSelector mismatch", "PVC pending", "image pull secret missing for new namespace"],
      "firstChecks": [
        "kubectl describe pod <pod> | grep -A10 Events",
        "kubectl get pvc -n <ns>",
        "kubectl describe node"
      ]
    }
  }
}
```

**Augment with more entries derived from INSTALL-FRICTIONS.md before committing.** Aim for 12–15 total entries to give the dispatcher meaningful coverage.

- [ ] **Step 3: Validate and commit**

```bash
jq . rwl-env/data/workflows-index.json >/dev/null && echo "JSON OK"
jq '.symptoms | keys | length' rwl-env/data/workflows-index.json
```

```bash
git add rwl-env/data/workflows-index.json
git commit -m "feat(rwl-env): workflows-index.json with symptom-to-skill mapping"
```

---

### Task 18: Catalog schema tests

**Files:**
- Create: `rwl-env/tests/test-catalog.sh`

- [ ] **Step 1: Write schema test**

Write `rwl-env/tests/test-catalog.sh`:

```bash
#!/usr/bin/env bash
# test-catalog.sh - Validate services-catalog.json and workflows-index.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

CATALOG="$PLUGIN_DIR/data/services-catalog.json"
WORKFLOWS="$PLUGIN_DIR/data/workflows-index.json"

PASS=0; FAIL=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s\n" "$desc"; FAIL=$((FAIL+1))
    fi
}

echo "== services-catalog.json =="
check "JSON parses" jq . "$CATALOG"
check "has chartAppVersion" jq -e '.chartAppVersion' "$CATALOG"
check "has chartName" jq -e '.chartName' "$CATALOG"
check "every service has imageTagKey" jq -e '.services | to_entries | map(select(.value.imageTagKey == null)) | length == 0' "$CATALOG"
check "every service has namespace" jq -e '.services | to_entries | map(select(.value.namespace == null)) | length == 0' "$CATALOG"
check "every service has podSelector" jq -e '.services | to_entries | map(select(.value.podSelector == null)) | length == 0' "$CATALOG"
check "no _TODO_ remaining" sh -c "! grep -q '_TODO_' '$CATALOG'"

# Cross-ref: every runtime.callsOut entry should be a known service, database, or subchart, OR a recognized prefix
check "callsOut references resolve" bash -c '
catalog="'"$CATALOG"'"
all_targets=$(jq -r "(.services|keys[]),(.databases|keys|map(\"postgres:\"+.)|.[]),(.subcharts|keys[]),\"redis\",\"vault\",\"qdrant\",\"neo4j\",\"seaweedfs\"" "$catalog" | sort -u)
unknown=$(jq -r ".services | to_entries[] | select(.value.runtime.callsOut) | .value.runtime.callsOut[]" "$catalog" | sort -u | while read -r t; do
    echo "$all_targets" | grep -qxF "$t" || echo "$t"
done)
[[ -z "$unknown" ]]
'

# Cross-ref: every consumedBy entry should be a known service
check "consumedBy references resolve" bash -c '
catalog="'"$CATALOG"'"
services=$(jq -r ".services | keys[]" "$catalog" | sort -u)
unknown=$(jq -r ".databases | to_entries[] | select(.value.consumedBy) | .value.consumedBy[]" "$catalog" | sort -u | while read -r s; do
    echo "$services" | grep -qxF "$s" || echo "$s"
done)
[[ -z "$unknown" ]]
'

echo "== workflows-index.json =="
check "JSON parses" jq . "$WORKFLOWS"
check "has chartAppVersion" jq -e '.chartAppVersion' "$WORKFLOWS"
check "every symptom has skill" jq -e '.symptoms | to_entries | map(select(.value.skill == null)) | length == 0' "$WORKFLOWS"
check "every symptom has matchHints" jq -e '.symptoms | to_entries | map(select(.value.matchHints == null or (.value.matchHints | length == 0))) | length == 0' "$WORKFLOWS"

# Cross-ref: every workflow skill should map to a skills/<skill>/SKILL.md file
check "every workflow skill exists as a file" bash -c '
skills=$(jq -r ".symptoms | to_entries[] | .value.skill" "'"$WORKFLOWS"'" | sort -u)
missing=$(for s in $skills; do
    [[ -f "'"$PLUGIN_DIR"'/skills/$s/SKILL.md" ]] || echo "$s"
done)
[[ -z "$missing" ]]
'

# Chart appVersion consistency
check "catalog and workflows agree on chartAppVersion" bash -c '
a=$(jq -r ".chartAppVersion" "'"$CATALOG"'")
b=$(jq -r ".chartAppVersion" "'"$WORKFLOWS"'")
[[ "$a" == "$b" ]]
'

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
```

Make executable:
```bash
chmod +x rwl-env/tests/test-catalog.sh
```

- [ ] **Step 2: Run the test**

```bash
rwl-env/tests/test-catalog.sh
```

NOTE: The "every workflow skill exists as a file" check will fail until Phase 7 lands. That's expected at this point; the catalog tests serve as the gate for Phase 7's completion.

Mark the file-existence assertion expected-to-fail-for-now in the task notes; when Phase 7 completes, this test should be re-run and confirmed green.

- [ ] **Step 3: Commit**

```bash
git add rwl-env/tests/test-catalog.sh
git commit -m "feat(rwl-env): catalog schema tests"
```

---

## Phase 5: Agents

Three agent docs. Each declares triggers, capabilities, command patterns, and explicit refusals.

### Task 19: `agents/helm-ops.md`

**Files:**
- Create: `rwl-env/agents/helm-ops.md`

- [ ] **Step 1: Write agent doc**

Write `rwl-env/agents/helm-ops.md`:

```markdown
---
name: helm-ops
description: Autonomous helm operations agent for rwl-env (get, upgrade, rollback, history)
triggers:
  - helm operations
  - helm upgrade
  - helm rollback
  - helm history
  - helm get values
---

# rwl-env Helm Operations Agent

Autonomous agent for helm read and write operations against the active rwl-env release. **Never calls `helm install` or `helm uninstall`** — release lifecycle is out of scope for this plugin.

## Prerequisites

1. **Source the runtime env file** from the working directory:
   ```bash
   source .claude/rwl-env-env
   ```
   If missing, abort with: "No rwl-env set for this project. Run /rwl-env-set first."

2. **Required env vars after sourcing:** `RWLENV_NAME`, `RWLENV_KUBECONFIG`, `RWLENV_CONTEXT`, `RWLENV_NAMESPACE`, `RWLENV_RELEASE`, `RWLENV_CHART_REPO`, `RWLENV_CHART_NAME`, `RWLENV_READ_ONLY`. If any are empty, abort.

3. **readOnly check:** before any write op, verify `[[ "$RWLENV_READ_ONLY" != "true" ]]`. If readOnly, refuse with: "rwl-env '$RWLENV_NAME' is read-only; helm mutations blocked."

## Command Pattern

Every helm invocation MUST include:
```bash
helm \
  --kubeconfig="$RWLENV_KUBECONFIG" \
  --kube-context="$RWLENV_CONTEXT" \
  -n "$RWLENV_NAMESPACE" \
  <subcommand> "$RWLENV_RELEASE" <args>
```

The PreToolUse hook validates these flags and the release name. Omitting any will block.

## Capabilities

### Reads

| Subcommand | Purpose |
|---|---|
| `helm get values $RWLENV_RELEASE` | Current values (use `-o yaml`) |
| `helm get manifest $RWLENV_RELEASE` | Rendered K8s manifests |
| `helm get metadata $RWLENV_RELEASE` | Chart name, version, app version, revision |
| `helm history $RWLENV_RELEASE` | Revision log (add `-o json` for parsing) |
| `helm status $RWLENV_RELEASE` | Current release status |

### Writes

| Subcommand | Purpose | Required flags |
|---|---|---|
| `helm upgrade $RWLENV_RELEASE $RWLENV_CHART_REPO/$RWLENV_CHART_NAME --reuse-values --version <X>` | Update values / chart version | `--reuse-values` always; `--version` matches current unless intentionally bumping |
| `helm rollback $RWLENV_RELEASE <revision>` | Restore prior revision | revision number from `helm history` |

For per-call chart overrides (offline / airgap), accept a `--chart <local-path>` flag from the calling skill and substitute that for the `$RWLENV_CHART_REPO/$RWLENV_CHART_NAME` argument.

### Explicitly refused

- `helm install`, `helm uninstall`, `helm delete`, `helm repo add`, `helm repo remove`, `helm dependency *` — out of scope. If asked, respond: "Release lifecycle is out of scope for rwl-env. Use the helm CLI directly outside Claude Code."

## Capturing pre-upgrade state

Before every write, capture the prior revision so callers can construct a rollback command:

```bash
prior_rev=$(helm --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
    history "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" -o json | jq -r '.[-1].revision')
```

Return this in the structured result so the caller can prompt: "Rollback hint: /rwl-rollback --to-revision $prior_rev".

## Structured result

After every operation, return:

```
{
  "ok": true|false,
  "subcommand": "upgrade|rollback|get values|...",
  "revisionBefore": <int>,
  "revisionAfter": <int>,
  "valuesDiff": "<yq diff output, optional>",
  "chartVersionBefore": "<semver>",
  "chartVersionAfter": "<semver>",
  "stderr": "<helm stderr if any>"
}
```

## Error handling

- **Cluster unreachable:** surface helm's exact stderr. Distinguish wrong-context (list contexts) vs auth-expired vs DNS.
- **Release missing:** "Helm release '$RWLENV_RELEASE' not in namespace '$RWLENV_NAMESPACE' on context '$RWLENV_CONTEXT'. Run /rwl-env-cur to verify."
- **Lock contention** (`another operation in progress`): do not retry; report and suggest `helm history` to inspect.
- **Chart fetch failure:** surface helm error; suggest `--chart <local-path>` override.
- **Partial rollout after upgrade succeeds:** the caller (skill) is responsible for `kubectl rollout status` polling; helm-ops returns success on helm-side success.

## Invocation

```
Task tool with subagent_type: "rwl-env:helm-ops"
```
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/agents/helm-ops.md
git commit -m "feat(rwl-env): helm-ops agent"
```

---

### Task 20: `agents/k8s-ops.md`

**Files:**
- Create: `rwl-env/agents/k8s-ops.md`

- [ ] **Step 1: Write agent doc**

Write `rwl-env/agents/k8s-ops.md`:

```markdown
---
name: k8s-ops
description: Autonomous kubectl operations agent for rwl-env (reads, exec, port-forward)
triggers:
  - kubernetes operations
  - kubectl get
  - kubectl logs
  - kubectl describe
  - kubectl exec
  - port-forward
---

# rwl-env Kubernetes Operations Agent

Read-only kubectl access to the active rwl-env's cluster. **Never constructs write commands** (`apply`, `delete`, `patch`, `edit`, `create`, `replace`, `scale`, `rollout restart`, `set image`, `label`, `annotate`, `cordon`, `drain`) — the PreToolUse hook would block them anyway, but the agent refuses at the source.

## Prerequisites

```bash
source .claude/rwl-env-env
```

Required: `RWLENV_KUBECONFIG`, `RWLENV_CONTEXT`, `RWLENV_NAMESPACE`. Also load the services catalog:
```bash
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

## Command Pattern

```bash
kubectl \
  --kubeconfig="$RWLENV_KUBECONFIG" \
  --context="$RWLENV_CONTEXT" \
  -n "$RWLENV_NAMESPACE" \
  <subcommand> <args>
```

Override `-n` only for catalog-recorded subchart namespaces (look up via `.subcharts.<name>.namespace` in the catalog; if it's `<rwl-env-ns>`, use `$RWLENV_NAMESPACE`).

## Capabilities

### Reads (always allowed)

| Subcommand | Purpose |
|---|---|
| `kubectl get <kind> [-l <selector>] [-o yaml\|json]` | Inspect resources |
| `kubectl describe <kind>/<name>` | Detailed status |
| `kubectl logs <pod> [-c <container>] [--previous] [--tail=N]` | Container logs |
| `kubectl get events --sort-by=.lastTimestamp [--field-selector ...]` | Event timeline |
| `kubectl top pod` / `kubectl top node` | Resource usage |
| `kubectl rollout status deploy/<name>` / `kubectl rollout history` | Rollout state (reads only) |
| `kubectl auth can-i ...` | Permission probe |
| `kubectl version`, `kubectl cluster-info` | Cluster meta |

### Interactive (allowed)

| Subcommand | Purpose | Notes |
|---|---|---|
| `kubectl exec <pod> [-c <container>] -- <cmd>` | Diagnostic shells, psql via in-pod 127.0.0.1 | If `<cmd>` is `psql`, only `-c '<query>'` form is auto-approved (hook enforces) |
| `kubectl port-forward svc/<svc> <local>:<remote>` | Local-port forwarding | Target must be in `$RWLENV_NAMESPACE` or a catalog-known subchart namespace |

### Refused

- All writes: `apply`, `delete`, `patch`, `edit`, `create`, `replace`, `scale`, `rollout restart`, `set image`, `set resources`, `set env`, `label`, `annotate`, `taint`, `cordon`, `uncordon`, `drain`.
- If asked, respond: "kubectl writes are not allowed from rwl-env. The only mutation path is helm-ops (helm upgrade / rollback). Use /rwl-rollback if you need to revert state."

## Service lookup via catalog

When asked about "papi" or "vault":
```bash
selector=$(jq -r ".services.papi.podSelector" "$CATALOG")
# → "app=papi"
kubectl --kubeconfig="$RWLENV_KUBECONFIG" --context="$RWLENV_CONTEXT" \
    get pod -l "$selector" -n "$RWLENV_NAMESPACE"
```

Substitute `<rwl-env-ns>` → `$RWLENV_NAMESPACE` and `<release>` → `$RWLENV_RELEASE` in any string read from the catalog.

## Error handling

- **API unreachable:** surface kubectl error; distinguish wrong context / expired auth / DNS.
- **Resource not found:** report cleanly; suggest `kubectl get <kind>` to list available.
- **Permission denied:** report; suggest `kubectl auth can-i <verb> <resource>` to probe.

## Invocation

```
Task tool with subagent_type: "rwl-env:k8s-ops"
```
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/agents/k8s-ops.md
git commit -m "feat(rwl-env): k8s-ops agent"
```

---

### Task 21: `agents/db-ops.md`

**Files:**
- Create: `rwl-env/agents/db-ops.md`

- [ ] **Step 1: Write agent doc**

Write `rwl-env/agents/db-ops.md`:

```markdown
---
name: db-ops
description: Read-only Postgres inspection via kubectl exec into the pg pod
triggers:
  - database queries
  - postgres queries
  - check db state
  - inspect database
  - psql
---

# rwl-env Database Operations Agent

Read-only Postgres inspection for the active rwl-env. Uses `kubectl exec` into the Spilo (or bundled) pg pod by default — no port-forward, no host psql dependency.

**Always read-only**, regardless of `$RWLENV_READ_ONLY`. The plugin never writes the DB; data changes happen through chart-managed migrations.

## Prerequisites

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

## Discovery flow

For a target database (e.g., `core`):

1. **Look up the database entry in the catalog:**
   ```bash
   db_entry=$(jq -r --arg db "core" '.databases[$db]' "$CATALOG")
   secret_pattern=$(echo "$db_entry" | jq -r '.secretNamePattern' | sed "s/<release>/$RWLENV_RELEASE/g")
   svc_selector=$(echo "$db_entry" | jq -r '.serviceLabelSelector' | sed "s/<release>/$RWLENV_RELEASE/g")
   fallback_svc=$(echo "$db_entry" | jq -r '.fallbackServiceName' | sed "s/<release>/$RWLENV_RELEASE/g")
   dbname=$(echo "$db_entry" | jq -r '.database')
   username=$(echo "$db_entry" | jq -r '.username')
   ```

2. **Find the pg pod:**
   ```bash
   pg_pod=$(kubectl --kubeconfig="$RWLENV_KUBECONFIG" --context="$RWLENV_CONTEXT" \
       get pod -l "$svc_selector" -n "$RWLENV_NAMESPACE" \
       -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
   ```
   If empty, fall back to discovering via the service name `$fallback_svc` → its endpoint pod.

3. **Pull the password from the K8s secret:**
   ```bash
   password=$(kubectl --kubeconfig="$RWLENV_KUBECONFIG" --context="$RWLENV_CONTEXT" \
       get secret "$secret_pattern" -n "$RWLENV_NAMESPACE" \
       -o jsonpath='{.data.password}' | base64 -d)
   ```
   **Never log this value.** Pass it directly into the env of the exec'd shell.

## Query execution (default: `kubectl exec`)

```bash
kubectl --kubeconfig="$RWLENV_KUBECONFIG" --context="$RWLENV_CONTEXT" \
    exec -n "$RWLENV_NAMESPACE" "$pg_pod" -- \
    env PGPASSWORD="$password" psql -h 127.0.0.1 -U "$username" -d "$dbname" -c '<query>'
```

The hook validates the `<query>` against read-only safety rules:
- Allowed: `SELECT`, `EXPLAIN`, `\d`, metadata reads.
- Blocked: DDL (`CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|VACUUM|REINDEX|CLUSTER`), DML (`INSERT|UPDATE|DELETE|MERGE|UPSERT`), `COPY ... TO`.
- Multi-statement queries with any forbidden component: blocked.

**Only the `-c '<query>'` form is supported.** `psql -f file`, stdin-piped queries, and bare interactive psql are blocked.

## Fallback: port-forward (opt-in only)

Only when the caller explicitly requests an interactive session:

```bash
local_port=5432
kubectl --kubeconfig="$RWLENV_KUBECONFIG" --context="$RWLENV_CONTEXT" \
    port-forward "svc/$fallback_svc" "$local_port:5432" -n "$RWLENV_NAMESPACE" &
pf_pid=$!
trap "kill $pf_pid 2>/dev/null" EXIT
sleep 2
PGPASSWORD="$password" psql -h 127.0.0.1 -p "$local_port" -U "$username" -d "$dbname"
```

## Common queries

| Purpose | Query |
|---|---|
| List tables | `SELECT schemaname, tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1,2` |
| Migration status (alembic) | `SELECT version_num FROM alembic_version` |
| Active connections | `SELECT pid, usename, state, query_start FROM pg_stat_activity WHERE state = 'active'` |
| Table sizes | `SELECT relname, pg_size_pretty(pg_total_relation_size(oid)) FROM pg_class WHERE relkind='r' ORDER BY pg_total_relation_size(oid) DESC LIMIT 20` |

## Error handling

- **Pod not found:** "pg pod for database '$db' not discovered via selector '$svc_selector'. Cluster may be down or the catalog is stale."
- **Secret missing:** "Secret '$secret_pattern' not found. Confirm release name and chart version (helm release may use different secret naming)."
- **Query blocked by hook:** surface the hook's stderr message verbatim.
- **psql connection refused:** check pg pod is `Running` (`kubectl get pod ...`) and the postgres process is up (`kubectl exec ... -- pg_isready`).

## Invocation

```
Task tool with subagent_type: "rwl-env:db-ops"
```
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/agents/db-ops.md
git commit -m "feat(rwl-env): db-ops agent (read-only psql via kubectl exec)"
```

---

## Phase 6: Helm Operation Skills

### Task 22: `/rwl-upgrade-image-tag` skill

**Files:**
- Create: `rwl-env/skills/rwl-upgrade-image-tag/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-upgrade-image-tag/SKILL.md`:

```markdown
---
name: rwl-upgrade-image-tag
description: Update a service's image tag via helm upgrade (deterministically revertible)
triggers:
  - /rwl-upgrade-image-tag
  - bump image tag
  - update image tag
args:
  - name: service
    description: Service name (papi, agentfarm, ...) — must be in services-catalog.json
    required: true
  - name: new_tag
    description: New image tag (e.g., 2026-05-22.3)
    required: true
  - name: chart
    description: Optional --chart <local-path> override for offline/airgap upgrades
    required: false
---

# Upgrade Image Tag via helm

Canonical write operation. Updates a single service's image tag via `helm upgrade --reuse-values --set <key>=<tag>`. Lists every other service that shares the same `imageTagKey` (since one helm values key can drive multiple deployments).

## Instructions

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

### Step 1: Refuse if read-only

If `$RWLENV_READ_ONLY == "true"`: abort with "rwl-env '$RWLENV_NAME' is read-only."

### Step 2: Resolve service → imageTagKey

```bash
key=$(jq -r --arg s "$service" '.services[$s].imageTagKey // empty' "$CATALOG")
if [[ -z "$key" ]]; then
    echo "Service '$service' not in catalog. Available:"
    jq -r '.services | keys[]' "$CATALOG"
    exit 1
fi
```

### Step 3: List all services sharing this imageTagKey

```bash
shared=$(jq -r --arg k "$key" '.services | to_entries | map(select(.value.imageTagKey == $k)) | .[].key' "$CATALOG")
```

Show these to the user so they know what else is moving.

### Step 4: Read current tag and chart version

Use the helm-ops agent (Task tool with subagent_type: "rwl-env:helm-ops") to run:
```
helm get values $RWLENV_RELEASE -n $RWLENV_NAMESPACE -o yaml
helm get metadata $RWLENV_RELEASE -n $RWLENV_NAMESPACE
helm history $RWLENV_RELEASE -n $RWLENV_NAMESPACE -o json
```

Extract:
- `currentTag` (via `yq <values> .<imageTagKey>`)
- `chartVersion` (from metadata)
- `currentRevision` (from history, the highest revision number)

### Step 5: Diff and confirm

AskUserQuestion:
```
Service:        <service>
Also affected:  <shared list>
Image tag:      <currentTag>  →  <new_tag>
Chart version:  <chartVersion>  (unchanged, --reuse-values)
Rollback hint:  /rwl-rollback --to-revision <currentRevision>
```
Options: "Yes, upgrade" / "No, cancel".

### Step 6: Execute upgrade via helm-ops

```bash
chart_ref="${chart_override:-$RWLENV_CHART_REPO/$RWLENV_CHART_NAME}"

helm \
    --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
    -n "$RWLENV_NAMESPACE" \
    upgrade "$RWLENV_RELEASE" "$chart_ref" \
    --version "$chartVersion" \
    --reuse-values \
    --set "$key=$new_tag"
```

### Step 7: Wait for rollouts

For every service sharing the `imageTagKey`, run via k8s-ops:
```bash
selector=$(jq -r --arg s "$svc" '.services[$s].podSelector' "$CATALOG")
kubectl --kubeconfig="$RWLENV_KUBECONFIG" --context="$RWLENV_CONTEXT" \
    -n "$RWLENV_NAMESPACE" \
    rollout status deploy/<resolve-deploy-name-from-podSelector> --timeout=3m
```

### Step 8: Report

```
Upgrade complete.
Revision: <currentRevision>  →  <newRevision>      (rollback: /rwl-rollback --to-revision <currentRevision>)
Rollout:  papi ✓  activities ✓  alerts ✓  ...
Image:    <imageTagKey>=<new_tag> pulled successfully.
```

### Step 9: If any rollout failed

Print the rollback command prominently:
```
*** ROLLOUT FAILED *** for: <deploy-name>
Run: /rwl-rollback --to-revision <currentRevision>
```
Offer to invoke `/rwl-rollback --to-revision <N>` directly via AskUserQuestion.

If the failure signature matches a known chart bug (e.g., the migration-controller hang on agentfarm tags predating `migration_controller.py`), end with:
```
This looks like a known chart-bug signature. Run /rwl-report-chart-bug --symptom "<recap>" to draft a report.
```

## Error Handling

- Service not in catalog → list available services and exit.
- helm-ops returns non-zero → surface the stderr verbatim. If it's a chart-fetch error, suggest the `--chart <local-path>` flag.
- Hook blocks the helm call → surface the hook's stderr; do not retry.
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/skills/rwl-upgrade-image-tag/SKILL.md
git commit -m "feat(rwl-env): /rwl-upgrade-image-tag skill"
```

---

### Task 23: `/rwl-rollback` skill

**Files:**
- Create: `rwl-env/skills/rwl-rollback/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-rollback/SKILL.md`:

```markdown
---
name: rwl-rollback
description: Roll back the active rwl-env release to a prior helm revision
triggers:
  - /rwl-rollback
  - helm rollback
  - revert release
args:
  - name: to_revision
    description: Optional revision number; prompted if omitted
    required: false
---

# Roll Back Helm Release

```bash
source .claude/rwl-env-env
```

### Step 1: Refuse if read-only

If `$RWLENV_READ_ONLY == "true"`: abort.

### Step 2: Show helm history

Via helm-ops:
```bash
helm history "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" -o json
```

Render a table: revision, updated, status, chart, appVersion, description.

### Step 3: Pick target revision

If `--to-revision N` was passed, use it. Otherwise AskUserQuestion with each revision as an option (most recent first).

### Step 4: Diff between current and target

```bash
helm get values "$RWLENV_RELEASE" --revision "$currentRev" -n "$RWLENV_NAMESPACE" -o yaml > /tmp/current.yaml
helm get values "$RWLENV_RELEASE" --revision "$targetRev"  -n "$RWLENV_NAMESPACE" -o yaml > /tmp/target.yaml
diff -u /tmp/current.yaml /tmp/target.yaml
```

Show a concise diff (changed keys only). Note both `chart` versions too — pull from `helm history -o json`.

### Step 5: Confirm

AskUserQuestion:
```
Roll back to revision <N>?
  Chart:       <X.Y.Z> → <A.B.C>  (or same)
  Image tag:   <new> → <old>     (sample key only)
  Description: <history entry description>
```
Options: "Yes, rollback" / "No, cancel".

### Step 6: Execute

Via helm-ops:
```bash
helm --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
    -n "$RWLENV_NAMESPACE" \
    rollback "$RWLENV_RELEASE" "$targetRev"
```

### Step 7: Wait for rollouts

Via k8s-ops, for every deployment in the release:
```bash
for dep in $(kubectl get deploy -n "$RWLENV_NAMESPACE" -l app.kubernetes.io/instance="$RWLENV_RELEASE" -o name); do
    kubectl rollout status "$dep" --timeout=3m
done
```

### Step 8: Report

```
Rollback complete.
Revision: <currentRev>  →  <newRev>       (new revision created; history is append-only)
Rolled back to chart <chart>, appVersion <app>, image-tag <tag>.
Rollouts complete for: <list>.
```

## Error Handling

- `helm history` shows only one revision → "Nothing to roll back to."
- Target revision === current → no-op message.
- helm rollback failure → surface stderr; do not retry.
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/skills/rwl-rollback/SKILL.md
git commit -m "feat(rwl-env): /rwl-rollback skill"
```

---

### Task 24: `/rwl-set-values` skill

**Files:**
- Create: `rwl-env/skills/rwl-set-values/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-set-values/SKILL.md`:

```markdown
---
name: rwl-set-values
description: Override arbitrary helm values via helm upgrade (deterministically revertible)
triggers:
  - /rwl-set-values
  - update helm values
  - override values
args:
  - name: sets
    description: Repeatable <key>=<value> overrides (e.g., papi.replicas=3)
    required: false
  - name: values_file
    description: Path to a values file (-f) for batch overrides
    required: false
  - name: chart
    description: Optional --chart <local-path>
    required: false
  - name: allow_subchart_toggle
    description: Required to permit toggling .deploy or .useSubchart keys
    required: false
---

# Override helm Values

Apply arbitrary helm value overrides via `helm upgrade --reuse-values`. Same diff-confirm-rollout cycle as `/rwl-upgrade-image-tag`.

### Step 1: Read inputs

Require at least one of `--set <k>=<v>` (repeatable) or `--values-file <path>`.

### Step 2: Refuse subchart toggles without override

If any `<key>` matches `(^|\.)(deploy|useSubchart)$` and `--allow-subchart-toggle` was NOT passed, refuse:
```
Key '<k>' toggles a subchart deploy/useSubchart. This has data-migration implications
beyond a simple helm upgrade. Pass --allow-subchart-toggle if you understand the cost.
```

### Step 3: Refuse if read-only

### Step 4: Build helm args

```bash
helm_args=(upgrade "$RWLENV_RELEASE" "${chart_override:-$RWLENV_CHART_REPO/$RWLENV_CHART_NAME}" \
    --version "$chartVersion" --reuse-values)
for set in "${sets[@]}"; do helm_args+=(--set "$set"); done
[[ -n "$values_file" ]] && helm_args+=(-f "$values_file")
```

### Step 5: Diff and confirm

Show:
- Each `--set` override (key → new value)
- If `--values-file`, show its content
- Current revision and chart version
- Rollback hint

AskUserQuestion: Yes / No.

### Step 6: Execute, wait for rollouts, report

Same as `/rwl-upgrade-image-tag` steps 6–8. Determine affected deployments by comparing `helm get manifest --revision <before>` vs after, or fall back to "all deployments in release".

## Error Handling

- Invalid `<key>=<value>` syntax → reject with a parser error.
- `--values-file` path doesn't exist or doesn't parse as YAML → reject.
- Same hook/helm error handling as `/rwl-upgrade-image-tag`.
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/skills/rwl-set-values/SKILL.md
git commit -m "feat(rwl-env): /rwl-set-values skill"
```

---

### Task 25: `/rwl-upgrade-chart` skill

**Files:**
- Create: `rwl-env/skills/rwl-upgrade-chart/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `rwl-env/skills/rwl-upgrade-chart/SKILL.md`:

```markdown
---
name: rwl-upgrade-chart
description: Bump the chart itself to a newer version (preserves values via --reuse-values)
triggers:
  - /rwl-upgrade-chart
  - bump chart version
  - upgrade chart
args:
  - name: version
    description: New chart version (semver)
    required: true
  - name: chart
    description: Optional --chart <local-path>
    required: false
---

# Upgrade Chart Version

### Step 1: Refuse if read-only.

### Step 2: Read current chart version

Via helm-ops: `helm get metadata "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE"`.
Extract `currentVersion`.

### Step 3: Soft-validate target chart exists

```bash
helm show chart "${chart_override:-$RWLENV_CHART_REPO/$RWLENV_CHART_NAME}" --version "$version"
```

If this fails, warn but allow the user to proceed (might be a private registry that requires auth helm will handle).

### Step 4: Diff and confirm

```
Chart version: <currentVersion>  →  <newVersion>
Rollback hint: /rwl-rollback --to-revision <currentRevision>

WARNING: Chart-version upgrades may change CRDs, RBAC, or values defaults.
         Review the chart's CHANGELOG before proceeding.
```
AskUserQuestion: Yes / No.

### Step 5: Execute

```bash
helm \
    --kubeconfig="$RWLENV_KUBECONFIG" --kube-context="$RWLENV_CONTEXT" \
    -n "$RWLENV_NAMESPACE" \
    upgrade "$RWLENV_RELEASE" "${chart_override:-$RWLENV_CHART_REPO/$RWLENV_CHART_NAME}" \
    --version "$version" \
    --reuse-values
```

### Step 6: Wait for rollouts and report

Same as `/rwl-upgrade-image-tag` steps 7–8.

### Step 7: Catalog-staleness check

If `$version`'s appVersion (from new release metadata) differs from `services-catalog.json.chartAppVersion`, print:
```
NOTE: Catalog appVersion (<catalog>) no longer matches live release (<new appVersion>).
      Debug recommendations may be stale until the catalog is updated.
```

## Error Handling

- `helm show chart` returns nothing → ask user to confirm proceeding without pre-flight.
- Same hook/helm error handling as image-tag skill.
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/skills/rwl-upgrade-chart/SKILL.md
git commit -m "feat(rwl-env): /rwl-upgrade-chart skill"
```

---

## Phase 7: Debug Skills

### Task 26: `/rwl-debug` dispatcher + `/rwl-debug-pod` (template)

The dispatcher scores user symptoms against `workflows-index.json` and routes to the right topic skill. `/rwl-debug-pod` is the first fully-authored topic skill; it doubles as the template for the remaining 6.

**Files:**
- Create: `rwl-env/skills/rwl-debug/SKILL.md`
- Create: `rwl-env/skills/rwl-debug-pod/SKILL.md`

- [ ] **Step 1: Write `/rwl-debug` dispatcher SKILL.md**

Write `rwl-env/skills/rwl-debug/SKILL.md`:

```markdown
---
name: rwl-debug
description: Dispatcher — route a free-text symptom to the right rwl-debug-<topic> skill
triggers:
  - /rwl-debug
  - debug the platform
  - something is wrong
args:
  - name: symptom
    description: Free-text description of what's wrong
    required: false
---

# rwl-debug Dispatcher

Take a free-text symptom, score it against `workflows-index.json`, and recommend the best `rwl-debug-<topic>` skill.

## Instructions

```bash
source .claude/rwl-env-env
INDEX="${CLAUDE_PLUGIN_ROOT}/data/workflows-index.json"
```

### Step 1: Get symptom

If `--symptom` was provided, use it. Otherwise prompt:
```
What's going wrong? Describe the symptom in your own words.
(Examples: 'papi returns 500s on /alerts', 'pod stuck in CrashLoopBackOff', 'vault is sealed')
```

### Step 2: Score against matchHints

For each entry under `.symptoms.*`:
```bash
# Sum up: how many of the symptom's matchHints appear (case-insensitive) in the user's text?
jq -r '.symptoms | to_entries[] | [.key, .value.skill, (.value.matchHints | tostring)] | @tsv' "$INDEX" \
    | while IFS=$'\t' read -r key skill hints; do
        # Score = count of hints found
        score=0
        for hint in $(echo "$hints" | jq -r '.[]'); do
            if echo "$user_symptom" | grep -iqF "$hint"; then
                score=$((score+1))
            fi
        done
        echo -e "$score\t$key\t$skill"
    done | sort -rn | head -3
```

### Step 3: Present recommendations

If the top-scoring entry has score >= 1:
```
Best match: <symptom-key> → /<skill>
  Likely causes: <list>
  First checks:  <list>

Run /<skill> to walk through diagnosis.
```

If multiple entries tie or score is 0:
```
I couldn't match your symptom confidently. Here are candidate debug skills:
  - /rwl-debug-pod          — generic CrashLoop / pending pod
  - /rwl-debug-image-pull   — ImagePullBackOff
  - /rwl-debug-migrations   — db-init / migration-controller
  - /rwl-debug-vault        — vault sealed / unsealer issues
  - /rwl-debug-papi         — papi runtime failures
  - /rwl-debug-agentfarm    — agentfarm runtime
  - /rwl-debug-llm          — llm-bootstrap / llm-gateway

Or describe the symptom in more detail and re-run /rwl-debug.
```

### Step 4: Catalog staleness check

If catalog `chartAppVersion` ≠ live release `appVersion`, prepend:
```
(catalog may be stale — recommendations could be out of date)
```

## Error Handling

- `workflows-index.json` missing → "Workflow index missing from plugin install. Reinstall rwl-env."
- No symptom provided and AskUserQuestion not available → list all debug skills and exit.
```

- [ ] **Step 2: Write `/rwl-debug-pod` SKILL.md (template + first topic)**

Write `rwl-env/skills/rwl-debug-pod/SKILL.md`:

```markdown
---
name: rwl-debug-pod
description: Walk through CrashLoopBackOff / pending-pod diagnosis
triggers:
  - /rwl-debug-pod
  - debug pod
  - pod crashloop
  - pending pod
args:
  - name: pod
    description: Pod name (prompted if omitted)
    required: false
---

# Debug Pod Issues (Generic)

Walks through the standard pod-troubleshooting sequence: state → describe → events → logs → init container logs → resource pressure.

## Instructions

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

### Step 1: Resolve pod name

If `--pod` provided, use it. Otherwise prompt for a pod name or a service name. If a service name, resolve via catalog:
```bash
selector=$(jq -r --arg s "$svc" '.services[$s].podSelector // empty' "$CATALOG")
[[ -n "$selector" ]] && pods=$(kubectl get pod -l "$selector" -n "$RWLENV_NAMESPACE" -o name)
```

### Step 2: Get current state via k8s-ops

```bash
kubectl --kubeconfig="$RWLENV_KUBECONFIG" --context="$RWLENV_CONTEXT" \
    get pod "$pod" -n "$RWLENV_NAMESPACE" -o wide
```

Report pod phase, restart count, age, node, conditions.

### Step 3: Describe pod (look for events)

```bash
kubectl describe pod "$pod" -n "$RWLENV_NAMESPACE"
```

Surface:
- Container last termination reason + exit code
- Init container statuses
- Events section (Scheduled → Pulled → Created → Started → BackOff etc.)

### Step 4: Logs (current + previous)

```bash
kubectl logs "$pod" -n "$RWLENV_NAMESPACE" --tail=200
kubectl logs "$pod" -n "$RWLENV_NAMESPACE" --previous --tail=100 2>/dev/null
```

### Step 5: Init container logs (if any)

```bash
init_containers=$(kubectl get pod "$pod" -n "$RWLENV_NAMESPACE" -o jsonpath='{.spec.initContainers[*].name}')
for ic in $init_containers; do
    kubectl logs "$pod" -c "$ic" -n "$RWLENV_NAMESPACE" --tail=100
done
```

### Step 6: Resource pressure

```bash
kubectl top pod "$pod" -n "$RWLENV_NAMESPACE" 2>/dev/null
kubectl describe node "$(kubectl get pod "$pod" -n "$RWLENV_NAMESPACE" -o jsonpath='{.spec.nodeName}')" | grep -A5 'Allocated resources'
```

### Step 7: Recent events for this pod

```bash
kubectl get events -n "$RWLENV_NAMESPACE" --field-selector involvedObject.name="$pod" --sort-by=.lastTimestamp
```

### Step 8: Diagnose & recommend

Based on the symptoms, recommend next steps:

| Symptom pattern | Next skill |
|---|---|
| `Failed to pull image`, `ErrImagePull`, `ImagePullBackOff` | `/rwl-debug-image-pull` |
| Init container `wait-for-migrations` hanging | `/rwl-debug-migrations` |
| `vault: Vault is sealed` in logs | `/rwl-debug-vault` |
| `OOMKilled`, OOM events | suggest `helm-set-values` to bump memory limits |
| `FailedScheduling`, `0/N nodes available` | resource pressure or nodeSelector mismatch |

If the failure signature matches a known chart bug entry in `workflows-index.json`, end with:
```
This matches '<symptom-key>' in the workflow index. Run /rwl-report-chart-bug --symptom "<recap>" to draft a report.
```

## Error Handling

- Pod not found → list pods in namespace.
- Permission denied → suggest `kubectl auth can-i get pod`.
```

- [ ] **Step 3: Commit**

```bash
git add rwl-env/skills/rwl-debug/SKILL.md rwl-env/skills/rwl-debug-pod/SKILL.md
git commit -m "feat(rwl-env): /rwl-debug dispatcher and /rwl-debug-pod skill"
```

---

### Task 27: Topic-specific debug skills (image-pull, migrations, vault, papi, agentfarm, llm)

Each follows the structure of `rwl-debug-pod`, with topic-specific facts pulled from `services-catalog.json`, `workflows-index.json`, and `INSTALL-FRICTIONS.md`. All use the same step shape: gather state → inspect specific resources/secrets/logs → recommend remediation or escalate to `/rwl-report-chart-bug`.

**Files:**
- Create: `rwl-env/skills/rwl-debug-image-pull/SKILL.md`
- Create: `rwl-env/skills/rwl-debug-migrations/SKILL.md`
- Create: `rwl-env/skills/rwl-debug-vault/SKILL.md`
- Create: `rwl-env/skills/rwl-debug-papi/SKILL.md`
- Create: `rwl-env/skills/rwl-debug-agentfarm/SKILL.md`
- Create: `rwl-env/skills/rwl-debug-llm/SKILL.md`

**Frontmatter template** (replace `<topic>` and triggers per skill):

```markdown
---
name: rwl-debug-<topic>
description: <one-line>
triggers:
  - /rwl-debug-<topic>
  - <natural language trigger>
---

# Debug <topic>

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

## Instructions

### Step 1: ...
### Step 2: ...
### Step N: Diagnose & recommend
### Step Final: If known chart-bug signature, recommend /rwl-report-chart-bug.
```

- [ ] **Step 1: Write `/rwl-debug-image-pull`**

Write `rwl-env/skills/rwl-debug-image-pull/SKILL.md`:

```markdown
---
name: rwl-debug-image-pull
description: Diagnose ImagePullBackOff / ErrImagePull
triggers:
  - /rwl-debug-image-pull
  - image pull backoff
  - cannot pull image
---

# Debug ImagePullBackOff

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

### Step 1: Identify the failing image

```bash
kubectl describe pod <pod> -n "$RWLENV_NAMESPACE" | grep -A2 'Failed to pull'
# Or:
kubectl get pod <pod> -n "$RWLENV_NAMESPACE" -o jsonpath='{.status.containerStatuses[*].state.waiting.message}'
```
Extract the full image reference (`<registry>/<repo>:<tag>`).

### Step 2: Check imagePullSecrets

```bash
kubectl get sa default -n "$RWLENV_NAMESPACE" -o jsonpath='{.imagePullSecrets}'
helm get values "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" | yq '.global.imagePullSecrets, .images.pullSecrets'
```

For each secret name listed, verify it exists:
```bash
kubectl get secret <pull-secret-name> -n "$RWLENV_NAMESPACE"
```

### Step 3: Test image reachability manually

```bash
# From inside the cluster (a debug pod):
kubectl run pull-test --rm -it --image=<failing-image> --restart=Never -n "$RWLENV_NAMESPACE" -- echo ok
```
This is a one-shot diagnostic; allowed by the hook since it's not a write to an existing resource.

### Step 4: Check registryOverride and per-image registry

```bash
helm get values "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" | yq '.registryOverride'
helm get values "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" | yq '.images.<svc>.registry'
```

### Step 5: Known chart-bug signatures

- Bitnami subchart pointing at retired `bitnami/*` free-tier tag — should be `bitnamilegacy/*`. See INSTALL-FRICTIONS §<n>.
- Airgap JFrog setup missing per-prefix registry — `registryOverride` won't work; need per-image `registry` overrides.

### Step 6: Recommend remediation

| Cause | Fix |
|---|---|
| Missing pullSecret | `/rwl-set-values --set images.pullSecrets[0].name=<secret>` |
| Wrong registry override | `/rwl-set-values --set registryOverride=<correct>` |
| Tag truly missing | bump to a known-good tag via `/rwl-upgrade-image-tag` |
| Airgap mirror not populated | populate it; this is an out-of-cluster fix |

If the signature matches a known chart bug, suggest `/rwl-report-chart-bug --symptom "ImagePullBackOff for <image>"`.

## Error Handling

- Image-pull failures from outside the cluster reveal nothing — the test pod must run inside. Note this if `kubectl run pull-test` fails for non-image reasons.
```

- [ ] **Step 2: Write `/rwl-debug-migrations`**

Write `rwl-env/skills/rwl-debug-migrations/SKILL.md`:

```markdown
---
name: rwl-debug-migrations
description: Diagnose db-init job and migration-controller hangs
triggers:
  - /rwl-debug-migrations
  - migration controller stuck
  - wait-for-migrations
  - db-init failed
---

# Debug Migration Controller / db-init

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

### Step 1: Check db-init-job status

```bash
kubectl get job -l app.kubernetes.io/component=db-init -n "$RWLENV_NAMESPACE"
kubectl logs -l app.kubernetes.io/component=db-init -n "$RWLENV_NAMESPACE" --tail=200
```

If failed: surface the error (most often: pg unreachable, secret missing, or schema-create permission denied).

### Step 2: Check migration-controller pod

```bash
kubectl get pod -l app=migration-controller -n "$RWLENV_NAMESPACE"
kubectl logs <migration-controller-pod> -n "$RWLENV_NAMESPACE" --tail=200
kubectl logs <migration-controller-pod> -n "$RWLENV_NAMESPACE" --previous --tail=100
```

### Step 3: Verify agentfarm image has migration_controller.py

The migration-controller StatefulSet runs `python3 webapp/migration_controller.py` from the agentfarm image. Tags older than 2026-05-XX may not ship this file → CrashLoopBackOff.

```bash
current_tag=$(helm get values "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" | yq '.images.agentfarm.tag')
echo "Current agentfarm tag: $current_tag"
# Spot-check the image:
kubectl exec <migration-controller-pod> -n "$RWLENV_NAMESPACE" -- ls webapp/migration_controller.py 2>/dev/null
```

If the file is missing: this is the known chart-bug signature. Recommend bumping to a newer agentfarm tag via `/rwl-upgrade-image-tag agentfarm <new-tag>` AND report via `/rwl-report-chart-bug`.

### Step 4: Check core DB reachability from migration-controller

Via db-ops:
```bash
# Just confirm the pg pod is up; queries don't even need to run
kubectl get pod -l "$(jq -r '.databases.core.serviceLabelSelector' "$CATALOG" | sed "s/<release>/$RWLENV_RELEASE/g")" -n "$RWLENV_NAMESPACE"
```

### Step 5: Inspect alembic version (db-ops, read-only)

```bash
# Use db-ops to query:
SELECT version_num FROM alembic_version;
```

Compare against the expected version (documented in the chart's CHANGELOG or hard-coded in migration source).

### Step 6: Recommend remediation

| Cause | Fix |
|---|---|
| agentfarm tag predates migration_controller.py | `/rwl-upgrade-image-tag agentfarm <newer-tag>` |
| db-init-job failed (pg unreachable) | check pg pod logs; fix vault/secret/network |
| Schema permission denied | check `core-pguser-postgres` secret + spilo init |
| alembic_version mismatched | usually self-resolves once controller runs; if not, escalate |

## Error Handling

- No db-init-job present → not all chart configurations create one; surface this as a non-error.
```

- [ ] **Step 3: Write `/rwl-debug-vault`**

Write `rwl-env/skills/rwl-debug-vault/SKILL.md`:

```markdown
---
name: rwl-debug-vault
description: Diagnose sealed vault, unsealer crashloop, vault-init failures
triggers:
  - /rwl-debug-vault
  - vault sealed
  - vault unsealer
---

# Debug Vault Issues

```bash
source .claude/rwl-env-env
```

### Step 1: Check vault pod status

```bash
kubectl get pod -l app.kubernetes.io/name=vault -n "$RWLENV_NAMESPACE"
```

### Step 2: Vault status

```bash
kubectl exec vault-0 -n "$RWLENV_NAMESPACE" -- vault status
```

Read: `Sealed`, `Initialized`, `Total Shares`, `Threshold`.

### Step 3: vault-init-job

```bash
kubectl get job -l app.kubernetes.io/component=vault-init -n "$RWLENV_NAMESPACE"
kubectl logs job/<release>-vault-init -n "$RWLENV_NAMESPACE"
```

If not completed: the unseal-key secret was never populated → subsequent unsealer can't function.

### Step 4: vault-unsealer deployment

```bash
kubectl get deploy vault-unsealer -n "$RWLENV_NAMESPACE"
kubectl logs deploy/vault-unsealer -n "$RWLENV_NAMESPACE" --tail=100
```

### Step 5: Unseal secret presence

```bash
kubectl get secret -n "$RWLENV_NAMESPACE" | grep -i unseal
```

The secret name varies by chart version; check vault-init-job's `valueFrom` references or the chart's `templates/vault/*` for the canonical name.

### Step 6: Recommend remediation

| Cause | Fix |
|---|---|
| Vault sealed + unsealer crashloop | check unseal secret + vault-init-job re-ran |
| Vault not initialized | re-run vault-init-job (via helm rollback to a revision that triggers it, or `kubectl delete job/<release>-vault-init` and helm upgrade) |
| vault-init-job's vault-client image tag mismatch with vault image | bump or align; this is a known chart-bug area |

If signature matches a known issue, suggest `/rwl-report-chart-bug`.
```

- [ ] **Step 4: Write `/rwl-debug-papi`**

Write `rwl-env/skills/rwl-debug-papi/SKILL.md`:

```markdown
---
name: rwl-debug-papi
description: Diagnose papi runtime failures (5xx, slow, returning empty)
triggers:
  - /rwl-debug-papi
  - papi errors
  - papi 500
---

# Debug papi Runtime

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

### Step 1: papi pod health

```bash
selector=$(jq -r '.services.papi.podSelector' "$CATALOG")
kubectl get pod -l "$selector" -n "$RWLENV_NAMESPACE"
kubectl describe pod -l "$selector" -n "$RWLENV_NAMESPACE"
```

### Step 2: papi logs (filter for ERROR)

```bash
kubectl logs -l "$selector" -n "$RWLENV_NAMESPACE" --tail=300 | grep -iE 'error|exception|timeout|refused' | head -50
```

### Step 3: Check papi's downstream dependencies (from catalog runtime.callsOut)

```bash
deps=$(jq -r '.services.papi.runtime.callsOut[]' "$CATALOG")
for d in $deps; do
    case "$d" in
        postgres:*)
            db=${d#postgres:}
            echo "Check DB $db pod readiness:"
            kubectl get pod -l "$(jq -r --arg db "$db" '.databases[$db].serviceLabelSelector' "$CATALOG" | sed "s/<release>/$RWLENV_RELEASE/g")" -n "$RWLENV_NAMESPACE"
            ;;
        *)
            echo "Check $d pod readiness:"
            sel=$(jq -r --arg s "$d" '.services[$s].podSelector // .subcharts[$s].selector // empty' "$CATALOG")
            [[ -n "$sel" ]] && kubectl get pod -l "$sel" -n "$RWLENV_NAMESPACE"
            ;;
    esac
done
```

### Step 4: For each known failure chain in catalog.services.papi.runtime.knownFailureChains

If user's symptom matches one (string match against `symptom` field), walk through that chain's `checkOrder` step-by-step.

### Step 5: papi DB connectivity check (db-ops)

```bash
# Use db-ops to run on the core DB:
SELECT count(*) FROM alembic_version;   -- proves schema is reachable
SELECT * FROM pg_stat_activity WHERE application_name LIKE 'papi%';  -- active papi connections
```

### Step 6: Recommend remediation

Based on which downstream is failing:
- alert-query down → `/rwl-debug-pod` on alert-query
- redis unreachable → `/rwl-debug-pod` on redis subchart pod
- core DB read failure → escalate to DB-side investigation

If the symptom matches a known chart-bug, suggest `/rwl-report-chart-bug --service papi --symptom "<recap>"`.
```

- [ ] **Step 5: Write `/rwl-debug-agentfarm`**

Write `rwl-env/skills/rwl-debug-agentfarm/SKILL.md`:

```markdown
---
name: rwl-debug-agentfarm
description: Diagnose agentfarm runtime and LLM gateway issues
triggers:
  - /rwl-debug-agentfarm
  - agentfarm errors
  - agent farm timeout
---

# Debug agentfarm Runtime

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
```

### Step 1: agentfarm pod health

```bash
selector=$(jq -r '.services.agentfarm.podSelector' "$CATALOG")
kubectl get pod -l "$selector" -n "$RWLENV_NAMESPACE"
kubectl describe pod -l "$selector" -n "$RWLENV_NAMESPACE"
kubectl logs -l "$selector" -n "$RWLENV_NAMESPACE" --tail=300
```

### Step 2: LLM gateway reachability

```bash
gw_selector=$(jq -r '.services["llm-gateway"].podSelector' "$CATALOG")
kubectl get pod -l "$gw_selector" -n "$RWLENV_NAMESPACE"
kubectl logs -l "$gw_selector" -n "$RWLENV_NAMESPACE" --tail=200
```

### Step 3: llmconfig configmap

```bash
kubectl get cm llmconfig -n "$RWLENV_NAMESPACE" -o yaml
```

Confirm providers (openai, anthropic, etc.) and model lists.

### Step 4: vault provider keys

```bash
kubectl exec vault-0 -n "$RWLENV_NAMESPACE" -- vault kv list secret/llm
```

Each provider should have a corresponding secret path.

### Step 5: llm-bootstrap status

```bash
kubectl get job -l app.kubernetes.io/component=llm-bootstrap -n "$RWLENV_NAMESPACE"
kubectl logs job/<release>-llm-bootstrap -n "$RWLENV_NAMESPACE"
```

If never completed → vault paths were never seeded → all LLM calls fail.

### Step 6: agentfarm DB (db-ops)

```bash
# Use db-ops to query agentfarm db
SELECT count(*) FROM agent_runs;   -- adjust to real table name from source
```

### Step 7: Recommend remediation

| Cause | Fix |
|---|---|
| llm-bootstrap failed (vault sealed) | `/rwl-debug-vault` first |
| llmconfig missing provider entry | `/rwl-set-values --values-file ...` |
| provider key not in vault | run llm-bootstrap again (helm rollback + upgrade, or manual job rerun) |
| migration_controller predates `webapp/migration_controller.py` | `/rwl-debug-migrations` |
```

- [ ] **Step 6: Write `/rwl-debug-llm`**

Write `rwl-env/skills/rwl-debug-llm/SKILL.md`:

```markdown
---
name: rwl-debug-llm
description: Diagnose llm-bootstrap, llm-gateway, and provider key issues
triggers:
  - /rwl-debug-llm
  - llm gateway errors
  - llm bootstrap failed
---

# Debug LLM Pipeline

```bash
source .claude/rwl-env-env
```

### Step 1: llm-bootstrap job

```bash
kubectl get job -l app.kubernetes.io/component=llm-bootstrap -n "$RWLENV_NAMESPACE"
kubectl logs job/<release>-llm-bootstrap -n "$RWLENV_NAMESPACE"
```

Most common failures:
- vault sealed → see Step 2
- llmconfig CM missing keys → see Step 3
- vault policy denies write → see Step 4

### Step 2: vault status

```bash
kubectl exec vault-0 -n "$RWLENV_NAMESPACE" -- vault status | grep Sealed
```

If sealed: escalate to `/rwl-debug-vault`.

### Step 3: llmconfig ConfigMap shape

```bash
kubectl get cm llmconfig -n "$RWLENV_NAMESPACE" -o yaml
```

Should list each provider you want available, with model lists. Missing entries == bootstrap silently skips.

### Step 4: vault paths after bootstrap

```bash
kubectl exec vault-0 -n "$RWLENV_NAMESPACE" -- vault kv list secret/llm
kubectl exec vault-0 -n "$RWLENV_NAMESPACE" -- vault kv get secret/llm/openai   # expect key data, never log the value
```

### Step 5: llm-gateway logs

```bash
kubectl logs deploy/llm-gateway -n "$RWLENV_NAMESPACE" --tail=200
```

LiteLLM logs include provider routing decisions; look for 401/403 (auth) or 404 (model unknown).

### Step 6: Recommend remediation

| Cause | Fix |
|---|---|
| Vault sealed | `/rwl-debug-vault` |
| llmconfig missing provider | `/rwl-set-values --values-file ...` to inject |
| Provider 401 | rotate key in `llmconfig` (or vault directly) and rerun bootstrap |
| Wrong model alias | edit llmconfig — model name must match provider's exact identifier |
```

- [ ] **Step 7: Verify all 7 topic skills exist and frontmatter parses**

```bash
for s in rwl-debug-image-pull rwl-debug-migrations rwl-debug-vault rwl-debug-papi rwl-debug-agentfarm rwl-debug-llm; do
    head -1 rwl-env/skills/$s/SKILL.md
done
```
Expected: each prints `---`.

- [ ] **Step 8: Rerun catalog tests (now all referenced skills exist)**

```bash
rwl-env/tests/test-catalog.sh
```
Expected: all PASS, including "every workflow skill exists as a file".

- [ ] **Step 9: Commit**

```bash
git add rwl-env/skills/rwl-debug-image-pull/ rwl-env/skills/rwl-debug-migrations/ rwl-env/skills/rwl-debug-vault/ rwl-env/skills/rwl-debug-papi/ rwl-env/skills/rwl-debug-agentfarm/ rwl-env/skills/rwl-debug-llm/
git commit -m "feat(rwl-env): topic debug skills (image-pull, migrations, vault, papi, agentfarm, llm)"
```

---

## Phase 8: Bug Report Skill

### Task 28: `/rwl-report-chart-bug` skill

**Files:**
- Create: `rwl-env/skills/rwl-report-chart-bug/SKILL.md`
- Create: `rwl-env/scripts/redact.sh`
- Create: `rwl-env/tests/test-redact.sh`
- Create: `rwl-env/tests/fixtures/values-with-secrets.yaml`

- [ ] **Step 1: Create test fixture with sensitive values**

Write `rwl-env/tests/fixtures/values-with-secrets.yaml`:

```yaml
postgresql:
  postgresqlPassword: super-secret-password
  auth:
    apiKey: ak_live_abc123
images:
  papi:
    tag: 2026-05-22.1
vault:
  unsealKey: barfoo123
secrets:
  token: AKIAIOSFODNN7EXAMPLE
  publicEndpoint: https://api.example.com
```

- [ ] **Step 2: Write failing test for redact.sh**

Write `rwl-env/tests/test-redact.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
REDACT="$PLUGIN_DIR/scripts/redact.sh"

PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" got="$3"
    if [[ "$got" == "$expected" ]]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
    else
        printf "  FAIL: %s (got: %s, expected: %s)\n" "$desc" "$got" "$expected"; FAIL=$((FAIL+1))
    fi
}

OUT=$(bash "$REDACT" values < "$SCRIPT_DIR/fixtures/values-with-secrets.yaml")

# Keys with sensitive substrings should be redacted; their key names should be kept.
check "postgresqlPassword redacted" '***REDACTED***' "$(echo "$OUT" | yq '.postgresql.postgresqlPassword')"
check "apiKey redacted" '***REDACTED***' "$(echo "$OUT" | yq '.postgresql.auth.apiKey')"
check "unsealKey redacted" '***REDACTED***' "$(echo "$OUT" | yq '.vault.unsealKey')"
check "token redacted" '***REDACTED***' "$(echo "$OUT" | yq '.secrets.token')"

# Non-sensitive values should pass through
check "image tag preserved" '2026-05-22.1' "$(echo "$OUT" | yq '.images.papi.tag')"
check "public endpoint preserved" 'https://api.example.com' "$(echo "$OUT" | yq '.secrets.publicEndpoint')"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
```
Make executable: `chmod +x rwl-env/tests/test-redact.sh`

- [ ] **Step 3: Run, confirm fail**

```bash
rwl-env/tests/test-redact.sh
```
Expected: FAIL (redact.sh missing).

- [ ] **Step 4: Implement redact.sh**

Write `rwl-env/scripts/redact.sh`:

```bash
#!/usr/bin/env bash
# redact.sh - Redact secrets from helm values / kubectl output / logs
#
# Usage:
#   redact.sh values  < input.yaml > redacted.yaml
#   redact.sh secret  < input.yaml > redacted.yaml   (drops data/stringData from Secret resources)
#   redact.sh logs    < input.log  > redacted.log

set -euo pipefail

MODE="${1:-values}"

# Pattern of sensitive key names (case-insensitive)
SECRET_KEY_RE='(?i)(password|secret|token|apikey|api_key|credential|.*-key|.*Key|privatekey)'

case "$MODE" in
  values)
    # Walk YAML keys; if a key matches the pattern, replace its value with ***REDACTED***.
    # Uses yq's eval ... |= ... pattern.
    yq 'walk(if type == "object" then with_entries(
        if (.key | test("password|secret|token|apikey|api_key|credential|key$|privatekey"; "i"))
        then .value = "***REDACTED***"
        else . end
    ) else . end)' -
    ;;
  secret)
    # For K8s Secret resources, drop data and stringData
    yq 'if (.kind == "Secret") then .data = {"<N entries redacted>": ""} | del(.stringData) else . end' -
    ;;
  logs)
    # Sweep regex matches in log lines
    sed -E \
        -e 's/(AKIA[0-9A-Z]{16})/***REDACTED-AWS-KEY***/g' \
        -e 's/(eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)/***REDACTED-JWT***/g' \
        -e 's#(https?://[^/]*:)[^@/]+(@)#\1***REDACTED-PASSWORD***\2#g'
    ;;
  *)
    echo "Usage: $0 {values|secret|logs}" >&2
    exit 1
    ;;
esac
```
Make executable: `chmod +x rwl-env/scripts/redact.sh`

- [ ] **Step 5: Run tests, confirm PASS**

```bash
rwl-env/tests/test-redact.sh
```
Expected: all PASS.

- [ ] **Step 6: Write SKILL.md**

Write `rwl-env/skills/rwl-report-chart-bug/SKILL.md`:

```markdown
---
name: rwl-report-chart-bug
description: Produce a shareable markdown bug report for the helm chart author
triggers:
  - /rwl-report-chart-bug
  - report chart bug
  - chart issue
args:
  - name: symptom
    description: Free-text symptom (pre-fillable from a debug skill)
    required: false
  - name: service
    description: Service name (e.g., papi)
    required: false
  - name: resource
    description: kind/name (e.g., deploy/papi)
    required: false
---

# Report Chart Bug

Collect diagnostic context for the active rwl-env release, redact secrets, render a markdown GitHub-issue body inline, and save to `./helm-bug-reports/<release>-<service-or-resource>-<YYYY-MM-DD-HHMM>.md`.

## Instructions

```bash
source .claude/rwl-env-env
CATALOG="${CLAUDE_PLUGIN_ROOT}/data/services-catalog.json"
INDEX="${CLAUDE_PLUGIN_ROOT}/data/workflows-index.json"
REDACT="${CLAUDE_PLUGIN_ROOT}/scripts/redact.sh"
```

### Step 1: Gather helm metadata

Via helm-ops:
```bash
metadata=$(helm get metadata "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE")
values=$(helm get values "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" -o yaml | bash "$REDACT" values)
history=$(helm history "$RWLENV_RELEASE" -n "$RWLENV_NAMESPACE" -o json | jq '.[-5:]')
```

### Step 2: Gather K8s resource state

If `--service` was given:
```bash
selector=$(jq -r --arg s "$service" '.services[$s].podSelector' "$CATALOG")
resources=$(kubectl get deploy,sts,pod -l "$selector" -n "$RWLENV_NAMESPACE" -o yaml | bash "$REDACT" secret)
```

If `--resource <kind/name>` was given:
```bash
resources=$(kubectl get "$kind" "$name" -n "$RWLENV_NAMESPACE" -o yaml | bash "$REDACT" secret)
describe_out=$(kubectl describe "$kind" "$name" -n "$RWLENV_NAMESPACE")
```

### Step 3: Gather logs for implicated pods

```bash
for pod in $implicated_pods; do
    logs=$(kubectl logs "$pod" -n "$RWLENV_NAMESPACE" --tail=200 | bash "$REDACT" logs)
    previous_logs=$(kubectl logs "$pod" -n "$RWLENV_NAMESPACE" --previous --tail=100 2>/dev/null | bash "$REDACT" logs)
done
```

### Step 4: Gather events

```bash
events=$(kubectl get events -n "$RWLENV_NAMESPACE" --sort-by=.lastTimestamp \
    ${implicated_pod:+--field-selector involvedObject.name=$implicated_pod})
```

### Step 5: Look up symptom in workflows-index

If `--symptom` matches an index entry, pull `likelyCauses` and `firstChecks`.

### Step 6: Compose markdown

Write to `./helm-bug-reports/<release>-<svc-or-res>-$(date +%Y-%m-%d-%H%M).md`:

```markdown
# [chart-bug] <release> · <service-or-resource> · <one-line-symptom>

**Reporter context** (auto-generated by rwl-env v0.1.0)

| | |
|---|---|
| Chart            | `runwhen-platform` |
| Chart version    | `<chartVer>`       |
| App version      | `<appVer>`         |
| Release          | `<release>`        |
| Revision         | `<rev>` (last upgraded <ts>) |
| Kubernetes       | `<kubectl version>` |
| rwl-env          | `<name>` |

## Observed
<symptom>

## Expected
<from workflows-index if available, else placeholder>

## Minimal repro
1. <derived from chart-bug signature>

## Diagnostic snapshot
### helm get values (redacted)
\`\`\`yaml
<redacted values>
\`\`\`

### Failing resource(s)
\`\`\`yaml
<redacted resources>
\`\`\`

### Recent events
\`\`\`
<events>
\`\`\`

### Recent logs (last 200 lines, redacted)
\`\`\`
<redacted logs>
\`\`\`

## Likely causes (from rwl-env workflows-index)
- <cause 1>
- <cause 2>

## Already-tried
<!-- Fill in before posting -->

---
*Generated by rwl-env. Redaction applied. Review the full file before posting publicly.*
```

### Step 7: Auto-gitignore the reports directory

```bash
if [[ -d "$PWD/.git" ]] && ! grep -qxF 'helm-bug-reports/' .gitignore 2>/dev/null; then
    echo 'helm-bug-reports/' >> .gitignore
fi
```

### Step 8: Print the path prominently

```
Bug report saved: ./helm-bug-reports/<filename>
Review the file (especially the redaction banner and 'Already-tried' section) before sharing.
```

If `./helm-bug-reports/` can't be created (read-only fs), fall back to printing the markdown body inline only, with a clear note.

## Error Handling

- helm-ops failures → still produce the report, with the failed-to-fetch sections noted explicitly.
- No symptom or service/resource specified → prompt the user for at least one.
```

- [ ] **Step 7: Commit**

```bash
git add rwl-env/skills/rwl-report-chart-bug/SKILL.md rwl-env/scripts/redact.sh rwl-env/tests/test-redact.sh rwl-env/tests/fixtures/values-with-secrets.yaml
git commit -m "feat(rwl-env): /rwl-report-chart-bug skill with redaction"
```

---

## Phase 9: Docs + Release

### Task 29: Manual testing runbook

**Files:**
- Create: `rwl-env/docs/MANUAL-TESTING.md`

- [ ] **Step 1: Write manual testing runbook**

Write `rwl-env/docs/MANUAL-TESTING.md`:

```markdown
# rwl-env Manual Testing Runbook

End-to-end smoke tests against a real cluster. Run before each release.

## Prerequisites

- `k3d` installed locally (https://k3d.io)
- `helm` >= 3.12, `kubectl` >= 1.28, `jq`, `yq`
- The runwhen-platform helm chart available (via OCI/HTTPS repo OR local path)

## Setup: spin up a test k3d cluster

```bash
k3d cluster create rwl-test --servers 1 --agents 1 --port "8080:80@loadbalancer"
kubectl config use-context k3d-rwl-test
kubectl create namespace runwhen
helm install rwl <chart-source>/runwhen-platform -n runwhen \
    -f <some-values.yaml> \
    --version <version>
```

Wait for all pods to become ready (10-20 minutes for first install).

## Phase 1: env management

- [ ] `/rwl-env-add helm-dev`
  - Walk through the prompts; pick `k3d-rwl-test` context, `runwhen` namespace, `rwl` release.
  - Verify `~/.claude/rwl-env/envs.json` contains the new entry.
  - Verify `.claude/rwl-env` and `.claude/rwl-env-env` are written.
  - Verify both are gitignored.
- [ ] `/rwl-env-list` shows `helm-dev` with `*`.
- [ ] `/rwl-env-cur` shows resolved values + live helm metadata.
- [ ] `/rwl-env-set helm-dev` (already active) reports idempotent.
- [ ] `/rwl-env-add helm-staging` with `readOnly: true`.
- [ ] `/rwl-env-set helm-staging` switches; `/rwl-env-cur` shows read-only warning.

## Phase 2: hook + agents

- [ ] On `helm-dev`: `kubectl get pods --kubeconfig=... --context=... -n runwhen` auto-approves.
- [ ] `kubectl get pods` (without flags) blocks with actionable message.
- [ ] `kubectl delete pod foo --kubeconfig=... --context=... -n runwhen` blocks (writes forbidden).
- [ ] `helm upgrade ... --reuse-values ...` auto-approves on helm-dev, blocks on helm-staging.
- [ ] `helm install` blocks always.

## Phase 3: image-tag upgrade (canonical write flow)

- [ ] `/rwl-upgrade-image-tag papi <some-known-good-tag>`:
  - Lists all services sharing the imageTagKey.
  - Shows current → new tag diff.
  - Prints rollback hint.
  - Executes helm upgrade.
  - Polls rollout status.
  - Reports new revision.
- [ ] `/rwl-rollback --to-revision <prior>`:
  - Shows values diff.
  - Confirms and executes.
  - New revision created; helm history grows.

## Phase 4: debug skills

- [ ] `/rwl-debug "papi 5xx on /alerts"` recommends `/rwl-debug-papi`.
- [ ] `/rwl-debug-pod <some-pod>` walks through state → describe → logs.
- [ ] Force an ImagePullBackOff (set images.papi.tag to a bogus tag via /rwl-set-values), then `/rwl-debug-image-pull` correctly identifies the cause.
- [ ] Roll back: `/rwl-rollback`.

## Phase 5: bug report

- [ ] `/rwl-report-chart-bug --service papi --symptom "5xx"` produces a redacted markdown file at `./helm-bug-reports/...`.
- [ ] Verify no secrets leak: `grep -i 'password\|secret\|token' helm-bug-reports/*.md | grep -v REDACTED`.
- [ ] Verify `helm-bug-reports/` added to `.gitignore`.

## Phase 6: read-only enforcement

- [ ] Switch to `helm-staging` (readOnly=true).
- [ ] `/rwl-upgrade-image-tag papi <tag>` refuses early.
- [ ] `/rwl-rollback` refuses early.
- [ ] `/rwl-env-cur` shows live state without warnings.
- [ ] DB queries still work via db-ops (read-only doesn't apply to reads).

## Phase 7: db-ops

- [ ] db-ops via natural-language: "show me the alembic version in the core DB" → executes `SELECT version_num FROM alembic_version` via kubectl exec.
- [ ] `INSERT INTO alembic_version VALUES ('x')` → blocked by hook with stderr message.
- [ ] `DROP TABLE x` → blocked.

## Teardown

```bash
k3d cluster delete rwl-test
```
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/docs/MANUAL-TESTING.md
git commit -m "docs(rwl-env): manual testing runbook"
```

---

### Task 30: Catalog authoring guide

**Files:**
- Create: `rwl-env/docs/CATALOG-AUTHORING.md`

- [ ] **Step 1: Write catalog authoring guide**

Write `rwl-env/docs/CATALOG-AUTHORING.md`:

```markdown
# Catalog Authoring Guide

How to (re)author `data/services-catalog.json` and `data/workflows-index.json` for a new chart `appVersion`.

## When to re-author

- Chart bump (new appVersion in `Chart.yaml`)
- New service added to `templates/`
- New known-failure mode worth documenting (especially after a chart bug ships)

## Inputs

- Helm chart source: `/Users/rohitekbote/emdash-projects/worktrees/main-for-ref-73t/runwhen-platform/`
  - `Chart.yaml` for `appVersion`, `name`
  - `templates/<svc>/` for deployment/statefulset specs
  - `values.yaml` for `images.<svc>.tag` keys and comments
  - `INSTALL-FRICTIONS.md` for known symptoms
- Application source (per service, see plan's Reference Material section).

## services-catalog.json — per-service field derivation

| Field | Source |
|---|---|
| `description` | Hand-written one-liner |
| `namespace` | Almost always `<rwl-env-ns>` (single-namespace deployment) |
| `imageTagKey` | Walk `templates/<svc>/*.yaml` for `image: ...{{ .Values.X.Y.tag }}...`; record `X.Y.tag` |
| `podSelector` | Selector that K8s API understands; usually `app=<svc>` |
| `containerName` | `spec.template.spec.containers[0].name` |
| `internalPort` | `spec.template.spec.containers[0].ports[0].containerPort` |
| `probes.readiness` | `spec.template.spec.containers[0].readinessProbe.httpGet.path` |
| `probes.liveness` | `spec.template.spec.containers[0].livenessProbe.httpGet.path` |
| `deploymentWaitFor` | Init container names that wait on other services (`wait-for-X`) |
| `runtime.summary` | One sentence from application README / main.py / module-doc |
| `runtime.callsOut` | Outbound HTTP/gRPC clients in source; cross-reference K8s service names |
| `runtime.calledBy` | Reverse of callsOut from other services |
| `runtime.knownFailureChains` | INSTALL-FRICTIONS entries + accumulated debug-session knowledge |

## databases — per-DB field derivation

| Field | Source |
|---|---|
| `secretNamePattern` | Helm template's Secret name with `<release>` placeholder |
| `serviceLabelSelector` | Spilo cluster labels — verify against `kubectl get svc -l ... -n runwhen` on a live install |
| `fallbackServiceName` | Service name in `templates/postgresql/` or `templates/<svc>-pgbouncer.yaml` |
| `database`, `username` | From `templates/postgresql/databases.yaml` or chart values |
| `consumedBy` | Cross-reference application source for which services connect to this DB |

## workflows-index.json

For each entry in `INSTALL-FRICTIONS.md` (and each known operational headache):

1. Pick a short `key` (e.g., `pod-stuck-init-wait-for-migrations`).
2. List `matchHints` — substrings users would type to describe the symptom.
3. Pick the right `skill` (one of the 7 topic skills).
4. List 2–4 `likelyCauses`.
5. List 2–4 `firstChecks` — concrete kubectl/helm commands with `<release>` placeholders.

## Validation

After authoring, run:

```bash
rwl-env/tests/test-catalog.sh
```

The test checks:
- JSON parses
- Required fields per service / database / symptom
- `consumedBy` references resolve
- `runtime.callsOut` references resolve
- `workflows-index.symptoms.*.skill` files exist
- Catalog and index agree on `chartAppVersion`

## Pinning to a chart appVersion

Both files have `chartAppVersion`. Update both when re-authoring against a new chart.

At runtime, `/rwl-env-cur` warns if the live release's appVersion differs from the catalog pin.
```

- [ ] **Step 2: Commit**

```bash
git add rwl-env/docs/CATALOG-AUTHORING.md
git commit -m "docs(rwl-env): catalog authoring guide"
```

---

### Task 31: Project-level CLAUDE.md update + marketplace version bump

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude-plugin/marketplace.json` (bump version)

- [ ] **Step 1: Add rwl-env section to project CLAUDE.md**

Append to `CLAUDE.md` (project-level, repo root):

```markdown

## rwl-env Plugin

Sibling plugin to `rwenv`, focused on helm-deployed RunWhen platform debugging.

### Differences from rwenv

| | rwenv | rwl-env |
|---|---|---|
| Topology | Multi-cluster GKE / k3s | Single helm release per entry |
| Execution | Container or local | Local only |
| Mutations | kubectl + helm gated | helm upgrade / rollback only |
| DB access | Per-env readOnly | Always read-only |
| Release lifecycle | n/a | `helm install`/`uninstall` out of scope |

### Safety invariants (enforced by `rwl-env/hooks/transform-commands.sh`)

- The only mutation paths are `helm upgrade` and `helm rollback`.
- `kubectl` writes (`apply`, `delete`, `patch`, etc.) are always blocked.
- `psql` is read-only: DDL/DML/COPY-TO blocked regardless of any readOnly flag.
- Hook engages only when `<project>/.claude/rwl-env-env` exists; otherwise pass-through.

### Key files

| File | Purpose |
|---|---|
| `rwl-env/lib/rwlenv-utils.sh` | Core utilities: config IO, kubeconfig discovery, write detection |
| `rwl-env/hooks/transform-commands.sh` | PreToolUse hook: validation, enforcement, auto-approval |
| `rwl-env/data/services-catalog.json` | Service facts (selector, image-tag-key, deps, runtime) |
| `rwl-env/data/workflows-index.json` | Symptom → debug skill mapping |
| `rwl-env/docs/CATALOG-AUTHORING.md` | How to refresh the catalog on chart bumps |
| `rwl-env/docs/MANUAL-TESTING.md` | End-to-end runbook |

### Version bumping

Bump `rwl-env/.claude-plugin/plugin.json` AND the entry in `.claude-plugin/marketplace.json`. Marketplace version is bumped independently.
```

- [ ] **Step 2: Bump marketplace.json version**

Modify `.claude-plugin/marketplace.json` — bump the marketplace's own `metadata.version` from `0.1.0` to `0.2.0`:

```bash
jq '.metadata.version = "0.2.0"' .claude-plugin/marketplace.json > /tmp/m.json && mv /tmp/m.json .claude-plugin/marketplace.json
```

- [ ] **Step 3: Verify marketplace parses**

```bash
jq . .claude-plugin/marketplace.json >/dev/null && echo "marketplace.json OK"
jq '.plugins[].name' .claude-plugin/marketplace.json
```
Expected: `"rwenv"` and `"rwl-env"`.

- [ ] **Step 4: Run all tests one final time**

```bash
rwl-env/tests/test-utils.sh
rwl-env/tests/test-hooks.sh
rwl-env/tests/test-catalog.sh
rwl-env/tests/test-redact.sh
```
Expected: every test exits 0.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md .claude-plugin/marketplace.json
git commit -m "docs(rwl-env): project CLAUDE.md updated; marketplace bumped to 0.2.0"
```

---

## Self-Review Checklist (Run After Plan Execution)

When all 31 tasks are complete, verify:

- [ ] All four test scripts pass.
- [ ] `rwl-env/.claude-plugin/plugin.json` parses; version is `0.1.0`.
- [ ] `.claude-plugin/marketplace.json` lists both `rwenv` and `rwl-env`.
- [ ] `rwl-env/docs/MANUAL-TESTING.md` runbook executes end-to-end against a k3d cluster.
- [ ] No `_TODO_` markers anywhere in `rwl-env/data/`.
- [ ] CLAUDE.md (project root) mentions rwl-env's safety invariants.
- [ ] Catalog `chartAppVersion` matches a known release tag of `runwhen-platform`.
- [ ] All seven debug skills exist; the dispatcher references them; catalog test "every workflow skill exists as a file" passes.
- [ ] `helm-bug-reports/` is `.gitignore`'d in any project that's used `/rwl-report-chart-bug`.
