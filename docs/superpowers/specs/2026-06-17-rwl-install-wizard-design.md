# rwl-install-wizard — Design

Status: Approved (V1 scope)
Owner: Rohit Ekbote
Date: 2026-06-17

## Summary

The RunWhen platform Helm chart (`runwhen-platform`, currently `0.2.34`) is a
large application: a 3,287-line `values.yaml`, ~45 workloads, and 5 subcharts
(postgresql, redis, neo4j, vault, qdrant, seaweedfs). Standing it up in a real
enterprise cluster is slow and error-prone — not because any single knob is
hard, but because the *combination* of knobs an operator needs depends heavily
on their environment (air-gap, BYO ServiceAccounts, non-root / read-only
rootfs, non-RFC1918 pod CIDR, internal CA, storage class, TLS mode). The chart
already documents this knowledge, but it is scattered across a 193 KB
`INSTALL-FRICTIONS.md`, an `INSTALL-CHECKLIST.md`, `security-hardening.md`,
airgap/registry-routing docs, and 7 `values-example-*.yaml` overlays.

`rwl-install-wizard` is a Claude Code plugin (conceptually inspired by
`/using-superpowers`) that interviews the operator about their cluster's
constraints and emits a **curated install kit**:

- **Layered `values` overlays** (one per axis-group, only the ones their
  answers require).
- A **tailored user guide** — a phase-structured runbook with the exact
  `helm`/`kubectl` commands to run, in order, with their overlay filenames and
  domain/namespace already substituted.
- A **tailored debug guide** — only the known issues their chosen install shape
  can actually hit, distilled from the friction log.

The plugin is **self-contained** (carries its own distilled knowledge as
structured data; needs no source repo at runtime), **generate-only** (never
touches a cluster), and **secret-free** (never asks for or persists any
credential).

## Goals

- An operator with only the plugin (and at most a pulled chart `.tgz`) can
  answer a guided interview and walk away with a reviewable, correct set of
  `values` overlays plus tailored guides for their exact environment.
- The interview, overlays, and guides are tailored to the operator's answers —
  short and high-signal, not a reprint of the full frictions doc.
- The operator's answers persist as a re-runnable profile, so a week-long
  iterative install means changing one answer and regenerating, not redoing the
  whole interview.
- Coverage is auditable and maintainable: a new chart knob or a newly logged
  friction is a **data edit**, never a skill rewrite.
- The plugin never asks for, echoes, or stores any secret or credential.

## Non-goals (V1)

- **No cluster access.** The wizard never runs `helm install/upgrade`, never
  applies/patches/deletes resources, never reads live cluster state. Live
  debugging of a running release is explicitly out of scope (the operator uses
  their own tooling).
- **No secret handling.** No prompting for, generation of, or storage of
  passwords, tokens, API keys, PATs, kubeconfigs, or cert private material.
- **Not coupled** to the `rwenv` / `rwl-env` plugins — it is an independent
  concept that happens to ship in the same marketplace. It does not inherit
  their prefixes, hooks, or state conventions.
- **No deterministic generation engine / Python / `yq` dependency.** Generation
  is performed by the skill (Claude) assembling exact fragments the catalog
  supplies; helper scripts stay bash-3.2 clean.
- **No multi-chart generalization** yet. The catalog targets the RunWhen
  platform chart; the architecture does not preclude generalization later but
  V1 does not build for it.

## Decisions (from brainstorming)

1. **Primary user:** customer operator, *without* the source repo (at most a
   pulled `.tgz`). ⇒ plugin is self-contained; overlays layer onto whatever
   `values.yaml` ships in the chart.
2. **Values output shape:** layered, purpose-scoped overlays (mirrors the
   chart's existing convention).
3. **Action scope:** generate-only; zero cluster access.
4. **Guide curation:** tailored strictly to the operator's answers (no
   "everything" appendix).
5. **State model:** persisted, re-runnable profile.
6. **Architecture:** Approach C — a structured **knob catalog** is the source of
   truth; interview + generation are **skills** that assemble overlays/guides
   from exact catalog fragments.
7. **Placement & name:** independent plugin `rwl-install-wizard` inside the
   existing `rohit-claude-plugins` marketplace.

## Architecture

### Component layout (plugin)

