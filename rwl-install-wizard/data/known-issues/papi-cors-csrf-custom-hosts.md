## PAPI/login: CORS and CSRF errors on custom ingress hosts

**Symptom:** Browser login or signup fails; devtools shows CORS or CSRF errors
(failed preflight, `400 Bad Request` on OPTIONS, or CSRF token rejection):

```text
Request URL: https://papi.<domain>/api/v3/users/register
Request Method: OPTIONS
Status Code: 400 Bad Request
```

**Cause (chart ≤ 0.2.36):** `papi.corsOriginRegexes`, `papi.csrfTrustedOrigins`,
and `papi.loginAllowedHosts` defaulted to `"[]"`, so every browser preflight
was rejected even when `global.domain` was set correctly.

**Fix (chart 0.2.37+):** A `browserOrigins` block auto-derives all three env
vars from `global.domain` and the `subdomains` list (default: `[app, papi,
agentfarm]`). No override needed for canonical installs where the SPA loads from
`https://app.<domain>`.

For non-canonical origins (Vercel preview, staging subdomain, separate brand
host), add them via:
```yaml
browserOrigins:
  extraOrigins:
    - "https://app-staging.acme.io"
```

For regex features (wildcard preview URLs), override the per-service knob only
for that one env var — the others continue to auto-derive:
```yaml
papi:
  corsOriginRegexes: '["^https://vercel-preview-.*-runwhen\\.vercel\\.app$"]'
```

After any `browserOrigins` or `papi.*` change, restart PAPI to reload the
ConfigMap (`kubectl rollout restart deployment/<release>-papi -n <ns>`).

_Source: INSTALL-FRICTIONS.md §3 (resolved chart 0.2.37)._
