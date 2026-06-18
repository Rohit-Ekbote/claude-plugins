## Thin chart: five Helm subchart aliases required before `helm dep update`

**Symptom:** `helm install` or `helm dependency update` fails immediately:

```text
Error: no such repository name: bitnami
```

or after pulling the chart:

```text
Error: cannot find Subchart `postgresql` in the chart's `charts/` directory
```

**Cause:** The `runwhen-platform` OCI chart is **thin** — it does not bundle
its upstream subcharts (Bitnami, HashiCorp Vault, Neo4j, Qdrant, SeaweedFS).
Each upstream chart's license (HashiCorp BSL, Bitnami CNCF terms, Neo4j
commercial, etc.) bars RunWhen from redistributing their chart bytes inside
the RunWhen artifact. The five subcharts must be fetched by the operator's
workstation at install time via `helm dependency update`.

`Chart.yaml` references each subchart as `@alias` (e.g. `repository: "@bitnami"`).
The alias must be registered in `helm repo` before `helm dep update` runs —
otherwise Helm cannot resolve the alias to a URL.

**Fix:** Register the five aliases on the install workstation before any
`helm pull` / `helm install` / `helm dependency update`:

```bash
# Connected install — public upstreams:
helm repo add bitnami    https://charts.bitnami.com/bitnami
helm repo add neo4j      https://helm.neo4j.com/neo4j
helm repo add hashicorp  https://helm.releases.hashicorp.com
helm repo add qdrant     https://qdrant.github.io/qdrant-helm
helm repo add seaweedfs  https://seaweedfs.github.io/seaweedfs/helm
helm repo update
helm dependency update ./runwhen-platform
```

For air-gapped installs, substitute each public URL with your enterprise
Helm chart mirror URL — the alias names must remain unchanged.

Use `helm dependency update` (not `build`). `build` requires `Chart.lock`
URLs to match the operator's registered aliases exactly; `update` rewrites
`Chart.lock` to match, which is what makes the same chart work for both
connected and air-gapped installs without editing `Chart.yaml`.

_Source: INSTALL-FRICTIONS.md §33 (by design, 2026-05-25)._
