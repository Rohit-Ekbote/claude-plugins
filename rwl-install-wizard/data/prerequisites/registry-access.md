## Mirror registry access (cluster prerequisite)

Images are pulled from your mirror at the host you supplied. Before install:

- confirm nodes can reach the mirror host and the per-upstream repos exist
  (docker-dockerhub, docker-ghcr, docker-runwhen-self-hosted, docker-suse or your
  renamed equivalents);
- confirm the image pull Secret you named exists in the release namespace;
- verify each PINNED subchart tag (neo4j, vault, bci-base) is present on the
  mirror — see the air-gap image manifest in your USER-GUIDE.
