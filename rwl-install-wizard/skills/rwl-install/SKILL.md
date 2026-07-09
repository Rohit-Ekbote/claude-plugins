---
name: rwl-install
description: Interview the operator about their cluster and generate a tailored RunWhen-platform install kit (layered values overlays + user guide + debug guide). Generate-only; never touches a cluster; never asks for or stores secrets.
triggers:
  - /rwl-install
  - install runwhen platform
  - generate runwhen values
  - runwhen install wizard
---

# RunWhen platform install wizard

Generate-only. **Never** run `helm install`/`helm upgrade`, `kubectl`, or any
command that contacts a cluster. The wizard never runs `helm`; the pre-flight
render gate is emitted as a command in PREREQUISITES.md. **Never** ask for,
echo, or store a secret (password, token, key, PAT, kubeconfig, cert material).
Secrets are wired by name (`existingSecret`/`*Ref`) only.

## Inputs
- Catalog: `${CLAUDE_PLUGIN_ROOT}/data/knob-catalog.yaml`
- Guide sections: `${CLAUDE_PLUGIN_ROOT}/data/guide-sections/`
- Known issues: `${CLAUDE_PLUGIN_ROOT}/data/known-issues/`
- Prerequisites: `${CLAUDE_PLUGIN_ROOT}/data/prerequisites/`
- Guard: `${CLAUDE_PLUGIN_ROOT}/lib/secret-guard.sh`

## State + output (in `$PWD`)
- Profile: `.claude/rwl-install-profile.yaml` (the ONLY state; secret-free)
- Kit: `rwl-install-out/{values-*.yaml, USER-GUIDE.md, DEBUG-GUIDE.md, PREREQUISITES.md}`

## Flow

1. **Chart-version gate.** State the targeted range (`chartCompat` from the
   catalog). Ask the operator which chart version they have. If out of range,
   warn and continue, and stamp generated files "unverified for chart <X>".

2. **Load or start profile.**
   - If `.claude/rwl-install-profile.yaml` exists: summarize saved answers and
     ask whether to (a) review all, (b) change a specific axis, or (c)
     regenerate as-is. Preload answers accordingly.
   - Else: start a fresh interview.

3. **Interview** — walk axes from the catalog **one question at a time** using
   the AskUserQuestion tool. For each axis:
   - Present the `question` and its `options` (label each from the catalog).
   - Skip an axis whose `dependsOn` precondition is unmet, or auto-resolve it
     when an earlier answer moots it (note the auto-resolution to the operator).
   - If a chosen option triggers a `conflictsWith` pair already selected,
     surface the conflict and ask the operator to resolve before continuing.
   - **Only collect non-sensitive shape facts** (domain, StorageClass,
     ingressClass, UID/GID, registry hostname/path, endpoint URLs, CA-bundle
     source reference). If a value would be a secret, do NOT collect it — instead
     record that a named secret is required and surface it in the guide.
   - If the axis declares a `params:` list (free-value inputs like domain,
     registry host, UID), prompt for each param and store its value in the
     profile under that axis's answer. These are always non-sensitive shape
     facts — never a secret.
   - **Required params (hard re-prompt).** A param marked `required: true` is a
     shape fact the kit cannot guess. You MUST obtain a real value: re-prompt
     until the operator provides one. Never substitute a placeholder, example, or
     guessed value, and never silently omit a required param. If the operator
     genuinely cannot provide it, do NOT generate that axis's overlay — tell them
     exactly what is blocked and stop that axis. (This is why the kit never ships
     a guessed ingress class or registry host.)
   - **dependsOn.** If an axis or option documents a `dependsOn`/appliesWhen
     precondition (e.g. the ingress-snippets axis applies only when cluster-shape
     is an Ingress option, not Gateway API), skip it when the precondition is
     unmet and note the auto-skip to the operator.
   - **Multi-select axes.** If the axis declares `multiSelect: true`, present it
     with the AskUserQuestion tool in multi-select mode: the operator may pick
     any combination of its options, or none. Such an axis has **no `none`
     option** — an empty selection *is* "none", so record the answer as an empty
     list and emit nothing for it. For each option the operator does select,
     collect that option's `params:` and, at GENERATE, deep-merge every selected
     option's `emits:` into the target overlay(s). Store the answer as a list of
     selected option ids under that axis. (Single-select axes are unchanged: one
     option id per axis.)
   - **ingress-snippets default + conflict.** When presenting the ingress-snippets
     axis, pre-select `snippets-blocked` if the operator chose the hardened
     security posture (a hardened/patched ingress-nginx rejects snippets);
     otherwise pre-select `snippets-allowed`. If the operator selected the
     alert-ingestor optional component, it REQUIRES snippet-capable ingress —
     surface the conflict and ask them to either drop alert-ingestor or confirm a
     snippet-capable controller (`snippets-allowed`) before generating.

