### Durable PVC persistence

All rebuildable components (Mimir, Neo4j, Redis) stay on their default PVCs.
SeaweedFS master/volume/filer use PVCs via the StorageClass set in the
cluster-shape overlay. Postgres and Vault PVCs are always present regardless
of this choice.

**Verify available StorageClasses before installing:**

```bash
kubectl get storageclass
```

All PVCs in this chart require `accessModes: ReadWriteOnce` (RWO).

**StatefulSet immutability:** switching `persistence.kind` or storageClass on an
existing install requires deleting the StatefulSet with `--cascade=orphan` and
its PVCs first. This is a fresh-install option.

_Source: STORAGE.md "Production / customer posture" section._
