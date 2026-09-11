# Fixed Topics — Design

**Date:** 2026-09-11
**Status:** Agreed in discussion with Nat (2026-09-11), pre-implementation
**Repo:** `powerups-wiki-ingest` (all code); the migration runs against the wiki content repo on a branch
**Supersedes:** the per-source `topic/<Title>.md` in `assets/wiki-CLAUDE.md` and in both ingest prompts. Continues kata `x0ry` (split ingest from curation).

## The problem, measured

Measured on the live wiki on 2026-09-11 with `wiki-curate` and a scan of the vault:

| measure | count |
|---|---|
| sources (`raw/`) | 1067 |
| digests (`summary/`) | 1160 |
| topic pages | 1151 |
| topic pages with exactly one source | 1051 |
| of those, named after their source (entity-like, `classify` at 0.5) | 980 |
| topic pages with 10+ sources | 28 |
| `index.md` section headings | 16 |

Nothing dynamically discovers topics because nothing tries. Both ingest prompts tell the model to write "its own `topic/<Title>.md`", so every source becomes a topic page by construction, and the only merge step (`wiki-compile`) runs on pages that already have multi-source provenance. The per-source topic page is a second, longer précis: recent pairs run about 250 words of `summary/` against 2400 words of `topic/` for the same source. Tags cannot cluster anything either: `#concept` is on 1145 of 1151 pages.

The pages that actually behave like topics already exist and already form a fixed list: the compiled themes (Agent Coding Workflow, 101 sources; Software Engineering Craft, 57; Guardrails and Feedback Loops, 51; and so on) and the 16 `index.md` sections. This design makes that list explicit, machine-readable, and the only way a topic page comes to exist.

## Decisions (2026-09-11)

1. **A fixed list of topics, including `misc`,** lives in `topics.md` at the wiki root. Only the list defines topics. Nothing else may create a `topic/` page.
2. **One page per source.** Ingest writes `raw/<slug>.md` and `summary/<slug>.md` and nothing under `topic/`. The analysis that used to be the per-source topic page moves into the summary, below the précis.
3. **Assignment happens at ingest, as data.** The summary frontmatter carries `topics: [primary, secondary?]`, chosen only from `topics.md`. One or two entries; `misc` when nothing fits.
4. **Topic pages are compiled artifacts only.** `topic/<Title>.md` exists only for list entries and is only ever written by `wiki-compile`, whose source set is "every summary tagged with this topic".
5. **The dynamic part is a split rule, gated on Nat.** `wiki-curate topics` reports topics over a threshold and the contents of `misc`. Nat edits `topics.md`; `wiki-retag` re-assigns the affected summaries. No tool invents a topic unattended.
6. **Old titles keep resolving.** Each summary carries `aliases: [<wiki title>]` so `[[Paperclip]]` resolves to `summary/paperclip.md` once there is no `topic/Paperclip.md`. `wiki-curate` learns aliases so the audit does not report them as dead links.
7. **Legacy pages stay until folded on a reviewed branch.** The 1051 single-source pages are folded into their summaries by a script, on a branch, reviewed with `wiki-review`, and merged only by Nat. Multi-source legacy pages that are not list topics are left alone and are no longer compiled.

## Why not dynamic clustering

Clustering 1100 précis needs embeddings or an LLM pass the plugin does not have (`wiki-curate` is stdlib-only by design), it is nondeterministic so the same corpus yields different topics on different days, and it reintroduces the new-edge problem the code already documents in `cmd_dirty`. A wiki wants stable link targets. The fixed list gives that; the split rule gives evolution at the pace a human can follow.

## Data model

### `topics.md` (wiki root)

Human-readable in Obsidian, parsed by the tools. One markdown table; nothing else in the file is significant.

```markdown
# Topics

Every source is filed under one or two of these. The slug goes in
`topics:` frontmatter; the title is the compiled page under `topic/`;
the scope line tells the ingest what belongs. Edit freely; then run
`wiki-retag` for anything that moved.

| slug | title | scope |
|---|---|---|
| agent-coding-workflow | Agent Coding Workflow | How practitioners actually work with coding agents day to day: loops, habits, prompts, verification, maturity models. |
| ... | ... | ... |
| misc | Miscellany | Anything that fits none of the above. Reviewed periodically for topics that want to exist. |
```

