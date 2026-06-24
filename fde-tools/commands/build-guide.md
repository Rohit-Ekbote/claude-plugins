---
description: Build a customer-specialized, offline-readable HTML field guide from the current FDE engagement directory and write it to guide/.
---

# Build FDE Field Guide

You are generating a multi-page offline HTML field guide for a Forward Deployed Engineer engagement. Read these instructions completely before taking any action.

---

## Step 0 — Load the shared engagement context

Follow the instructions in `${CLAUDE_PLUGIN_ROOT}/commands/_engagement-context.md` exactly:

1. Read `corrections.md` first if it exists in the current working directory. Also check for a legacy `side-notes.md` if present. For any topic, apply the latest-wins-by-topic resolver: the most recent dated statement across all notes and `corrections.md` is current truth.
2. Read every readable text file recursively under `slack/`, `granola/`, and `raw/`. Skip any directory that does not exist — do not error.
3. Infer the customer name from the combined content. If it cannot be confidently determined, use `[Customer]` and note the ambiguity.
4. For every **material contradiction** found (incompatible factual claims that affect decisions), pause and show the user the two conflicting quotes (with file paths) and ask which is correct. Record each resolution in `corrections.md` using the resolution block format from the convention file.
5. If a contradiction is **unresolved** (user defers, skips, or the run is non-interactive), do **not** use a markdown `>` callout. Instead, render it as a `<div class="box warn">` callout on the relevant guide page (see Box component below).

**Read-only rule:** Never modify any file under `slack/`, `granola/`, or `raw/`. The guide content reflects current truth per topic as determined by the latest-wins-by-topic resolver.

---

## Step 1 — Prepare the output directory

```
mkdir -p guide/assets
```

Copy `${CLAUDE_PLUGIN_ROOT}/assets/fde-guide.css` to `guide/assets/style.css`.

Do not fetch any external resources. The guide must work completely offline — no CDN links, no web fonts, no JavaScript.

---

## Step 2 — Derive the chapter list from the engagement content

**Do NOT hard-code a fixed chapter list.** Analyze the topics actually present in the engagement context and derive chapters from that content. Different customers will produce different chapters.

Where the material supports it, organize chapters loosely as:

- Orientation group (e.g. Customer Overview, Engagement Goals, Team & Contacts)
- Infrastructure group (e.g. Architecture, Environments, Auth & Secrets, Networking)
- Deploying group (e.g. Installation, Configuration, Upgrade Procedures, Runbooks)
- Reference group (e.g. Troubleshooting, Glossary, Quick Reference)

Only include groups and chapters that the material actually supports. Do not invent chapters for topics with no content.

Number chapters with zero-padded two-digit integers:
- `index.html` — the landing page (not numbered)
- `00-overview.html` — first chapter
- `01-...html` — second chapter
- etc.

Build a complete ordered list of chapters (filename, title, group label) before writing any files.

---

## Step 3 — Build the sidebar nav markup

The **identical** sidebar nav block is used on every page (including index.html). Generate it once and reuse it.

Structure:
<!-- ILLUSTRATIVE STRUCTURE ONLY — substitute the chapters you derived in Step 2 -->
```html
<div class="brand">
  <strong>[Customer Name]</strong><small>FDE Offline Field Guide</small>
</div>
<div class="group">Orientation</div>
<a href="00-overview.html" class="active"><span class="num">00</span> Overview</a>
<a href="01-team.html"><span class="num">01</span> Team &amp; Contacts</a>
<div class="group">Infrastructure</div>
<a href="02-architecture.html"><span class="num">02</span> Architecture</a>
...
```

Rules:
- Use only the groups/chapters derived in Step 2.
- On each page, add `class="active"` to the anchor matching the current page's filename.
- Include `index.html` in the nav as a "Home" link at the top (no `.num` span needed, or use `·` as the label).
- Paths are relative (e.g. `href="00-overview.html"`).

---

## Step 4 — HTML component vocabulary

Use only the CSS classes already defined in `${CLAUDE_PLUGIN_ROOT}/assets/fde-guide.css`. Do not invent new class names or add inline styles.

**Box callouts** (`<div class="box [modifier]"><span class="label">...</span> ...</div>`):
- `.note` — informational note (blue)
- `.warn` — warning or unresolved contradiction (amber) — USE THIS for unresolved contradictions
- `.flura` — customer-specific callout (purple)
- `.ok` — positive confirmation (green)

**Cards grid** (for index page chapter listing):
```html
<div class="cards">
  <div class="card">
    <div class="n">00</div>
    <h3><a href="00-overview.html">Overview</a></h3>
    <p>Short description of chapter content.</p>
  </div>
  ...
</div>
```

