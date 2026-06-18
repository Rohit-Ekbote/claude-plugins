## tiktoken price-book DNS fetch to `openaipublic.blob.core.windows.net` — benign failure

**Symptom** — The `llm-gateway` pod logs show a warning or DNS resolution failure
at startup:

```
WARNING: failed to download tiktoken price book from
  https://openaipublic.blob.core.windows.net/encodings/...
```

or the gateway pod is `Running` but its startup logs contain connection errors
referencing `openaipublic.blob.core.windows.net`.

**Cause** — LiteLLM imports the `tiktoken` library at startup to handle BPE
tokenization. On import, `tiktoken` attempts to fetch an encoding price-book file
from `openaipublic.blob.core.windows.net` (a Microsoft Azure Blob Storage domain
used by the public OpenAI SDK). In air-gapped or restricted-egress clusters that
block this domain, the fetch fails.

**Impact** — None. The fetch is a background version-check / cache warm-up. When
it fails, `tiktoken` falls back to its bundled encoding tables. The gateway
continues to start, serve `/chat/completions`, and proxy requests to your upstream
model endpoint. LiteLLM does not require the price-book to function.

**This is not a crash.** Contrast with `llm-gateway-nonroot-prisma` (the Prisma
`FileNotFoundError` / tiktoken `PermissionError`) — that failure is a write-path
crash under non-root / read-only rootfs, a distinct issue fixed by the
`litellm-non_root` image and `llmGateway.scratchVolumes.enabled: true` (default).

**Resolution** — No action required. If the log noise is distracting, you can
suppress it by ensuring the `tiktoken` cache is pre-warmed in your image build,
or by setting `TIKTOKEN_CACHE_DIR` to a path inside `llmGateway.scratchVolumes`
that is populated by an init container — but this is optional.

**Air-gap note** — `openaipublic.blob.core.windows.net` does NOT need to be
unblocked for the platform to function. Add it to your egress allowlist only if
you want tiktoken to pre-warm its encoding cache on startup.

_Source: values.yaml `images.llmGateway` comment (BerriAI/litellm#19852, #23218;
known-issues/llm-gateway-nonroot-prisma.md — tiktoken DNS note); airgap.md §4 LLM
(benign startup warning)._
