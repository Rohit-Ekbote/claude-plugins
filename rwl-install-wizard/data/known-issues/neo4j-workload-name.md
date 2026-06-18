## Neo4j pod named `rw-0` instead of `neo4j-0`

**Symptom (§12):** The bundled Neo4j StatefulSet's pod appears in `kubectl get pods`
as `rw-0` (where `rw` is the Helm release name) rather than `neo4j-0`. The upstream
`neo4j.fullname` helper falls back to `.Release.Name` when no `nameOverride` is set,
making the first ordinal `<release>-0` — indistinguishable from "random platform pod 0"
when triaging.

The chart defaults `neo4j.nameOverride: "neo4j"` (values.yaml line 1137), which
produces the StatefulSet name `rw-neo4j` and pod name `rw-neo4j-0`. If an operator
overlay resets `nameOverride` to empty, the confusing `rw-0` name returns.

**Identification:** if you see `rw-0` and suspect it's Neo4j, confirm with:
```bash
kubectl describe pod rw-0 -n <ns>    # check image / env vars
kubectl get pod rw-0 -n <ns> -o yaml | grep -i neo4j
```

Or filter by Neo4j label if present:
```bash
kubectl get pods -n <ns> -l app.kubernetes.io/name=neo4j
```

**Mitigation:** do not override `neo4j.nameOverride: ""` in your overlay — keep the
chart default (`neo4j`) or set a different non-empty string.

_Source: INSTALL-FRICTIONS.md §12; values.yaml line 1137._
