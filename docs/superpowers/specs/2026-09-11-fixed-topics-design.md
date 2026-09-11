# Fixed Topics — Design

**Date:** 2026-09-11
**Status:** Agreed in discussion with Nat (2026-09-11); revised the same day after the load-bearing pass (see "Load-bearing ledger" at the end); pre-implementation
**Repo:** `powerups-wiki-ingest` (all code); the migration runs against the wiki content repo
**Supersedes:** the per-source `topic/<Title>.md` in `assets/wiki-CLAUDE.md` and in both ingest prompts. Continues kata `x0ry` (split ingest from curation). Tracked as kata `1srn`.

## The problem, measured

Measured on the live wiki on 2026-09-11 with `wiki-curate` and a scan of the vault:

| measure | count |
|---|---|
| sources (`raw/`) | 1067 |
| digests (`summary/`) | 1160 |
| topic pages | 1151 |
| topic pages with exactly one source | 1051 |
| of those, named after their source (entity-like, `classify` at 0.5) | 980 |
| multi-source topic pages that are not on the list below | 83 |
| topic pages with 10+ sources | 28 |
| `index.md` section headings | 16 |

Nothing dynamically discovers topics because nothing tries. Both ingest prompts tell the model to write "its own `topic/<Title>.md`", so every source becomes a topic page by construction, and the only merge step (`wiki-compile`) runs on pages that already have multi-source provenance. Tags cannot cluster anything either: `#concept` is on 1145 of 1151 pages.

The pages that actually behave like topics already exist and already form a fixed list: the compiled themes (Agent Coding Workflow, 101 sources; Software Engineering Craft, 57; Guardrails and Feedback Loops, 51; and so on) and the 16 `index.md` sections. This design makes that list explicit, machine-readable, and the only way a `topic/` page comes to exist.

The per-source analysis page itself is not the problem. It is good writing (the Paperclip page is a real analysis, not a second précis) and it is what 9,000 links in the corpus point at. It was simply misfiled as a topic.

## Decisions (2026-09-11, revised after the load-bearing pass)

1. **A fixed list of topics, including `misc`,** lives in `topics.md` at the wiki root. Only the list defines topics. Nothing else may create a `topic/` page.
2. **Per-source pages stay, renamed.** Each source keeps three files: `raw/<slug>.md` (verbatim), `summary/<slug>.md` (précis, now carrying `topics:`), and `note/<Title>.md` (the per-source analysis, exactly what `topic/<Title>.md` was). `topic/` holds only list topics. The original decision was to fold the analysis into the summary under an `aliases:` entry; that rested on Obsidian resolving `[[Title]]` through aliases, which it does not (ledger A1). Basename resolution is vault-wide and case-insensitive, so a directory move keeps every existing link working with no rewrite.
3. **Assignment happens at ingest, as data.** The summary frontmatter carries `topics:` (one or two slugs from `topics.md`, primary first; `misc` when nothing fits).
4. **Topic pages are compiled artifacts only.** `topic/<Title>.md` exists only for list entries and is only ever written by `wiki-compile`, whose source set is "every summary tagged with this topic".
5. **The dynamic part is a split rule, gated on Nat.** `wiki-curate topics` reports topics over a threshold and the contents of `misc`. Nat edits `topics.md`; `wiki-retag` re-assigns the affected summaries. No tool invents a topic unattended.
6. **New behaviour is gated on `topics.md` existing in the wiki.** The hourly launchd job calls this repo's working-tree `bin/` directly (ledger A5), so ingest code goes live the moment it lands on `main`. Without `topics.md` in the worktree, `wiki-ingest-run` behaves exactly as today; with it, the new prompt and guard apply. The migration lands `topics.md` and the new behaviour switches on at that commit.
7. **The migration runs in a quiesced window and merges fast-forward.** `merge=union` duplicates moved `index.md` sections when the other side appended to them (ledger A4, reproduced), and a branch that rewrites 1160 summaries cannot absorb a fortnight of ingests. So: ingests stop, the migration runs on a branch off the then-current `main`, `wiki-review`, Nat merges, ingests resume. Nothing is left to catch up.
8. **Lists are written in block YAML form.** Obsidian reads flow lists but rewrites them to block form on any property edit and fails silently on malformed `aliases`/`tags` (ledger A12); block form avoids both.

## Why not dynamic clustering

Clustering 1100 précis needs embeddings or an LLM pass the plugin does not have (`wiki-curate` is stdlib-only by design), it is nondeterministic so the same corpus yields different topics on different days, and it reintroduces the new-edge problem the code already documents in `cmd_dirty`. A wiki wants stable link targets. The fixed list gives that; the split rule gives evolution at the pace a human can follow.