**Tags:** `<span class="tag open">open</span>` or `<span class="tag resolved">resolved</span>`

**Code blocks:** Use `<pre><code>...</code></pre>` — the CSS styles them as dark blocks automatically.

**Tables:** Standard `<table>` with `<thead>` / `<tbody>` — the CSS handles styling.

**Pager:** Previous/next navigation between chapters:
```html
<a class="next" href="01-team.html">Next: Team &amp; Contacts &rarr;</a>
```
For the first chapter, omit a "previous" link. For the last chapter, omit the "next" link (or link back to index). Wrap in `<div class="pager">...</div>` (the template already provides the outer div — only emit the inner anchor(s) for `{{PAGER}}`).

---

## Step 5 — Fill the page template

The template is at `${CLAUDE_PLUGIN_ROOT}/assets/fde-guide-page.html.tmpl`. It contains exactly five placeholder tokens that must be replaced for each page:

- `{{PAGE_TITLE}}` — Browser tab title, e.g. `Acme Corp — FDE Field Guide · Overview`
- `{{SIDEBAR_NAV}}` — The full sidebar nav markup from Step 3 (with the current page's anchor marked `active`)
- `{{KICKER}}` — Short eyebrow line, e.g. `Forward Deployed Engineer · Offline Field Guide`
- `{{PAGE_BODY}}` — The chapter content: `<h1>`, `.lede` paragraph, boxes, tables, code blocks, etc.
- `{{PAGER}}` — The prev/next anchor(s) only (no outer wrapper — the template supplies `<div class="pager">`)

For each chapter page, produce the final HTML by substituting all five tokens. Write the result to `guide/<filename>.html`.

---

## Step 6 — Generate guide/index.html (landing page)

The index page is the "Start here" entry point. Build it using the same template with:

- `{{PAGE_TITLE}}` → `[Customer] — FDE Offline Field Guide`
- `{{KICKER}}` → `Forward Deployed Engineer · Offline Field Guide`
- `{{PAGE_BODY}}` →
  ```html
  <h1>[Customer] FDE Offline Field Guide</h1>
  <p class="lede">Everything you need to deploy and support [Customer]'s environment, readable offline.</p>
  <div class="cards">
    <!-- one .card per chapter, with chapter number in .n, title in h3>a, short description in p -->
  </div>
  <div class="box note"><span class="label">Provenance</span>
    This guide was assembled from the engagement's source material: Slack exports, Granola meeting notes, and raw field notes found in <code>slack/</code>, <code>granola/</code>, and <code>raw/</code>. Corrections and resolutions are recorded in <code>corrections.md</code>, and a legacy <code>side-notes.md</code> may be present; the most recent dated statement per topic is current truth. Regenerate at any time by running <code>/build-guide</code>.
  </div>
  ```
- `{{PAGER}}` → `<a class="next" href="00-overview.html">Start reading &rarr;</a>` (or the first chapter's filename)
- `{{SIDEBAR_NAV}}` → Same nav as all other pages, with the `index.html` link marked `active`

---

## Step 7 — Write all files

Write every page to `guide/`. Overwrite the entire `guide/` directory on each run — regenerate all pages, do not preserve stale pages from a previous run.

Final output list:
- `guide/assets/style.css` (copied CSS)
- `guide/index.html` (landing page)
- `guide/00-<slug>.html` … `guide/NN-<slug>.html` (one file per chapter)

Output only into `guide/`. Do not touch `slack/`, `granola/`, or `raw/` (except to record contradiction resolutions in `corrections.md` as instructed in Step 0).

---

## Quick-reference checklist

Before reporting completion, verify:

- [ ] `guide/assets/style.css` copied from `${CLAUDE_PLUGIN_ROOT}/assets/fde-guide.css`
- [ ] Template `${CLAUDE_PLUGIN_ROOT}/assets/fde-guide-page.html.tmpl` used for every page; all five tokens (`{{PAGE_TITLE}}`, `{{SIDEBAR_NAV}}`, `{{KICKER}}`, `{{PAGE_BODY}}`, `{{PAGER}}`) substituted on every page
- [ ] Chapter list derived from actual content — not a fixed hard-coded list
- [ ] Identical sidebar nav on every page (only `active` class differs)
- [ ] `guide/index.html` exists with `.cards` grid and provenance note
- [ ] Unresolved contradictions rendered as `<div class="box warn">` callouts
- [ ] No CDN links, no web fonts, no JavaScript anywhere in `guide/`
- [ ] `slack/`, `granola/`, `raw/` untouched
