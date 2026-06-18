### BYO external datastores

Use managed (customer-operated) datastores instead of bundled subcharts. Set each
datastore's deploy flag to `false` and supply external connection details. The chart
treats the external service as already bootstrapped — it skips the relevant init Jobs.

**PostgreSQL external** (`postgresql.kind: external`):

```yaml
postgresql:
  kind: external
  deploy: false
  external:
    host: "<PG_HOST>"
    port: "<PG_PORT>"
    database: "<PG_DATABASE>"
    username: "<PG_USERNAME>"
```

Credentials: pre-create a Kubernetes Secret and reference it via a separate
credentials overlay. The chart reads `rw-postgresql-credentials` by default;
supply it out-of-band or use the chart's `postgresql.external.password` field
in a non-wizard overlay (wizard never emits password literals).

**Redis external** (`redis.deploy: false`):

```yaml
redis:
  deploy: false
  external:
    host: "<REDIS_HOST>"
    port: "<REDIS_PORT>"
```

Credentials: set `redis.external.password` in a credentials-only overlay (not via wizard).

**Neo4j external** (`neo4j.deploy: false`):

```yaml
neo4j:
  deploy: false
  external:
    uri: "<NEO4J_URI>"
    username: "<NEO4J_USERNAME>"
```

URI format: `bolt://host:7687`. Credentials: set `neo4j.external.password` in a
credentials-only overlay (not via wizard). For production, Neo4j Aura or self-hosted
on local SSD/NVMe (NFS NOT supported — see known issues).

**Vault external** (`vault.deploy: false`):

```yaml
vault:
  deploy: false
  address: "<VAULT_ADDRESS>"
```

Address format: `https://vault.example.com`. The chart skips `vault-init` Job when
`vault.deploy: false` — the external Vault must be pre-bootstrapped with the
`runner-system` KV mount and Kubernetes auth method configured for the release namespace.

**Qdrant external** (`qdrant.deploy: false`):

```yaml
qdrant:
  deploy: false
  useSubchart: false
  external:
    url: "<QDRANT_URL>"
```

URL format: `http://qdrant.example.com:6333`. Both flags must be `false` to avoid
an unused subchart StatefulSet (see `Chart.yaml` line 64 comment).

Source: `Chart.yaml` lines 39–68; `values.yaml` lines 1006–1016 (postgres external),
1077–1084 (redis external), 1232–1238 (neo4j external), 1244–1249 (vault deploy/address),
1756–1824 (qdrant deploy/useSubchart/external).
