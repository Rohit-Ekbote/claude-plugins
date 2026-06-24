# sample-engagement fixture

A minimal FDE engagement directory for manually smoke-testing the fde-tools commands.

Planted material:
- **Dates** across Granola (header + filename `2026-03-12`), Slack timestamps (`2026-03-19`, `2026-03-25`), and a raw note (`2026-04-01`) — exercises every date source in `_date-parsing.md`.
- **A material contradiction:** kickoff says "NFS-only" storage; Slack says "Postgres needs block storage"; the raw note (2026-04-01, latest) resolves it (block storage available; NFS-only is archive-tier only). Exercises contradiction handling and latest-wins resolution.
- **Two feature-asks:** Okta SSO (2026-03-12), offline guide (2026-03-25) — exercises `update-requirements`.

## Manual smoke (needs the Claude runtime — not run in CI)

From inside `tests/fixtures/sample-engagement/`:

    claude "/summarize-engagement"     # -> summary.md, 7 sections, current-truth
    claude "/update-progress"          # -> progress.md, dated sections newest-first
    claude "/update-requirements"      # -> requirements.md, asks under 2026-03-12 and 2026-03-25
    claude "/build-guide"              # -> guide/ offline HTML
    claude "/qna where did the storage decision come from?"   # cites provenance

Generated files (summary.md, progress.md, requirements.md, guide/, corrections.md, changelog.md)
are throwaway — do not commit them. They are covered by the repo .gitignore patterns or should be
removed after smoke-testing.
