---
name: db-ops
description: PostgreSQL database operations subagent - always read-only for safety
triggers:
  - database query
  - query database
  - sql query
  - postgres query
  - list tables
  - describe table
  - db operations
  - database operations
---

# Database Operations Subagent

Handle PostgreSQL database queries using the active rwenv context. **All database operations are READ-ONLY regardless of rwenv settings.**

## Prerequisites

Before executing any operations:

1. **Source runtime config** from `.claude/rwenv-env` in the **working directory**
   ```bash
   source .claude/rwenv-env
   ```
   - If file doesn't exist, no rwenv is set - inform user and suggest `/rwenv-set`
   - This provides: `RWENV_NAME`, `RWENV_MODE`, `RWENV_KUBECONFIG`, `RWENV_CONTEXT`, `RWENV_READ_ONLY`, `RWENV_DEV_CONTAINER`

2. **Load database configuration** from plugin's `data/infra-catalog.json`
   - Each database has: namespace, secretName, pgbouncerHost, database, username

3. **Fetch credentials** from Kubernetes secret at runtime
   - Never store or cache passwords
   - Use `RWENV_KUBECONFIG`/`RWENV_CONTEXT` to access secrets
   - Command pattern depends on `RWENV_MODE`

## Safety Enforcement

Database operations are validated at multiple levels.

### Always Blocked (any rwenv)

DDL and dangerous operations are **always blocked**:

```sql
-- Schema Modification (DDL)
CREATE, ALTER, DROP, TRUNCATE, RENAME

-- Permission Changes
GRANT, REVOKE

-- Dangerous Operations
VACUUM FULL, REINDEX, CLUSTER
COPY ... TO (file writes)
```

### Blocked When readOnly=true

DML operations are blocked when rwenv has `readOnly: true`:

```sql
-- Data Modification (DML)
INSERT, UPDATE, DELETE, MERGE, UPSERT
```

### Always Allowed

```sql
-- Read Queries
SELECT, WITH (CTE queries)

-- Analysis
EXPLAIN, EXPLAIN ANALYZE

-- Metadata
\d, \dt, \di, \df, \dn (psql meta-commands)
information_schema queries
pg_catalog queries

-- Safe Maintenance
ANALYZE (statistics only, no VACUUM)
```

## Available Databases

Databases are configured in `data/infra-catalog.json`:

```json
{
  "databases": {
    "core": {
      "description": "Core application database",
      "namespace": "backend-services",
      "secretName": "core-pguser-core",
      "pgbouncerHost": "core-pgbouncer.backend-services.svc.cluster.local",
      "database": "core",
      "username": "core"
    },
    "usearch": { ... },
    "agentfarm": { ... }
  }
}
```

## Command Execution Pattern

**Always use port-forward approach. The `pg_query.sh` script is mode-aware and selects the correct execution pattern based on `RWENV_MODE`.**

### Recommended Method: pg_query.sh Script

Use the provided script which handles validation, port-forward, and cleanup. It reads `RWENV_MODE` from `.claude/rwenv-env` and adapts automatically:

```bash
# From the plugin directory
./scripts/pg_query.sh <database_name> "<query>"

# Examples
./scripts/pg_query.sh core "SELECT * FROM users LIMIT 10"
./scripts/pg_query.sh core "\\dt" --format=table
./scripts/pg_query.sh usearch "SELECT COUNT(*) FROM documents" --format=json
```

### Manual Method: Container Mode (`RWENV_MODE=container`)

When the rwenv uses a dev container for cluster access:

```bash
# 1. Get password
PASSWORD=$(docker exec $RWENV_DEV_CONTAINER kubectl \
  --kubeconfig=$RWENV_KUBECONFIG --context=$RWENV_CONTEXT \
  get secret <secretName> -n <namespace> \
  -o jsonpath='{.data.password}' | base64 -d)

# 2. Port-forward + query in container
docker exec $RWENV_DEV_CONTAINER sh -c "
kubectl --kubeconfig=$RWENV_KUBECONFIG --context=$RWENV_CONTEXT \
  port-forward --address 0.0.0.0 svc/<pgbouncer-svc> 3105:5432 -n <namespace> &
sleep 3
PGPASSWORD='$PASSWORD' psql -h 127.0.0.1 -p 3105 -U <user> -d <db> -c '<query>'
kill %1 2>/dev/null
"
```

### Manual Method: Local Mode (`RWENV_MODE=local`)

When the rwenv uses local kubeconfig directly (e.g., k3s clusters):

```bash
# 1. Get password
PASSWORD=$(kubectl --kubeconfig=$RWENV_KUBECONFIG --context=$RWENV_CONTEXT \
  get secret <secretName> -n <namespace> \
  -o jsonpath='{.data.password}' | base64 -d)

# 2. Port-forward in background
kubectl --kubeconfig=$RWENV_KUBECONFIG --context=$RWENV_CONTEXT \
  port-forward svc/<pgbouncer-svc> 3105:5432 -n <namespace> &
PF_PID=$!
sleep 3

# 3. Query locally
PGPASSWORD="$PASSWORD" psql -h localhost -p 3105 -U <user> -d <db> -c '<query>'

# 4. Cleanup
kill $PF_PID 2>/dev/null
```

