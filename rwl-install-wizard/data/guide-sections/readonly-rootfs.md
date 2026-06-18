### Read-only root filesystem + automatic scratch volumes

Setting `global.containerSecurityContext.readOnlyRootFilesystem: true` mounts
the container's root filesystem read-only. All writes must go to an explicit
volume — the image itself cannot be modified at runtime.

**Automatic scratch volumes:** When `readOnlyRootFilesystem: true`, the chart
automatically mounts writable `emptyDir` volumes at `/tmp` and `/home/app` on
every first-party container, and injects these environment variables so tools
behave correctly even under an arbitrary UID with no `/etc/passwd` entry:

| Env var | Value | Why |
|---------|-------|-----|
| `HOME` | `/home/app` | Caches, `~/.config`, etc. land on a writable volume |
| `TMPDIR` | `/tmp` | Temp files use the writable scratch mount |
| `USER` / `LOGNAME` | `app` | Tools that look up the current user work even without a `/etc/passwd` entry |

You do not need to configure this — it follows `readOnlyRootFilesystem`
automatically. To force it on or off explicitly:

```yaml
global:
  scratchVolumes:
    enabled: true   # or false to opt out
```

**Init containers** inherit `containerSecurityContext` in full — including
`readOnlyRootFilesystem: true` — because all chart-managed init containers
are write-free with respect to their root filesystem (readiness `wget`/`nc`
probes; vault binary copy to an emptyDir shared volume).

If you add a custom init container that must write to its own rootfs:

```yaml
global:
  initContainers:
    readOnlyRootFilesystem: false
```

_Source: security-hardening.md §2 "Writable scratch volumes" + §1 init-container table._