Rules:

- `slug` matches `^[a-z0-9][a-z0-9-]*$` and is unique. `misc` must exist.
- `title` is the exact filename of the compiled page, `topic/<title>.md`, and is unique.
- `scope` is one or two sentences and is fed verbatim to the ingest prompt and the compile prompt.
- The plugin ships a default in `assets/topics.md`; `wiki-ingest-setup` seeds it into a new wiki. The live wiki gets one from the migration (below).
- The ingest LLM is told the list and must never edit the file. The completeness guard rejects any ingest that stages `topics.md`.

### Starting list for the live wiki

Derived from the existing compiled themes (titles kept exactly, so existing links survive) and the fattest `index.md` sections. Eighteen entries. Nat renames or splits at will afterwards; the tooling treats the file as data.

| slug | title | origin |
|---|---|---|
| agent-coding-workflow | Agent Coding Workflow | compiled, 101 sources |
| agent-architecture | Agent Architecture | index section "Agent Design & Architecture", 170 entries |
| agent-orchestration | Agent Orchestration | compiled, 38 |
| agent-memory-and-context | Agent Memory and Context | compiled, 41 |
| guardrails-and-feedback-loops | Guardrails and Feedback Loops | compiled, 51 |
| specifications-as-the-product | Specifications as the Product | compiled, 26 |
| security-and-sandboxing | Security and Sandboxing | compiled, 41 |
| software-engineering-craft | Software Engineering Craft | compiled, 57 |
| databases-and-data | Databases and Data | compiled, 46 |
| distributed-systems | Distributed Systems | reconstructed, 15 |
| developer-tools | Developer Tools | index section, 132 |
| local-and-open-source-inference | Local and Open Source Inference | reconstructed, 29 |
| ai-research-and-models | AI Research and Models | index section, 90 |
| ai-infrastructure-and-hardware | AI Infrastructure and Hardware | index sections, 14 |
| personal-agents | Personal Agents | compiled, 25 |
| ai-product-and-business | AI Product and Business | pricing, unit economics, enterprise adoption pages scattered today |
| ideas-and-culture | Ideas and Culture | index section, 111 |
| misc | Miscellany | required |

"Agent Design & Architecture" at 170 entries is over the split threshold from day one. That is accepted: the first `wiki-curate topics` report will say so, and splitting it is exactly the workflow this design is meant to exercise.

### `summary/<slug>.md` — the source note

Frontmatter gains two keys. Everything already there stays.

```yaml
---
url: https://github.com/paperclipai/paperclip
title: "Paperclip"
author: Paperclip Labs, Inc.
date_fetched: 2026-09-11
date_published: 2026
aliases: ["Paperclip"]
topics: [agent-orchestration, agent-architecture]
---
```

- `aliases`: the wiki title the model would previously have used for the topic page. Exactly one entry on a new ingest. Must be unique across summaries; the ingest guard rejects a collision with an existing alias or an existing `topic/` filename.
- `topics`: one or two slugs from `topics.md`, primary first. Flow form `[a, b]` is what the tools write; block form is accepted on read.

Body structure, in this order:

1. The précis: a few short paragraphs, no heading. This is what compile reads.
2. Optional analysis sections, each an H2: `## Key Quotes`, `## Analysis`, `## Architecture`, `## Related` and so on. This is where the former topic page content lives. The `## Related` section holds the 2 to 4 outbound links to related pages that ingest already writes.
3. The footer: `*Sources: [[raw/<slug>]]*` and `*Last updated:*`.

**Compile context is the précis only**: frontmatter plus body up to the first H2. This keeps a 130-source compile at roughly 40k words, the same as today, rather than 300k. It matches the monograph's "compile from digests, pull `raw/` only when quoting in depth".

### `topic/<Title>.md`

Unchanged in format. Provenance footer as today. The source set changes: it is the set of summaries whose `topics:` contains the slug, in either position. Link-preservation and the other compile gates are unchanged.

### `index.md`

