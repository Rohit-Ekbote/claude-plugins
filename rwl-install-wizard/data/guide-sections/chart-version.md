### Confirm your chart version (Phase 0)

This kit was generated for chart range `<CHART_COMPAT>`. The overlays assume the
image tags, subchart pins, and knob shapes of a chart in that range. Confirm the
version you are about to install matches — a mismatch is the most common reason
a mirrored overlay renders a tag your registry does not have.

**Where to read your chart version:**

- **OCI pull (thin chart from your registry):**
  ```bash
  helm show chart oci://<REGISTRY_HOST>/.../charts/runwhen-platform --version <CHART_VERSION> \
    | grep '^version:'
  ```
- **Chart already on disk** (after `helm pull ... --untar`): the `version:` field
  in `runwhen-platform/Chart.yaml`.
- **Installed release:** `helm list -n <namespace>` → the `CHART` column shows
  `runwhen-platform-<version>`.

**Subchart image tags this kit pins** (verify against your chart's resolved
subchart versions — they move independently of the parent chart version):

| Subchart | Image | Tag pinned here |
|---|---|---|
| Neo4j | `library/neo4j` | `5.26.0` |
| Vault (server) | `hashicorp/vault` | `1.21.2` |
| Qdrant | `qdrant/qdrant` | chart default (`v1.18.0`) |
| Redis | `bitnamilegacy/redis` | chart default |
| SeaweedFS | `chrislusf/seaweedfs` | chart default |

Read your chart's `Chart.lock` (after `helm dependency update`) for the exact
resolved subchart versions, or run `image-scripts/fetch-chart-images.sh` to have
the chart itself report the tags it renders. If your chart is **outside**
`<CHART_COMPAT>`, treat these overlays as unverified and re-confirm every image
tag before install.
