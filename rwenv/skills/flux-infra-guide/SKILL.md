---
name: flux-infra-guide
description: Infrastructure reference for debugging and operations in the Flux-managed environment
triggers:
  - infrastructure guide
  - where does X run
  - what namespace
  - how to debug
  - check logs
  - flux resources
  - service unhealthy
  - pod failing
---

# Flux Infrastructure Guide

Quick reference for navigating the RunWhen infrastructure managed by Flux CD.

## When to Use This Skill

- Debugging service issues (unhealthy pods, failed migrations)
- Finding where a service/config is defined
- Understanding how secrets and config flow into services
- Querying logs and metrics for a specific service
- Tracing Flux reconciliation failures

## Prerequisites

- rwenv must be set (`/rwenv-cur` to verify)
- For Flux CLI commands: dev container running
- For log queries: access to observability stack

## Loading Data Files

This skill uses lazy loading. Read data files only when needed:

| Question Type | Data File |
|---------------|-----------|
| Service location ("where does X run") | `data/services.json` |
| Flux status ("why isn't X syncing") | `data/flux-resources.json` |
| Secrets ("where does X get credentials") | `data/secrets-map.json` |
| Config ("what value does X have") | `data/configmaps.json` |

Data files are located in this skill's `data/` directory.
