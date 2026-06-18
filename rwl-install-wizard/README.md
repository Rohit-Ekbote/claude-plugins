# rwl-install-wizard

Guided installer for the RunWhen platform Helm chart. Answer an interview about
your cluster's constraints; the wizard generates layered `values` overlays and a
tailored user guide + debug guide for your exact install shape.

- **Generate-only** — never touches a cluster, never runs `helm`/`kubectl`.
- **Self-contained** — needs no chart source repo at runtime.
- **Secret-free** — never asks for or stores any credential. Secrets are wired
  via `existingSecret` references; the user guide hands you `kubectl create
  secret` templates to fill at your own terminal.

## Skills

- `/rwl-install` — run or resume the interview, then generate the kit.
- `/rwl-install-show` — show the saved profile and what's been generated.
- `/rwl-install-explain <topic>` — explain one install decision in depth.

## Output (in your working dir, gitignored)

- `.claude/rwl-install-profile.yaml` — your saved answers (re-runnable).
- `rwl-install-out/values-*.yaml` — layered overlays.
- `rwl-install-out/USER-GUIDE.md`, `rwl-install-out/DEBUG-GUIDE.md`.

Targets chart versions `>=0.2.30 <0.3`. See
`docs/superpowers/specs/2026-06-17-rwl-install-wizard-design.md` for design.
