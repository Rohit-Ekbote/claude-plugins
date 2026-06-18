## Mimir TSDB head + WAL on ephemeral filesystem (not PVC)

**Symptom:** Mimir pod restarts wipe ~2h of un-shipped metrics. PromQL queries
return thin or empty data after restarts. The Mimir PVC is Bound but empty
(`du -sh` shows 4K). Distributor/ingester metrics show ingest is fine but
the on-disk story is ephemeral.

**Cause (pre-fix chart):** Mimir's local path keys were not configured in the
chart's `metricstore/configmap.yaml`. The Mimir defaults for `tsdb.dir`,
`bucket_store.sync_dir`, `compactor.data_dir`, `ruler.rule_path`, and
`alertmanager.data_dir` are relative paths evaluated against the container's
working directory (`cwd=/`). All writes went to the container rootfs (not the
PVC). The PVC was allocated and entirely unused.

**Fix (landed in chart):** All Mimir local paths are now pinned to
subdirectories under `/data` (the PVC mount). After `kubectl rollout restart
sts/<release>-mimir`, the PVC populates correctly.

**If you see this on an existing install:**

1. Check whether the PVC is populated:
   ```bash
   kubectl debug <release>-mimir-0 --image=busybox:1.36 --target=mimir \
     --share-processes -it=false -- sh -c 'du -sh /proc/1/root/data'
   ```
2. If empty, upgrade to the latest chart version and restart Mimir.

**With `metricstore.persistence.kind: emptyDir`:** the TSDB head/WAL is on
emptyDir by design. Long-term blocks live in S3 (`mimir-blocks` bucket). The
first query after a pod restart is slow while the bucket-store re-syncs from
S3; steady-state performance is unaffected. This is the expected trade-off for
the NFS/emptyDir posture.

_Source: INSTALL-FRICTIONS.md §23._
