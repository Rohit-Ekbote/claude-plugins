## LiteLLM ConfigMap placeholder — `internal-openai.customer.local/v1` must be replaced

**Symptom** — After install, the `llm-gateway` pod starts but every
`/chat/completions` request from agentfarm fails with:

```
AuthenticationError: litellm.AuthenticationError: OpenAIException - Connection error.
```

or:

```
httpx.ConnectError: [Errno -2] Name or service not known
  'internal-openai.customer.local'
```

**Cause** — `values-example-airgap-jcr.yaml` (the canonical customer airgap
overlay) ships `llmGateway.models[]` entries with `api_base:
https://internal-openai.customer.local/v1` as an illustrative placeholder.
If an operator copies these blocks verbatim without substituting a real endpoint,
the rendered `litellm.yaml` ConfigMap (mounted at `/etc/litellm/config.yaml`)
points every model at a DNS name that does not exist in the customer cluster.

The chart does NOT validate `api_base` values at template time — it passes
the `models[]` list to LiteLLM verbatim. The placeholder hostname ships in the
example to make the shape obvious, but the gateway will fail at request-routing
time once deployed.

**Resolution** — Replace `api_base` in every `llmGateway.models[]` entry with the
actual base URL of your OpenAI-compatible endpoint (e.g.
`https://my-openai-proxy.corp.example/v1`, `http://ollama.svc:11434/v1`,
`https://<resource>.openai.azure.com`). This value is non-secret and should appear
in your values overlay as plain text.

**BYO ConfigMap path** — If you maintain `litellm.yaml` outside the chart (e.g.
via Flux Kustomization or SealedSecrets), set `llmGateway.configMapName: <name>`
to bypass the chart's rendered ConfigMap entirely. When this key is set, the chart
mounts your ConfigMap at `/etc/litellm/config.yaml` as-is and skips rendering
`<release>-llm-gateway-config`.

**`scratchVolumes` note** — The `litellm-non_root` image requires writable
emptyDirs at `/tmp`, `/app/cache`, and `/app/migrations`; these are injected by
`llmGateway.scratchVolumes.enabled: true` (default). If you disable scratch
volumes or change `llmGateway.podSecurityContext`, verify the gateway pod starts
cleanly before debugging `api_base` connectivity. A Prisma or tiktoken write-path
crash (see `llm-gateway-nonroot-prisma`) will surface before any API call is made.

_Source: values-example-airgap-jcr.yaml §llmGateway (`api_base:
https://internal-openai.customer.local/v1` placeholder); values.yaml
`llmGateway.configMapName` and `llmGateway.scratchVolumes.*`._
