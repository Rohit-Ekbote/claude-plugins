### Admission-webhook labels + security context propagation

Enterprise clusters often require specific labels on every resource (cost-center,
compliance classification, OPA policy bundle) or specific `securityContext`
fields on every pod. The chart provides two top-level extension points:

**`global.commonLabels`** — propagates to EVERY chart-rendered resource
(Deployments, Services, Secrets, ConfigMaps, Ingresses, RBAC, Jobs):

```yaml
global:
  commonLabels:
    cost-center: "platform-eng"
    compliance.example.com/data-classification: "internal"
```

**`global.podLabels` / `global.podAnnotations`** — applied at the pod-template
level only; used by service-mesh sidecar injectors and per-pod policy controls:

```yaml
global:
  podLabels:
    policy.example.com/enforce: "baseline"
  podAnnotations:
    linkerd.io/inject: enabled
```

**`global.podSecurityContext` / `global.containerSecurityContext`** — override
the default hardened baseline for every chart-managed first-party pod. The
hardened defaults already satisfy PSS `restricted`:

```yaml
global:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: ["ALL"]
```

**Note:** `global.commonLabels` does NOT propagate to the Neo4j subchart's
StatefulSet (Neo4j renders its own pod spec). Mirror required labels under
`neo4j.commonLabels` if your admission controller targets Neo4j pods.

_Source: values-example-enterprise-byo-sa.yaml §1; security-hardening.md §1; INSTALL-FRICTIONS.md §N (chart 0.2.2)._