```
rwl-install-wizard/
├── .claude-plugin/plugin.json          # name, version, chartCompat range (e.g. ">=0.2.30 <0.3")
├── README.md
├── skills/
│   ├── rwl-install/SKILL.md            # /rwl-install — run/resume interview → generate kit
│   ├── rwl-install-show/SKILL.md       # /rwl-install-show — show profile + generated kit (read-only)
│   └── rwl-install-explain/SKILL.md    # /rwl-install-explain <topic> — explain one axis/knob
├── data/
│   ├── knob-catalog.yaml               # SOURCE OF TRUTH: axes → questions → value fragments
│   ├── guide-sections/                 # phase-structured user-guide section library
│   └── known-issues/                   # debug-guide entries distilled from INSTALL-FRICTIONS
└── tests/                              # catalog lint + golden-profile fixtures + secret-guard
```

### Generated kit (operator's working dir, auto-gitignored)

```
.claude/rwl-install-profile.yaml         # persisted answers (re-runnable, the ONLY state)
rwl-install-out/
├── values-cluster.yaml                  # layered overlays — only files that received content
├── values-registry.yaml
├── values-storage.yaml
├── values-posture.yaml
├── USER-GUIDE.md                        # tailored, phase-structured install runbook
└── DEBUG-GUIDE.md                       # tailored known-issues for the chosen shape
```

The wizard only ever writes the profile and `rwl-install-out/`. It never edits
the chart.

### Knob catalog (source of truth)

`knob-catalog.yaml` is a list of **axes**. Each axis is one operator decision
and declares: how to ask it, what values each option emits, which overlay file
the values land in, and which guide sections / known-issues the option
activates. Skills hold **no** hardcoded RunWhen knowledge.

Axis taxonomy (V1):

| Axis | Primary overlay | Key choices |
|---|---|---|
| `cluster-shape` | `values-cluster.yaml` | public domain, StorageClass (GKE/EKS/AKS/on-prem/NFS), ingress className, TLS mode (3) |
| `registry-routing` | `values-registry.yaml` | connected public upstreams / flat `registryOverride` mirror / per-upstream JFrog routing |
| `storage` | `values-storage.yaml` | PVC vs NFS vs emptyDir; object storage = bundled SeaweedFS vs external S3 |
| `security-posture` | `values-posture.yaml` | non-root / specific-UID, read-only rootfs, admission-webhook labels/securityContext |
| `rbac-identity` | `values-posture.yaml` | BYO ServiceAccounts (no chart SA/RoleBindings), drop ClusterRoleBindings, Vault injector/authDelegator off, imagePullSecrets off |
| `internal-ca` | `values-cluster.yaml` | private/corporate CA trust-bundle injection |
| `subcharts` | `values-cluster.yaml` | each of postgres/redis/neo4j/vault/qdrant: bundled vs BYO-external |
| `networking` | `values-cluster.yaml` | non-RFC1918 pod CIDR → mimir `bind_addr`/`advertise_addr` fix |
| `llm-endpoint` | `values-cluster.yaml` | internal OpenAI-compatible endpoint wiring (URL only — no key) |
| `optional-components` | `values-cluster.yaml` | Slack, alert-ingestor, redis toggle |

Shape of one axis entry (illustrative):

```yaml
- id: networking
  title: Pod network CIDR
  question: "Is your pod network in standard private (RFC1918) ranges?"
  options:
    - id: rfc1918
      label: "Yes — 10.x / 172.16-31.x / 192.168.x"
      emits: {}                       # no override needed
    - id: non-rfc1918
      label: "No — e.g. DoD/carrier space like 21.121.x"
      overlay: values-cluster.yaml
      emits:                          # exact fragment the generator drops in
        metricstore:
          config:
            memberlist: { bind_addr: ["127.0.0.1"], advertise_addr: "127.0.0.1" }
      guide_sections: [networking-non-rfc1918]
      known_issues: [mimir-memberlist-no-private-ip]
```

Optional per-axis / per-option fields:
- `since:` / `until:` — chart-version bounds; the option is only offered when
  the confirmed chart version is in range.
- `conflictsWith:` — list of `<axis>:<option>` pairs that cannot coexist
  (must be declared symmetrically).
- `dependsOn:` — earlier answers that make this axis relevant; lets the
  interview skip/auto-answer mooted axes.

## Skills, profile, and data flow

### Profile

`.claude/rwl-install-profile.yaml` holds the operator's answers plus provenance
only — never derived data, never secrets:

