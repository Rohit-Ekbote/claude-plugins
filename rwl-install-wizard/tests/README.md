# rwl-install-wizard tests

## Automated (run directly, bash 3.2)

Run everything via the aggregate runner:

    bash tests/run-all.sh

It runs each `test-*.sh` suite and a `secret-guard` sweep over `data/`, and
exits non-zero if anything fails. The individual suites can also be run alone:

    bash tests/test-secret-guard.sh
    bash tests/test-catalog-lint.sh

Both must print `N passed, 0 failed`. (No CI workflow ships with this repo yet;
run `run-all.sh` before opening a PR that touches the plugin.)

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
