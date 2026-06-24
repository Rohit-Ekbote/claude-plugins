# Engagement Context — Shared Include

> This file is a shared include referenced by the fde-tools commands (`build-guide`, `summarize-engagement`, `update-progress`, `update-requirements`, `qna`). It is **not** a slash command and is not run directly.

---

## Loading the engagement context

Read every readable text file found recursively under each of these directories in the current working directory:

- `slack/`
- `granola/`
- `raw/`

Include all files regardless of file extension. If any of these directories is absent, skip it silently — do not error, do not attempt to create it.

The combined contents of all files read constitute **the engagement context** for this session.

## Corrections overlay (precedence & resolution)

`corrections.md` is the single dated overlay journal in the working directory. Read it before processing the engagement context.

**Resolution rule** (latest-wins-by-topic): for any topic, the most recent dated statement wins as current truth, across notes and corrections. On a date tie, a `corrections.md` entry wins over a raw note. A correction is never deleted.

Topics are short human-readable slugs matched **semantically**, not a strict enum — e.g. `setup-status`, `storage-backend`, `ingress-plan`.

**Read-only inputs:** Files under `slack/`, `granola/`, and `raw/` are pristine source material — never modify them. You may append to or create `corrections.md`; new entries are always written to `corrections.md`.

**Legacy back-compat:** If a legacy `side-notes.md` exists in the working directory, read it too and treat its entries identically. Always write new entries to `corrections.md`.

### Correction block format

Use this format when recording a direct correction (e.g. the user states that something inferred or recorded earlier was wrong):

```
### Correction: <short-topic>
Date: YYYY-MM-DD

**Correction:** <what is actually true>
**Corrects:** <the mistaken claim / where it appeared>
```

**Example:**

```
### Correction: setup-status
Date: 2026-06-23

**Correction:** setup is not actually ready yet — install still in progress
**Corrects:** notes/summary inferred setup was complete
```

### Resolution block format

Use this format when recording a user-confirmed resolution to a detected contradiction:

```
### Resolution: <topic>
Date: YYYY-MM-DD

**Source A** (`path/to/file-a.md`):
> <exact quote from source A>

**Source B** (`path/to/file-b.md`):
> <exact quote from source B>

**User-confirmed resolution:** <what the user said is correct>
```

**Example:**

```
### Resolution: Storage backend requirement
Date: 2025-11-04

**Source A** (`granola/kickoff-call.md`):
> "The cluster only supports NFS-based shared storage."

**Source B** (`slack/engineering-channel.txt`):
> "Postgres requires block storage; NFS won't work for our write patterns."

**User-confirmed resolution:** Block storage is required. The NFS-only constraint applies to the archive tier only, not the database tier.
```

## Customer identity

Infer the customer name and organizational profile from the engagement context itself — for example, a company name that appears consistently across meeting notes, Slack messages, and raw notes. Do not require the customer name to be configured anywhere.

Use the inferred customer name for:
- Titles and headings in all outputs
- Branding and framing in summaries, guides, and reports

If the customer name cannot be confidently inferred, use the placeholder `[Customer]` and note the ambiguity at the top of any output.

## Contradiction handling

**Threshold:** Only material or factual contradictions trigger action. A material contradiction is one where two sources make incompatible factual claims that would affect decisions or recommendations — for example, "ingress is staying" versus "ingress is being deprecated," or "storage is NFS-only" versus "Postgres needs block storage." Stylistic restatements of the same underlying fact (different wording, different level of detail) should be merged silently without flagging.

**Flow when a material contradiction is detected:**
1. PAUSE before producing output.
2. Show the user the conflicting sources, including the file path and exact quote for each side.
3. Ask the user which version is correct.

**Recording the resolution:**
- Append a resolution block (see [Corrections overlay](#corrections-overlay-precedence--resolution) for format) to `corrections.md`, creating the file if it does not exist.
- Raw input files remain untouched.

**When the conflict is unresolved** (user defers, skips, or the command runs non-interactively), surface the contradiction inline in the command's own output using this exact callout format:

`> ⚠️ Contradiction: <topic> — <A> vs <B>; unresolved.`