## Data model

### `topics.md` (wiki root)

Human-readable in Obsidian, parsed by the tools. One markdown table; nothing else in the file is significant to the tools, so Nat can write notes around it.

```markdown
# Topics

Every source is filed under one or two of these. The slug goes in
`topics:` frontmatter on the summary; the title is the compiled page under
`topic/`; the scope line tells the ingest what belongs. Edit freely; then run
`wiki-retag` for anything that moved and `wiki-recompile` to rebuild.

| slug | title | scope |
|---|---|---|
| agent-coding-workflow | Agent Coding Workflow | How practitioners actually work with coding agents day to day: loops, habits, prompts, verification, maturity models. |
| ... | ... | ... |
| misc | Miscellany | Anything that fits none of the above. Reviewed periodically for topics that want to exist. |
```

Rules:

- `slug` matches `^[a-z0-9][a-z0-9-]*$` and is unique. `misc` must exist.
- `title` is the exact filename of the compiled page, `topic/<title>.md`, unique, and must not collide case-insensitively with any `note/` filename (Obsidian resolves case-insensitively; a note and a topic sharing a name would make `[[X]]` ambiguous).
- `scope` is one or two sentences and is fed verbatim to the ingest prompt and the compile prompt.
- The plugin ships a default in `assets/topics.md`; `wiki-ingest-setup` seeds it into a new wiki. The live wiki gets one from the migration.
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

Seven of these have no page today (Agent Architecture, Developer Tools, AI Research and Models, AI Infrastructure and Hardware, AI Product and Business, Ideas and Culture, Miscellany); `wiki-compile` must be able to create a first page (below). "Agent Design & Architecture" at 170 entries is over the split threshold from day one. That is accepted: the first `wiki-curate topics` report will say so, and splitting it is exactly the workflow this design is meant to exercise.

### `summary/<slug>.md` — the digest

Frontmatter gains one key. Everything already there stays.

```yaml
---
url: https://github.com/paperclipai/paperclip
title: "Paperclip"
author: Paperclip Labs, Inc.
date_fetched: 2026-09-11
date_published: 2026
topics:
  - agent-orchestration
  - agent-architecture
---
```

`topics:` holds one or two slugs from `topics.md`, primary first. Written in block form; flow form `[a, b]` is accepted on read.

Body unchanged: the précis. Measured (ledger A2): 661 of 1160 existing digests already contain H2 sections and 460 have under 40 words before the first heading, so "body up to the first H2" is not a usable definition of a précis for this corpus. Compile keeps reading the whole digest, as it does today.

### `note/<Title>.md` — the per-source analysis

Exactly today's per-source `topic/<Title>.md`, in a directory that says what it is. Format, tags, `## Related`-style outbound links, and the `*Sources: [[raw/<slug>]], [[summary/<slug>]]*` footer are unchanged. One note per ingest; a multi-source note (the Paperclip page cites two sources, a website and a repo) is fine. Written once by ingest and not edited by anything else except a `--force` re-ingest of the same source. Legacy multi-source analysis pages that are not list topics live here too.

### `topic/<Title>.md` — a compiled topic

Unchanged in format. Provenance footer as today. The source set is the set of summaries whose `topics:` contains the slug, in either position. Link-preservation and the other compile gates are unchanged. `topic/` contains exactly the list titles and nothing else; the audit enforces it.

### `index.md`

Stays the live directory, because it is updated at ingest time and compile is periodic. Its sections become exactly the topics, in `topics.md` order, heading text equal to the topic title. Under each heading, the first line links the compiled page and repeats the scope; then one bullet per source, `- [[<note title>]] — one line`, filed under the primary topic only (876 of 876 existing entries already have this shape). A leading `## Topics` section lists the compiled pages. `merge=union` behaviour is unchanged, which is why the restructure happens only inside the quiesced window.

### `log.md`

Unchanged. `[[Page Title]]` in the line format is the note title. The podcast pipeline resolves that name by searching the vault recursively, so it finds `note/` pages without change (verified in `~/Source/wiki-podcast/generate.py`).

## Tools

### `wiki-ingest-run` (changed, gated)

At the top of the LLM phase: `if [ -f "$WT/topics.md" ]` selects the new prompts and guard; otherwise the current code runs unchanged. The old path stays until every wiki this plugin serves has migrated; it is already covered by `test-guard.sh`.

New prompts (article and repo) differ from today's in:

