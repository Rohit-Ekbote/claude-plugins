### Secret pre-flight checklist (Phase 1 — before `helm install`)

This wizard never asks for, echoes, or writes a secret. It only records the
**names** you gave for Secrets the chart references by name. Every named Secret
below must exist in the release namespace **before** the first `helm install`,
or pods stay in `CreateContainerConfigError` / fail upstream auth.

Create each Secret you were asked to name (only the templates whose feature you
enabled apply — fill in the redacted values yourself):

- [ ] **Image pull Secret** — `<PULL_SECRET_NAME>` (registry mirror). The
      `--docker-server` must be the mirror **host only** — no scheme, no path:
      ```bash
      kubectl -n <NAMESPACE> create secret docker-registry <PULL_SECRET_NAME> \
        --docker-server=<REGISTRY_HOST_ONLY> \
        --docker-username='<user>' \
        --docker-password='<token>'
      ```
- [ ] **TLS Secret** — `<TLS_SECRET>` (BYO wildcard cert; only when you chose the
      bring-your-own-TLS option):
      ```bash
      kubectl -n <NAMESPACE> create secret tls <TLS_SECRET> \
        --cert=wildcard.crt --key=wildcard.key
      ```
- [ ] **Corporate CA bundle** — `<CA_BUNDLE_SECRET>` (only with internal-CA
      trust). The `--from-file` key must equal the `bundleFile` you entered:
      ```bash
      kubectl -n <NAMESPACE> create secret generic <CA_BUNDLE_SECRET> \
        --from-file=<BUNDLE_FILE>=/path/to/ca-bundle.crt
      ```
- [ ] **S3 credentials** — `<S3_EXISTING_SECRET>` (external S3 backend only):
      ```bash
      kubectl -n <NAMESPACE> create secret generic <S3_EXISTING_SECRET> \
        --from-literal=AWS_ACCESS_KEY_ID='<redacted>' \
        --from-literal=AWS_SECRET_ACCESS_KEY='<redacted>'
      ```
- [ ] **LLM provider key** — `<LLM_API_KEY_SECRET>` (internal/on-prem LLM). Each
      key name must match a `os.environ/<VAR>` in your model list:
      ```bash
      kubectl -n <NAMESPACE> create secret generic <LLM_API_KEY_SECRET> \
        --from-literal=<LLM_API_KEY_ENV>='<redacted>'
      ```
- [ ] **Slack credentials** — `<SLACK_SECRET_NAME>` (Slack integration only):
      ```bash
      kubectl -n <NAMESPACE> create secret generic <SLACK_SECRET_NAME> \
        --from-literal=SLACK_SIGNING_SECRET='<redacted>' \
        --from-literal=SLACK_CLIENT_ID='<redacted>' \
        --from-literal=SLACK_CLIENT_SECRET='<redacted>'
      ```

Verify presence before installing (names should all resolve):

```bash
kubectl -n <NAMESPACE> get secret \
  <PULL_SECRET_NAME> <TLS_SECRET> <CA_BUNDLE_SECRET> \
  <S3_EXISTING_SECRET> <LLM_API_KEY_SECRET> <SLACK_SECRET_NAME> 2>/dev/null
```

Managing secrets via SealedSecrets / External Secrets / SOPS / Vault CSI is
fully compatible — the chart only ever references these by name.
