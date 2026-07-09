## Gateway API routing (operator-provided)

You selected Gateway API, so this kit does NOT emit any `ingress.*` config — the
chart's Ingress objects stay disabled. YOU are responsible for routing and TLS:

- a Gateway API implementation installed (`kubectl get gatewayclass`);
- a `Gateway` + `HTTPRoute` targeting the platform Services on `<your domain>`;
- TLS terminated at your Gateway (the chart issues no ingress certificate in this mode).
