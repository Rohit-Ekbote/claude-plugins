### Bundled SeaweedFS object storage

SeaweedFS is the chart's default S3 backend (Apache 2.0, namespace-scoped, no
CRDs, no ClusterRole). It exposes the S3 API on port 8333. All platform S3
consumers (workspace uploads, Mimir blocks/ruler/alertmanager, presigned URLs,
Postgres WAL-G backups, Vault backups) use the same access key wired through
`objectStorage.accessKey` / `objectStorage.secretKey`.

**Key values set by this option:**

```yaml
objectStorage:
  kind: seaweedfs
seaweedfs:
  deploy: true
```

The chart generates an `identities.json` Secret (`<release>-seaweedfs-identities`)
and wires it to `seaweedfs.s3.existingConfigSecret`. The access and secret keys
in `platform-secrets` and the SeaweedFS identities Secret are generated in
lockstep on first install to avoid the Access Denied mismatch (see known issue
`seaweedfs-s3-access-denied`).

**Buckets provisioned automatically** (via the chart-managed bucket-init Job):
`shared-workspace`, `mimir-blocks`, `mimir-ruler`, `mimir-alertmanager`,
`agentfarm-artifacts`, `postgres-backups`, `vault-backups`.

_Source: values.yaml `objectStorage` block (lines 1842–1944); INSTALL-FRICTIONS.md §22._
