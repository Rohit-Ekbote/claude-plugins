### Vault injector and authDelegator

The HashiCorp Vault subchart ships two cluster-scoped objects by default:
1. **Agent Injector** — a `MutatingWebhookConfiguration` + `ClusterRole` +
   `ClusterRoleBinding` for sidecar injection via Vault Agent.
2. **authDelegator** — a `ClusterRoleBinding` to `system:auth-delegator`
   that allows Vault to call the Kubernetes TokenReview API (required for the
   Kubernetes auth method).

**Chart-managed services do not use the injector** — they authenticate to Vault
via the Kubernetes auth method directly (pod identity / projected service-account
tokens). Disable the injector unconditionally:

```yaml
vault:
  injector:
    enabled: false
```

This cuts a Deployment, a Service, a MutatingWebhookConfiguration, and three
cluster-scoped RBAC objects. It also eliminates the Helm server-side apply
`caBundle` field-manager conflict (INSTALL-FRICTIONS §2).

**authDelegator — suppress chart-rendering, pre-create manually:**

```yaml
vault:
  server:
    authDelegator:
      enabled: false
```

When `authDelegator.enabled: false`, the chart no longer renders the
ClusterRoleBinding. A cluster admin must create it once, out-of-band:

```bash
kubectl create clusterrolebinding <release>-vault-server-binding \
  --clusterrole=system:auth-delegator \
  --serviceaccount=<namespace>:<release>-vault
```

Without this binding (chart-rendered OR manually created), Vault's
Kubernetes auth method (`vault auth enable kubernetes`) cannot validate
service-account tokens via the TokenReview API, and every vault-init
policy/role write will fail with 403.

**If `system:auth-delegator` is also blocked by policy:**
Switch Vault's auth method to AppRoles:
```bash
vault auth enable approle
vault write auth/approle/role/platform ...
```
AppRoles authenticate without calling TokenReview, so no ClusterRoleBinding
is needed. This requires changes to the vault-init Job's bootstrap logic —
confirm with RunWhen support before proceeding.

_Source: values.yaml `vault.injector` / `vault.server.authDelegator` blocks
(lines 1260–1289); values-example-enterprise-byo-sa.yaml §3; INSTALL-FRICTIONS
§2 (Vault MutatingWebhook conflict)._
