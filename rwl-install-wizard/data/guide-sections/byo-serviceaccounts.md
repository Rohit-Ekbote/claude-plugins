### BYO ServiceAccounts (chart does not create them)

In enterprise clusters with a centralized RBAC pipeline, the chart must
consume pre-existing ServiceAccounts rather than creating its own. Set
`serviceAccount.<sa>.create: false` for each identity and supply the
pre-provisioned SA name.

**Three ServiceAccounts the platform needs — all must exist before `helm install`:**

| Values key | Default chart name | Role |
|---|---|---|
| `serviceAccount.platform` | `<release>-platform` | PAPI, taskiq workers, migration-controller, and all first-party backend pods |
| `serviceAccount.vaultBackup` | `<release>-vault-backup` | Vault backup CronJob (`pods/exec` on vault pod + `secrets/get`) |
| `serviceAccount.postgresql` | `<release>-postgresql` | Spilo leader-election (endpoints/configmaps/pods/services in the release namespace) |

**What `create: false` disables:** the ServiceAccount object rendering AND the
chart's Role+RoleBinding for that SA. If your pipeline also forbids the chart
creating Roles and RoleBindings, supply both the SA and the Role+RoleBinding
out-of-band, using the rules from `templates/rbac.yaml` and
`templates/postgresql/spilo-rbac.yaml` as the reference.

**Values snippet:**
```yaml
serviceAccount:
  platform:
    create: false
    name: "rw-platform"      # must exist in the release namespace
  vaultBackup:
    create: false
    name: "rw-vault-backup"
  postgresql:
    create: false
    name: "rw-postgresql"
```

**Propagation note:** All pod specs and RoleBinding subjects resolve through
`runwhen.serviceAccountName.*` helpers — a single `name:` override propagates
consistently to every template that references that identity.

_Source: values-example-enterprise-byo-sa.yaml §2 "BYO ServiceAccounts";
values.yaml `serviceAccount:` block (lines 349–375)._