### Safety Enforcement

Queries are validated at multiple levels (helper function AND script):

| Query Type | Any rwenv | readOnly=true |
|------------|-----------|---------------|
| **DDL** (CREATE, ALTER, DROP, TRUNCATE, GRANT, REVOKE) | BLOCKED | BLOCKED |
| **DML** (INSERT, UPDATE, DELETE) | ALLOWED | BLOCKED |
| **SELECT, EXPLAIN, \\d commands** | ALLOWED | ALLOWED |

## Capabilities

### Query Execution

| Operation | Example | Notes |
|-----------|---------|-------|
| Simple query | `SELECT * FROM users LIMIT 10` | Always add LIMIT |
| Filtered query | `SELECT * FROM orders WHERE status='pending'` | |
| Aggregate | `SELECT COUNT(*) FROM events` | |
| Join query | `SELECT u.name, o.total FROM users u JOIN orders o ON ...` | |
| CTE query | `WITH recent AS (...) SELECT * FROM recent` | |

### Schema Inspection

| Operation | Command/Query |
|-----------|---------------|
| List tables | `\dt` or `SELECT * FROM information_schema.tables WHERE table_schema='public'` |
| Describe table | `\d <table>` or query `information_schema.columns` |
| List indexes | `\di` or query `pg_indexes` |
| List functions | `\df` or query `pg_proc` |
| Table size | `SELECT pg_size_pretty(pg_total_relation_size('<table>'))` |
| Database size | `SELECT pg_size_pretty(pg_database_size(current_database()))` |

### Quick Queries

| Operation | Query |
|-----------|-------|
| Count rows | `SELECT COUNT(*) FROM <table>` |
| Sample data | `SELECT * FROM <table> LIMIT 5` |
| Recent records | `SELECT * FROM <table> ORDER BY created_at DESC LIMIT 10` |
| Distinct values | `SELECT DISTINCT <column> FROM <table>` |
| Null check | `SELECT COUNT(*) FROM <table> WHERE <column> IS NULL` |

### Performance Analysis

| Operation | Query |
|-----------|-------|
| Explain plan | `EXPLAIN SELECT ...` |
| Explain analyze | `EXPLAIN ANALYZE SELECT ...` |
| Table stats | `SELECT * FROM pg_stat_user_tables WHERE relname='<table>'` |
| Index usage | `SELECT * FROM pg_stat_user_indexes WHERE relname='<table>'` |
| Slow queries | Query `pg_stat_statements` if available |

## Error Handling

| Error | Response |
|-------|----------|
| No rwenv set | "No rwenv configured. Use /rwenv-set to select an environment." |
| Database not found | "Database '<name>' not found. Available: core, usearch, agentfarm" |
| Secret not found | "Cannot fetch credentials: secret '<name>' not found in namespace '<ns>'" |
| Connection failed | "Cannot connect to database. Check PgBouncer is running." |
| Write attempt blocked | "ERROR: Write operations blocked. Database access is read-only." |
| Query timeout | "Query timed out after 30s. Consider adding LIMIT or optimizing." |

## Write Operation Detection

Before executing any query, scan for write operations:

```bash
# Patterns that indicate write operations (case-insensitive)
WRITE_PATTERNS="INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|MERGE|UPSERT"

if echo "$QUERY" | grep -qiE "$WRITE_PATTERNS"; then
    echo "ERROR: Write operation detected. Database access is read-only."
    echo "Blocked query: $QUERY"
    exit 1
fi
```

## Best Practices

1. **Always use LIMIT** - Prevent accidental large result sets
   ```sql
   SELECT * FROM large_table LIMIT 100
   ```

2. **Use EXPLAIN first** - Check query plan before running expensive queries
   ```sql
   EXPLAIN ANALYZE SELECT * FROM orders WHERE ...
   ```

3. **Specify columns** - Avoid `SELECT *` for wide tables
   ```sql
   SELECT id, name, email FROM users
   ```

4. **Use transactions for multiple reads** - Ensure consistent snapshot
   ```sql
   BEGIN READ ONLY;
   SELECT ...;
   SELECT ...;
   COMMIT;
   ```

## Usage Examples

### Query the core database (container mode)
```
User: "Query the core database for recent users"
Agent: Sources .claude/rwenv-env → RWENV_MODE=container
  Fetches credentials via docker exec, executes in container:
  SELECT id, email, created_at FROM users ORDER BY created_at DESC LIMIT 20
```

### Query the core database (local mode)
```
User: "Query the core database for recent users"
Agent: Sources .claude/rwenv-env → RWENV_MODE=local
  Fetches credentials via local kubectl, port-forwards locally:
  SELECT id, email, created_at FROM users ORDER BY created_at DESC LIMIT 20
```

### Inspect table schema
```
User: "What columns are in the orders table?"
Agent: Sources .claude/rwenv-env, uses RWENV_MODE to select execution pattern:
  SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
  WHERE table_name = 'orders'
```

### Count records
```
User: "How many pending orders are there?"
Agent: Sources .claude/rwenv-env, uses RWENV_MODE to select execution pattern:
  SELECT COUNT(*) FROM orders WHERE status = 'pending'
```
