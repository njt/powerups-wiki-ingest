# Nat's Wiki

This is an LLM-maintained personal wiki inside an [Obsidian](https://obsidian.md) vault. I throw URLs, papers, tweets, and repos at it; the LLM reads them, writes up what matters, and cross-links everything. I ask questions against it. It grows.

~490 topic pages, ~500 raw sources. The LLM does the writing; I do the curating.

## How it's organized

```
Wiki/
  README.md       — you are here (human-facing overview)
  CLAUDE.md       — schema and conventions (LLM-facing instructions)
  index.md        — catalog of every topic page, grouped by section
  log.md          — append-only chronology of ingests and maintenance
  raw/            — immutable source documents (the drop zone)
  *.md            — topic pages, flat in the root
```

### Topic pages

Each `.md` file in the root is a wiki page — wrote by the LLM, cross-linked with `[[wikilinks]]`. Pages follow a consistent format: one-paragraph summary, then body with blockquoted source excerpts, thematic analysis, and a sources footer.

### `raw/` — Source documents

Every ingested URL gets saved here first. The raw file preserves the original content with YAML frontmatter (url, title, author, dates). Raw files are immutable in principle — topic pages may be updated, but the raw source is the permanent record.

### `index.md` — The catalog

Every topic page gets a one-line entry in the index, grouped under one of these sections:

| Section | What's in it |
|---|---|
| **Synthesis** | Cross-cutting analysis pulling threads across individual pages |
| **Agentic Development** | Building software with AI coding agents — practices, workflows, opinions |
| **Agent Design & Architecture** | Frameworks, runtimes, patterns, and production concerns |
| **Agent Orchestration & Coordination** | Multi-agent systems, task graphs, coordination patterns |
| **Memory & Context** | Persistence, retrieval, context engineering for agents |
| **Quality & Guardrails** | Evals, testing, linting, feedback loops |
| **Security & Sandboxing** | Isolation, credentials, prompt injection defense |
| **Software Engineering** | Craft beyond agents — simplicity, reliability, specs, project management |
| **Databases & Data** | Storage engines, query patterns, vector/graph databases |
| **Developer Tools** | CLIs, utilities, code analysis, infrastructure |
| **Local & Personal Computing** | Running models locally, personal agent setups |
| **AI Research & Models** | Papers, benchmarks, model capabilities |
| **AI Infrastructure & Hardware** | GPUs, serving, scaling |
| **Ideas & Culture** | Essays, arguments, cultural commentary on AI |

### `log.md` — The audit trail

Every ingest, query, and maintenance run gets appended here. Date, source URL, pages created or updated, cross-links made. It's the wiki's memory of its own operations.

## How pages get created

1. I feed a URL to `/wiki-ingest` (or drop content into `raw/`)
2. The LLM reads the source, checks for duplicates, fetches the page
3. It writes a topic page with precis, key quotes, themes, and critical analysis
4. It updates `index.md` and appends to `log.md`
5. It cross-links to related pages it already knows about

For GitHub repos, the LLM clones the repo and does a deep architectural analysis — reading source files, identifying patterns and trade-offs — before writing.

## How to use it

- **Browse `index.md`** — it's the map. Every page has a one-liner
- **Follow `[[wikilinks]]`** — pages link to each other, Obsidian-style
- **Search** — Obsidian's search or grep. Pages are markdown
- **Ask the LLM** — "what does the wiki say about X?" and it'll read the index, find relevant pages, and synthesize

## Relationship to the rest of the vault

This wiki sits inside a larger Obsidian vault. Other folders (`Agent Journals/`, `AI/`, `Band/`, `Ontempo/`, `Spain 2026/`) are my personal space — the LLM only writes to `Wiki/`. Wiki pages can link out to those folders, but the LLM doesn't touch them.

## Maintenance

The LLM periodically lints: finds orphan pages, flags stale claims, checks for contradictions, and verifies the index is complete. This is triggered by asking or when things get messy.

---

*Last updated: 2026-06-06*
