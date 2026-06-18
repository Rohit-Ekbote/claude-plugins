### NFS-backed storage posture

This overlay implements the lab/NFS posture from `values-example-storage-nfs.yaml`:

- **Persistent tier (NFS PVCs):** SeaweedFS master topology metadata,
  volume server bulk data, and filer LevelDB metadata. These are the durability
  anchor — losing them is unrecoverable in this posture.
- **Ephemeral tier (emptyDir):** SeaweedFS filer logs, S3 gateway logs,
  Redis (cache only), Neo4j workspace graph (rebuilt from Postgres on next
  reconcile), Mimir TSDB head/WAL (long-term blocks live in S3).
- **Qdrant:** NFS is not supported by Qdrant (RocksDB needs block-level POSIX
  semantics). Set `qdrant.useSubchart: false` to use the chart's in-chart
  Deployment on emptyDir instead. Vectors are rebuildable from source.

**Prerequisites:**

1. An NFS-backed StorageClass must exist on the cluster. Common provisioners:
   `sig-storage/nfs-subdir-external-provisioner`, Trident (NetApp),
   `csi-driver-nfs`. Verify with `kubectl get sc`.
2. The StorageClass name should already be set in the cluster-shape overlay.

**Important:** this overlay is designed for fresh installs. Switching
`volumeClaimTemplates`-backed components from PVC to emptyDir on a running
install requires deleting StatefulSets with `--cascade=orphan` and their PVCs
first.

After applying: zero hostPath volumes remain. Persistent surface narrows to
SeaweedFS NFS PVCs + Postgres PVC + Vault PVC (Postgres and Vault are also
backed up to SeaweedFS S3 by their respective backup jobs).

_Source: values-example-storage-nfs.yaml header comments; STORAGE.md
"Lab / fresh-install posture" and "NFS is the only StorageClass available"
sections._
