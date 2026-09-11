# CLAUDE.md — powerups-wiki-ingest

A Claude Code plugin that ingests URLs into an Obsidian wiki.

## Layout

- `skills/wiki-ingest/SKILL.md` — the `/wiki-ingest` skill (orchestration only). It supersedes the old `commands/wiki-ingest.md`, which is deleted: a skill and a command of the same name collide, and the skill wins.
- `bin/` — the executables, added to PATH when the plugin is enabled. Call them by bare name.
  - `wiki-ingest-run` — the ingest engine (dup-check → worktree → fetch/extract → LLM → commit → merge → push). The script fetches and stages `raw/<slug>.md`; the LLM only reads it. Also hosts `--verbatim-only` (archive only) and `--summary-only` (backfill a precis from an existing `raw/` file).
  - `wiki-ingest-fetch` — `curl` piped into `trafilatura --markdown`: deterministic readability extraction, no browser and no LLM; exit 3 on an empty/JS-shell page.
  - `wiki-ingest-dupcheck` — deterministic duplicate detection; scans `raw/` and `summary/`.
  - `wiki-ingest-backfill` — re-archives URLs recorded in `ingest-queue.md`.
  - `wiki-ingest-setup` — one-time wiki bootstrap; seeds `topics.md` and `note/`.
  - `wiki-meta` — Python 3, stdlib only. The one parser/writer for summary frontmatter and `topics.md` (`topics`, `get`, `set`, `normalize-topics`). Other scripts import it with `SourceFileLoader` (it has no `.py` extension). Lists are written in block YAML form on purpose: Obsidian rewrites flow lists and fails silently on malformed ones.
  - `wiki-retag` — LLM re-files summaries against `topics.md` (after a split or for `misc`); writes only `topics:` lines, on a branch, and a worktree diff touching anything else fails the run. That diff check, not `--allowedTools`, is the guardrail: the configured CLI wrapper runs with permissions skipped.
  - `wiki-migrate-topics` — the one-off 2.x → 3.0 migration (move per-source pages to `note/`, seed `topics.md`, backfill `topics:`, restructure `index.md`), on a branch, rerunnable.
  - `wiki-curate` — Python 3, stdlib only. Read-only corpus index + health audit; never writes to the wiki. Subcommands: `index`, `audit`, `themes`, `sources`, `dirty` (what a batch touched), `classify` (entity vs concept), `gaps`, `fixme`. Filenames are NFC-normalised before resolving links: macOS/iCloud store them decomposed and markdown links compose them, so raw comparison silently reports accented titles as dead links.
  - `wiki-compile` — rebuilds ONE topic page from all its sources. Detached worktree, commits to a branch, moves the branch ref afterwards; never checks the branch out (that broke a whole batch run once) and never merges.
  - `wiki-recompile` — drives `wiki-compile` serially, auditing before and after. `--since REF` selects only the themes a batch touched; `--top` caps it.
  - `wiki-review` — renders a compile branch as a review report (per-page word/link deltas, dropped links, corpus audit delta). Built because a multi-page compile diff is otherwise unreviewable — it is what caught the compiler destroying cross-links.
- `assets/wiki-CLAUDE.md` — the schema template seeded into a new wiki.
- `tests/` — five suites, all offline with no real LLM: `test-fetch.sh` (extraction, fixture-based), `test-guard.sh` (completeness guard + `--summary-only`), `test-curate.sh` (the corpus index and every audit check), `test-compile.sh` (the compile safety gates and the recompile driver), `test-meta.sh` (frontmatter read/write byte-fidelity, `topics.md` validation, every `normalize-topics` branch). The latter three are mutation-tested: deliberately reintroducing each fixed bug turns them red.

## Testing

Both test scripts are runnable with no network and no real LLM. **`test-guard.sh` seeds the throwaway wiki with a pre-existing `summary/` and `topic/` page on purpose** — the completeness guard's original bug was that it globbed the whole worktree, which only looks wrong on a *populated* wiki. Remove the seed and the test silently stops testing anything.

Never point `WIKI_PATH` at a real wiki when testing.

## Conventions

- Scripts target bash 3.2 (macOS `/bin/bash`): no `mapfile`, no associative arrays, no negative indexing.
- Config comes from env: `WIKI_PATH` (required), `WIKI_INGEST_CLI` (default `claude`). No hardcoded paths.
- Scripts must NOT reference `${CLAUDE_PLUGIN_ROOT}` (broken in command markdown, issue #9354). Rely on `bin/`-on-PATH and `$(dirname "$0")` for sibling/asset lookups.
- Command and skill markdown must NOT contain `$0`–`$9` anywhere in its body, fenced code included. Claude Code replaces them with the user's arguments before the agent ever sees the text — 0-based, so `$2` becomes the *third* URL and silently rewrites the snippet into something that no longer runs. Out-of-range indices survive, so a short invocation hides it. In shell examples reach for `$NF`, or `$k` with `awk -v k=2`, or a form that does not start with `$`.
- The LLM runs with `--allowedTools` as a real guardrail — do not add `--dangerously-skip-permissions` to the default path.

## Topics (3.0)

`topic/` holds exactly the titles listed in `topics.md`, and only `wiki-compile`
writes there. The per-source analysis page is `note/<Title>.md`. Every summary
carries `topics:` (one or two slugs, primary first). The new ingest prompt and
guard switch on only when `topics.md` exists in the wiki worktree; without it
the 2.x behaviour runs unchanged, because the hourly launchd job calls this
repo's working-tree `bin/` directly and a wiki must not change shape before it
has been migrated. Design and the load-bearing ledger:
`docs/superpowers/specs/2026-09-11-fixed-topics-design.md`.

## Merging compile cycles

Nat's standing decision (2026-08-10): **merge a compile cycle without asking
when `wiki-review` comes back clean.** Clean means all three:

- zero cross-links dropped on every page,
- no `dead-links` increase in the corpus audit delta,
- no `orphans` increase.

Anything else — a dropped link, new dead links, a validation rejection, or a
page whose provenance looks over-attributed — stop and show him the review
instead. Growth in `oversized` is expected and is not a reason to stop; he has
accepted that compiled pages roughly double.

Always run `wiki-review` before merging. It is the only thing that has caught
the two real regressions so far (the compiler destroying 48 cross-links, and a
page fabricating 117 provenance slugs), and a compile diff is unreviewable by
eye.

## Releasing

Bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then update the entry in `powerups-marketplace`.
