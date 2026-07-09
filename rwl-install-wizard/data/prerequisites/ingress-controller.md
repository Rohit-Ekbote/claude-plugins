## Ingress controller + class (cluster prerequisite)

This kit renders Ingress objects with `ingress.className: <your value>`. That
class must be backed by an ingress controller already running in the cluster, or
the Ingress is accepted but never routed.

**Verify before `helm install`:**

    kubectl get ingressclass
    kubectl get pods -A | grep -i ingress   # controller pods Running

The class name you gave the wizard must appear in `kubectl get ingressclass`.
