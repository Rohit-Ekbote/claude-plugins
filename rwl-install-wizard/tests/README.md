# rwl-install-wizard tests

## Automated (run directly, bash 3.2)

    bash tests/test-secret-guard.sh
    bash tests/test-catalog-lint.sh

Both must print `N passed, 0 failed`. CI runs them on every change.

## Golden fixtures (semantic equivalence)

Generation is Claude-assembled (Approach C), so golden checks assert
STRUCTURAL/SEMANTIC equivalence, not byte-for-byte:

- `fixtures/profiles/<name>.yaml` — an input profile.
- `fixtures/expected/<name>/` — the expected `values-*.yaml` overlays (the
  merged key/value tree) and the expected list of guide_section / known_issue
  ids in the guides.

To verify a slice: run `/rwl-install` (or regenerate from the fixture profile),
then confirm the generated overlay parses to the same key/value tree as the
expected file (`diff <(yaml-normalize a) <(yaml-normalize b)` where available),
and that the guides contain exactly the expected ids. The deterministic core —
which fragments and ids a profile selects — is exact; only rendered prose varies.
