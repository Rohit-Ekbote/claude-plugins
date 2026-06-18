## mcp-server (and other backends): `CERTIFICATE_VERIFY_FAILED` against internal HTTPS

**Symptom:** `mcp-server` (and/or `sobrain`, `agentfarm`, `sobow-index`, `papi`,
`slackbot`, `alerts`, `user-pages`, `cc-catalog-svc`) log TLS errors when
connecting to internal HTTPS endpoints:

```text
httpx.ConnectError: [SSL: CERTIFICATE_VERIFY_FAILED]
  certificate verify failed: unable to get local issuer certificate (_ssl.c:...)
  while fetching https://papi.<your-domain>/.well-known/openid-configuration
```

Additional symptoms from the same root cause:
- `sobrain` / `agentfarm` JWT validation fails with `CERTIFICATE_VERIFY_FAILED`
  (PAPI's `jwks_uri` is the public URL, fetched at token validation time).
- PAPI fails to deliver webhooks to `https://webhooks.<your-domain>/`.
- `user-pages` SSR errors on `/api/*` fetches to `https://papi.<your-domain>`.
- `cc-catalog-svc` or PAPI fails to clone from an internal Gitea/Gitlab repo
  with TLS errors.

**Cause:** The platform's container images ship with only public root CAs in
their trust store.  When ingress TLS (or any in-cluster HTTPS endpoint the
platform calls) is signed by a private/corporate CA, Python `httpx`/`requests`,
Node, Go, curl, and git all fail certificate verification.

**Secondary symptom — `FileNotFoundError` (chart 0.2.28 clusters with SSL_CERT_FILE injection):**
Some enterprise clusters inject `SSL_CERT_FILE` on every pod via a mutating
admission webhook, pointing at a path that doesn't exist inside the platform's
images.  Python `httpx` honors `SSL_CERT_FILE` exclusively and aborts with:

```text
FileNotFoundError: [Errno 2] No such file or directory
...ssl.create_default_context(cafile=os.environ["SSL_CERT_FILE"])
```

The volume overlay alone (chart 0.2.28) does not fix this — `setEnvVars: true`
(chart 0.2.29+) is required to override the injected value.

**Fix:** Apply the `internal-ca` overlay, which sets:
```yaml
global:
  trustBundle:
    enabled: true
    existingSecret: <CA_BUNDLE_SECRET>   # pre-created Secret; NAME only, no PEM
    bundleFile: ca-bundle.crt
    setEnvVars: true
```

Pre-create the Secret with the **complete** bundle (public roots + your CA):
```bash
cat /etc/ssl/certs/ca-certificates.crt your-internal-ca.crt > /tmp/ca-bundle.crt
kubectl create secret generic <CA_BUNDLE_SECRET> \
  -n <release-namespace> \
  --from-file=ca-bundle.crt=/tmp/ca-bundle.crt
```

> **Important:** The chart **overlays** (replaces) the trust store rather than
> appending to it.  Omitting public roots from the bundle breaks outbound calls
> to Slack, GitHub, Anthropic, AWS, and other public services.

**Affected chart versions:** 0.2.27 and earlier (no trust-bundle knob).
Chart 0.2.28 added the volume overlay but not `setEnvVars`.
Chart 0.2.29+ adds `setEnvVars: true` — fully resolved when the overlay is applied.

_Source: values-example-internal-ca.yaml §CONCRETE SYMPTOMS and §WHY setEnvVars EXISTS; values.yaml lines 145–197._
