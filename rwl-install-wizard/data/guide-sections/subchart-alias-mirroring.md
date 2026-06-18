### Subchart Helm chart alias mirroring

The `runwhen-platform` chart is **thin** — it ships without bundled subcharts
(Bitnami/HashiCorp/Neo4j/Qdrant/SeaweedFS licenses bar redistribution). The
install workstation must register five Helm repo aliases before `helm dep update`:

**Connected install — public upstreams:**

```bash
helm repo add bitnami    https://charts.bitnami.com/bitnami
helm repo add neo4j      https://helm.neo4j.com/neo4j
helm repo add hashicorp  https://helm.releases.hashicorp.com
helm repo add qdrant     https://qdrant.github.io/qdrant-helm
helm repo add seaweedfs  https://seaweedfs.github.io/seaweedfs/helm
helm repo update
helm dependency update ./runwhen-platform
```

**Air-gapped install — point each alias at your enterprise mirror:**

```bash
helm repo add bitnami    https://<your-helm-mirror>/bitnami
helm repo add neo4j      https://<your-helm-mirror>/neo4j
helm repo add hashicorp  https://<your-helm-mirror>/hashicorp
helm repo add qdrant     https://<your-helm-mirror>/qdrant
helm repo add seaweedfs  https://<your-helm-mirror>/seaweedfs
helm repo update
helm dependency update ./runwhen-platform
```

The alias **names** (`bitnami`, `neo4j`, `hashicorp`, `qdrant`, `seaweedfs`)
are non-negotiable — `Chart.yaml` references them as `@bitnami`, `@neo4j`,
etc. Use `helm dependency update` (not `build`) — it rewrites `Chart.lock`
to match the operator's registered aliases, which is what makes the same chart
work for both connected and air-gapped installs.

**Symptom when aliases are missing:**
```text
Error: no such repository name: bitnami
```
or:
```text
Error: cannot find Subchart `postgresql` in the chart's `charts/` directory
```

_Source: INSTALL-FRICTIONS.md §33 (by design). Chart.yaml subchart alias block._
