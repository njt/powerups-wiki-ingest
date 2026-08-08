# CLAUDE.md — powerups-wiki-ingest

A Claude Code plugin that ingests URLs into an Obsidian wiki.

## Layout

- `commands/wiki-ingest.md` — the `/wiki-ingest` slash command (orchestration only).
- `bin/` — the executables, added to PATH when the plugin is enabled. Call them by bare name.
  - `wiki-ingest-run` — the ingest engine (dup-check → worktree → fetch/extract → LLM → commit → merge → push). The script fetches and stages `raw/<slug>.md`; the LLM only reads it. Also hosts `--verbatim-only` (archive only) and `--summary-only` (backfill a precis from an existing `raw/` file).
  - `wiki-ingest-fetch` — `curl` piped into `trafilatura --markdown`: deterministic readability extraction, no browser and no LLM; exit 3 on an empty/JS-shell page.
  - `wiki-ingest-dupcheck` — deterministic duplicate detection; scans `raw/` and `summary/`.
  - `wiki-ingest-backfill` — re-archives URLs recorded in `ingest-queue.md`.
  - `wiki-ingest-setup` — one-time wiki bootstrap.
  - `wiki-curate` — Python 3, stdlib only. Read-only corpus index + health audit; never writes to the wiki. Subcommands: `index`, `audit`, `themes`, `sources`.
  - `wiki-compile` — rebuilds ONE topic page from all its sources. Detached worktree, commits to a branch, moves the branch ref afterwards; never checks the branch out (that broke a whole batch run once) and never merges.
  - `wiki-recompile` — drives `wiki-compile` over the top themes serially, auditing before and after.
- `assets/wiki-CLAUDE.md` — the schema template seeded into a new wiki.
- `tests/` — `test-fetch.sh` (extraction, fixture-based, no network) and `test-guard.sh` (completeness guard + `--summary-only`, against a throwaway wiki with a stubbed `WIKI_INGEST_CLI`).

## Testing

Both test scripts are runnable with no network and no real LLM. **`test-guard.sh` seeds the throwaway wiki with a pre-existing `summary/` and `topic/` page on purpose** — the completeness guard's original bug was that it globbed the whole worktree, which only looks wrong on a *populated* wiki. Remove the seed and the test silently stops testing anything.

Never point `WIKI_PATH` at a real wiki when testing.

## Conventions

- Scripts target bash 3.2 (macOS `/bin/bash`): no `mapfile`, no associative arrays, no negative indexing.
- Config comes from env: `WIKI_PATH` (required), `WIKI_INGEST_CLI` (default `claude`). No hardcoded paths.
- Scripts must NOT reference `${CLAUDE_PLUGIN_ROOT}` (broken in command markdown, issue #9354). Rely on `bin/`-on-PATH and `$(dirname "$0")` for sibling/asset lookups.
- Command markdown must NOT contain `$0`–`$9` anywhere in its body, fenced code included. Claude Code replaces them with the user's arguments before the agent ever sees the text — 0-based, so `$2` becomes the *third* URL and silently rewrites the snippet into something that no longer runs. Out-of-range indices survive, so a short invocation hides it. In shell examples reach for `$NF`, or `$k` with `awk -v k=2`, or a form that does not start with `$`.
- The LLM runs with `--allowedTools` as a real guardrail — do not add `--dangerously-skip-permissions` to the default path.

## Releasing

Bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then update the entry in `powerups-marketplace`.