4. **Write the profile** to `.claude/rwl-install-profile.yaml` (schemaVersion: 1,
   chartCompat, generatedAt = today, answers map). Save even a partial profile
   if the operator stops early.

5. **GENERATE** (always fully rewrite `rwl-install-out/`):
   1. For each answered option, take its `emits:` fragment and target `overlay:`.
      Substitute any `<TOKEN>` placeholders in the fragment with the operator's
      matching `params:` values from the profile (e.g. `<DOMAIN>` →
      `rw.example.com`). Deep-merge fragments per overlay file. Write only
      overlays that received content. Prepend each overlay with a header:
      chartCompat, generatedAt, and the axis answers that produced it.
   2. Collect the de-duplicated union of `guide_sections` ids → assemble
      `USER-GUIDE.md` in INSTALL-CHECKLIST Phase 0→10 order, with command blocks
      that name the generated overlays in `-f` flags and substitute the
      operator's domain/namespace. Secret creation appears only as
      `kubectl create secret ... <PLACEHOLDER>` templates.
      - **`-f` lists name only overlays that were actually written.** Compose
        every `helm` command from the files present in `rwl-install-out/`, in the
        order values.yaml → values-registry → values-storage → values-cluster →
        values-posture. Never emit a `-f values-<x>.yaml` for an overlay this run
        did not generate (e.g. no `values-posture.yaml` unless a posture/RBAC axis
        produced it).
      - **Never emit a dangling placeholder.** If an optional free-value param was
        left blank (e.g. `helmMirrorUrl`), OMIT the guide block that depends on it
        rather than rendering the literal `<TOKEN>`. Substitute a param only when
        the operator supplied it; otherwise drop the block and keep the fallback
        prose the guide section provides for the blank case.
   3. Collect the de-duplicated union of `known_issues` ids → assemble
      `DEBUG-GUIDE.md` from the matching `data/known-issues/<id>.md` files.
   4. Assemble `rwl-install-out/PREREQUISITES.md` (ALWAYS written). It has:
      - A header: the targeted chart range (`chartCompat`), `generatedAt` (today),
        and the apply order (values.yaml → values-registry → values-storage →
        values-cluster → values-posture, naming only overlays this run produced).
      - The de-duplicated union of `prereqs:` ids across every answered option →
        concatenate the matching `data/prerequisites/<id>.md` fragments, in catalog
        order. Include a fragment at most once. If no option carried a `prereqs:`
        id, still write the header + render gate below.
      - A final "Pre-flight render gate" section — a copy-paste command block the
        OPERATOR runs (the wizard never runs it). Build it with an EXPLICIT `-f`
        per generated overlay, in apply order, using the operator's release name:

            helm template <RELEASE> <chart> \
              -f <chart>/values.yaml \
              -f rwl-install-out/values-registry.yaml \
              -f rwl-install-out/values-storage.yaml \
              -f rwl-install-out/values-cluster.yaml \
              -f rwl-install-out/values-posture.yaml \
              | kubectl apply --dry-run=client -f -

        List ONLY the overlays that exist in `rwl-install-out/`. Each overlay is a
        separate `-f` argument on its own line — never join them into one string.
   5. Both guides end with a short "verify it's running / when you're stuck"
      pointer (checklist Phases 6/8); note that live-cluster debugging is out of
      scope for this wizard.
   6. **Offline sanity check.** Confirm each generated `values-*.yaml` parses as
      YAML. Do NOT run `helm` — the plugin never invokes helm. The render check is
      emitted as the copy-paste command in PREREQUISITES.md for the operator to run.
      Report the YAML-parse result in the summary.

6. **Secret-guard gate.** Run
   `bash ${CLAUDE_PLUGIN_ROOT}/lib/secret-guard.sh .claude/rwl-install-profile.yaml rwl-install-out`.
   If it exits non-zero, DELETE the offending generated content, tell the
   operator exactly which file/line tripped it, and stop — do not present a kit
   that contains secret-shaped content.

7. **Summary.** Print which overlays + guides were written and the first command
   from the user guide. Point the operator at `PREREQUISITES.md` and its
   pre-flight render-gate command before installing. Suggest `/rwl-install-show`
   to review.

## Hard rules
- Generate-only. No cluster contact and NO helm at all: never run
  `helm install`/`helm upgrade`/`helm template`, `kubectl`, or anything that
  reaches a cluster. The pre-flight render gate is emitted as a command in
  PREREQUISITES.md for the operator to run — the wizard itself never invokes helm.
- Secret-free. No secret is ever requested, echoed, or written.
- Output is a pure function of (profile + catalog): always regenerate wholesale.
