## SeaweedFS S3 `Access Denied` — platform-secrets key mismatch

**Symptom:** Mimir (and other S3 consumers) log:

```text
blocks storage: unable to successfully send a request to object storage: Access Denied.
ruler storage: unable to successfully send a request to object storage: Access Denied.
```

SeaweedFS S3 gateway is up; the bucket-init Job may have succeeded. Access key
matches (e.g. `rw`) but the secret key does not.

**Cause:** On first install, `randAlphaNum 32` was called independently for
each Secret template in a single Helm render, producing three different random
secret keys:

| Consumer | Secret | Key |
|---|---|---|
| Mimir, PAPI, Vault backup | `<release>-platform-secrets` | `S3_SECRET_KEY` |
| SeaweedFS S3 gateway | `<release>-seaweedfs-identities` | identities JSON |
| Spilo WAL-G | `<release>-postgresql-credentials` | `AWS_SECRET_ACCESS_KEY` |

Clients authenticate with key A, SeaweedFS expects key B, WAL-G uses key C.

**Resolution (chart-side fix landed):** The `secretKeyValue` helper now caches
the generated value once per render, so all three Secrets receive the same key
on a fresh install.

**Workaround for an already-installed release (pre-fix chart):**

```bash
NS=<your-namespace>
ACCESS=$(kubectl -n $NS get secret <release>-platform-secrets \
  -o jsonpath='{.data.S3_ACCESS_KEY}' | base64 -d)
SECRET=$(kubectl -n $NS get secret <release>-platform-secrets \
  -o jsonpath='{.data.S3_SECRET_KEY}' | base64 -d)
# Rebuild SeaweedFS identities Secret to match platform-secrets
kubectl -n $NS create secret generic <release>-seaweedfs-identities \
  --from-literal=seaweedfs_s3_config="$(python3 -c "
import json; print(json.dumps({'identities':[
  {'name':'anonymous','actions':['Read']},
  {'name':'$ACCESS','credentials':[{'accessKey':'$ACCESS','secretKey':'$SECRET'}],
   'actions':['Admin','Read','Write','List','Tagging']}
]}))")" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n $NS rollout restart deployment/<release>-seaweedfs-s3
kubectl -n $NS rollout restart statefulset/<release>-mimir
```

_Source: INSTALL-FRICTIONS.md §36 (2026-05-26 entry)._
