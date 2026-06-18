## PostgreSQL bundled subchart: single-pod, node-local storage

**Symptom (§20):** The default `bitnami/postgresql` subchart runs as a
single-pod StatefulSet on a single PVC. With `local-path` StorageClass the PVC
is node-local — if the node disappears the volume disappears and all platform
state is lost. There are no backups and no HA.

**Resolution:** Switch `postgresql.kind: spilo` for production installs. The
chart ships a namespaced Spilo StatefulSet (Patroni + WAL-G) that handles HA
and continuous WAL archiving to S3 — no CRDs, no ClusterRole.

---

## `postgresql.spilo.persistence.kind` modes (§20a)

When using `postgresql.kind: spilo`, the persistence kind controls how the
Postgres data directory is backed:

| kind | Behavior | When to pick |
|---|---|---|
| `pvc` (default) | StatefulSet `volumeClaimTemplates` — data survives pod restart | Cluster has a real RWO StorageClass |
| `ephemeral` | Inline generic ephemeral PVC — deleted with pod, auto-GC'd | StorageClass exists but you want per-pod-lifecycle semantics |
| `emptyDir` | No StorageClass needed at all — data lost on restart, WAL-G restore | Cluster has no RWO StorageClass available |

**Hard constraint for `emptyDir`:** `walg.enabled: true` is required (the
chart fails the template render if you set `kind: emptyDir` with
`walg.enabled: false`). With emptyDir, the S3 backend becomes load-bearing
for normal operations — if S3 is down when all replicas restart, the database
is offline until S3 returns.

**Recommended `archiveTimeout` for emptyDir:** 10s (default 60s). Controls
the worst-case "WAL committed but not yet shipped to S3" window.

_Source: INSTALL-FRICTIONS.md §20 and §20a; STORAGE.md "Postgres" row._
