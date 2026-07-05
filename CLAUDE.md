# CLAUDE.md — powerups-wiki-ingest

A Claude Code plugin that ingests URLs into an Obsidian wiki.

## Layout

- `commands/wiki-ingest.md` — the `/wiki-ingest` slash command (orchestration only).
- `bin/` — the executables, added to PATH when the plugin is enabled. Call them by bare name.
  - `wiki-ingest-run` — the ingest engine (worktree → LLM → commit → merge → push).
  - `wiki-ingest-dupcheck` — deterministic duplicate detection.
  - `wiki-ingest-setup` — one-time wiki bootstrap.
- `assets/wiki-CLAUDE.md` — the schema template seeded into a new wiki.

## Conventions

- Scripts target bash 3.2 (macOS `/bin/bash`): no `mapfile`, no associative arrays, no negative indexing.
- Config comes from env: `WIKI_PATH` (required), `WIKI_INGEST_CLI` (default `claude`). No hardcoded paths.
- Scripts must NOT reference `${CLAUDE_PLUGIN_ROOT}` (broken in command markdown, issue #9354). Rely on `bin/`-on-PATH and `$(dirname "$0")` for sibling/asset lookups.
- The LLM runs with `--allowedTools` as a real guardrail — do not add `--dangerously-skip-permissions` to the default path.

## Releasing

Bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then update the entry in `powerups-marketplace`.
