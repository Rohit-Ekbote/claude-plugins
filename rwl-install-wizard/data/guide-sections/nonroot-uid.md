### Non-root UID/GID selection

The chart runs every first-party pod as a fixed UID/GID via
`global.podSecurityContext.runAsUser` / `runAsGroup` / `fsGroup`.

**Safe value — 65534 (nobody/nogroup):** The upstream chart ships uid `1000`
as its default; `65534` is equally valid and is preferred in clusters where
uid `1000` is a mapped user. The chart's webhook-policy stance is to reject
uid `0`, uid `500`, and any unset uid — any other non-zero uid is accepted.

**OpenShift / arbitrary-UID clusters:** Do NOT set `runAsUser` / `runAsGroup`
/ `fsGroup` — the SCC assigns them. Only `runAsNonRoot: true` and
`seccompProfile` are needed.

**Volume ownership:** `fsGroup` controls the group that owns volumes (including
the automatic `/tmp` and `/home/app` scratch emptyDirs). Keep `fsGroup` equal
to `runAsGroup` so the process can write to those mounts without supplemental
group overhead.

**UID-sensitive subcharts:** Postgres/Spilo (`101`), Vault (`100`), Neo4j
(`7474`), Redis (`1001`), LLM Gateway (`65534`), and SeaweedFS/Qdrant (`1000`)
carry their own per-workload contexts in `values.yaml` that override the global
block for that workload only.

_Source: security-hardening.md §1 "Pod-level settings" + §4 "OpenShift"._
