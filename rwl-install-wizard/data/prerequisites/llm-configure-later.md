## LLM endpoint — deferred (llmGateway.deploy: false)

You chose to configure the LLM gateway later, so this kit emits
`llmGateway.deploy: false`. The platform installs cleanly, but chat, background
summarisation, and embedding stay inert until you enable an LLM.

**Before enabling LLM features**, set `llmGateway.deploy: true` AND provide a
non-empty `llmGateway.models[]` (chart-rendered config) OR
`llmGateway.configMapName` (bring-your-own ConfigMap). With `deploy: true` and no
model list the chart fail-fasts at template time
(`templates/llm-gateway/configmap.yaml`). Re-run `/rwl-install` and pick the
internal-OpenAI option when you have the endpoint + model IDs.
