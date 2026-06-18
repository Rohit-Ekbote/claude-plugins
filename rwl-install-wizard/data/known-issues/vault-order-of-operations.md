## Vault order-of-operations: migration controllers race vault-init

**Symptom (§32 + §34):** On a clean install, migration controllers start as soon
as Postgres is ready (~15–45 s). The `vault-init` Job takes 30–90 s to complete
(Vault container start + `vault operator init` + unseal + policy seeding). If
migration controllers win the race they run Alembic against a Vault that is not
yet initialized — secret-seeding steps silently no-op. App pods then start (their
`wait-for-migrations` init container exits successfully) and crash on the first
request that resolves a Vault-backed secret.

**The chart fixes this (resolved 2026-05-18):** all three migration-controller
StatefulSets include a `wait-for-vault` init container (runs AFTER `wait-for-db`)
that polls `http://<release>-vault:8200/v1/sys/health` every 5 s and only proceeds
when the response is HTTP 200 (initialized + unsealed + active). This init container
is rendered only when `vault.deploy: true`; external Vault skips it.

**Gating rule (§34, resolved 2026-05-25):** downstream pods (`papi`, `agentfarm`,
`usearch`) use a `wait-for-migrations` init container. That container MUST poll
`/ready` (HTTP 200 = Alembic at head, migrations complete), NOT `/health`
(HTTP 200 = process alive only). The migration controller serves `/health: 200`
even when Alembic migrations have not yet run to completion. Using `/health` was
the root cause of §34; the shipped chart now polls `/ready`.

**Required start-up order:**

```
Vault initialized + unsealed (vault-init Job completes)
    ↓
DB bootstrap complete (db-init Job + pgbouncer app auth ready)
    ↓
Migration controllers reach /ready (Alembic at head for all three schemas)
    ↓
Application workloads start
```

**Workaround for pre-fix chart** (if hitting §32):
```bash
for ss in rw-migration-controller rw-agentfarm-migration-controller rw-usearch-migration-controller; do
  kubectl rollout restart statefulset/$ss -n <ns>
done
kubectl rollout restart deployment/rw-papi deployment/rw-agentfarm -n <ns>
```

_Source: INSTALL-FRICTIONS.md §32 (vault race, 2026-05-18) and §34 (db-init race, 2026-05-25)._