Stays the live directory, because it is updated at ingest time and compile is periodic. Its sections become exactly the topics, in `topics.md` order, heading text equal to the topic title. Under each heading, the first line links the compiled page and repeats the scope; then one bullet per source, `- [[<alias>]] — one line`, filed under the primary topic only. A leading `## Topics` section lists the compiled pages. `merge=union` behaviour is unchanged.

### `log.md`

Unchanged. `[[Page Title]]` in the existing line format becomes the alias link.

## Tools

### `wiki-ingest-run` (changed)

Both prompts (article and repo) change in the same way:

- The prompt embeds the topics table and the rule: choose one primary and at most one secondary slug; use `misc` only when nothing fits; never edit `topics.md`.
- The per-source topic page instructions are replaced by the source-note structure above. The repo prompt's Architecture, Key techniques, Design decisions and Comparison sections become H2s in the summary.
- `index.md` instruction: add the source under the primary topic's section.
- The output checklist drops the topic page and adds `aliases:` and `topics:`.

The completeness guard changes from "a `topic/` path must be staged" to:

- `summary/<slug>.md` staged (unchanged).
- **No `topic/` path staged.** Ingest touching `topic/` is now a hard failure. Previously it was required; that is the inversion at the centre of this design.
- `topics.md` not staged.
- `topics:` present and valid after normalisation. Normalisation, in the script, is deterministic: a title that matches a `topics.md` title case-insensitively becomes its slug; case is folded; duplicates collapse; more than two entries are truncated to two. Anything still unresolvable is dropped with a warning on stderr. If nothing remains, `misc` is written. The commit message records a repair. The ingest is **not** rejected for a bad topic: the raw and summary are intact and valuable, a rejection throws away a five-minute LLM run for a metadata slip, and the audit reports repairs so they are not silent. (Contrast: a missing summary still rejects, because that output is unusable.)
- `aliases:` present; if absent, set to the frontmatter `title`. Rejected if the alias collides with an existing summary alias or an existing `topic/` filename other than a list topic's own page.

`--summary-only` writes `aliases:` and `topics:` as well; it already writes the frontmatter. `--verbatim-only` is unchanged.

The stray-root-file guard's allow list gains `topics.md`.

### `wiki-meta` (new, Python 3, stdlib)

The one place summary frontmatter and `topics.md` are parsed and written, so the format is defined once and every script agrees.

```
wiki-meta topics [--json]                    # parse topics.md
wiki-meta get FILE KEY                       # print a scalar, or a list one per line
wiki-meta set FILE KEY VALUE [VALUE...]      # rewrite one key in place; lists written as [a, b]
wiki-meta normalize-topics FILE              # the ingest repair described above; prints what it did
```

It is also importable by the migration and retag scripts. Frontmatter rewriting preserves every other line byte for byte. Filenames and aliases are NFC-normalised on comparison, per the existing rule in `wiki-curate`.

### `wiki-curate` (changed; still read-only)

- `parse_frontmatter` returns lists for `[a, b]` and block-list values.
- `Vault` registers each summary's aliases in `by_basename`, ranked after real filenames, so `[[Paperclip]]` resolves to `summary/paperclip` once the topic page is gone. The truncation check in `wiki-compile` uses the same set.
- `Vault` parses `topics.md` (via `wiki-meta`) and exposes `topic_members(slug)`.
- New subcommand `topics`: one row per list topic with member count, compiled-page presence, words, last compiled; flags rows over `--split-at N` (default 60); prints the `misc` members. `--json` for tooling.
- `dirty --since REF` becomes set arithmetic over `topics:` of the changed summaries. The link-graph reconstruction path stays only for legacy pages and is no longer what compile uses.
- New audit checks: `untagged-digests` (summaries without `topics:`), `unlisted-topics` (a slug not in `topics.md`), `topic-page-missing` (a list topic with no compiled page), `topic-page-unlisted` (a `topic/` file whose name is neither a list title nor a legacy page recorded at migration), `alias-collisions`, `topic-oversized` (members over the split threshold), `index-sections-drift` (index headings not equal to the topic titles).

### `wiki-compile` (changed)

