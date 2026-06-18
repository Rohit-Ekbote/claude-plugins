## vault-init: `/home/app/.vault` permission denied under hardened context

**Symptom:** The `vault-init` Job pod crashes or exits non-zero with a
`permission denied` error referencing `/home/app/.vault` (Vault CLI token
helper default location). Logs show the `vault` CLI attempting to cache a
token on the read-only root filesystem:

```
Error writing to /home/app/.vault/token: open /home/app/.vault/token: read-only file system
```

**Cause:** `readOnlyRootFilesystem: true` makes the image's own `/home/app`
directory read-only. The Vault CLI's token helper writes the acquired root
token to `~/.vault/token` (`HOME=/home/app` by default). Without a writable
`/home/app` mount, this write fails and the vault-init script cannot complete
policy seeding.

**Resolution (chart):** The vault-init Job template mounts the standard
`global.scratchVolumes` emptyDirs (`/tmp` and `/home/app`) onto its container.
This is why `global.scratchVolumes.enabled` must remain `true` (the default)
when running with `readOnlyRootFilesystem: true`. Setting it to `false`
re-exposes this failure.

If you see this error, confirm:
1. `global.scratchVolumes.enabled` is not explicitly set to `false`.
2. The vault-init Job's pod template includes a `/home/app` emptyDir volumeMount
   (`kubectl describe pod <release>-vault-init-<hash>`).

**Resolved:** chart 0.2.7 — `runwhen.scratchVolumes` helper wired into
vault-init Job template.

_Source: security-hardening.md §2 "Writable scratch volumes"; templates/vault-init-job.yaml comment at `scratchVolumes`._