```yaml
schemaVersion: 1
chartCompat: ">=0.2.30 <0.3"      # range this kit was generated against
generatedAt: "2026-06-17"
answers:
  cluster-shape: { domain: rw.example, storageClass: managed-csi, ingressClass: nginx, tls: clusterIssuer }
  registry-routing: { mode: jfrog-per-upstream, registry: jcr.example }
  security-posture: { runAsNonRoot: true, uid: 65534, readOnlyRootfs: true }
  rbac-identity: { byoServiceAccounts: true, clusterRoleBindings: false }
  networking: { cidr: non-rfc1918 }
  # ... only answered axes appear
```

The profile schema has **no field capable of holding a secret**.

### `/rwl-install` (the wizard)

```
load knob-catalog.yaml
  ├─ confirm chart version is in chartCompat range (warn + flag "unverified" if not)
  ├─ profile exists?
  │     yes → preload answers, summarize what's saved, ask:
  │             "review all / change a specific axis / regenerate as-is"
  │     no  → walk axes in dependency order, ONE question at a time (AskUserQuestion);
  │            skip/auto-answer downstream axes mooted by earlier answers;
  │            surface any conflictsWith collision and require resolution
  ├─ write profile (partial profile saved even if the operator quits mid-interview)
  ├─ GENERATE
  └─ print summary + the first command to run
```

### GENERATE (a step within the skill, not a separate binary)

1. For each answered axis option, collect its `emits:` fragment and target
   overlay.
2. Deep-merge fragments per overlay file → write only overlays that received
   content. Each overlay gets a header naming the `chartCompat` range and the
   axis answers that produced it.
3. Collect the de-duplicated union of `guide_sections` / `known_issues` ids →
   assemble `USER-GUIDE.md` (rendered in checklist Phase 0→10 order) and
   `DEBUG-GUIDE.md` (rendered in severity/phase order). Each known-issue is
   rendered from `data/known-issues/<id>.md` (symptom → cause → fix),
   cross-linked to its friction-log origin.
4. Run an offline sanity check: YAML parses; run `helm template` only if a
   chart path is present locally, otherwise skip. Report results.
5. Run the **secret-guard** scan over the profile and `rwl-install-out/`; abort
   with the offending location if anything secret-shaped is found.

GENERATE always **fully rewrites** `rwl-install-out/` from the profile — never
patches in place — so output is a pure function of (profile + catalog).

### `/rwl-install-show`

Read-only. Prints the saved profile, which overlays/guides exist, and the exact
install command line.

### `/rwl-install-explain <axis|knob>`

Explains one decision in depth (what it does, why it matters, the friction it
prevents) from the catalog + known-issues, without running the interview. The
"I don't understand this question" escape hatch.

## Generated artifacts & tailoring

- **Values overlays** — only files that received `emits:` content are written;
  each carries a header naming the chart-compat range and the answers that
  produced it, so a reviewer sees *why* each key exists.
- **USER-GUIDE.md** — assembled from `data/guide-sections/`, ordered by the
  `INSTALL-CHECKLIST.md` Phase 0→10 skeleton. Only phases/sub-blocks whose
  activating axis was selected appear (e.g. air-gap operators get the
  subchart-alias-mirroring blocks; BYO-SA operators get the enterprise BYO-SA
  blocks; connected installs see neither). Command blocks render with the
  operator's overlay filenames already in the `-f` flags and their
  domain/namespace substituted — but secret creation stays as `<PLACEHOLDER>`
  templates (see invariant).
- **DEBUG-GUIDE.md** — the union of `known_issues` ids activated by the
  operator's answers, nothing else.

**Tailoring mechanism = set union over ids.** Each chosen axis-option
contributes `guide_sections` + `known_issues` ids; the guides are the
de-duplicated union rendered in canonical order. Relevance is *declared in the
catalog*, not decided ad hoc — so tailoring is deterministic and auditable.

Both guides end with a short "when it's running / when you're stuck" pointer:
verification steps drawn from checklist Phases 6/8, and a note that live-cluster
debugging is a separate concern.

## Secret-free invariant (hard rule)

The wizard never asks for and never persists any credential or secret.

- **Interview** only collects non-sensitive *cluster shape* facts: domain,
  StorageClass, ingressClass, UID/GID, registry **hostname/repo path** (not its
  password), CA-bundle *source reference*, endpoint URLs. There is no free-text
  "secret" answer path.
- **Generated overlays** wire every secret the chart needs via `existingSecret:`
  / secret-**name** references only. Values files contain secret *names*, never
  secret *contents*.
