### Registry: connected (public upstreams)

No registry override is needed. The chart pulls every image from its default
upstream registry:

- First-party services (`backend-services`, `agent-farm`, `runner-control`,
  `webhooks-service`, `usearch`, `user-pages`, `embedder`) from
  `us-docker.pkg.dev/runwhen-self-hosted/platform-images`.
- `mcp-server`, `cc-catalog-svc`, and `cortex-tenant` from `ghcr.io/runwhen-contrib`.
- LiteLLM gateway from `ghcr.io/berriai`.
- Subchart images (Vault, Spilo, Redis, Neo4j, Mimir, Qdrant, SeaweedFS) from
  Docker Hub / ghcr.io as defined in each subchart's defaults.

Ensure the cluster's nodes have outbound HTTPS (port 443) access to:
`us-docker.pkg.dev`, `ghcr.io`, `docker.io`, `quay.io`.
