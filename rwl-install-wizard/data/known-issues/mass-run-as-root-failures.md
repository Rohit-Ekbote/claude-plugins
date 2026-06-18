## Mass permission-denied at `/` paths (pre-0.2.6 hardening)

**Symptom (pre-chart 0.2.6):** Multiple pods crash at startup with
`read-only file system` or `permission denied` errors referencing absolute
paths on the container root filesystem (not the data PVC). Affected workloads
before the 0.2.6 hardening release included: qdrant, metricstore (Mimir),
agentfarm, embedder, usearch, postgresql (Spilo), and cc-catalog. Common
error patterns:

```
OSError: [Errno 30] Read-only file system: '/agentfarm/agentfarm-artifacts'
mkdir: cannot create directory '/qdrant/storage': Read-only file system
open /tmp/...: read-only file system
```

**Cause:** These workloads wrote to paths on the image's root filesystem at
startup — `/tmp`, workdir-relative paths, or fixed absolute paths — and had
not yet been given writable `emptyDir` mounts over those paths. When
`readOnlyRootFilesystem: true` was enabled globally, every pod that lacked
its own writable-mount configuration failed.

**Resolution (chart 0.2.6):** The 0.2.6 release was the dedicated hardening
pass that:
- Wired `global.scratchVolumes` emptyDirs (`/tmp`, `/home/app`) into every
  first-party pod template that needed them.
- Added per-subchart writable-mount keys (`writableDirs`, `additionalVolumes`,
  `extraVolumes`) for Spilo, Neo4j, Vault, SeaweedFS, and Qdrant.
- Changed the agentfarm artifact backend default from `gcs` (which silently
  fell back to the local `FileArtifactService`) to `s3` (the bundled object
  store), eliminating the `/agentfarm/agentfarm-artifacts` mkdir crash.

**Affected versions:** chart < 0.2.6. Upgrade to 0.2.6+ to get the full set
of writable-mount fixes. No overlay changes required for existing installs
that stay on the default hardening.

_Source: security-hardening.md §2–§5 (writable-mount table per workload);
INSTALL-FRICTIONS.md §38 (agentfarm / 0.2.6 resolution)._