- **USER-GUIDE** provides `kubectl create secret …` / secret-manager command
  **templates** with `<PLACEHOLDER>` tokens the operator fills at their own
  terminal; the wizard neither captures, echoes, nor stores those values.
- **Profile** has no field capable of holding a secret.
- **Enforcement:**
  - Catalog-lint rule: fails if any axis option's `emits:` writes under
    secret-ish keys (`password`/`token`/`key`/`secret`/`credential`/…) with a
    literal value instead of an `existingSecret` reference.
  - Post-GENERATE secret-guard scan: aborts generation if the profile or
    `rwl-install-out/` contains secret-shaped content, naming the location.

## Versioning / drift

Chart-version drift is the plugin's biggest long-term risk (the chart moved
`0.2.3 → 0.2.34` during a single customer install).

- `plugin.json` declares a `chartCompat` range; every generated overlay and
  guide is stamped with it.
- The interview's first step states the targeted chart range and asks the
  operator to confirm their chart version is in range. Out of range → warn,
  still generate, flag the kit "unverified for chart X".
- Catalog entries may carry `since:`/`until:` so version-specific knobs are
  offered only when applicable.
- Maintenance contract (documented in the catalog header): a new chart knob or a
  newly logged friction is a catalog/data edit, never a skill rewrite.

## Error handling

| Situation | Behavior |
|---|---|
| Operator quits mid-interview | Partial profile saved; re-running resumes. |
| Catalog references a missing `guide_sections`/`known_issues` id | Caught by lint in tests; at runtime, hard error naming the offending id. |
| Conflicting answers | `conflictsWith` in catalog; interview surfaces and requires resolution before GENERATE. |
| Chart not present locally | Fine — skip the optional `helm template` check, still emit everything (the no-chart primary user). |
| Chart version out of `chartCompat` | Warn, generate, flag kit "unverified". |
| Secret-shaped content in output | Abort generation; report location (invariant guard). |

## Testing (offline, no live cluster)

- **Catalog lint:** every referenced section/issue id resolves to a file; no
  orphan files; no `emits:` writes a literal secret; every axis option has a
  label; `conflictsWith` pairs are symmetric; `since`/`until` ranges parse.
- **Golden-profile fixtures:** representative profiles (connected-vanilla,
  air-gap-JFrog, enterprise-BYO-SA-hardened, NFS-single-node, and a full
  "enterprise" shape combining non-root + non-RFC1918 + air-gap) each have an
  expected `rwl-install-out/` tree checked into `tests/`. Because generation is
  Claude-assembled (Approach C), the assertion is **structural/semantic
  equivalence**, not byte-for-byte: the expected overlays parse to the same
  merged key/value tree, the same set of overlay files is written, and the same
  set of `guide_sections` / `known_issues` ids appears in the guides. (The
  deterministic core — which fragments and ids a profile selects — is a pure
  function of profile + catalog and can be asserted exactly; only the rendered
  prose is allowed to vary.)
- **Secret-guard test:** feed a profile through GENERATE and assert the scanner
  finds nothing secret-shaped.
- **Shell helpers** (lint/guard) stay bash-3.2 clean per the marketplace
  convention (no `declare -A`, `${var,,}`, `|&`, or `local` outside functions).

## Open items / V2 candidates

- Generalizing the catalog to non-RunWhen charts (the architecture allows it;
  V1 does not build for it).
- A `helm template`-based deep validation mode when a chart path *is* present
  (V1 only does a presence-gated syntax check).
- Auto-detecting chart version from a local `.tgz`/`Chart.yaml` rather than
  asking the operator to confirm.
- An optional "explain my whole kit" summary that walks every generated file.

## References (in `runwhen/rwlight-helm`)

- `charts/runwhen-platform/values.yaml` — 3,287-line base values (the knobs).
- `charts/runwhen-platform/values-example-*.yaml` — 7 overlays that seeded the
  axis taxonomy.
- `charts/runwhen-platform/docs/install/INSTALL-CHECKLIST.md` — Phase 0→10
  skeleton + conditional blocks → user-guide structure.
- `charts/runwhen-platform/INSTALL-FRICTIONS.md` — ~36 dated known issues →
  debug-guide / known-issues catalog.
- `charts/runwhen-platform/docs/install/{registry-routing,security-hardening,airgap,customer-access}.md`
  — per-axis detail.
