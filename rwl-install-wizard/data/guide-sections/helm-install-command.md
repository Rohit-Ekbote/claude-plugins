### The composed install command (Phase 5)

Layer the overlays this kit generated **in order**, each as its own `-f`. Order
matters: `values.yaml` is the base; later files win on conflict.

> The wizard writes this command with **exactly one `-f` per overlay that
> actually landed in `rwl-install-out/`** — no more, no fewer. The full set of
> possible overlays is `values-registry.yaml`, `values-storage.yaml`,
> `values-cluster.yaml`, `values-posture.yaml`; a run that produced no
> posture/RBAC overlay, for instance, has **no** `-f values-posture.yaml` line.
> Match the `-f` list to the file list printed in the generation summary.

Canonical layer order (drop any line whose file this run did not write):

```
-f runwhen-platform/values.yaml     # always — chart base
-f values-registry.yaml             # if generated — image routing (goes early)
-f values-storage.yaml              # if generated — persistence
-f values-cluster.yaml              # if generated — domain / ingress / TLS / LLM / optional
-f values-posture.yaml              # if generated — security / RBAC
```

```bash
helm upgrade --install <RELEASE> <CHART_REF> \
  --namespace <NAMESPACE> --create-namespace \
  -f runwhen-platform/values.yaml \
  <one -f line per generated overlay, in the order above>
```

- `<CHART_REF>` is the local path (`./runwhen-platform`, after `helm pull … --untar`
  + `helm dependency update`) or the OCI ref
  (`oci://<REGISTRY_HOST>/.../charts/runwhen-platform --version <CHART_VERSION>`).
- Registry routing is layered early so every later layer inherits mirrored images.
- Do a client-side dry run first (no cluster contact), using the same `-f` set:
  ```bash
  helm template <RELEASE> <CHART_REF> \
    -f runwhen-platform/values.yaml <same -f overlays as above> \
    | grep -E '^\s+image:\s' | sort -u
  ```
  In an air-gap install every line must start with `<REGISTRY_HOST>`. Any line
  still on `us-docker.pkg.dev`, `ghcr.io`, `docker.io`, or `quay.io` is an image
  your overlay has not re-pointed — fix it before installing.
