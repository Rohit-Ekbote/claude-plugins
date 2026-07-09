## Ingress snippet annotations disabled (hardened controller)

Your ingress controller rejects nginx snippet annotations (the ingress-nginx
default since v1.9; CVE-2021-25742). This kit therefore emits:

- `ingress.allowSnippetAnnotations: false`
- `runnerMetricProxy.cnValidation.enabled: false`
- `runnerMetricProxy.ingress.renderWithoutSnippet: true`

Effect: the runner-metric-proxy Ingress renders WITHOUT the mTLS / CN-validation
snippet annotations (server-TLS only). Enforce runner authentication at the
network layer. Full runbook: the chart's `docs/install/runner-metric-proxy-no-mtls.md`.

Do NOT also enable the alert-ingestor optional component in this mode — it
requires snippet annotations the controller will reject.
