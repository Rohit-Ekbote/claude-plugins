### Cluster domain

`global.domain` is the base DNS suffix from which every public ingress hostname
is derived. The chart expects these subdomains to resolve to the cluster's ingress
LoadBalancer IP before `helm install` runs:

```
papi.<domain>       app.<domain>       agentfarm.<domain>
runner-control.<domain>                runner-metrics.<domain>
webhooks.<domain>   mcp.<domain>       slack.<domain>
alert-ingestor.<domain>                vault.<domain>
s3.<domain>
```

Set this value once in the overlay; all ingress hosts, CORS allowlists
(`CORS_ALLOWED_ORIGIN_REGEXES`, `CSRF_TRUSTED_ORIGINS`,
`LOGIN_ALLOWED_USER_PAGES_HOSTS`), and internal URL env vars derive from it
automatically (chart 0.2.37+).

**DNS check before install:**
```bash
for sub in papi app agentfarm runner-control vault s3; do
  host "$sub.<your-domain>"
done
```
All should resolve to the same LoadBalancer IP.
