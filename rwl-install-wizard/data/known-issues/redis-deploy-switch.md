## Redis: does `redis.deploy` need to be explicitly set?

**Open question (2026-06-15):** The chart default is `redis.deploy: true` in
`values.yaml`. On a standard install Redis deploys without any explicit overlay.
However, there is a question of whether certain cluster configurations or
multi-overlay setups could inadvertently shadow this default with `redis.deploy: false`.

**Current behavior:** `redis.deploy: true` is the values.yaml default (line 1025).
No explicit overlay is required for a standard bundled-subchart install.

**Why the wizard pins it explicitly:** If an upstream overlay sets `redis.deploy: false`
(e.g. an airgap or BYO-datastores overlay merged in the wrong order), Redis will
not deploy even though no error is shown. Pinning `redis.deploy: true` in the
generated overlay makes the intent explicit and protects against accidental shadowing.

**Status:** Open — confirm whether any chart-managed overlay path can set
`redis.deploy: false` and silently break the default bundled install.

_Source: values.yaml `redis.deploy: true` (line 1025); open operational question noted 2026-06-15._
