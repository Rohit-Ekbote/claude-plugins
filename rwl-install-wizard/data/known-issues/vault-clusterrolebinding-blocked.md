## vault-clusterrolebinding-blocked: Vault subchart ClusterRoleBinding denied by admission policy

**Symptom:** `helm install` or `helm upgrade` fails with an admission webhook
or OPA/Kyverno/Gatekeeper denial blocking the creation of the
`<release>-vault-server-binding` ClusterRoleBinding:

```
Error: admission webhook "..." denied the request:
ClusterRoleBindings are not permitted in this cluster
```

Or the Vault injector's MutatingWebhookConfiguration is blocked:

```
conflict occurred while applying object rw-vault-agent-injector-cfg
admissionregistration.k8s.io/v1, Kind=MutatingWebhookConfiguration
```

**Cause:** The upstream HashiCorp Vault subchart renders two cluster-scoped
objects by default:
1. `<release>-vault-server-binding` ClusterRoleBinding (for `system:auth-delegator`)
2. `<release>-vault-agent-injector-cfg` MutatingWebhookConfiguration + backing
   ClusterRole/ClusterRoleBinding for the Vault Agent Injector

Enterprise clusters with policy controllers (OPA Gatekeeper, Kyverno, PSS
admission, internal webhooks) commonly block both.

**Resolution:**

Set both values to disable chart-side rendering:
```yaml
vault:
  injector:
    enabled: false
  server:
    authDelegator:
      enabled: false
```

Then have a cluster admin pre-create the one binding Vault genuinely needs:
```bash
kubectl create clusterrolebinding <release>-vault-server-binding \
  --clusterrole=system:auth-delegator \
  --serviceaccount=<namespace>:<release>-vault
```

The injector is not needed by chart-managed services and can remain
permanently disabled. The authDelegator binding MUST exist (pre-created
out-of-band) for the Vault Kubernetes auth method to function.

**Resolved:** chart 0.2.3 — `vault.injector.enabled` defaults `false`;
`vault.server.authDelegator.enabled` toggle added.

_Source: values-example-enterprise-byo-sa.yaml §3; values.yaml lines 1260–1289;
INSTALL-FRICTIONS §2 (Vault MutatingWebhook caBundle conflict)._
