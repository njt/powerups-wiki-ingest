# Wiki Schema

This is an LLM-maintained wiki inside an Obsidian vault. The LLM writes and maintains all wiki pages. The human sources material, asks questions, and reads the output.

## Structure

```
Wiki/
  CLAUDE.md       — this file (schema, conventions, workflows)
  index.md        — catalog of all wiki pages with one-line summaries
  log.md          — append-only record of ingests, queries, and maintenance
  raw/            — immutable source documents (drop zone)
  (topic pages)   — LLM-generated markdown, flat in the wiki root
```

Wiki pages live flat in the wiki root (no subfolders). Obsidian links and tags provide the structure.

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

Every raw source file MUST begin with YAML frontmatter, and it MUST include a `url:` line whose value is exactly the ingested URL — the duplicate check depends on it:

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
