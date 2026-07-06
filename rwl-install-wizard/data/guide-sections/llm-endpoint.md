### LLM endpoint (Phase 7 — platform configuration)

The platform uses an LLM for SLI/SLO triage, runbook synthesis, and agentfarm
reasoning. PAPI's LLM catalog has four roles: `chat`, `bg` (background — summaries
and title generation), `embedding` (vector search), and `default` (fallback when a
feature does not pin a role). Every role must resolve to a `model_name` that exists
in `llmGateway.models[]` (or your external proxy's published list).

#### Chart-bundled LiteLLM gateway (default)

The chart deploys an in-cluster LiteLLM proxy (`<release>-llm-gateway` Service,
port 4000) when `llmGateway.deploy: true` (default). PAPI talks to it at
`http://<release>-llm-gateway:4000` and never touches the upstream API key directly.

**Upstream provider wiring** — register your upstream key(s) by name only. Two patterns:

- **Pattern A — inline (smoke-test only):** populate `llmGateway.providers` map with env-var names
  and values. Chart renders `<release>-llm-gateway-providers` Secret. The key value lands in
  your values file — not recommended beyond quick tests.
- **Pattern B — BYO Secret (recommended for production):** pre-create a Secret holding your
  upstream key, then set `llmGateway.providersExistingSecret: <secret-name>`. Chart skips
  rendering its own Secret and `envFrom`s the named one. Works with SealedSecrets,
  ExternalSecrets, SOPS, or Vault CSI.

**Model list** — `llmGateway.models[]` follows the LiteLLM `model_list` schema verbatim.
Each entry must declare `model_name`, `litellm_params.model`, `litellm_params.api_base`
(your internal endpoint base URL — non-secret), and `litellm_params.api_key` as
`os.environ/<VAR_NAME>` referencing a key in `providersExistingSecret`. The chart fails
fast at template time when `deploy: true` and `models` is empty.

**Model names must match bootstrap** — the `model_name` strings in `llmGateway.models[]`
must exactly match `llmBootstrap.models.{chat,bg,embedding}.name`. Mismatches surface
as 404s from agentfarm at request time, not at deploy time.

#### Internal OpenAI-compatible endpoint

For air-gapped or on-premises deployments pointing at an internal model gateway (Azure
OpenAI in a private VNet, AWS Bedrock over VPC endpoint, in-cluster Ollama / vLLM,
or any OpenAI-compatible proxy):

```yaml
llmGateway:
  deploy: true
  providersExistingSecret: <LLM_API_KEY_SECRET>   # Secret name only — never the key value
  models:
    - model_name: <CHAT_MODEL_NAME>
      litellm_params:
        model: openai/<CHAT_MODEL>
        api_base: <LLM_BASE_URL>
        # api_key: os.environ/<ENV_VAR_IN_SECRET>  # e.g. os.environ/OPENAI_API_KEY
    - model_name: <BG_MODEL_NAME>
      litellm_params:
        model: openai/<BG_MODEL>
        api_base: <LLM_BASE_URL>
        # api_key: os.environ/<ENV_VAR_IN_SECRET>
    - model_name: <EMBEDDING_MODEL_NAME>
      litellm_params:
        model: openai/<EMBEDDING_MODEL>
        api_base: <LLM_BASE_URL>
        # api_key: os.environ/<ENV_VAR_IN_SECRET>
```

In each `litellm_params` entry, add `api_key: os.environ/<ENV_VAR_NAME>` where
`<ENV_VAR_NAME>` is a key inside the Secret named by `providersExistingSecret`
(e.g. `os.environ/OPENAI_API_KEY`). The Secret must exist in the release namespace
before `helm upgrade`; the chart never writes this Secret — it only `envFrom`s it
onto the gateway pod.

#### Fully air-gapped: local / in-cluster models (no external vendor)

The examples above still call a *vendor* endpoint (Azure/OpenAI on a private
link). A truly egress-free cluster runs the models **in-cluster** — an Ollama or
vLLM Deployment for chat/background, and a local embedding server for `embedding`.
Point `api_base` at the in-cluster Service and give a dummy key (local servers
ignore auth, but LiteLLM still requires the field):

```yaml
llmGateway:
  deploy: true
  # A Secret is still referenced by name; put any placeholder value in it —
  # local model servers do not check it, but LiteLLM requires the env var.
  providersExistingSecret: <LLM_API_KEY_SECRET>
  models:
    - model_name: <CHAT_MODEL_NAME>
      litellm_params:
        model: openai/<CHAT_MODEL>              # e.g. openai/llama3.1  (Ollama's OpenAI-compat shim)
        api_base: http://ollama.<NAMESPACE>.svc.cluster.local:11434/v1
        api_key: os.environ/<LLM_API_KEY_ENV>   # any non-empty placeholder
    - model_name: <BG_MODEL_NAME>
      litellm_params:
        model: openai/<BG_MODEL>
        api_base: http://ollama.<NAMESPACE>.svc.cluster.local:11434/v1
        api_key: os.environ/<LLM_API_KEY_ENV>
    # Local embedder — REQUIRED for vector search when no external embedding API
    # is reachable. Run a small OpenAI-compatible embedding server in-cluster
    # (e.g. a text-embeddings-inference / Infinity Deployment) and point at it:
    - model_name: <EMBEDDING_MODEL_NAME>
      litellm_params:
        model: openai/<EMBEDDING_MODEL>         # e.g. openai/bge-small-en-v1.5
        api_base: http://embeddings.<NAMESPACE>.svc.cluster.local:80/v1
        api_key: os.environ/<LLM_API_KEY_ENV>
```

Keep `embedding.dimension` in `llmBootstrap.models.embedding` (below) matched to
your local embedder's output dimension (e.g. `384` for `bge-small`, `1536` for
`text-embedding-3-small`) — a wrong dimension surfaces as pgvector insert errors,
not a deploy-time failure. Mirror the local model images through `<REGISTRY_HOST>`
alongside the platform images.

