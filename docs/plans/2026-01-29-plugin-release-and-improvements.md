# rwenv Plugin Release and Improvements

**Date:** 2026-01-29
**Status:** Implemented

## Summary

This session covered converting the rwenv plugin to an installable format and implementing several improvements based on testing feedback.

## Part 1: Plugin Release

### Naming Decision
- Name: `rwenv` (short acronym, RunWhen brand focus)
- Repository: `https://github.com/Rohit-Ekbote/rwenv`
- Distribution: GitHub repo, user-level installation

### Structure Changes
- Renamed `skills/` flat files to `skills/<name>/SKILL.md` (superpowers convention)
- Renamed `subagents/` to `agents/` (plugin loader convention)
- Added `.claude-plugin/plugin.json` and `marketplace.json`
- Renamed `pre-command.sh` to `transform-commands.sh`
- Added MIT LICENSE

### Installation
```bash
claude plugins add Rohit-Ekbote/rwenv
```

## Part 2: db-ops Improvements

### Problem
- Documentation showed two options (kubectl exec vs port-forward) without clear guidance
- No helper function for psql like other commands
- Safety enforcement was always blocking all writes

### Solution
- **Port-forward as THE approach** on port 3105 (already exposed by dev container)
- **Defense in depth validation**:
  - DDL (CREATE, ALTER, DROP, etc.) always blocked on any rwenv
  - DML (INSERT, UPDATE, DELETE) blocked only when `rwenv.readOnly=true`
- **New helper functions** in `rwenv-utils.sh`:
  - `validate_db_query()` - shared validation logic
  - `build_psql_cmd()` - builds port-forward + psql commands

### Port-Forward Config
- Port: `3105`
- Address: `0.0.0.0` (accessible from host)

## Part 3: Service Access Patterns

### Problem
- Claude was using port-forward for services when it shouldn't
- No clear guidance on how to access different types of services

### Solution
Services catalog (`data/services-catalog.json`) now defines:

```json
{
  "papi": {
    "exposed": true,
    "address": "https://papi.<rwenv-name>.runwhen.com",
    "namespace": "backend-services",
    "podSelector": "app=papi",
    "internalPort": 8080
  }
}
```

### Access Patterns

| Service Type | Method |
|--------------|--------|
| **Exposed** (papi, app, vault, gitea, agentfarm) | Direct curl from host: `curl https://papi.rdebug-61.runwhen.com/...` |
| **Internal** (all others) | kubectl exec: `kubectl exec <pod> -- curl http://localhost:<port>/...` |

### New Helper Functions
- `get_service_info()` - returns service details with resolved address
- `list_services()` - lists all services in catalog
- `get_plugin_dir()` - returns plugin installation directory

## Commits

1. `8a70dd5` - feat: convert to installable Claude Code plugin format
2. `b8b95da` - fix: add marketplace.json for plugin installation
3. `b826f4a` - fix: remove unsupported fields from plugin.json
4. `eee9757` - refactor: restructure skills and agents for plugin loader compatibility
5. `e34ec5e` - feat: improve db-ops with port-forward approach and safety enforcement
6. `6f16ff6` - feat: add service catalog with exposed/internal access patterns

## Files Modified

- `.claude-plugin/plugin.json` - Plugin metadata
- `.claude-plugin/marketplace.json` - Marketplace metadata
- `hooks/hooks.json` - Hook declarations
- `hooks/transform-commands.sh` - Renamed from pre-command.sh
- `lib/rwenv-utils.sh` - Added validation and helper functions
- `scripts/pg_query.sh` - Port-forward approach, shared validation
- `agents/db-ops.md` - Simplified documentation
- `agents/k8s-ops.md` - Service access patterns
- `data/services-catalog.json` - Exposed services with addresses
- `skills/*/SKILL.md` - Restructured to subdirectories
