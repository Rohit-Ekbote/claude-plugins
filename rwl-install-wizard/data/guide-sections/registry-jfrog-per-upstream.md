### Registry: JFrog per-upstream mirror (per-image `registry:`)

Use this pattern when the mirror path differs per upstream registry — the
canonical example is JFrog Artifactory / JCR with one virtual repo per
upstream (`docker-dockerhub/`, `docker-ghcr/`, `docker-quay/`, etc.).

A single `registryOverride` cannot express this layout. Instead, set
per-image `registry:` overrides. The chart concatenates
`<registry>/<repository>:<tag>` for each image.

**YAML anchor pattern** (recommended) — collapse each upstream prefix to one
rotatable value. Changing the JCR host is then one edit:

```yaml
x-jcr-anchors:
  jcr-rwsh:        &jcr_rwsh        "<REGISTRY_HOST>/docker-runwhen-self-hosted/runwhen-self-hosted/platform-images"
  jcr-dh:          &jcr_dh          "<REGISTRY_HOST>/docker-dockerhub"
  jcr-ghcr-rwc:    &jcr_ghcr_rwc    "<REGISTRY_HOST>/docker-ghcr/runwhen-contrib"
  jcr-ghcr-zalando: &jcr_ghcr_zalando "<REGISTRY_HOST>/docker-ghcr/zalando"
  jcr-ghcr-berriai: &jcr_ghcr_berriai "<REGISTRY_HOST>/docker-ghcr/berriai"

global:
  imagePullSecrets:
    - name: <PULL_SECRET_NAME>
  utility:
    busybox:     { registry: *jcr_dh }
    dbInit:      { registry: *jcr_dh }
    vaultClient: { registry: *jcr_dh }

images:
  pullSecrets:
    - name: <PULL_SECRET_NAME>
  registry: *jcr_rwsh          # default for first-party services
  mcpServer:   { registry: *jcr_ghcr_rwc }
  ccCatalog:   { registry: *jcr_ghcr_rwc }
  llmGateway:  { registry: *jcr_ghcr_berriai }

runnerMetricProxy:
  image:
    registry: *jcr_ghcr_rwc

postgresql:
  spilo:
    image:
      registry: *jcr_ghcr_zalando
  pgbouncer:
    image:
      registry: *jcr_dh

vault:
  autoUnseal:
    image:
      registry: *jcr_dh
  backup:
    image:
      registry: *jcr_dh

metricstore:
  image:
    registry: *jcr_dh
```

Subchart images (Vault server, Redis, Neo4j, Qdrant, SeaweedFS) use different
schema — see `registry-routing.md` Subchart images table for the per-subchart
override key for each.

**JFrog remote setup prerequisite:** each upstream needs a Docker Remote
repository in JFrog/JCR with the correct `includesPattern`. See
`docs/install/airgap-jfrog-proxy-setup.md` for the per-remote YAML configs
and the idempotent applier script.
