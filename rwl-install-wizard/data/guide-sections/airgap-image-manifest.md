### Air-gap image manifest (`images-to-mirror.txt`) + pre-seeding

Before the cluster can pull anything, **every** image the chart renders must
already live on your mirror (`<REGISTRY_HOST>`). Produce the exact list from
*your* overlays, then copy each image across.

#### 1. Generate the authoritative list from your overlays (preferred)

The chart ships `image-scripts/fetch-chart-images.sh`. Run it on the install
workstation against the same overlays you install with — it renders the chart
(parent + all five subcharts) and emits `images.txt` (flat, deduped) plus
`images.json`:

```bash
./charts/runwhen-platform/image-scripts/fetch-chart-images.sh \
  -f charts/runwhen-platform/values.yaml \
  -f values-registry.yaml \
  -f values-storage.yaml \
  -f values-cluster.yaml \
  -o ./out
cp ./out/images.txt images-to-mirror.txt
```

This is the source of truth — it reflects the exact tags pinned in *your* chart
version, so it never drifts from the baseline table below.

#### 2. Baseline list (fallback, chart `~0.2.x`)

If you cannot render the chart yet, seed from this baseline, then re-verify with
step 1 once you have the chart on disk. Save as `images-to-mirror.txt`
(upstream refs — the left column is what you copy *from*):

```text
# images-to-mirror.txt — upstream refs; mirror each to <REGISTRY_HOST>/<repo>:<tag>
us-docker.pkg.dev/runwhen-self-hosted/platform-images/backend-services:2026-07-02.1
us-docker.pkg.dev/runwhen-self-hosted/platform-images/agent-farm:2026-07-02.1
us-docker.pkg.dev/runwhen-self-hosted/platform-images/runner-control:rc-2026-06-12.1
us-docker.pkg.dev/runwhen-self-hosted/platform-images/webhooks-service:2026-06-29.1
us-docker.pkg.dev/runwhen-self-hosted/platform-images/usearch:2026-07-02.1
us-docker.pkg.dev/runwhen-self-hosted/platform-images/ui:2026-07-02.1
us-docker.pkg.dev/runwhen-self-hosted/platform-images/shared-services:2026-07-02.1
ghcr.io/runwhen-contrib/runwhen-platform-mcp:2026-06-30.2
ghcr.io/runwhen-contrib/cc-catalog-svc:2026-06-23.2
ghcr.io/runwhen-contrib/cortex-tenant:2026-05-20.1
ghcr.io/berriai/litellm-non_root:v1.88.2
ghcr.io/zalando/spilo-17:4.0-p2
docker.io/library/busybox:1.36
docker.io/hashicorp/vault:1.21.2
docker.io/bitnamilegacy/redis:8.2.1-debian-12-r0
docker.io/bitnamilegacy/postgresql:17.6.0-debian-12-r4
docker.io/grafana/mimir:2.14.0
docker.io/qdrant/qdrant:v1.18.0
docker.io/library/neo4j:5.26.0
docker.io/chrislusf/seaweedfs:4.25
docker.io/edoburu/pgbouncer:v1.24.1-p1
# helm-test-only (qdrant test pod) — mirror ONLY if you run `helm test`:
registry.suse.com/bci/bci-base:15.7
```

> Tags track a specific chart revision. `neo4j`, `vault`, `qdrant`, `redis`,
> and `seaweedfs` are pinned by the resolved subchart versions — confirm each
> against your chart (see the chart-version section) or, better, regenerate with
> step 1. The six code-collection images (`rw-*`/`*-c7n-codecollection`) are
> selected dynamically by `cc-catalog-svc` at task time; mirror the current
> dated tag and keep `listRemoteFolderItems` enabled on the ghcr remote.

> **Canonical source for the overlay's hard-pinned tags.** Three tags in this
> baseline — `library/neo4j:5.26.0`, `hashicorp/vault:1.21.2`, and
> `bci/bci-base:15.7` — are also emitted as full-value overrides in
> `values-registry.yaml` (and restated in its `x-airgap-pinned-tags-notice`
> block). This baseline is the single source of truth for those three; if you
> change one here, change it in the overlay too. The wizard's regression guard
> asserts the two stay identical, so they cannot silently drift.

#### 3. Copy each image to the mirror — PER-UPSTREAM, path-preserving (skopeo)

The generated `values-registry.yaml` uses the per-upstream, path-preserving
model: each image keeps its source path under a per-upstream remote
(`docker-dockerhub`, `docker-ghcr`, `docker-runwhen-self-hosted`, `docker-suse`).
**The push target for every image is exactly the ref the overlay renders** — so
the copy targets below are, by construction, what the cluster will pull. (This is
why the old single-prefix `registryOverride`/flat-mirror model was removed: it
collapsed images to `<mirror>/<repo>`, disagreeing with these push paths →
ImagePullBackOff.)

Map each upstream host to its per-upstream remote and preserve the rest of the
path (rename the `docker-*` remote segments if your mirror named them differently
— keep them identical in `values-registry.yaml` and here):

```bash
to_mirror() {
  ref="$1"; host="${ref%%/*}"; path="${ref#*/}"
  case "$host" in
    us-docker.pkg.dev)               echo "<REGISTRY_HOST>/docker-runwhen-self-hosted/${path}" ;;
    ghcr.io)                         echo "<REGISTRY_HOST>/docker-ghcr/${path}" ;;
    docker.io|registry-1.docker.io)  echo "<REGISTRY_HOST>/docker-dockerhub/${path}" ;;
    registry.suse.com)               echo "<REGISTRY_HOST>/docker-suse/${path}" ;;
    quay.io)                         echo "<REGISTRY_HOST>/docker-quay/${path}" ;;
    *) echo "UNMAPPED-UPSTREAM:$ref" >&2; return 1 ;;
  esac
}
while read -r ref; do
  case "$ref" in \#*|"") continue ;; esac
  dst="$(to_mirror "$ref")" || { echo "no mapping for $ref — add one"; continue; }
  skopeo copy --all "docker://$ref" "docker://$dst"
done < images-to-mirror.txt
```

**Verify overlay == manifest** before installing — every rendered ref must be a
target this loop pushes to:

```bash
helm template <RELEASE> <CHART_REF> \
  -f runwhen-platform/values.yaml -f values-registry.yaml \
  | grep -Eo '(image|customImage): *"?[^" ]+' | awk '{print $2}' | sort -u
# Each line must start with <REGISTRY_HOST>/docker-... and match a to_mirror() target.
```

`crane cp <upstream-ref> <to_mirror-target>` works equally well.

#### 4. Digest-pin for immutable, supply-chain-verifiable installs

Tags are mutable; a re-pushed upstream tag silently changes what you deploy.
For hardened installs, resolve each ref to its `sha256:` digest and pin by
digest in your overlay so the cluster only ever runs the bytes you scanned:

```bash
# Resolve digests once, after mirroring (against the per-upstream target path):
crane digest <REGISTRY_HOST>/docker-dockerhub/library/neo4j:5.26.0
#   sha256:abc123...
```

Then pin the resolved digest instead of the tag, e.g.:

```yaml
neo4j:
  image:
    customImage: "<REGISTRY_HOST>/docker-dockerhub/library/neo4j@sha256:abc123..."
vault:
  server:
    image:
      repository: "<REGISTRY_HOST>/docker-dockerhub/hashicorp/vault"
      tag: "sha256:def456..."        # digest form; drops tag-rug risk
```

Record the digest ↔ tag mapping in your change-control system so a re-scan is
reproducible. Re-resolve digests whenever you bump the chart version.
