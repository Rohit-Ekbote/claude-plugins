## SeaweedFS image lives under `chrislusf/` on Docker Hub (looks personal, is upstream-canonical)

**Symptom:** Security review flags the `chrislusf/seaweedfs` Docker Hub
namespace as a personal account. Enterprise firewall whitelists or JFrog
`includesPattern` entries for `chrislusf/**` raise questions about supply-chain
trust.

**Cause:** The `seaweedfs` Helm subchart defaults its image to
`chrislusf/seaweedfs:<appVersion>`. `chrislusf` is Chris Lu, the SeaweedFS
project author. The SeaweedFS upstream README (verified 2026-05-15) points
exclusively to `chrislusf/seaweedfs` on Docker Hub — no org-namespaced
alternative (`ghcr.io/seaweedfs/seaweedfs`) has publicly-pullable manifests;
tag listings exist but every manifest endpoint returns HTTP 404 to anonymous
pulls. `chrislusf/seaweedfs` IS the canonical upstream artifact today.

**Mitigations:**

1. **Document for security reviewers:** The `chrislusf/` namespace is the
   upstream-canonical publish path, not a personal fork. Add a note in your
   JFrog/Artifactory proxy config or firewall runbook so reviewers have a
   one-paragraph answer without a separate Q&A round-trip.

2. **Optional digest pinning:** For hardened installs requiring supply-chain
   immutability, override `seaweedfs.image.tag` with the resolved
   `sha256:...` manifest digest of `chrislusf/seaweedfs:<version>`. This does
   not change the namespace optic but eliminates tag-rug risk.

3. **Long-term fix (RW-1058):** Mirror SeaweedFS into the `runwhen-self-hosted`
   GAR under the first-party image path, eliminating Docker Hub from the
   airgap manifest for the SeaweedFS path entirely.

Re-evaluate `ghcr.io/seaweedfs/seaweedfs` quarterly — if the upstream README
starts pointing at a public ghcr or quay artifact, the `seaweedfs.global.seaweedfs.image.name`
override can be switched to the org-namespaced path.

_Source: INSTALL-FRICTIONS.md §29 (accepted upstream choice, 2026-05-15)._