- The topics table from `topics.md` is embedded, with the rule: choose one primary and at most one secondary slug; use `misc` only when nothing fits; write them as a block list under `topics:` in the summary frontmatter; never edit `topics.md`.
- "topic/<Title>.md" becomes "note/<Title>.md" throughout. The content instructions are otherwise the same.
- `index.md` instruction: add the note under the primary topic's section.
- The output checklist replaces the topic-page item with the note item and adds `topics:`.

New guard (replaces the "a `topic/` path must be staged" check):

- `summary/<slug>.md` staged (unchanged).
- **Exactly one `note/` path staged, and it is an addition,** unless `--force` (re-ingest), in which case a modification of the note the previous ingest wrote is allowed. A modification of any other note is rejected. This closes kata `6ctn` (the LLM writing over an existing page) as a side effect.
- **No `topic/` path staged.** Previously required; now a hard failure.
- `topics.md` not staged.
- `topics:` present and valid after normalisation. Normalisation is deterministic and in the script: a title that matches a `topics.md` title case-insensitively becomes its slug; case is folded; duplicates collapse; more than two entries truncate to two. Anything still unresolvable is dropped with a warning on stderr. If nothing remains, `misc` is written. The commit message records a repair. The ingest is **not** rejected for a bad topic: the raw, summary and note are intact and valuable, a rejection throws away a five-minute LLM run for a metadata slip, and the audit reports repairs so they are not silent. (A missing summary still rejects, because that output is unusable.)

`--summary-only` writes `topics:` as well when `topics.md` is present. `--verbatim-only` is unchanged. The stray-root-file allow list gains `topics.md`.

### `wiki-meta` (new, Python 3, stdlib)

The one place summary frontmatter and `topics.md` are parsed and written, so the format is defined once and every script agrees.

```
wiki-meta topics [--wiki DIR] [--json]        # parse topics.md; exit 3 if absent
wiki-meta get FILE KEY                        # scalar, or a list one per line
wiki-meta set FILE KEY VALUE [VALUE...]       # rewrite one key in place; lists in block form
wiki-meta normalize-topics FILE               # the ingest repair; prints what it did; exit 0 clean, 1 repaired
```

Also importable by the migration and retag scripts. Frontmatter rewriting preserves every other line byte for byte. Filenames and titles are NFC-normalised on comparison, per the existing rule in `wiki-curate`.

### `wiki-curate` (changed; still read-only)

- `WIKI_DIRS` gains `note`; `KIND_RANK` puts `note` between `topic` and `summary`. Everything that today says "topic pages" over the authored per-source pages (orphans, single-source, classify, duplicate titles) runs over `topic` and `note` together, so the numbers stay comparable across the migration.
- `parse_frontmatter` returns lists for block-list and flow-list values.
- `Vault` parses `topics.md` (via `wiki-meta`) and exposes `topic_members(slug)`.
- New subcommand `topics`: one row per list topic with member count, compiled-page presence, words, last compiled; flags rows over `--split-at N` (default 60); prints the `misc` members. `--json` for tooling.
- `dirty --since REF` becomes set arithmetic over `topics:` of the changed summaries. The link-graph reconstruction stays only as information about legacy pages.
- New audit checks: `untagged-digests` (summaries without `topics:`), `unlisted-topics` (a slug not in `topics.md`), `topic-page-missing` (a list topic with no compiled page), `topic-dir-stray` (a `topic/` file whose name is not a list title), `note-topic-name-clash` (a note and a topic title equal case-insensitively), `topic-oversized` (members over the split threshold), `index-sections-drift` (index headings not equal to the topic titles in order), `topics-repaired` (summaries whose last commit message recorded a repair, if cheap; otherwise dropped).

### `wiki-compile` (changed)

- `--theme` must be a `topics.md` title or slug; anything else exits 3 with "not a listed topic; add it to topics.md and retag". The source set comes from `topics:` membership. The page path comes from `topics.md`, not from the vault, so a topic with no page yet compiles: the worktree gets an empty `topic/<Title>.md` first (so the mtime check and the `HEAD:` read behave), and the link-preservation set is empty. The reconstructed-provenance plausibility cap is removed with the code path that needed it.
- Context is every member digest in full, as today.
- The prompt receives the scope line and is told sources tagged secondary may be mentioned lightly.
- A topic with fewer than 2 members still exits 3.

### `wiki-recompile` (changed)

Default selection is every list topic; `--since` uses the new `dirty`; `--top` still caps.

### `wiki-retag` (new)

The tool that makes the split rule work.

