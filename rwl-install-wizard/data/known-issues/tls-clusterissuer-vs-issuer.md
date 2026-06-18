## TLS issuer confusion: internal runner-control Issuer vs public ingress ClusterIssuer

**Symptom:** Operators installing cert-manager see both `Issuer` and
`ClusterIssuer` resources in the namespace after install and are unsure which
one controls public HTTPS, or why a `ClusterIssuer` is not listed even when
only `ingress.tls.certManager.clusterIssuer` is set.

**Cause:** The chart uses cert-manager for two independent purposes:

| Purpose | Resource kind | Configured via |
|---------|--------------|----------------|
| Public ingress TLS | `ClusterIssuer` (cluster-scoped) | `ingress.tls.certManager.clusterIssuer` in overlay |
| Runner mTLS bundle (internal) | `Issuer` (namespace-scoped) | `runwhenCA.deploy: true` (default); chart-managed, not operator-configured |

The runner-control `Issuer` resources (`<release>-selfsigned`,
`<release>-runner-ca-issuer`, `<release>-runner-metrics-ca-issuer`) are always
created when `runwhenCA.deploy: true` (the default). They issue certificates for
runner ↔ platform mTLS; they are **not** the public ingress cert authority.

The public ingress `ClusterIssuer` (e.g. `letsencrypt-prod`) is **not** created
by this chart — it must already exist on the cluster before `helm install`.

**Verification:**
```bash
# Should list the chart-managed runner CA issuers:
kubectl get issuer -n <ns>

# Should exist independently (cluster admin pre-created):
kubectl get clusterissuer <your-clusterissuer-name>
```

**cert-manager CRDs are required** regardless of TLS mode — even Mode 3
(BYO wildcard secret) requires cert-manager for runner mTLS Issuers and
Certificates. Install will fail at apply with `no matches for kind "Issuer"`
if cert-manager is absent.

_Source: INSTALL-FRICTIONS.md §19 (cert-manager is always required)._
