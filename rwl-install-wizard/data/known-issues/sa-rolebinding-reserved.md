## sa-rolebinding-reserved: Enterprise pipeline reserves SA and RoleBinding creation

**Symptom:** `helm install` is blocked because your cluster's admission policy
or security policy forbids chart-created ServiceAccounts or RoleBindings:

```
Error: admission webhook "..." denied the request:
ServiceAccount creation is not permitted; use a pre-provisioned identity
```

Or the chart's Role+RoleBinding is rejected because the SA it binds to does
not yet exist at apply time.

**Cause:** Enterprise clusters with a centralized RBAC pipeline (GitOps-driven
RBAC, PAM integration, automated least-privilege provisioning) reserve
ServiceAccount and RoleBinding creation for that pipeline exclusively. The
chart's default behavior of creating its own SAs and RoleBindings is
incompatible with this posture.

**Resolution:**

1. Have your RBAC pipeline pre-provision all three ServiceAccounts (and
   optionally the Roles+RoleBindings) before `helm install`:
   - `<PLATFORM_SA_NAME>` — used by all backend pods
   - `<VAULT_BACKUP_SA_NAME>` — used by the vault-backup CronJob
   - `<POSTGRESQL_SA_NAME>` — used by Spilo for Patroni leader election

2. Set `create: false` and provide the pre-provisioned names:
   ```yaml
   serviceAccount:
     platform:
       create: false
       name: "<PLATFORM_SA_NAME>"
     vaultBackup:
       create: false
       name: "<VAULT_BACKUP_SA_NAME>"
     postgresql:
       create: false
       name: "<POSTGRESQL_SA_NAME>"
   ```

3. If your pipeline also forbids chart-rendered Roles and RoleBindings:
   consult `templates/rbac.yaml` and `templates/postgresql/spilo-rbac.yaml`
   for the exact rules (they are namespace-scoped only — no ClusterRoles) and
   have the pipeline provision them before install.

**Note:** `create: false` disables BOTH the SA object AND the chart's
Role+RoleBinding for that identity. If you want the chart to render the
Role+RoleBinding against your own SA name, keep `create: true` and override
only `name:`.

_Source: values-example-enterprise-byo-sa.yaml §2 (BYO ServiceAccounts —
comment "If your policy also forbids the chart creating Roles/RoleBindings");
values.yaml lines 340–375 (serviceAccount block with `create: false`
semantics documented inline)._
