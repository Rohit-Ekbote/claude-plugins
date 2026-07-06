### The composed install command (Phase 5)

Layer the overlays this kit generated **in order**, each as its own `-f`. Order
matters: `values.yaml` is the base; later files win on conflict. Only the
overlays that were actually generated appear below — drop any `-f` line whose
file this kit did not write.

```bash
helm upgrade --install <RELEASE> <CHART_REF> \
  --namespace <NAMESPACE> --create-namespace \
  -f runwhen-platform/values.yaml \
  -f values-registry.yaml \
  -f values-storage.yaml \
  -f values-cluster.yaml \
  -f values-posture.yaml
```

- `<CHART_REF>` is the local path (`./runwhen-platform`, after `helm pull … --untar`
  + `helm dependency update`) or the OCI ref
  (`oci://<REGISTRY_HOST>/.../charts/runwhen-platform --version <CHART_VERSION>`).
- **Recommended `-f` order:** base → `values-registry.yaml` (image routing) →
  `values-storage.yaml` (persistence) → `values-cluster.yaml` (domain/ingress/TLS/
  LLM/optional) → `values-posture.yaml` (security/RBAC). Registry routing goes
  early so every later layer inherits mirrored images.
- Do a client-side dry run first (no cluster contact):
  ```bash
  helm template <RELEASE> <CHART_REF> \
    -f runwhen-platform/values.yaml -f values-registry.yaml \
    -f values-storage.yaml -f values-cluster.yaml -f values-posture.yaml \
    | grep -E '^\s+image:\s' | sort -u
  ```
  In an air-gap install every line must start with `<REGISTRY_HOST>`. Any line
  still on `us-docker.pkg.dev`, `ghcr.io`, `docker.io`, or `quay.io` is an image
  your overlay has not re-pointed — fix it before installing.
