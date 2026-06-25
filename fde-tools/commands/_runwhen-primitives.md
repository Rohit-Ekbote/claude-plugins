# RunWhen Primitives — Shared Include

> Shared include referenced by `design-solutions`. It is **not** a slash command. It is a concise vocabulary of RunWhen's building blocks — not a tutorial — used to express each proposed solution in real RunWhen terms.

> **Accuracy note:** this encodes a point-in-time understanding of RunWhen, grounded in the RunWhen docs (`https://docs.runwhen.com/docs/use/common-user-journeys/` and the `learn/` concept pages). Review it for correctness over time. Because it ships with the plugin, corrections to it are plugin edits — not engagement-data edits via `/qna`.

## Primitives

- **Workspace** — a collaborative tenant/scope boundary; contains SLXs, assistants, and shared knowledge.
- **SLX (Service Level Experience)** — bundles a service/resource's health indicators and objectives; triggers investigation when thresholds are breached.
- **SLI (Service Level Indicator)** — a health-check task defining what healthy operation looks like, used within an SLX.
- **SLO (Service Level Objective)** — an alerting threshold within an SLX that determines when an Issue is raised.
- **Task / CodeBundle (Runbook)** — an executable diagnostic or remediation procedure; the investigative backbone and the main artifact built during tool-building.
- **CodeCollection** — a git repo packaging reusable tasks.
- **AI Assistant (Digital Assistant)** — an intelligent agent in Workspace Chat and integrations (e.g. Slack) that answers questions and runs diagnostic tasks. Tuned by **access level** (read-only / read-write) and **confidence thresholds** (filter confidence = which tasks it considers; run confidence = which it executes), plus task-tag filters. Draws context from Rules, Commands, and Knowledge. Create different personas for different risk profiles — e.g. an interactive-thorough assistant vs. an autonomous-conservative one for webhooks (low run confidence keeps scale/COGS down).
- **Workflow** — event-driven automation: an external alert/webhook/SLO-trip launches an assistant investigation and routes the result (Slack, PagerDuty, etc.). The incident-integration path.
- **Scheduled Command** — a cron-triggered recurring investigation/briefing that runs an assistant's instructions and delivers to Slack or email.
- **Rule** — standing interpretive guidance (de-noise / re-prioritize / reframe) that shapes how an assistant **interprets** findings. It does NOT change which tasks run (confidence thresholds do that) or which procedures users invoke (Commands do that). Configured in Workspace Studio, scoped workspace / per-assistant / per-user.
- **Knowledge (KB)** — curated narrative context (ownership, architecture, environment specifics) attached at resource/SLX level; how SME knowledge is encoded. There is no central KB registry.
- **RunSession / Issue** — a RunSession is the record of one investigation; an Issue is a detected problem flagged when an SLX health check fails.
- **Runner / RunWhen Local** — discovers resources and executes tasks.
- **MCP Server** — the interface an LLM client (e.g. Claude) uses to craft tasks, scheduled commands, rules, and KBs.

## Using these in a solution design

Map each proposed solution onto only the primitives it needs. Common shapes:

- **Reduce SME dependency** → an **AI Assistant** (the "SME simulator") + **Knowledge** encoding the SME's domain expertise + the **Tasks** it runs.
- **Incident triage at scale without COGS blowup** → a **Workflow** (alert/incident integration) → a conservative **autonomous Assistant** (low run confidence) + **Rules** to de-noise expected events.
- **Recurring scheduled checks** (e.g. pre-market prep-job health) → a **Scheduled Command** running a **Task**, with a **Rule** to reframe expected churn and pair failures with rerun guidance.
- **Custom resource troubleshooting** (e.g. a bespoke CRD) → a custom **Task/CodeBundle** (authored via the **MCP**) + **Knowledge** describing the resource.
