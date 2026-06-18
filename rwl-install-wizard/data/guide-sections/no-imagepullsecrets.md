### No imagePullSecrets — registry-layer auth

When image pull authentication is handled at the registry layer (Artifactory
pull-through cache, Harbor proxy, ECR pull-through, or any registry that
issues node-level credentials via a credential provider plugin), per-pod
`imagePullSecrets` are unnecessary. Set both lists to empty:

```yaml
global:
  imagePullSecrets: []   # subcharts that honor global.* (vault, redis, seaweedfs)

images:
  pullSecrets: []        # chart-managed pods via ServiceAccount annotation
```

The chart only emits `imagePullSecrets:` blocks on ServiceAccounts and pod
specs when these lists are **non-empty**. Leaving both as empty lists (the
chart default) is therefore correct for this posture — no change required
unless you were previously setting them.

**Subchart exceptions — still need per-subchart override if NOT honoring global:**
- `neo4j.imagePullSecrets: []` (Neo4j does not honor `global.imagePullSecrets`)
- `qdrant.imagePullSecrets: []` (same; requires `[{name: ...}]` format)

For most registry-layer-auth deployments these are already empty by default, so
no explicit override is needed.

**Contrast with airgap/mirror posture:** if you are using a flat mirror or
JFrog per-upstream layout (`registry-routing` axis), you DO need
`imagePullSecrets` pointing at the pre-created pull secret. This guide section
applies only to the enterprise posture where auth is at the registry node layer.

_Source: values-example-enterprise-byo-sa.yaml §1 (both `imagePullSecrets: []`
and `images.pullSecrets: []` with comment "Use when image pull is authenticated
at the registry layer"); values.yaml lines 260–265 (global.imagePullSecrets
block + DISABLING comment)._