- `--theme` must be a `topics.md` title or slug; anything else exits 3 with "not a listed topic; add it to topics.md and retag". The source set comes from `topics:` membership, not link provenance. The reconstructed-provenance plausibility cap becomes moot for list topics and is left in place for nothing; remove it.
- Context is the précis of each member (frontmatter plus body up to the first H2), not the whole file.
- The prompt receives the scope line and is told that sources tagged secondary may be mentioned lightly.
- A topic with fewer than 2 members still exits 3, as today.

### `wiki-recompile` (changed)

Default selection is every list topic; `--since` uses the new `dirty`; `--top` still caps. Nothing else changes.

### `wiki-retag` (new)

The tool that makes the split rule work.

```
wiki-retag --topic misc            # re-assign everything currently in misc
wiki-retag --since REF             # summaries changed since REF
wiki-retag --slugs FILE            # an explicit list
wiki-retag --all                   # the whole corpus (migration backfill leftovers)
        [--branch NAME] [--batch 30] [--dry-run]
```

For each batch it hands the LLM `topics.md` plus the précis and current `topics:` of N summaries and asks for a JSON map slug → topics. The script validates every answer against `topics.md` (same normaliser as ingest), writes only the `topics:` line of each summary via `wiki-meta`, and commits on a branch in a detached worktree, the same way `wiki-compile` does. It never checks the branch out, never merges, and never touches anything but `topics:` lines; a diff that touches anything else fails validation. It prints a before/after count per topic. `--allowedTools` is `Read` only: the model answers, the script writes.

### `wiki-fold-legacy` (new, one-off, kept in `bin/` because it is reviewable and rerunnable)

Folds a single-source legacy topic page into its summary:

- Eligible: a `topic/` page whose declared provenance is exactly one summary, whose title is not a list title, and whose summary has no analysis sections yet.
- New summary = existing frontmatter plus `aliases: ["<Title>"]` (plus any existing aliases), plus `topics:` if missing; existing précis body; then the topic page body with its H1 and its Sources footer removed, under the H2s it already had (a topic body that starts with prose gets `## Analysis`); then the footer.
- The topic file is deleted in the same commit. `index.md` and `log.md` lines are untouched: their `[[Title]]` links resolve through the alias.
- Refuses if the alias would collide, if the topic page has more than one source, or if anything else in the commit would change.
- Runs on a branch in a detached worktree, N pages per commit. Reviewed with `wiki-review` (which gains a per-fold link-preservation row: every link the folded page had must still resolve from somewhere in its summary) and by `wiki-curate audit` deltas: `dead-links` and `orphans` must not increase.

### `wiki-review` (changed)

Understands the fold branch as above, and reports alias-resolved links as resolved.

### `wiki-ingest-setup`, `assets/`

Seeds `topics.md` from `assets/topics.md`. `assets/wiki-CLAUDE.md` is rewritten: the three-tier section becomes archive, source note, compiled topic; the topics rule; the index rule; the log format unchanged.

### `skills/wiki-ingest/SKILL.md`

Description and report section updated (topics assigned, not index placement; no topic page). The curation paragraph gains `wiki-curate topics`, `wiki-retag`. The "Your job" section is otherwise unchanged; the orchestration does not change.

## Migration of the live wiki

All on branches, nothing merged by a tool. Order matters.

1. **Seed `topics.md`** with the starting list, on branch `curate/topics-<date>`.
2. **Backfill `topics:` deterministically** for all 1160 summaries, on the same branch. Signals, in priority order: (a) membership in the declared provenance of a compiled page whose title is on the list; (b) the `index.md` section of the summary's single-source topic page, through a fixed section-to-slug mapping recorded in the migration script; (c) `misc`. Keep at most two. Print the resulting per-topic counts and the `misc` count.
3. **Retag `misc`** with `wiki-retag --topic misc` on the same branch, if the misc count after step 2 is large. Expected: most of it, because the `section` signal covers only pages the index still lists.
4. **Restructure `index.md`**: rename and merge sections to the topic titles using the same mapping; move each entry under its primary topic; add the `## Topics` section. Entries are preserved exactly.
5. **Update the wiki's own `CLAUDE.md`** on the branch. It has drifted from `assets/wiki-CLAUDE.md` (it carries Workflows, Relationship-to-the-vault and Principles sections that are Nat's); only the tier and topic sections are replaced.
6. **Compile every list topic** with `wiki-recompile` onto the same branch. Existing compiled pages are rebuilt from their tag-derived source set; the link-preservation gate keeps every link they had. New topics get their first page.
7. **`wiki-review`** the branch. Nat merges. The standing "merge clean compile cycles without asking" decision does not cover this branch: it restructures `index.md` and the schema, so it is shown to Nat regardless of the review result.
8. **Fold the legacy pages** with `wiki-fold-legacy` on a second branch, `curate/fold-<date>`, after step 7 is merged. `wiki-review`; Nat merges. Legacy multi-source pages that are not list topics are recorded in `topics.md` under a "Legacy pages" note so the `topic-page-unlisted` audit check knows them; they are not compiled again unless promoted to the list.

