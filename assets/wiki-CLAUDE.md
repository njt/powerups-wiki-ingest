# Wiki Schema

This is an LLM-maintained wiki inside an Obsidian vault. The LLM writes and maintains all wiki pages. The human sources material, asks questions, and reads the output.

## Structure

```
Wiki/
  CLAUDE.md       — this file (schema, conventions, workflows)
  index.md        — catalog of all wiki pages with one-line summaries
  log.md          — append-only record of ingests, queries, and maintenance
  raw/            — verbatim fetched sources (frontmatter + original text)
  summary/        — concise précis of each source
  topic/          — LLM-generated analysis pages
```

Obsidian links and tags provide the structure; `[[wikilinks]]` resolve by name regardless of folder.

## Three-tier layout

Each source produces up to three artifacts, sharing one slug:

- `raw/<slug>.md` — the **verbatim** fetched source (frontmatter + original text). Written by the pipeline, never rewritten by the model. The `url:` line here is what duplicate detection reads.
- `summary/<slug>.md` — a concise précis of that source.
- `topic/<Title>.md` — analysis and synthesis; may draw on several sources. Cross-linked with `[[wikilinks]]` (which resolve by name regardless of folder).

`index.md` and `log.md` stay at the wiki root.

## Page Format

Every wiki page starts with:

```markdown
# Page Title

One-paragraph summary of what this page covers.

---

(body)

---
*Sources: [[raw/filename]]*
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

The richer curated frontmatter (title, author, published/fetched dates) lives on the `summary/<slug>.md` précis, not on the raw file:

```markdown
---
url: https://example.com/article
title: "Article Title"
author: Author Name
date_fetched: YYYY-MM-DD
date_published: YYYY-MM-DD
---
```

## index.md

Every topic page gets a one-line entry in `index.md`, grouped under a section heading. Pick the most appropriate existing section; if none fits, add a new one.

## log.md

Append exactly ONE bullet line per ingest, in EXACTLY this format (no headings, no multi-line entries):

- YYYY-MM-DD: Ingested [Title](URL) (author, site, publication-date) — 1–3 sentence summary. → raw/<slug>.md, [[Page Title]]. Cross-links: [[A]], [[B]].
