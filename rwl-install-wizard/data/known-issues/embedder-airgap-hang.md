## Embedder hangs forever in air-gap (fastembed model download at import time)

**Symptom:** The `rw-embedder-*` pod enters `CrashLoopBackOff` in an
air-gapped cluster. Pod logs show only:

```
[WARNING] ASGI Lifespan errored, continuing without Lifespan support
```

Port 8000 is listening but every HTTP request — including `127.0.0.1:8000/healthz`
from inside the pod — times out. Kubernetes kills the pod after failed startup
probes and the cycle repeats.

**Cause:** `local_llm/views.py` instantiates `TextEmbedding('sentence-transformers/all-MiniLM-L6-v2')`
at **module-import time** (top-level statement). `fastembed.TextEmbedding`
downloads ~80 MB of ONNX weights from HuggingFace LFS on first construction
if the model is not cached. The HuggingFace client has no connect timeout —
it blocks the TCP `connect()` call forever when egress is denied. Granian's
ASGI lifespan start loads the module, which blocks indefinitely, causing all
HTTP handlers to stall even though the port is open.

**Fix (permanent — PR #3619):** The embedder image bakes the fastembed model
cache at Docker build time (`RUN poetry run python -c "from fastembed import
TextEmbedding; TextEmbedding(...)"` in the `python-base` stage) and sets
`HF_HUB_OFFLINE=1` / `TRANSFORMERS_OFFLINE=1` at runtime. The `views.py`
instantiation passes `cache_dir` from `FASTEMBED_CACHE_DIR` env var so the
pre-baked cache is found on startup.

**Workaround (pre-fix images):** Pin the embedder image to a pre-bake PR
build in your overlay:

```yaml
images:
  embedder:
    repository: "shared-services"
    tag: "pr-3619-a2777b2"
```

Mirror this image through your registry alongside the standard release images.
After PR #3619 merges and a release tag is cut, remove the pin and use the
tagged release image.

_Source: INSTALL-FRICTIONS.md §31._
