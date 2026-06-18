### Alert-ingestor public ingress

The alert-ingestor service (`alert-ingestor` deployment) receives SLI/SLO alert
payloads from Mimir Ruler and forwards them into the alert pipeline. Its public
ingress uses an nginx `server-snippet` annotation to restrict the endpoint.

nginx-ingress **denies snippet annotations by default** unless
`controller.allowSnippetAnnotations: true` is set on the ingress controller AND
`ingress.allowSnippetAnnotations: true` is set in the chart values.

The generated overlay sets `ingress.allowSnippetAnnotations: true` so the
alert-ingestor ingress renders its snippet. You must also ensure the nginx
ingress controller allows snippets — set `controller.allowSnippetAnnotations: true`
and `controller.config.annotations-risk-level: Critical` on the ingress-nginx
Helm release.

Emergency controller patch (unblocks install before Flux sync):
```bash
kubectl -n ingress-nginx patch configmap ingress-nginx-controller --type merge \
  -p '{"data":{"allow-snippet-annotations":"true","annotations-risk-level":"Critical"}}'
kubectl -n ingress-nginx rollout restart deployment ingress-nginx-controller
```

_Source: INSTALL-FRICTIONS.md §1 (2026-04-29) — snippet annotations denied._
