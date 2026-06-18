### Bundled datastores (all-in-cluster)

The chart deploys six bundled subchart components by default — five datastores plus
SeaweedFS (object storage, covered by the `object-storage` axis separately):

| Subchart | Condition key | Role |
|---|---|---|
| `bitnami/postgresql` | `postgresql.deploy: true` | Platform state (users, workspaces, migrations) — **production: prefer `kind: spilo`** |
| `bitnami/redis` | `redis.deploy: true` | Celery broker + Django cache (rebuildable) |
| `neo4j/neo4j` | `neo4j.deploy: true` | Workspace topology graph (rebuildable) |
| `hashicorp/vault` | `vault.deploy: true` | Secrets backend (initialised by `vault-init` Job) |
| `qdrant/qdrant` | `qdrant.useSubchart: true` | Vector store for embeddings (rebuildable) |

Source: `Chart.yaml` lines 39–68.

**PostgreSQL mode selector.** The chart has three PG backends:
`kind: spilo` (default, production — Patroni + WAL-G, no CRDs),
`kind: bundled` (bitnami subchart, dev/lab only, single pod, no HA, no backups — see known issues),
`kind: external` (point at managed Postgres).
`postgresql.deploy: true` is the legacy flag for `kind: bundled`; when `kind` is set it takes precedence.

Source: `values.yaml` lines 594–612.

**Start-up dependency chain.** Clean installs must proceed in this order:

```
vault-init Job (initialises + unseals Vault)
    ↓
migration-controllers (wait-for-vault init container polls /v1/sys/health until 200)
    ↓  (also wait-for-db-bootstrap: Postgres role + DB must exist)
papi / agentfarm / usearch (wait-for-migrations polls /ready — NOT /health)
```

Three migration controllers run in parallel once Vault is ready:
`rw-migration-controller` (core schema),
`rw-agentfarm-migration-controller` (agentfarm schema),
`rw-usearch-migration-controller` (usearch schema).

Gating rule: migration-controller dependents MUST poll `/ready` (HTTP 200 = Alembic at head),
not `/health` (HTTP 200 = controller process alive). Using `/health` was the root cause of
INSTALL-FRICTIONS §34; the fix is chart-side and shipped.

Source: INSTALL-FRICTIONS §32 (vault race, resolved 2026-05-18) and §34 (db-init race, resolved 2026-05-25).