Steps 1 to 6 are rerunnable from scratch against `main` because every step is a script. Step 8 is reversible with git.

## What changes for Nat

- `/wiki-ingest <url>` behaves the same and reports which topics the source was filed under.
- The nightly report (`wiki-curate topics`) names any topic over 60 members and lists what is in `misc`. To split a topic: edit `topics.md`, run `wiki-retag --topic <old-slug>`, then `wiki-recompile`.
- Topic pages are about 18 and stay about 18 unless he adds one.

## Non-goals

- Automatic topic discovery. Explicitly rejected above.
- Renaming the `summary/` directory. Every existing `[[summary/<slug>]]` link and the slug-sharing with `raw/` depend on it. The name is now slightly off for a file that also carries analysis; the schema text calls it the source note and the directory name is a historical detail.
- Compiling from full source notes or `raw/`. Précis only, as today.
- `facts/<slug>.json` structured extraction (scrapped in the monograph, still scrapped).
- Query.

## Open questions

1. **Alias resolution in Obsidian.** The design assumes an existing `[[Paperclip]]` link resolves to a note whose frontmatter has `aliases: ["Paperclip"]` when no file of that name exists, case-insensitively. To be verified against the Obsidian documentation before the fold phase; if false, the fold phase is replaced by leaving the legacy pages in place, and the rest of the design stands.
2. **Compile quality at 130 to 170 précis.** The compiler has produced acceptable pages from 101. The first `Agent Architecture` compile is the test; if it is poor, that topic is split before the branch is offered for merge rather than after.
3. **Where secondary-topic sources appear on a compiled page.** The prompt says "lightly". Whether that produces a useful page or a padded one is a review question for the migration compile.

## Load-bearing assumptions to verify

- Obsidian resolves `[[X]]` through `aliases:` frontmatter (open question 1).
- `merge=union` on `index.md` still behaves after the section restructure (it is line-based; section moves are just lines).
- The compile link-preservation gate tolerates a page whose source set shrinks (a legacy compiled page whose provenance included summaries that are now tagged elsewhere). It only checks links, not provenance, so it should.
- `claude -p --allowedTools Read` returns JSON reliably enough for `wiki-retag` batches of 30. Fallback: `--batch 10`.
- Frontmatter flow lists `[a, b]` are read by Obsidian's Properties view as lists (they are YAML; Obsidian uses a YAML parser).

## Phases

1. **Foundations, no wiki changes:** `wiki-meta`; `wiki-curate` frontmatter lists, aliases, `topics.md`, `topics` subcommand, new audit checks, tag-based `dirty`; tests.
2. **Ingest:** both prompts, the inverted guard, the normaliser, `--summary-only`; `assets/topics.md`, `assets/wiki-CLAUDE.md`, setup, SKILL.md; tests; live-fire against a clone of the wiki.
3. **Compile:** tag-derived source set, précis-only context, listed-topics-only, recompile default; tests.
4. **Retag and migration scripts:** `wiki-retag`, the backfill and index restructure scripts; tests with a fake CLI; dry runs against a clone.
5. **Migration steps 1 to 7** on the live wiki's branch; `wiki-review`; hand to Nat.
6. **Fold:** `wiki-fold-legacy`, `wiki-review` support; run on a branch; hand to Nat.
7. **Release:** version 3.0.0, marketplace entry.
