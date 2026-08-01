# CLAUDE.md — powerups-wiki-ingest

A Claude Code plugin that ingests URLs into an Obsidian wiki.

## Layout

- `commands/wiki-ingest.md` — the `/wiki-ingest` slash command (orchestration only).
- `bin/` — the executables, added to PATH when the plugin is enabled. Call them by bare name.
  - `wiki-ingest-run` — the ingest engine (fetch → worktree → LLM → commit → merge → push). Also hosts `--verbatim-only` (archive only) and `--summary-only` (backfill a precis from an existing `raw/` file).
  - `wiki-ingest-fetch` — trafilatura extraction helper; exit 3 on an empty/JS-shell page.
  - `wiki-ingest-dupcheck` — deterministic duplicate detection; scans `raw/` and `summary/`.
  - `wiki-ingest-backfill` — re-archives URLs recorded in `ingest-queue.md`.
  - `wiki-ingest-setup` — one-time wiki bootstrap.
- `assets/wiki-CLAUDE.md` — the schema template seeded into a new wiki.
- `tests/` — `test-fetch.sh` (extraction, fixture-based, no network) and `test-guard.sh` (completeness guard + `--summary-only`, against a throwaway wiki with a stubbed `WIKI_INGEST_CLI`).

## Testing

Both test scripts are runnable with no network and no real LLM. **`test-guard.sh` seeds the throwaway wiki with a pre-existing `summary/` and `topic/` page on purpose** — the completeness guard's original bug was that it globbed the whole worktree, which only looks wrong on a *populated* wiki. Remove the seed and the test silently stops testing anything.

Never point `WIKI_PATH` at a real wiki when testing.

## Conventions

- Scripts target bash 3.2 (macOS `/bin/bash`): no `mapfile`, no associative arrays, no negative indexing.
- Config comes from env: `WIKI_PATH` (required), `WIKI_INGEST_CLI` (default `claude`). No hardcoded paths.
- Scripts must NOT reference `${CLAUDE_PLUGIN_ROOT}` (broken in command markdown, issue #9354). Rely on `bin/`-on-PATH and `$(dirname "$0")` for sibling/asset lookups.
- The LLM runs with `--allowedTools` as a real guardrail — do not add `--dangerously-skip-permissions` to the default path.

## Releasing

Bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then update the entry in `powerups-marketplace`.
