### No ClusterRoleBindings — namespace-scoped RBAC only

Enterprise clusters often enforce a policy that forbids ClusterRoleBindings. The
chart's own first-party templates are already namespace-scoped (Roles +
RoleBindings only — no ClusterRoles, no ClusterRoleBindings). The only
cluster-scoped binding the chart would otherwise render comes from the
HashiCorp Vault subchart's `server.authDelegator` toggle.

**What to disable:**
- `vault.server.authDelegator.enabled: false` — suppresses the
  `<release>-vault-server-binding` ClusterRoleBinding that the upstream Vault
  chart creates to grant the `system:auth-delegator` ClusterRole.

**What must be pre-created out-of-band** (one-time, cluster admin):
```bash
kubectl create clusterrolebinding <release>-vault-server-binding \
  --clusterrole=system:auth-delegator \
  --serviceaccount=<namespace>:<release>-vault
```
Vault's Kubernetes auth method (`vault auth enable kubernetes`) will not
function without this binding — it needs to call the TokenReview API, which
`system:auth-delegator` grants. Once pre-created by your cluster admin, the
chart no longer needs to manage it.

**If your policy also blocks `system:auth-delegator`:** you must switch Vault's
auth backend to AppRoles or another method that does not require the
TokenReview API. See `vault-injector-authdelegator` for details.

**First-party RBAC summary (all namespace-scoped):**
- Platform SA: Role covering ConfigMaps, Secrets, Pods (run/exec for task
  workers), and standard workload verbs within the release namespace.
- Vault-backup SA: Role scoped to `pods/exec` on the vault StatefulSet pod
  and `secrets/get` for the unseal-keys Secret.
- PostgreSQL/Spilo SA: Role covering endpoints, configmaps, pods, and
  services for Patroni leader election within the release namespace.

_Source: values.yaml `vault.server.authDelegator` block (lines 1266–1289);
values-example-enterprise-byo-sa.yaml §3 "Vault subchart — cluster-scoped RBAC
opt-outs"; INSTALL-FRICTIONS.md §2 (Vault MutatingWebhook) context._
