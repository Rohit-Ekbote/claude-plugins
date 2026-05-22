# rwl-env

Local debugger for helm-deployed RunWhen platform installs. All mutations go through `helm upgrade` / `helm rollback` so cluster state stays fully describable by `helm history` — every change is deterministically revertible.

## Quick start

```bash
# Register your first deployment
/rwl-env-add helm-dev

# Activate it for the current project
/rwl-env-set helm-dev

# Check status
/rwl-env-cur

# Bump an image tag
/rwl-upgrade-image-tag papi 2026-05-22.3
```

## Safety invariants

- Only `helm upgrade` and `helm rollback` mutate cluster state.
- `kubectl` writes (`apply`, `delete`, `patch`, etc.) are blocked by the PreToolUse hook.
- Postgres access is always read-only (no DDL/DML), regardless of the rwl-env's `readOnly` flag.
- `helm install` / `helm uninstall` are out of scope — this plugin debugs existing installs.

## Design

See `docs/plans/2026-05-22-rwl-env-design.md`.

## Comparison with rwenv

| | rwenv | rwl-env |
|---|---|---|
| Topology | Multi-cluster GKE / k3s | Single helm release per entry |
| Execution | Dev container or local | Local only |
| Mutations | kubectl + helm (gated) | helm upgrade / rollback only |
| DB access | Read/write per env | Always read-only |
