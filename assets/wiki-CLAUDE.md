# Wiki Schema

This is an LLM-maintained wiki inside an Obsidian vault. The LLM writes and maintains all wiki pages. The human sources material, asks questions, and reads the output.

## Structure

```
Wiki/
  CLAUDE.md       — this file (schema, conventions, workflows)
  topics.md       — the fixed list of topics (slug, title, scope); the only source of topic pages
  index.md        — directory of every source note, one section per topic
  log.md          — append-only record of ingests, queries, and maintenance
  raw/            — verbatim fetched sources (frontmatter + original text)
  summary/        — concise précis of each source, tagged with its topics
  note/           — one analysis page per source
  topic/          — compiled topic pages, one per entry in topics.md
```

Obsidian links and tags provide the structure; `[[wikilinks]]` resolve by name regardless of folder.

## One source, three files; one topic, one compiled page

Each source produces three files. `raw/` and `summary/` share one slug; the note is named by its title:

- `raw/<slug>.md` — the **verbatim** fetched source (frontmatter + original text). Written by the pipeline, never rewritten by the model. The `url:` line here is what duplicate detection reads.
- `summary/<slug>.md` — a concise précis of that source. Its frontmatter carries `topics:`, the one or two topics the source is filed under.
- `note/<Title>.md` — the analysis of that one source: what it argues, key quotes with commentary, an opinionated take, and links to the related pages in the wiki. One note per ingest. A note is never edited by anything except a re-ingest of the same source.

Topics are different. `topic/<Title>.md` exists only for the entries in `topics.md`, and is only ever written by `wiki-compile`, which rebuilds it from every summary tagged with that topic. Nothing else creates or edits a topic page, and no page lives in `topic/` that is not in the list.

`index.md`, `log.md` and `topics.md` stay at the wiki root.

## Topics

`topics.md` is a table of `slug | title | scope`. Every source is filed under one primary topic and at most one secondary topic, chosen from that table and written in the summary's frontmatter as a block list, primary first:

```yaml
topics:
  - agent-orchestration
  - agent-architecture
```

Use `misc` only when nothing in the table fits. Never invent a slug, and never edit `topics.md` during an ingest; the list changes only by a person editing it, after which `wiki-retag` re-files what moved and `wiki-recompile` rebuilds the pages.

## Ingest files; curation compiles

These are two operations, and keeping them apart is the point.

**Ingest** handles one source. It writes only files it uniquely owns —
`raw/<slug>.md`, `summary/<slug>.md`, its own `note/<Title>.md` — plus the
union-merged `index.md` and `log.md`. It links OUT from its own note to the
2–4 most-related existing pages, in a sentence saying how this source
strengthens, nuances, or complicates each. It **never edits another note or
any topic page.** Obsidian derives the backlink, so the connection is made
without the contended write.

**Curation** handles a topic. `wiki-recompile` rebuilds a topic page from *all*
of its tagged summaries at once, which is the only way a page can be
**revised** rather than merely appended to — stale claims corrected,
duplicated passages merged, sections reorganised, weak material dropped.

Why the split: a per-source pass has one document in view and may only add. It
cannot correct a claim resting on forty sources, and when several run at once
they collide on the same popular pages. Topic pages are **derived artifacts** —
regenerable from `summary/`, which with `raw/` is the only thing that is
precious.

Every compiled topic page therefore ends with the digests it was built from:

    *Compiled from N sources: [[summary/slug-a]], [[summary/slug-b]], ...*

That provenance is not decoration. It is what makes a page auditable (do its
claims survive contact with its sources?), rebuildable (which pages does a new
source dirty?), and citable.

## Page Format

Every note and topic page starts with:

```markdown
# Page Title

One-paragraph summary of what this page covers.

---

(body)

---
*Sources: [[raw/filename]], [[summary/filename]]*
*Last updated: YYYY-MM-DD*
```

Use `[[wikilinks]]` for cross-references. Use tags sparingly: `#person`, `#concept`, `#tool`, `#project`, `#comparison`.

## raw/ frontmatter

Every `raw/<slug>.md` file holds the **verbatim** fetched body directly under minimal YAML frontmatter. It MUST include a `url:` line whose value is exactly the ingested URL — the duplicate check depends on it. The pipeline writes this file; the model never rewrites it (it only keeps or deletes it):

```markdown
---
url: https://example.com/article
date_fetched: YYYY-MM-DD
---

(verbatim source body follows, unchanged)
```

## summary/ frontmatter

The richer curated frontmatter (title, author, dates, topics) lives on the `summary/<slug>.md` précis, not on the raw file:

```markdown
---
url: https://example.com/article
title: "Article Title"
author: Author Name
date_fetched: YYYY-MM-DD
date_published: YYYY-MM-DD
topics:
  - primary-slug
  - secondary-slug
---
```

## index.md

A `## Topics` section at the top links every compiled topic page. Then one `## <Topic Title>` section per topic, in `topics.md` order, whose first line links the compiled page and repeats the scope. Every note gets exactly one entry, `- [[Note Title]] — one line`, under its **primary** topic's section. Never add a section heading that is not a topic title.

## log.md

Append exactly ONE bullet line per ingest, in EXACTLY this format (no headings, no multi-line entries):

- YYYY-MM-DD: Ingested [Title](URL) (author, site, publication-date) — 1–3 sentence summary. → raw/<slug>.md, [[Note Title]]. Cross-links: [[A]], [[B]].
