# Fixed Topics — Implementation Plan

Spec: `docs/superpowers/specs/2026-09-11-fixed-topics-design.md` (read it first; the ledger at its end explains every constraint below). Kata `1srn`.

Ground rules for every task:

- Work in this worktree on branch `fixed-topics`. The main checkout is what the hourly launchd job runs; it must not change until the migration.
- Scripts target bash 3.2 (no `mapfile`, no associative arrays, no negative indexing) or Python 3 stdlib. No `${CLAUDE_PLUGIN_ROOT}`. Sibling lookup via `$(dirname "$0")`.
- Skill/command markdown must not contain `$0`–`$9`.
- Tests are offline with a stub CLI; `WIKI_PATH` is always a temp dir. New behaviour gets a case in the matching `tests/test-*.sh`; where a bug is fixed, the case must go red when the fix is reverted.
- Commit after each task, adding named paths only (`git add <paths>`, never `-A`). No AI attribution trailers.
- `topics:` and every other list is written in block YAML form.

## Task 1 — `bin/wiki-meta` (Python 3, stdlib)

New executable. Subcommands:

- `topics [--wiki DIR] [--json]` — parse `<wiki>/topics.md`. Find the first markdown table whose header row has columns `slug`, `title`, `scope` (case-insensitive, any order); skip the separator row; each data row yields `{slug, title, scope}`. Validate: slug matches `^[a-z0-9][a-z0-9-]*$`, slugs unique, titles unique case-insensitively after NFC, `misc` present. Exit 3 with a message if `topics.md` is absent; exit 2 on a validation error naming the row. Text output: one line per topic `slug<TAB>title<TAB>scope`.
- `get FILE KEY` — print a scalar, or a list one item per line. Exit 1 if the key is absent. Reads both flow `[a, b]` and block lists; strips matching quotes from scalars and items.
- `set FILE KEY VALUE [VALUE...]` — rewrite exactly that key inside the frontmatter, preserving every other byte. One VALUE writes a scalar unless `--list` is given; two or more write a block list. Replaces an existing key in place (removing a block list's continuation lines); appends before the closing `---` when absent. A file with no frontmatter gets one created. Writes atomically (temp file + rename).
- `normalize-topics FILE [--wiki DIR]` — the ingest repair. Read `topics:`; map each entry: exact slug → keep; case-insensitive match on a slug or a title (NFC) → slug; else drop with a warning on stderr. Dedupe preserving order, truncate to two. Empty → `misc`. Write back in block form only if changed. Exit 0 when nothing changed, 1 when repaired (and print one line saying what), 2 on error.
- Expose the parsing/writing as functions so `wiki-retag` and the migration script can `import` the file (`importlib.util.spec_from_file_location`, since it has no `.py` extension). Do not name any module after a stdlib module.

Tests: new `tests/test-meta.sh` — fixture files exercising flow/block lists, quoted scalars, key replacement in the middle of the frontmatter, appending a missing key, no-frontmatter file, `topics.md` parsing with extra prose around the table and with a header in a different column order, each validation failure, and every branch of `normalize-topics` (title→slug, case fold, dedupe, truncate, drop, empty→misc, unchanged exit 0).

## Task 2 — `bin/wiki-curate`

- `WIKI_DIRS` gains `note`; `KIND_RANK` `{"topic":0,"note":1,"summary":2,"raw":3}`.
- `parse_frontmatter` returns lists for flow and block-list values (reuse `wiki-meta`'s parser by import so there is one definition).
- `Vault.topics()` keeps returning `topic` pages; add `Vault.authored()` returning `topic` + `note` pages. Every check that today iterates `topics()` as "the authored per-source pages" (orphans, single-source, no-provenance, reconstructed, duplicate-titles, oversized, classify, stale-counts' `actual` count) switches to `authored()`, so numbers stay comparable across the migration. `themes`, `dirty`, `sources`, `gaps`, `fixme` keep operating on `topic`.
- `Vault` loads `topics.md` through `wiki-meta` when present (`self.topic_list`, ordered; `None` when absent) and builds `self.topic_members: slug -> sorted summary keys` from each summary's `topics:` list.
- New subcommand `topics [--split-at N] [--json]`: rows in `topics.md` order: slug, title, members, page present (bool), words, `Last compiled:` date if present; `OVER` marker when members > N (default 60). After the table, the `misc` members as `summary/<slug>` with their `title`. Exit 3 when no `topics.md`.
- `dirty --since REF`: when `topics.md` exists, a topic is dirty when any changed summary lists it; output titles. Keep the old behaviour when there is no `topics.md`.
- `sources --theme X`: when `topics.md` exists, resolve X as a slug or title, return `{"theme": title, "path": "topic/<title>.md", "sources": [...members...], "provenance": "declared-topics"}` even if the page does not exist yet; exit 3 if X is not a listed topic (message: "not a listed topic; add it to topics.md and retag"). Without `topics.md`, unchanged.
- New audit checks (each only when `topics.md` exists, else empty): `untagged-digests`, `unlisted-topics`, `topic-page-missing`, `topic-dir-stray`, `note-topic-name-clash`, `topic-oversized` (uses the same default 60), `index-sections-drift` (H2 headings of `index.md` after the `## Topics` section must equal the topic titles in order).
- Update the module docstring and `--help`.

Tests: extend `tests/test-curate.sh` with a `note/` page in the fixture (linked from a topic page; counted by orphans/single-source as before), a `topics.md`, summaries with block and flow `topics:`, and one case per new check (positive and negative). Mutation guidance: removing the `note` entry from `WIKI_DIRS` must turn the suite red.

## Task 3 — `bin/wiki-ingest-run` (gated)

- After the worktree is created: `TOPICS_MODE=0; [ -f "$WT/topics.md" ] && TOPICS_MODE=1`. `mkdir -p "$WT/note"` in topics mode.
- In topics mode, the article and repo prompts are the new versions: `note/<Title>.md` instead of `topic/<Title>.md` throughout; the topics table (from `wiki-meta topics`) embedded with the selection rule and the block-form example; index instruction "under the primary topic's section heading (the section heading is the topic title)"; checklist updated. Keep the old prompts byte-identical for `TOPICS_MODE=0`. Factor the shared prompt text into shell variables rather than duplicating 200 lines where that keeps it readable; do not change the old path's behaviour.
- `--summary-only` in topics mode: the prompt also asks for `topics:` (block form) chosen from the table; after the LLM, run `wiki-meta normalize-topics`.
- Guard in topics mode (replacing the `^topic/` check): exactly one staged `note/` path; it must be an addition (`--diff-filter=A`) unless `FORCE=1`, in which case a modification is allowed only if that note's `*Sources:*` footer cites `raw/$SLUG` or `summary/$SLUG` (read from `HEAD:` in the worktree); any staged `topic/` path → reject; staged `topics.md` → reject; `wiki-meta normalize-topics "$WT/summary/$SLUG.md"` → if exit 1, re-`git add` the file and append "(topics repaired)" to the commit message; exit 2 → reject. The stray-root allow list gains `topics`.
- Header comment and `usage` updated.

Tests: extend `tests/test-guard.sh`. Add a second sandbox wiki (or a phase) that has `topics.md` with two topics plus `misc`, and stub modes: `note-good` (summary with block `topics:` + one new note + index/log), `note-flow-topics` (flow list → accepted, rewritten block), `note-title-case` (`topics:` holds a title → normalised to slug), `note-bad-topic` (unknown slug → repaired to `misc`, commit message says so), `note-writes-topic-dir` (→ reject), `note-edits-topics-md` (→ reject), `note-two-notes` (→ reject), `note-overwrites-other-note` (a note that already exists on main → reject; with `--force` on the same source → accepted). Assert that with `topics.md` absent, the existing `good` mode still passes and a `note/` write is not required (old behaviour intact).

## Task 4 — `bin/wiki-compile`, `bin/wiki-recompile`, `bin/wiki-review`

- `wiki-compile`: source set via `wiki-curate sources` (now topic-aware). When `topics.md` exists and the page does not, create an empty `topic/<Title>.md` in the worktree before the mtime back-dating, and treat the "old" link set as empty (`git show HEAD:path` failing is not an error in that case). Remove the reconstructed-provenance plausibility cap and its env var. The prompt gets a `SCOPE:` line from `topics.md` and one sentence about secondary-tagged sources. Header comment updated.
- `wiki-recompile`: with `topics.md`, the default list is every listed topic in order (`wiki-curate topics --json`), `--top` caps, `--since` uses the new `dirty`; without it, unchanged.
- `wiki-review`: add a "Topics" table (before/after members per topic from `wiki-curate topics --json` on base and branch) when `topics.md` exists on the branch; render renamed files (`git diff --name-status -M`) as a "Moved" count rather than as a deleted+added page pair; count `note/` pages in link resolution the same as `topic/`.

Tests: extend `tests/test-compile.sh` with a `topics.md` fixture: compile a listed topic with no existing page (bootstrap) → page created, footer lists the tag members; compile an unlisted theme → exit 3 with the message; a summary tagged secondary is in the context; `wiki-recompile` with no args compiles the listed topics only; a legacy multi-source page in `note/` is not compiled.

## Task 5 — `bin/wiki-retag` (bash + embedded Python, or Python)

Per spec. Detached worktree on `--branch` (default `curate/retag-<date>`), batches of `--batch` (default 20) summaries. Prompt: the topics table, then for each summary its slug, title and précis (first 200 words of the body), then "Return exactly one fenced JSON object mapping slug to a list of one or two topic slugs." Invoke `$WIKI_INGEST_CLI -p --allowedTools Read` with the prompt on stdin, capture stdout, extract the first ```json fence (or the first `{…}` balanced object if no fence), validate with the normaliser, write via `wiki-meta set … --list`, verify with `git status --porcelain` that only `summary/*.md` changed and that a `git diff` of each touched file changes only `topics:` lines (frontmatter diff check in Python), commit one batch per commit, move the branch ref with `update-ref`. `--dry-run` prints the proposed map and writes nothing. Print a before/after count per topic at the end. Selection: `--topic SLUG`, `--since REF`, `--slugs FILE`, `--all`.

Tests: new `tests/test-retag.sh` with a stub CLI that returns a fenced JSON map (and a mode that returns prose around it, a mode that returns an invalid slug, and a mode that also writes a stray file → run fails validation, branch unchanged). Assert the live checkout never moves.

## Task 6 — `bin/wiki-migrate-topics` (Python 3, stdlib; one-off but rerunnable)

`--wiki`, `--branch` (default `curate/topics-<date>`), `--topics-file assets/topics.md`, `--step N` / `--all`, `--dry-run`. Runs in a detached worktree; commits per step; moves the branch ref; never checks out or merges. Steps:

1. `git mv` every `topic/*.md` whose NFC title is not a listed title into `note/`. Create `note/.gitkeep`.
2. Write `topics.md` from the topics file.
3. Backfill `topics:` on every summary lacking it, from (a) declared provenance of listed compiled pages (parse the `*Compiled from …*` footer and `*Sources:*` lines of the listed pages), (b) the `index.md` section of the summary's note (map old section heading → slug; the mapping table lives in the script and is printed), (c) `misc`. Print per-topic counts and the `misc` list.
4. Restructure `index.md`: parse sections and entries; emit `# Wiki Index`, an intro line without a page count, `## Topics` listing `[[<title>]] — <scope>` for each topic, then one `## <title>` section per topic with the scope line and the entries whose note's primary topic is that slug (entries whose target has no summary or no `topics:` go to `Miscellany`). Every original entry line must appear exactly once in the output; the script asserts that.
5. Rewrite the tier/topic sections of the wiki's `CLAUDE.md` from `assets/wiki-CLAUDE.md`, keeping the wiki's own extra sections (everything from `## Workflows` onward is preserved verbatim).

Steps 6–7 of the spec (retag `misc`, recompile) are run by hand with `wiki-retag --branch` and `wiki-recompile --branch` on the same branch.

Tests: `tests/test-migrate.sh` builds a small fake legacy wiki (topic pages with and without list titles, an accented title, an index with two old sections, summaries with and without provenance) and asserts each step's result, plus a full dry run leaving `main` untouched.

## Task 7 — assets, skill, docs, version

- `assets/topics.md` with the starting list from the spec (scope lines written properly).
- `assets/wiki-CLAUDE.md` rewritten per spec (archive, digest, note, compiled topic; topics rule; index rule).
- `bin/wiki-ingest-setup` creates `note/`, seeds `topics.md`.
- `skills/wiki-ingest/SKILL.md`: description, script list (`wiki-meta`, `wiki-retag`, `wiki-migrate-topics`, `wiki-curate topics`), report section.
- `CLAUDE.md` (repo): layout list, testing list, the "Merging compile cycles" section unchanged, a new short "Topics" section stating the invariant (`topic/` holds only listed titles; per-source analysis is `note/`; new behaviour gated on `topics.md`).
- `README.md` if it describes the tiers.
- Version 3.0.0 in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. The marketplace entry in `powerups-marketplace` is updated at release, not in this task.
- `.gitignore`: add `.claude/worktrees/` and `bin/__pycache__/`.

## Task 8 — dry run against a clone

Clone the live wiki into the scratchpad, run `wiki-migrate-topics --all` against the clone, then `wiki-curate audit` and `wiki-curate topics` on the resulting branch, then one `wiki-ingest-run --content` ingest against the clone's branch (checked out in the clone) with the real configured CLI, then `wiki-compile --theme misc` (small) on the clone. Record the numbers in the kata issue. Nothing touches the live wiki.

## Hand-off (needs Nat)

Freeze (unload `com.gnat.ytx-wiki-ingest`, no `/wiki-ingest`), run the migration on the live wiki's branch, retag `misc`, recompile all topics, `wiki-review`, merge, reload, update the plugin cache, release 3.0.0.
