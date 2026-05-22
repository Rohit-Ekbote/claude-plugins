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
