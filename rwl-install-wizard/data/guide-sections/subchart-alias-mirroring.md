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

**Air-gapped install — point each alias at your enterprise Helm chart mirror:**

An image mirror is not enough — the thin chart resolves five *chart* aliases at
`helm dependency update` time. You gave the wizard a Helm chart-mirror base URL
(`<HELM_MIRROR_URL>`); each alias below is re-pointed at it. (If you left it
blank, substitute your enterprise Helm chart repository base URL — one per
upstream, e.g. `.../helm-bitnami`, `.../helm-neo4j` on Artifactory/JCR.)

```bash
helm repo add bitnami    <HELM_MIRROR_URL>/bitnami
helm repo add neo4j      <HELM_MIRROR_URL>/neo4j
helm repo add hashicorp  <HELM_MIRROR_URL>/hashicorp
helm repo add qdrant     <HELM_MIRROR_URL>/qdrant
helm repo add seaweedfs  <HELM_MIRROR_URL>/seaweedfs
helm repo update
helm dependency update ./runwhen-platform
```

On Artifactory/JCR, remotes are usually one URL per upstream — use
`<HELM_MIRROR_URL>/helm-bitnami`, `<HELM_MIRROR_URL>/helm-neo4j`, etc., and add
`--username`/`--password` on each `helm repo add` if the remote requires auth
(`helm registry login` alone returns 401 on classic Helm indexes).

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
