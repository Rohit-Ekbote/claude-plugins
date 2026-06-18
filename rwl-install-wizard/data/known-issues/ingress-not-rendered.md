## Ingress not rendered: `ingress.enabled` default is false / snippet webhook denies

**Symptom A — no Ingress objects created after install:**
`kubectl get ingress -n <ns>` returns nothing. All services are deployed but
nothing is reachable at `papi.<domain>` etc.

**Cause A:** `ingress.enabled` defaults to `false` in `values.yaml`. The
generated overlay sets it to `true`; verify the overlay is passed to `helm
upgrade --install` with `-f values-cluster.yaml`.

**Symptom B — `helm install` fails with admission webhook error:**
```text
Error: admission webhook "validate.nginx.ingress.kubernetes.io" denied the request:
nginx.ingress.kubernetes.io/server-snippet annotation cannot be used.
Snippet directives are disabled by the Ingress administrator
```

**Cause B:** The chart uses `server-snippet` on the PAPI Ingress (to deny
`/internal/` paths) and `configuration-snippet` on the runner-metric-proxy
Ingress (for mTLS client cert header). The ingress-nginx admission webhook
rejects these unless snippet mode is enabled at the controller level.

**Fix B — controller (cluster admin):** In the ingress-nginx HelmRelease or
ConfigMap, set:
```yaml
controller:
  allowSnippetAnnotations: true
  config:
    allow-snippet-annotations: "true"
    annotations-risk-level: Critical
```

**Workaround (temporary):** Set `ingress.allowSnippetAnnotations: false` in the
overlay to skip snippet annotations. Side effects: no `/internal/` nginx deny
on PAPI, and the runner-metric-proxy Ingress is not created (external runner
metric push disabled until snippets are re-enabled).

_Source: INSTALL-FRICTIONS.md §1._