> **Air-gap gotcha — the bundled `rw-embedder` pod.** The platform's own
> `rw-embedder` (separate from the LiteLLM embedding *model* above) downloads a
> fastembed model from HuggingFace at import time and hangs forever when egress
> is denied. This is a known issue — see the debug guide entry
> **"Embedder hangs forever in air-gap"** for the pre-baked-cache image fix and
> the pre-fix image pin. Mirror the embedder image and apply the pin before
> installing into an air-gapped cluster.

#### LLM bootstrap (catalog seeding)

Enable `llmBootstrap.enabled: true` alongside four required fields so the chart's
post-install Job registers the provider, mints a LiteLLM virtual key (scoped to only
the three model names), and seeds PAPI's `llm_providers` / `llm_models` / `llm_configs`
rows. PAPI receives the virtual key only — the `LITELLM_MASTER_KEY` never reaches PAPI.

```yaml
llmBootstrap:
  enabled: true
  staffUser:
    email: "platform-sa@your-org.example"
  provider:
    name: "your-litellm"
  models:
    chat:      { name: <CHAT_MODEL_NAME>,      maxTokens: 0 }
    bg:        { name: <BG_MODEL_NAME>,        maxTokens: 0 }
    embedding: { name: <EMBEDDING_MODEL_NAME>, maxTokens: 0, dimension: 1536 }
```

When `llmBootstrap.enabled: false`, seed manually via
`https://app.<domain>/rwsupport` → LLM Providers / Models / Configs,
or run `staff-bootstrap.sh --papi-url ... --llm-api-key ...` from a workstation.

#### Verify providers via the LiteLLM UI

The gateway exposes an admin UI at port 4000 — no ingress by default; use port-forward:

```bash
kubectl -n <ns> port-forward svc/<release>-llm-gateway 4000:4000
LITELLM_MASTER_KEY="$(kubectl -n <ns> get secret <release>-platform-secrets \
  -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)"
# Open http://localhost:4000/ui/ — log in with the master key
```

In the UI: confirm each `model_name` is listed under **Models**, then run a
playground round-trip for each role.

_Source: values.yaml `llmGateway.*` and `llmBootstrap.*` comment blocks;
values-example-airgap-jcr.yaml §llmGateway; INSTALL-CHECKLIST.md Phase 7;
airgap.md §4 LLM._
