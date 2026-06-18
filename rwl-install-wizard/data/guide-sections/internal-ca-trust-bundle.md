### Internal CA trust bundle

Use this overlay when cluster TLS (ingress, internal HTTPS endpoints, git repos)
is signed by a private/corporate CA that the platform's container images do not
trust by default.

#### What the chart does

Setting `global.trustBundle.enabled: true` makes the chart project a pre-created
Kubernetes Secret onto every first-party backend pod at the standard system CA
directory (`/etc/ssl/certs/`), overlaying the image's default trust store.
Python (`ssl`/`requests`/`httpx`), Node, Go, curl, and git all read this path by
default — no per-service env-var plumbing required.

With `setEnvVars: true` the chart additionally renders
`SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` / `CURL_CA_BUNDLE` /
`NODE_EXTRA_CA_CERTS` / `GIT_SSL_CAINFO` on every backend pod, pointing at
`<mountPath>/<bundleFile>`.  These are appended **last** in the container env
list so kubelet's "last duplicate wins" semantics beat any earlier
webhook-injected `SSL_CERT_FILE`.

> **Scope:** covers all 23 first-party runwhen-platform pod templates.
> Subchart pods (postgresql, redis, neo4j, qdrant, seaweedfs, vault) are
> inbound-only datastores and are **not** wired by this knob.

#### Pre-install: create the Secret out-of-band

The chart does **not** create or rotate the Secret — the operator owns its lifecycle.

```bash
# 1. Concatenate the complete public-roots bundle with your internal CA(s).
#    Omitting public roots will break outbound calls to Slack, GitHub, LLM
#    providers, etc. — the chart OVERLAYS (replaces) the trust store.
cat /etc/ssl/certs/ca-certificates.crt your-internal-ca.crt \
  > /tmp/ca-bundle.crt

# 2. Create the Secret in the release namespace.
#    The KEY name (--from-file=<key>=...) MUST match bundleFile in your overlay.
kubectl create secret generic <CA_BUNDLE_SECRET> \
  -n <release-namespace> \
  --from-file=ca-bundle.crt=/tmp/ca-bundle.crt
```

The wizard sets `existingSecret` to the Secret **name** only — PEM/cert material
is never embedded in the generated overlay.

#### Key chart values (from `values.yaml` lines 145–197)

| Key | Default | Purpose |
|-----|---------|---------|
| `global.trustBundle.enabled` | `false` | Master switch |
| `global.trustBundle.existingSecret` | `""` | Secret name (chart does not create it) |
| `global.trustBundle.bundleFile` | `""` | Filename key inside the Secret; becomes `<mountPath>/<bundleFile>` after projection |
| `global.trustBundle.setEnvVars` | `false` | Set SSL env vars on every pod (strongly recommended) |
| `global.trustBundle.mountPath` | `"/etc/ssl/certs/"` | Override only if images use a non-standard trust store path |

#### Rotate the bundle

```bash
kubectl create secret generic <CA_BUNDLE_SECRET> \
  -n <release-namespace> \
  --from-file=ca-bundle.crt=/tmp/ca-bundle-new.crt \
  --dry-run=client -o yaml | kubectl apply -f -
# Projected volumes update within the kubelet sync period (~1 min) without pod restart.
```

#### Post-install verification

```bash
# Confirm the volume/mount are present
kubectl -n <ns> get deploy <release>-mcp-server -o yaml | grep -A3 trust-bundle

# Confirm the file lands inside the pod
kubectl -n <ns> exec deploy/<release>-mcp-server -- ls -l /etc/ssl/certs/ca-bundle.crt

# Confirm env vars are set (requires setEnvVars: true)
kubectl -n <ns> exec deploy/<release>-mcp-server -- env \
  | grep -E '^(SSL_CERT_FILE|REQUESTS_CA_BUNDLE|CURL_CA_BUNDLE|NODE_EXTRA_CA_CERTS|GIT_SSL_CAINFO)='

# Confirm TLS now succeeds
kubectl -n <ns> exec deploy/<release>-mcp-server -- \
  python3 -c "import httpx; r=httpx.get('https://papi.<your-domain>/.well-known/openid-configuration'); print(r.status_code)"
# Expected: 200
```

_Source: values-example-internal-ca.yaml §PRE-INSTALL and §VERIFICATION; values.yaml lines 145–197._
