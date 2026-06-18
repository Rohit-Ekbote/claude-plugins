### StorageClass pinning

The chart pins a single StorageClass across SeaweedFS, Mimir, and Qdrant PVCs.
Discover what is available on your cluster:

```bash
kubectl get storageclass
```

Common defaults by cloud:

| Cloud | StorageClass |
|-------|-------------|
| GKE (2024+) | `standard-rwo` |
| EKS | `gp3` |
| AKS | `managed-csi` |
| k3s / local-path | `local-path` |

**Important:** `seaweedfs.volume.dataDirs` is a list that Helm replaces
wholesale. The overlay must restate all fields (`name`, `type`, `size`,
`storageClass`, `maxVolumes`). Keep `maxVolumes × volumeSizeLimitMB` under
75% of `size` to leave headroom for per-volume overhead.

All PVCs in this chart require `accessModes: ReadWriteOnce` (RWO) — a RWX or
NFS-backed class will work but is not required.
