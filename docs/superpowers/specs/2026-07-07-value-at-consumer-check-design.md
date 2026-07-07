# Design: value-at-consumer check for rwl-install-wizard

**Date:** 2026-07-07
**Status:** Approved (brainstorming) — pending spec review → implementation plan
**Owner:** Rohit Ekbote

## Problem

Four bugs across v0.1.4–v0.1.6 share one root cause: **the plugin emits a value in
one shape while the chart reads it in another**, so the operator's input is
silently replaced by a chart fallback — the kit renders green but points the
platform at the wrong thing. The clearest case is MISSED-11: byo-datastores set
`vault.external.address` but not flat `vault.address`/`vault.runnerAddress`, so
`VAULT_URL`/`RUNNER_VAULT_URL` resolved to `https://vault.<global.domain>` instead
of the operator's Vault. Each time, a **too-loose test** hid it — e.g.
`grep -q vault.example.com` passed on one occurrence while another consumer was
wrong.

The through-line fix has been manual each time: render verbatim, then eyeball the
value at the consumer. This design makes that mechanical.

## Goal & non-goals

**Goal:** assert that each operator-supplied input reaches **every** rendered
consumer that should reflect it, so a shape mismatch that drops the value to a
fallback fails a test — automatically, data-driven, no hardcoded env keys in test
code.

**Non-goals:** does not validate values are semantically correct (a well-formed
but wrong URL the operator typed is their problem); does not replace the existing
render / public-ref / no-`--set` guards — it complements them.

## Decisions (from brainstorming)

- **Location:** BOTH. Primary in the plugin render guard (`tests/test-airgap-registry.sh`),
  which renders full fixture profiles that have the context consumers need. The
  `rwl-catalog-update` detector reuses the same declarations opportunistically.
- **Declaration:** per-param `consumers:` metadata in `knob-catalog.yaml` (single
  source of truth read by both).
- **Scope:** `equals` + `contains` in v1.

## The declaration

An optional `consumers:` field on any param that feeds a rendered consumer:

```yaml
- { id: vaultAddress, prompt: "…", consumers: { equals: [VAULT_URL, RUNNER_VAULT_URL, VAULT_ADDR] } }
- { id: pgHost,       prompt: "…", consumers: { contains: [DATABASE_URL] } }
- { id: llmBaseUrl,   prompt: "…", consumers: { equals: [api_base] } }
```

- `equals` — every rendered occurrence of the key must equal the param value
  (identity consumers: VAULT/NEO4J/LLM/S3/qdrant).
- `contains` — every occurrence must contain the value as a substring (composite
  consumers: DATABASE_URL/REDIS_URL, where credentials wrap the host).
- Only params that feed a consumer declare it; the rest are untouched.

**Check semantics (what makes it non-weak):** for a param with value `v` and its
consumer keys —
1. **≥1** of the keys must appear in the render (catches "input silently dropped"), and
2. **every** rendered occurrence of **every** listed key must satisfy equals/contains `v`
   (catches "fell through to a fallback in some pod").

A bare `grep v` passes when `v` appears anywhere; this asserts it at *every*
consumer.

## Components

1. **Catalog `consumers:` metadata** — the declarations above, on relevant params.
2. **`consumer-values.rb`** (shared extractor) — `consumer-values.rb <render.yaml> <KEY>`
   prints every rendered value of `KEY`, handling both forms:
   - configmap data: `  KEY: "value"` / `  KEY: value`
   - pod env: `- name: KEY` followed by `value: "value"`
   One responsibility; unit-testable on a fixed manifest.
3. **`check-consumers.sh`** (shared assertion driver) — inputs: a profile-answers
   file (param id → value), the catalog, a rendered manifest. For each answered
   param that declares `consumers`, substitute the value, run the extractor per
   key, apply the two-part semantics, emit `ok`/`no` lines. The guard treats
   output as test assertions; the detector treats it as report items.

## Integration

- **Plugin guard (primary):** formalize the byo scenario as a real profile —
  `tests/fixtures/profiles/byo.yaml` (answers incl. `vaultAddress`, `pgHost`,
  `redisHost`, `neo4jUri`, `qdrantUrl`) + its expected overlays. The guard renders
  each profile (airgap + byo) verbatim (no `--set`) and calls `check-consumers`
  with that profile's answers. airgap exercises `llmBaseUrl → api_base`; byo
  exercises the datastore consumers. No consumer env key is hardcoded in the test.
- **Detector (opportunistic):** where an option it renders resolves a declared
  consumer (e.g. the internal-openai option's `api_base`), it runs the same
  `check-consumers` and emits a `consumerMismatch` finding. Isolation limits
  coverage; cost is ~zero because declarations + checker are shared.
- **`catalog-lint`:** add a rule validating the `consumers` shape (`equals`/`contains`
  are lists of non-empty key tokens) so a typo can't silently disable a check.

## Testing

- `consumer-values.rb`: unit test on a crafted manifest containing both env forms
  + a decoy key; asserts exact extraction.
- `check-consumers.sh`: two fixtures — a correct render (passes) and a fallback
  render where `VAULT_URL` = `vault.<domain>` (must FAIL). Proves non-vacuity.
- Wire both into the plugin `tests/run-all.sh` and the detector `tests/`.

## Risks / notes

- **Composite creds in output:** `contains` compares against the host substring
  only; the extractor must not leak/compare secret portions. Declarations use
  `contains` for the host param (e.g. `pgHost`), never the password (which is a
  Secret and never in values — consistent with the secret-free contract).
- **Env-form drift:** if the chart introduces a third way of surfacing a value
  (e.g. `valueFrom`), the extractor returns nothing → the "≥1 present" rule fails
  loudly rather than passing silently. That is the correct failure direction.
- **byo profile fixture** is a small standalone improvement — byo is currently an
  ad-hoc test layering with no answers file.

## File layout

```
rwl-install-wizard/
  data/knob-catalog.yaml                         # + consumers: on relevant params
  lib/catalog-lint.sh                            # + consumers-shape rule
  lib/consumer-values.rb                         # extractor (shared)
  lib/check-consumers.sh                         # assertion driver (shared)
  tests/test-airgap-registry.sh                  # call check-consumers per profile
  tests/fixtures/profiles/byo.yaml               # new byo profile answers
  tests/fixtures/expected/byo/                    # new byo expected overlays
  tests/test-consumer-values.sh                  # extractor unit test
  tests/test-check-consumers.sh                  # driver non-vacuity test
.claude/skills/rwl-catalog-update/detect-drift.sh # opportunistic consumerMismatch
```

(The detector references the plugin's `lib/` helpers by repo-relative path, as it
already does for `catalog-lint.sh` and the fixtures.)
