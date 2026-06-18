### Ingress TLS modes

The chart supports three TLS modes — pick exactly one:

**Mode 2 — cert-manager ClusterIssuer** (generated overlay uses this)
The named `ClusterIssuer` must be `Ready=True` before `helm install`:
```bash
kubectl get clusterissuer <name>
```
cert-manager annotates every Ingress and issues per-service certs automatically.

**cert-manager Issuer (namespace-scoped)**
Use `ingress.annotations: { cert-manager.io/issuer: <name> }` and set
`ingress.tls.certManager.enabled: true` with `certManager.clusterIssuer: ""`.
The Issuer must exist in the release namespace.

**Mode 3 — Bring-your-own wildcard Secret** (generated overlay uses this for BYO)
Pre-create a TLS Secret in the release namespace holding `*.<domain>` cert+key:
```bash
kubectl create secret tls <secret-name> \
  --cert=path/to/wildcard.crt \
  --key=path/to/wildcard.key \
  -n <release-namespace>
```
Set `ingress.tls.existingSecret: <secret-name>` and
`ingress.tls.certManager.enabled: false`.

**Snippet annotations** (`ingress.allowSnippetAnnotations: true`) require the
ingress-nginx controller ConfigMap to set `allow-snippet-annotations: "true"`.
Without this, the admission webhook rejects the install. See known issue
`ingress-not-rendered` for details.
