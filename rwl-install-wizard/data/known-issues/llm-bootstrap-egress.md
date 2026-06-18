## LLM bootstrap Job: `llmGateway` must be ready before seeding succeeds

**Symptom** — The `<release>-llm-bootstrap` post-install Job (stage 2) fails or
loops with a connection-refused error against `http://<release>-llm-gateway:4000`
when `llmGateway.deploy=true`:

```
PermissionError: [Errno 13] Permission denied: '/app/tiktoken_cache'
```

or (connectivity variant):

```
ConnectionRefusedError: [Errno 111] Connection refused — http://<release>-llm-gateway:4000/key/generate
```

**Cause (two distinct sub-cases)**

1. **Gateway not yet ready** — Stage 2 (`mint-papi-vkey.py`) calls the in-cluster
   LiteLLM proxy to mint a virtual key. If `llm-gateway` is still starting (Prisma
   migration pending, OOMKilled, or waiting on `db-init`), the Job's `wait-for-papi`
   init only gates on PAPI TCP — it does NOT wait for the gateway. The Job will
   backoff-retry up to `llmBootstrap.backoffLimit` times (default 5).

2. **Egress blocked at model-inference time** — when `llmGateway.models[]` points at
   an external provider (OpenAI, Azure, Anthropic) and the cluster has no egress to
   that provider's API, the gateway starts and serves virtual-key minting (purely
   in-cluster), but the first real `/chat/completions` from agentfarm will fail.
   The bootstrap Job itself succeeds (it only mints the key and seeds PAPI rows),
   but every subsequent chat or background task errors until egress is restored or
   the model list is updated to point at an accessible provider.

**Relationship to INSTALL-FRICTIONS §15** — This is the documented bootstrap
dependency: the Job expects `llm-gateway` to be reachable because it calls
`/key/generate` with `LITELLM_MASTER_KEY`. Historically (before the chart-managed
Job, when `k3s-setup.sh staff-setup` was required) the same sequencing constraint
applied — the operator had to wait for the gateway before running the seed script.
The Job simply automates that sequencing inside the cluster.

**Resolution**

- For a gateway startup race: watch `kubectl logs -n <ns> deploy/<release>-llm-gateway`
  for `Prisma migrate deploy` completion; once healthy, delete the failed Job pod to
  trigger a retry (the Job's backoff handles this automatically within the limit).
- For an egress gap: update `llmGateway.models[]` to point at a reachable endpoint
  (internal Ollama / vLLM, Azure OpenAI over VNet, or a corporate LiteLLM proxy),
  supply the corresponding key in `llmGateway.providersExistingSecret`, and upgrade.
- For air-gapped installs: the bootstrap Job itself runs purely in-cluster and is
  not blocked by external LLM egress — only inference calls are affected. The Job
  mints a virtual key and seeds catalog rows regardless of whether the upstream
  model endpoint is reachable.

**Opt-out path** — Set `llmBootstrap.enabled: false` and seed PAPI manually via
`/rwsupport` or `staff-bootstrap.sh` if you prefer to decouple LLM catalog
provisioning from Helm lifecycle events.

_Source: values.yaml `llmBootstrap.*`; INSTALL-FRICTIONS.md §15
(llmBootstrap Job pipeline, stage 2 mint-papi-vkey); airgap.md §4 LLM._
