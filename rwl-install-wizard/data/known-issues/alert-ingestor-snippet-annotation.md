## Alert-ingestor ingress: `allowSnippetAnnotations: false` does not suppress hardcoded server-snippet

**Symptom:** When `ingress.allowSnippetAnnotations: false` is set in the chart values,
the alert-ingestor ingress still emits a `server-snippet` annotation. If the nginx
ingress controller has snippet annotations disabled (the secure default), the admission
webhook rejects the Ingress object:

```
Error: admission webhook "validate.nginx.ingress.kubernetes.io" denied the request:
nginx.ingress.kubernetes.io/server-snippet annotation cannot be used. Snippet
directives are disabled by the Ingress administrator
```

**Cause:** The alert-ingestor ingress template has a `server-snippet` annotation
hardcoded independently of the `ingress.allowSnippetAnnotations` flag. The flag
guards the papi and runner-metric-proxy snippets but was not wired to the
alert-ingestor template.

**Workaround:** Set `ingress.allowSnippetAnnotations: true` in the values overlay
(the wizard generates this when you select the alert-ingestor option) AND ensure
the nginx-ingress controller has `controller.allowSnippetAnnotations: true` and
`controller.config.annotations-risk-level: Critical`.

**Status:** Open — the alert-ingestor template needs its snippet guarded by the
same `ingress.allowSnippetAnnotations` flag as the other snippets.

_Source: INSTALL-FRICTIONS.md §1 (2026-04-29) — snippet annotations denied; alert-ingestor template gap noted 2026-06-11._
