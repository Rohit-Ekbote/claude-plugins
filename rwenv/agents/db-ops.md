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

1. **Verify rwenv is set** for current directory
   - Database operations require an rwenv to get kubernetes context

2. **Load rwenv configuration** from `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json`
   - Get `kubernetesContext`, `kubeconfigPath` settings
   - These are required to access Kubernetes secrets for credentials

3. **Load database configuration** from `data/infra-catalog.json`
   - Databases are defined in the plugin's infra catalog
   - Each database has: namespace, secretName, pgbouncerHost, database, username

4. **Fetch credentials** from Kubernetes secret at runtime
   - Never store or cache passwords
   - Use kubeconfig/context from step 2 to access secrets

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

**Always use port-forward approach via `pg_query.sh` script.**

### Recommended Method: pg_query.sh Script

Use the provided script which handles validation, port-forward, and cleanup:

```bash
# From the plugin directory
./scripts/pg_query.sh <database_name> "<query>"

# Examples
./scripts/pg_query.sh core "SELECT * FROM users LIMIT 10"
./scripts/pg_query.sh core "\\dt" --format=table
./scripts/pg_query.sh usearch "SELECT COUNT(*) FROM documents" --format=json
```

### Manual Method (If Needed)

Step-by-step port-forward approach:

```bash
# 1. Get password from K8s secret
PASSWORD=$(docker exec <container> kubectl --kubeconfig=<path> --context=<ctx> \
  get secret <secretName> -n <namespace> -o jsonpath='{.data.password}' | base64 -d)

# 2. Port-forward (binds to 0.0.0.0:3105, accessible from host)
docker exec <container> kubectl --kubeconfig=<path> --context=<ctx> \
  port-forward --address 0.0.0.0 svc/<pgbouncer-svc> 3105:5432 -n <namespace> &

# 3. Wait for port-forward to establish
sleep 2

# 4. Run query (from container)
docker exec <container> sh -c "PGPASSWORD='$PASSWORD' psql -h 127.0.0.1 -p 3105 -U <user> -d <db> -c '<query>'"

# Or from host (if psql installed):
# PGPASSWORD="$PASSWORD" psql -h localhost -p 3105 -U <user> -d <db> -c '<query>'

# 5. Cleanup
pkill -f "port-forward.*<pgbouncer-svc>"
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

### Query the core database
```
User: "Query the core database for recent users"
Agent: Fetches credentials, executes:
  SELECT id, email, created_at FROM users ORDER BY created_at DESC LIMIT 20
```

### Inspect table schema
```
User: "What columns are in the orders table?"
Agent: Executes:
  SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
  WHERE table_name = 'orders'
```

### Count records
```
User: "How many pending orders are there?"
Agent: Executes:
  SELECT COUNT(*) FROM orders WHERE status = 'pending'
```
