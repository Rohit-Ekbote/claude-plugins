### Registry: flat mirror (`registryOverride`)

Use this pattern when a single mirror host fronts every upstream registry under
a flat namespace — e.g. a Harbor project, an ECR pull-through cache, or a
generic Distribution mirror.

Set the chart's top-level `registryOverride` knob. When set, it **replaces the
registry portion** of every chart-rendered image:

```yaml
registryOverride: "<REGISTRY_HOST>"

images:
  pullSecrets:
    - name: <PULL_SECRET_NAME>

global:
  imagePullSecrets:
    - name: <PULL_SECRET_NAME>
```

`registryOverride` covers first-party services, utility init containers
(busybox, db-init psql, vault-client), and chart-controlled subchart-adjacent
images (Mimir, pgbouncer, Vault unsealer/backup). It does **not** reach
subchart-emitted images (Vault server, Redis, Neo4j, Qdrant, SeaweedFS,
Spilo) — those need per-subchart `image.*` overrides in the same overlay.

**Pull secret pre-flight:**
Create the pull secret before `helm install`. The `docker-server` field must be
the host name only (no scheme, no path):

```bash
kubectl -n <namespace> create secret docker-registry <PULL_SECRET_NAME> \
  --docker-server=<REGISTRY_HOST_ONLY> \
  --docker-username=<user> \
  --docker-password=<token>
```

**Verify your overrides** before installing:

```bash
helm template rw charts/runwhen-platform \
  -f charts/runwhen-platform/values.yaml \
  -f values-registry.yaml \
  | grep -E '^\s+image:\s' | sort -u
```

Every line should start with your mirror host. Lines still pointing at
`us-docker.pkg.dev`, `ghcr.io`, or `docker.io` are subchart images not yet
covered by `registryOverride`.
