## PostgreSQL bundled subchart: single-pod, no HA, no backups, node-local storage

**Symptom (§20):** `postgresql.kind: bundled` (or legacy `postgresql.deploy: true`)
deploys `bitnami/postgresql` as a StatefulSet with `replicas: 1` and a single PVC.
On clusters using a `local-path` StorageClass the PVC is node-local — if the node
disappears, the volume disappears and all platform state is lost.

Nothing in the chart provides backups, high availability, read replicas, automatic
failover, or WAL archiving when using the bundled subchart. This PVC holds every
durable state object the platform owns: PAPI `core` DB (workspaces, users, orgs,
LLM config), agentfarm sessions, webhooks subscriptions.

**Recommended path for production:** switch to `postgresql.kind: spilo`. The chart
ships a Spilo StatefulSet (Postgres + Patroni + WAL-G) in the release namespace:
no CRDs, no cluster-scoped RBAC, namespace-scoped HA with automatic failover and
continuous WAL archiving to S3 (SeaweedFS or external).

Patroni members: set `postgresql.spilo.replicas: 2` (1 leader + 1 replica) or `3`
(full quorum, 3 nodes required). Anti-affinity preset: `podAntiAffinity: soft`
tolerates single-node clusters; `hard` requires N distinct nodes.

To migrate from bundled to Spilo: pg_dump from the bundled pod, pg_restore into
Spilo, then switch `kind: spilo` and `deploy: false` in the overlay.

Postgres operators (CloudNativePG, Crunchy PGO, Zalando postgres-operator) give
the same HA + PITR capabilities more declaratively but each requires CRDs and a
cluster-wide controller — incompatible with namespace-only installs.

_Source: INSTALL-FRICTIONS.md §20; values.yaml lines 594–612._
