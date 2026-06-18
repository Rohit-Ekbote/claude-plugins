## LLM Gateway: `litellm` image incompatible with non-root / read-only rootfs

**Symptom:** The `llm-gateway` pod crashes at startup under hardened context
(`runAsNonRoot: true`, `readOnlyRootFilesystem: true`) with a Prisma
`FileNotFoundError` or a tiktoken `PermissionError`:

```
FileNotFoundError: [Errno 2] No such file or directory:
  '/home/app/.cache/prisma-python/binaries/...'
```

or (air-gap clusters, pre-PR-23498 tags):

```
PermissionError: [Errno 13] Permission denied: '/app/tiktoken_cache'
```

**Cause:** The default `litellm` image (uid `0`, root) uses paths that are not
writable when running as a non-root user with a read-only root filesystem.
Prisma bundles a query engine binary that it unpacks to a path under `$HOME`;
tiktoken caches BPE encoding files to a fixed path under the app directory.

**Resolution:** The chart defaults to the `litellm-non_root` image
(`ghcr.io/berriai/litellm-non_root`, uid `65534`) which rebuilds all
write-sensitive paths relative to `$HOME=/app`. The chart also mounts
writable emptyDirs at `/tmp`, `/app/cache`, and `/app/migrations` via
`llmGateway.scratchVolumes.enabled: true` (default), and sets the required
env vars:

- `PRISMA_BINARY_CACHE_DIR=/app/.cache/prisma-python/binaries`
- `LITELLM_MIGRATION_DIR=/app/migrations`
- `XDG_CACHE_HOME=/app/cache`

The tiktoken DNS lookup at import-time is benign — it is a version-check that
fails silently if the cluster is airgapped; it does not cause a crash.

**If you override `images.llmGateway.repository` back to `litellm`**, you must
also set `llmGateway.podSecurityContext.runAsUser: 0` and
`llmGateway.containerSecurityContext.readOnlyRootFilesystem: false`, which
relaxes the hardened baseline for that pod.

_Source: values.yaml `images.llmGateway` comment (BerriAI/litellm#19852, #23218);
security-hardening.md §3 "LLM Gateway"; values.yaml `llmGateway.scratchVolumes`._
