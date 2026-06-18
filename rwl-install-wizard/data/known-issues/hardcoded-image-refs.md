## Hardcoded image refs blocked air-gapped installs (RESOLVED chart 0.2.x, 2026-05-18)

**Symptom:** In a fully air-gapped cluster, backend deployments stall in
`Init:0/N` even after setting registry overrides. Init containers pull from
literal image strings like `busybox:1.36` that ignore any `registryOverride`
or per-image `registry:` knob.

**Cause (chart ≤ v1 airgap surface):** Five template files emitted hardcoded
image strings that no values overlay could redirect: `busybox:1.36` (used by
the `wait-for-migrations` init container across 18+ deployments),
`docker.io/bitnami/postgresql:latest` (db-init Job), `hashicorp/vault:1.21.2`
(vault-init Job), `docker.io/amazon/aws-cli:latest` (Spilo bucket-init Job),
and `quay.io/minio/mc:...` (MinIO bucket-init). Containerd resolved each
literal string against Docker Hub regardless of mirror configuration.

**Fix (chart 0.2.x, final form — `registryOverride` aligned with runner chart):**
The chart now exposes:
- A single top-level `registryOverride: ""` knob (replaces registry portion of
  every chart-rendered image when set).
- `global.utility.{busybox,dbInit,vaultClient}` blocks with standard
  `{registry, repository, tag}` shape — these cover every formerly-hardcoded
  utility image.

Setting `registryOverride: "<mirror>"` (flat mirror) or per-image
`global.utility.<key>.registry: "<mirror>"` (per-upstream) routes all utility
images through the customer mirror. No hardcoded paths remain in chart
templates (except the Qdrant `helm test` Pod, which only renders during
`helm test`, not `helm install`).

_Source: INSTALL-FRICTIONS.md §30 (resolved v2, 2026-05-18)._