```
wiki-retag --topic misc            # re-assign everything currently in misc
wiki-retag --since REF             # summaries changed since REF
wiki-retag --slugs FILE            # an explicit list
wiki-retag --all                   # the whole corpus
        [--branch NAME] [--batch 20] [--dry-run]
```

For each batch it hands the LLM `topics.md` plus the précis and current `topics:` of N summaries and asks for one fenced JSON object, slug → list of topic slugs, on stdout. The script extracts the JSON tolerantly, validates every answer with the same normaliser as ingest, writes only the `topics:` key of each summary via `wiki-meta`, and commits on a branch in a detached worktree the way `wiki-compile` does. It never checks the branch out, never merges, and a worktree diff that touches anything but `topics:` lines fails validation (this, not `--allowedTools`, is the guardrail: the configured CLI is a wrapper that runs with permissions skipped, ledger A6). It prints a before/after count per topic. Batch defaults to 20; drop to 10 if the JSON is unreliable through the configured model.

### `wiki-review` (changed)

Reports the `topics` table delta alongside the audit delta, and understands the migration branch (renames are not word deltas).

### `wiki-ingest-setup`, `assets/`

Seeds `topics.md` from `assets/topics.md` and creates `note/`. `assets/wiki-CLAUDE.md` is rewritten: archive, digest, note, compiled topic; the topics rule; the index rule; the log format unchanged.

### `skills/wiki-ingest/SKILL.md`

Description and report section updated (topics assigned; the page is a note). The curation paragraph gains `wiki-curate topics`, `wiki-retag`. Orchestration is otherwise unchanged.

## Migration of the live wiki

Preconditions, both needing Nat: the hourly launchd job `com.gnat.ytx-wiki-ingest` is unloaded for the window, and he does not run `/wiki-ingest` until told. The plugin's marketplace cache is at 2.0.0 and would keep writing `topic/` pages through the skill path after the migration; the cache is updated in the same window.

All scripted, all rerunnable from a fresh branch off `main`.

1. **Branch** `curate/topics-<date>` off `main`.
2. **Move** every `topic/` page whose title is not a list title to `note/` with `git mv` (verified on a clone: git tracks the names NFC and records clean renames, accented names included). 1133 files today. Links are untouched and keep resolving by basename.
3. **Seed `topics.md`** with the starting list.
4. **Backfill `topics:`** for all 1160 summaries. Signals, in priority order: (a) membership in the declared provenance of a compiled page whose title is on the list; (b) the `index.md` section of the summary's note, through a fixed section-to-slug mapping in the migration script; (c) `misc`. Keep at most two. Measured coverage: (a) reaches 382 summaries, (a)+(b) reaches 1064, leaving about 96 for `misc`.
5. **Retag `misc`** with `wiki-retag --topic misc` on the same branch.
6. **Restructure `index.md`**: rename and merge sections to the topic titles using the same mapping; move each entry under its primary topic; add the `## Topics` section. Entries are preserved exactly.
7. **Update the wiki's own `CLAUDE.md`** on the branch. It has drifted from `assets/wiki-CLAUDE.md` (it carries Workflows, Relationship-to-the-vault and Principles sections that are Nat's); only the tier and topic sections are replaced.
8. **Compile every list topic** with `wiki-recompile` onto the branch. Existing compiled pages are rebuilt from their tag-derived source set; the link-preservation gate keeps every link they had. New topics get their first page. If `Agent Architecture` at 170 members compiles badly, split it in `topics.md`, retag, and recompile before going further.
9. **`wiki-review`** the branch; `wiki-curate audit` on it must show `dead-links` and `orphans` not increased. Nat merges (fast-forward, because `main` has not moved). The standing "merge clean compile cycles without asking" decision does not cover this branch: it restructures the schema, so it is shown to Nat regardless.
10. **Resume**: reload the launchd job; update the marketplace cache; the next ingest exercises the new path for real.

Reversal at any point before step 9 is `git branch -D`. After the merge, the move is a `git revert` of one commit.

## What changes for Nat

- `/wiki-ingest <url>` behaves the same and reports which topics the source was filed under.
- `wiki-curate topics` names any topic over 60 members and lists what is in `misc`. To split a topic: edit `topics.md`, run `wiki-retag --topic <old-slug>`, then `wiki-recompile`.
- `topic/` holds about 18 pages and stays about 18 unless he adds one. The 1133 per-source analyses are in `note/`, unchanged.

## Non-goals

- Automatic topic discovery. Explicitly rejected above.
- Folding the analysis into the digest, or renaming `summary/`. See ledger A1.
- Compiling from full notes or `raw/`. Digests only, as today.
- `facts/<slug>.json` structured extraction (scrapped in the monograph, still scrapped).
- Query.

