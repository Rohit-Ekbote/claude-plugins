## Qdrant does not support NFS for its primary data volume

**Symptom:** Qdrant pods crash or produce corrupt collection data when
`/qdrant/storage` is on an NFS-backed PVC. Errors may appear as RocksDB
file-lock failures, mmap errors, or silent data corruption.

**Cause:** Qdrant (via RocksDB) requires block-level POSIX filesystem semantics
— specifically reliable `mmap` and `fsync` behavior. NFS does not provide these
guarantees. This is an explicit vendor restriction documented in
[Qdrant installation docs](https://qdrant.tech/documentation/installation/).

**Fix:** Set `qdrant.useSubchart: false`. This replaces the upstream Qdrant
StatefulSet-on-PVC with the chart's minimal in-chart Deployment on emptyDir.
The Service name and ports are unchanged, so consumer wiring (`VECTOR_STORE_URL`
env var) is unaffected.

```yaml
qdrant:
  useSubchart: false
```

**Trade-off:** Vectors are stored on emptyDir — lost on pod restart and rebuilt
from source on the next embedding pass. Qdrant is classified as REBUILDABLE
(tier 3) in the chart's storage matrix: losing `/qdrant/storage` is an
embedding-cost event, not data loss.

**Neo4j note:** Neo4j also does not support NFS for its primary data volume
(RocksDB internals, same root cause). Use
`neo4j.volumes.data.mode: volume` + `emptyDir` on NFS clusters. The workspace
topology graph is rebuilt from Postgres on the next reconcile cycle.

_Source: values-example-storage-nfs.yaml (Qdrant comment, line 47–51);
STORAGE.md "Qdrant" row and "NFS is the only StorageClass available" section._
