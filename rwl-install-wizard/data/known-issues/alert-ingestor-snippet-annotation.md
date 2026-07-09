## Alert-ingestor ingress snippet under `allowSnippetAnnotations: false`

**Status (chart 0.2.59): resolved.** The alert-ingestor `server-snippet` is now
gated by `ingress.allowSnippetAnnotations` — the same flag that guards papi's
snippet, in the shared `templates/ingress/ingress.yaml`. Setting
`allowSnippetAnnotations: false` no longer makes the admission webhook reject the
Ingress. (The earlier bug, where the alert-ingestor snippet was emitted
independently of the flag, has been fixed upstream.)

**What snippets-off costs you.** On the hardened / `ingress-snippets =
snippets-blocked` path (`allowSnippetAnnotations: false`), alert-ingestor renders
its Ingress WITHOUT the `nginx.ingress.kubernetes.io/server-snippet` that denies
`/metrics` — exactly as papi renders without its `/internal/` deny snippet. The
endpoints still route; you lose the nginx-level deny rule and must enforce that
restriction at the network layer if you need it.

**Why the wizard has no separate "alert-ingestor" toggle.** Its only purpose was to
force `allowSnippetAnnotations: true`. Since 0.2.59 gates alert-ingestor on the same
flag as papi (graceful degradation, no forced snippets), snippet policy is owned
entirely by the `ingress-snippets` axis: choose `snippets-allowed` if your controller
permits snippets and you want the deny rules, `snippets-blocked` if it does not.

_Historical: original friction logged INSTALL-FRICTIONS.md §1 (2026-04-29); the
alert-ingestor template gap was fixed upstream and verified on chart 0.2.59._
