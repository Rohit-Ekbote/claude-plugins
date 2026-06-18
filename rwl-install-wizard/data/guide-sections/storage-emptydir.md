### emptyDir (ephemeral) persistence

All rebuildable components use emptyDir. This posture requires no RWO
StorageClass for the rebuildable tier, suitable for clusters with no dynamic
provisioner or for disposable lab environments.

**What this sets:**

- `metricstore.persistence.kind: emptyDir` — Mimir TSDB head/WAL/bucket-store
  sync. Long-term metric blocks still live in the S3 backend (SeaweedFS or
  external). First query after a pod restart is slow while the bucket-store
  re-syncs from S3.
- `redis.master.persistence.enabled: false` — Bitnami's standard emptyDir
  fallback. Redis is a cache; in-flight Celery jobs retry on restart.
- `neo4j.volumes.data.mode: volume` + `emptyDir` — workspace topology graph
  rebuilt from Postgres on next reconcile. Cost: minutes of indexing lag.
- `postgresql.spilo.persistence.kind: emptyDir` — Postgres data directory on
  emptyDir. **Requires `walg.enabled: true`** (enforced by the chart): if all
  replicas restart simultaneously, recovery is via WAL-G restore from S3.
  S3 backend becomes load-bearing for normal operations.
- `qdrant.useSubchart: false` — uses the chart's minimal in-chart Deployment on
  emptyDir instead of the upstream StatefulSet-on-PVC. NFS and emptyDir are the
  only safe options for Qdrant (vendor does not support NFS anyway).

**StatefulSet immutability:** switching an existing install to emptyDir requires
deleting affected StatefulSets with `--cascade=orphan` and their PVCs. Designed
for fresh installs.

_Source: STORAGE.md per-component matrix; INSTALL-FRICTIONS.md §20a
(postgresql.spilo.persistence.kind emptyDir mode)._
