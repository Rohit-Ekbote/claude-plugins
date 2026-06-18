### External S3 object storage

Use an external S3-compatible backend (AWS S3, GCS S3-interop, Backblaze B2,
JFrog Artifactory S3 generic, etc.) instead of the bundled SeaweedFS.

**Key values set by this option:**

```yaml
objectStorage:
  kind: external
  external:
    host: "<S3_ENDPOINT>"        # public host for presigned URLs (no scheme)
    internalHost: "<S3_ENDPOINT>" # in-cluster host:port for pods
    region: "us-east-1"          # or your bucket's region
seaweedfs:
  deploy: false
```

**Credentials:** supply access key and secret key via a pre-created Kubernetes
Secret referenced by `objectStorage.existingSecret` (or by `existingConfigSecret`
depending on the chart version). Never pass credentials as inline values — wire
by `existingSecret` name only.

**Buckets:** create the required buckets on the external backend before
installing. The chart-managed bucket-init Job targets SeaweedFS only and is
skipped when `kind: external`. Required bucket names:
`shared-workspace`, `mimir-blocks`, `mimir-ruler`, `mimir-alertmanager`,
`agentfarm-artifacts`, `postgres-backups`, `vault-backups`.

**Endpoint format:** provide the full URL including scheme (e.g.
`https://s3.amazonaws.com` or `http://internal-s3.corp:9000`). For AWS S3
the `host` parameter should be your bucket's regional endpoint or a custom
domain for presigned URL routing.

_Source: values.yaml `objectStorage.external` block (lines 1932–1944);
INSTALL-FRICTIONS.md §22._