## Open questions

1. **Compile quality at 130 to 170 digests** through the configured model (DeepSeek v4 pro via the `dscldy` wrapper, not Claude; the 101-source precedent was compiled with Claude). Answered by migration step 8; the remedy is a split before the branch is offered.
2. **Secondary-topic sources on a compiled page.** The prompt says "lightly". Whether that produces a useful page or a padded one is a review question for step 8.

## Load-bearing ledger (2026-09-11)

| ID | Claim | Status | Evidence | Consequence |
|---|---|---|---|---|
| A1 | Obsidian resolves bare `[[X]]` via `aliases:` | **falsified**, high confidence | help/aliases wording; forum 113902 (May 2026, moderator: by design, never worked); FR 8993 open since 2020; plugins exist to add it | Fold dropped; per-source pages move to `note/`. Basename resolution is vault-wide and case-insensitive (forum 2844, 52331). |
| A2 | "Body up to first H2" is a usable précis | **falsified** by measurement | 661/1160 digests have H2s; 460 have <40 words before the first | Compile keeps reading whole digests. |
| A3 | Most legacy pages are fold-eligible | moot | 581/1051 summaries already have H2s | Fold dropped anyway. |
| A4 | `merge=union` tolerates an `index.md` section restructure | **falsified**, reproduced | branch moved sections, main appended a bullet: merge rc 0, entry under wrong heading, moved block duplicated | Migration runs quiesced, merges fast-forward. |
| A5 | Plugin code and wiki migration can be sequenced independently | **falsified** | `~/Source/ytx/scripts/ingest-ytx-gists.sh` line 12 calls this repo's working-tree `bin/wiki-ingest-run` hourly; the skill runs the 2.0.0 marketplace cache | Feature gate on `topics.md`; develop in a git worktree; cache bump in the window. |
| A6 | `--allowedTools` is a real guardrail for the nested CLI | **falsified** | `WIKI_INGEST_CLI` is `dscldy`, which runs `claude --dangerously-skip-permissions` against DeepSeek v4 pro | Retag/compile rely on the worktree-diff validation; noted as the guardrail. Residual risk accepted: the model could reach the live checkout; unchanged from today. |
| A7 | `claude -p` returns parseable JSON for batches of 30 | deferred | untested through the proxy | Tolerant extractor, batch 20, fallback 10. |
| A8 | Compiler is acceptable at 130–170 digests | open | best prior 101 with a different model | Migration step 8 decides; split before offering. |
| A9 | Compile can bootstrap a topic with no page | design gap found | `wiki-curate sources` dies on a missing page; compile reads `HEAD:` | Page path from `topics.md`; seed empty page. |
| A10 | Migration branch merges onto a moving `main` | **falsified** | 14–29 ingest commits per active day; branch rewrites all summaries | Quiesced window. |
| A11 | Aliases unique across summaries | moot | 6 duplicate summary titles; 0 duplicate topic titles | Note-title collision is guarded at ingest instead. |
| A12 | Obsidian reads flow-list YAML | confirmed, medium-high | moderator statements 77031/66665; 1.9.0 changelog; historical help page | Write block form anyway (rewrite churn, silent failure on malformed lists). |
| A13 | No other consumer depends on `topic/` holding per-source pages | verified | `wiki-podcast/generate.py` resolves root → `topic/` → recursive; `article_select.py` reads `log.md` names | `note/` is found by the recursive fallback. |
| A14 | `git mv` of NFD-on-disk names into `note/` is clean | verified on a clone | `core.precomposeunicode=true`; rename recorded for `LLM Cliché Highlighter.md` | Step 2 is a plain `git mv`. |

## Phases

1. **Foundations, no wiki changes:** `wiki-meta`; `wiki-curate` lists, `note/`, `topics.md`, `topics` subcommand, audit checks, tag-based `dirty`; tests.
2. **Ingest:** gated prompts and guard, normaliser, `--summary-only`; `assets/topics.md`, `assets/wiki-CLAUDE.md`, setup, SKILL.md; tests; live-fire against a clone of the wiki with `topics.md` present and absent.
3. **Compile:** tag-derived source set, listed-topics-only, bootstrap, recompile default; tests.
4. **Retag and migration scripts:** `wiki-retag`, `wiki-migrate-topics` (steps 2–7 as one rerunnable script with `--step` and `--dry-run`); tests with the fake CLI; a full dry run against a clone.
5. **Migration** (needs Nat: freeze, merge, resume).
6. **Release:** version 3.0.0, marketplace entry, cache update.
