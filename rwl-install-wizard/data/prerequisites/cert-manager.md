## cert-manager (cluster prerequisite)

This kit relies on cert-manager. It is required when EITHER:
- the chart's internal runner CA is enabled (`runwhenCA.deploy: true`, the
  default) — it renders `cert-manager.io/v1` Issuer + Certificate objects; OR
- ingress TLS is issued by a cert-manager ClusterIssuer/Issuer.

**Verify it is installed and healthy before `helm install`:**

    kubectl get pods -n cert-manager
    kubectl get crd | grep cert-manager.io
    kubectl get clusterissuers 2>/dev/null   # if you use a ClusterIssuer

If cert-manager is NOT installed and you cannot add it, re-run `/rwl-install`,
answer "No" to the internal runner CA question (emits `runwhenCA.deploy: false`),
and choose the bring-your-own TLS Secret ingress option.
