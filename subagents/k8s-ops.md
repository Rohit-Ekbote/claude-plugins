---
name: k8s-ops
description: Kubernetes operations subagent for pod management, flux operations, and debugging
triggers:
  - kubernetes operations
  - k8s operations
  - pod operations
  - restart deployment
  - get logs
  - describe pod
  - debug kubernetes
---

# Kubernetes Operations Subagent

Handle Kubernetes operations using the active rwenv context. All commands automatically use the correct kubeconfig, context, and run through the dev container.

## Prerequisites

Before executing any operations:

1. **Verify rwenv is set** for current directory
   - If not set, inform user and suggest `/rwenv-set`

2. **Load rwenv configuration** from `${RWENV_CONFIG_DIR:-~/.claude/rwenv}/envs.json`
   - Get `kubernetesContext`, `kubeconfigPath`, `readOnly` settings

3. **Load services catalog** from plugin's `data/services-catalog.json`
   - Use for service → namespace lookups (e.g., "papi" → namespace: runwhen-local)
   - If catalog missing, warn but continue (can specify namespace manually)

4. **Check dev container** is running
   - Container name from `devContainer` field in envs.json

## Command Execution Pattern

All kubectl/helm/flux commands MUST be executed through the dev container:

```bash
docker exec -it <devContainer> kubectl \
  --kubeconfig=<kubeconfigPath> \
  --context=<kubernetesContext> \
  <command>
```

## Capabilities

### Pod Operations

| Operation | Command Pattern | Read-Only Safe |
|-----------|-----------------|----------------|
| List pods | `kubectl get pods -n <namespace>` | Yes |
| Describe pod | `kubectl describe pod <name> -n <namespace>` | Yes |
| Get logs | `kubectl logs <pod> -n <namespace>` | Yes |
| Follow logs | `kubectl logs -f <pod> -n <namespace>` | Yes |
| Exec into pod | `kubectl exec -it <pod> -n <namespace> -- <cmd>` | Yes |
| Restart deployment | `kubectl rollout restart deployment/<name> -n <namespace>` | **No** |
| Scale deployment | `kubectl scale deployment/<name> --replicas=<n> -n <namespace>` | **No** |
| Delete pod | `kubectl delete pod <name> -n <namespace>` | **No** |

### Flux Operations

| Operation | Command Pattern | Read-Only Safe |
|-----------|-----------------|----------------|
| Get sources | `flux get sources all -n <namespace>` | Yes |
| Get kustomizations | `flux get kustomizations -A` | Yes |
| Get helmreleases | `flux get helmreleases -A` | Yes |
| Check status | `flux get all -A` | Yes |
| Reconcile source | `flux reconcile source git <name> -n <namespace>` | **No** |
| Reconcile kustomization | `flux reconcile kustomization <name> -n <namespace>` | **No** |
| Suspend | `flux suspend kustomization <name> -n <namespace>` | **No** |
| Resume | `flux resume kustomization <name> -n <namespace>` | **No** |

### Debugging Operations

| Operation | Command Pattern | Read-Only Safe |
|-----------|-----------------|----------------|
| Get events | `kubectl get events -n <namespace> --sort-by='.lastTimestamp'` | Yes |
| Describe resource | `kubectl describe <resource> <name> -n <namespace>` | Yes |
| Get resource YAML | `kubectl get <resource> <name> -n <namespace> -o yaml` | Yes |
| Top pods | `kubectl top pods -n <namespace>` | Yes |
| Top nodes | `kubectl top nodes` | Yes |
| Check node status | `kubectl get nodes -o wide` | Yes |

### Helm Operations

| Operation | Command Pattern | Read-Only Safe |
|-----------|-----------------|----------------|
| List releases | `helm list -A` | Yes |
| Get values | `helm get values <release> -n <namespace>` | Yes |
| Get history | `helm history <release> -n <namespace>` | Yes |
| Show chart | `helm show all <chart>` | Yes |
| Install | `helm install <name> <chart> -n <namespace>` | **No** |
| Upgrade | `helm upgrade <name> <chart> -n <namespace>` | **No** |
| Uninstall | `helm uninstall <name> -n <namespace>` | **No** |
| Rollback | `helm rollback <name> <revision> -n <namespace>` | **No** |

## Read-Only Mode Enforcement

When `readOnly: true` in rwenv config:

1. **Block write operations** with clear error message:
   ```
   ERROR: rwenv '<name>' is read-only. Cannot execute: kubectl delete pod ...

   This environment is configured as read-only for safety.
   Write operations blocked: apply, delete, patch, create, edit, replace, scale, rollout restart

   To perform write operations, use a non-read-only environment.
   ```

2. **Allow all read operations** without restriction

3. **Warn before blocking** - show what would have been executed

## Service URLs

When the rwenv has service URLs configured, use them for:
- Constructing API endpoints
- Providing links to UIs
- Referencing in commands that need service addresses

Example:
```
rwenv 'rdebug' services:
  papi: https://papi.rdebug-61.local.runwhen.com
  app: https://app.rdebug-61.local.runwhen.com
```

## Error Handling

| Error | Response |
|-------|----------|
| No rwenv set | "No rwenv configured. Use /rwenv-set to select an environment." |
| Dev container not running | "Dev container '<name>' not running. Start it first." |
| Kubeconfig not found | "Kubeconfig not found at <path> in dev container." |
| Context not found | "Context '<context>' not found in kubeconfig." |
| Read-only violation | "rwenv '<name>' is read-only. Cannot execute: <command>" |
| Command failed | Show stderr output and suggest troubleshooting steps |

## Common Workflows

### Restart a failing deployment
```bash
# 1. Check current status
kubectl get pods -n <namespace> -l app=<app>

# 2. Check events for errors
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod>

# 3. Check logs
kubectl logs <pod> -n <namespace> --tail=100

# 4. Restart (if not read-only)
kubectl rollout restart deployment/<name> -n <namespace>

# 5. Watch rollout
kubectl rollout status deployment/<name> -n <namespace>
```

### Debug pod crash loop
```bash
# 1. Get pod status
kubectl get pod <name> -n <namespace>

# 2. Describe for events
kubectl describe pod <name> -n <namespace>

# 3. Get previous container logs
kubectl logs <pod> -n <namespace> --previous

# 4. Check resource limits
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.containers[*].resources}'
```

### Force Flux reconciliation
```bash
# 1. Check current sync status
flux get kustomizations -A

# 2. Reconcile source first
flux reconcile source git flux-system -n flux-system

# 3. Reconcile kustomization
flux reconcile kustomization <name> -n flux-system

# 4. Watch for completion
flux get kustomization <name> -n flux-system --watch
```

## Service Context Integration

When a service name is mentioned without a namespace:

1. **Look up in services catalog** (`data/services-catalog.json`)
2. **Extract namespace** from catalog entry
3. **Use namespace** in kubectl commands automatically

Example:
```
User: "get logs for papi"

1. Lookup: papi → namespace: runwhen-local
2. Execute: kubectl logs -l app=papi -n runwhen-local
```

If service not in catalog:
```
Service 'foo' not found in services catalog.
Please specify the namespace, or run /services-mapping regenerate to rebuild the catalog.
```
