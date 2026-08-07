# powerups-wiki-ingest — Design

**Date:** 2026-07-05
**Status:** Approved, pre-implementation
**Load-bearing check:** run 2026-07-05 — corrected script-referencing mechanism from `${CLAUDE_PLUGIN_ROOT}` to the `bin/`-on-PATH pattern (see "Script location").

## Goal

Repackage the personal `wiki-ingest` command + scripts (currently in `~/Source/wiki`, installed via a `~/.claude/commands` symlink) as a public Powerups plugin, `powerups-wiki-ingest`, that anyone can install via the Powerups marketplace and run against their own Obsidian wiki. Nat becomes a normal installer of his own plugin.

## Constraints and context

- Follows the `powerups-*` plugin convention documented in `github.com/njt/powerups-template` (CLAUDE.md + README read 2026-07-05).
- The current tooling is battle-tested (see `~/Source/wiki`): worktree-per-ingest, `merge=union` on index.md/log.md, deterministic dup-check, merge retry, best-effort push, exit-code contract (0/2/3), reaping of stale branches, and recursion guards preventing the ingest subagent from re-orchestrating the pipeline.
- The deployed LLM CLI on Nat's machine is `dscldy` (DeepSeek behind an Anthropic-compatible endpoint, API key in the macOS keychain, runs with `--dangerously-skip-permissions`). That must NOT be the default for strangers.

## Decisions (from brainstorming)

1. **LLM backend:** `claude`, allowlist-only. Scripts invoke `"$WIKI_INGEST_CLI" -p --allowedTools Read,Write,Edit,Bash,WebFetch,WebSearch --add-dir "$WT"` with **no** `--dangerously-skip-permissions`, so the allowlist is a genuine guardrail on other people's machines. `WIKI_INGEST_CLI` defaults to `claude`; Nat sets it to his `dscldy` wrapper.
2. **Wiki location:** `WIKI_PATH` env var, **no default**. Scripts exit with setup instructions if it is unset or not a directory. No risk of writing into a wrong default location.
3. **Onboarding:** ship a `setup-wiki.sh` bootstrap script plus an `assets/wiki-CLAUDE.md` schema/conventions template. Zero-to-working in one command.
4. **Surf fallback:** kept, marked optional ("requires the `surf` CLI; without it, failed URLs are queued"). `ingest.sh --content FILE` is surf-agnostic — any grabbed text file works.
5. **Migration:** new repo with clean history; `~/Source/wiki` stays as archive with a "moved" note; Nat installs the plugin like anyone else and the `~/.claude/commands/wiki-ingest.md` symlink is retired.

## Repository structure

```
powerups-wiki-ingest/
├── .claude-plugin/
│   ├── plugin.json              # name, description, v1.0.0, MIT, repo/homepage, keywords
│   └── marketplace.json         # local-dev marketplace (source: "./")
├── commands/
│   └── wiki-ingest.md           # orchestration; calls the bin/ executables by bare name
├── bin/                         # added to the Bash tool's PATH while the plugin is enabled
│   ├── wiki-ingest-run          # the ingest engine (was ingest.sh)
│   ├── wiki-ingest-dupcheck     # deterministic dup check (was dup-check.sh)
│   └── wiki-ingest-setup        # NEW — bootstrap a wiki directory
├── assets/
│   └── wiki-CLAUDE.md           # schema/conventions template (from the wiki's CLAUDE.md)
├── CLAUDE.md                    # how to work on this plugin repo
├── README.md                    # what/why/install (marketplace + manual)/config/LICENSE
└── LICENSE                      # MIT
```

### Script location: `bin/`, not `${CLAUDE_PLUGIN_ROOT}`

**Load-bearing decision, validated 2026-07-05 against official docs + GitHub issues.** The intuitive approach — reference scripts as `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh` in the command markdown — **does not work**: `${CLAUDE_PLUGIN_ROOT}` expands to empty in command/skill markdown (documented bug [anthropics/claude-code#9354](https://github.com/anthropics/claude-code/issues/9354)), and its availability to agent-issued Bash calls is undocumented and known-inconsistent ([#38699](https://github.com/anthropics/claude-code/issues/38699), [#42564](https://github.com/anthropics/claude-code/issues/42564)).

The **documented, reliable** mechanism ([Plugins docs](https://code.claude.com/docs/en/plugins.md)): executables in the plugin's `bin/` directory are added to the Bash tool's `PATH` while the plugin is enabled. So:

- The three scripts live in `bin/`, named distinctively (`wiki-ingest-*`, no `.sh`, `chmod +x`) to avoid PATH collisions with anything else the user has.
- The command invokes them by **bare name** (`wiki-ingest-run <url>`), no path.
- `wiki-ingest-run` finds its siblings and the asset template by resolving its own location — `SELF="$(cd "$(dirname "$0")" && pwd)"`, then `"$SELF/wiki-ingest-dupcheck"` and `"$SELF/../assets/wiki-CLAUDE.md"` — rather than assuming they're on PATH. When invoked via PATH, `$0` is the resolved path, so this holds.
- The plugin install path itself is treated as ephemeral (it changes on update); nothing writes into it.

Because the PATH-injection behavior is documented but not something we can unit-test in isolation, the **end-to-end test (install the plugin, run `/wiki-ingest`) is the confirmation** that this mechanism works on the real machine.

## Configuration contract

Two environment variables, read by every script:

| Var | Required | Default | Meaning |
|-----|----------|---------|---------|
| `WIKI_PATH` | yes | — (exit with instructions if unset/not a dir) | absolute path to the Obsidian wiki directory |
| `WIKI_INGEST_CLI` | no | `claude` | the LLM CLI invoked for analysis/writing |

Scripts resolve their own directory via `$(cd "$(dirname "$0")" && pwd)` so `wiki-ingest-run` can call its sibling `wiki-ingest-dupcheck` and read `../assets/wiki-CLAUDE.md`. The command invokes the scripts by bare name (they are on PATH via `bin/`; see "Script location" above).

## Port changes from the current scripts

Everything ports as-is except:

- **`WIKI`** is sourced from `$WIKI_PATH` (was a hardcoded iCloud path), with the required-check described above.
- **LLM invocation** uses `$WIKI_INGEST_CLI` without skip-permissions (was the hardcoded `dscldy` path).
- **Commit author** generalizes from `dscldy <dscldy@deepseek>` to `wiki-ingest <noreply@wiki-ingest>`.
- **Script names/paths**: `ingest.sh`→`bin/wiki-ingest-run`, `dup-check.sh`→`bin/wiki-ingest-dupcheck`, new `bin/wiki-ingest-setup`; sibling/asset lookups resolve via `$(dirname "$0")`.
- Reaping, dup canonicalization (protocol/www/fragment/tracking-param/host-case, x.com≡twitter≡xcancel), merge retry, best-effort push, exit codes 2/3, the CWD-and-prompt recursion guards, and `--dry-run` are **unchanged**.

## wiki-ingest-setup (setup-wiki bootstrap)

Idempotent bootstrap of `$WIKI_PATH`; only creates what is missing, never overwrites existing files (reads its template as `$(dirname "$0")/../assets/wiki-CLAUDE.md`):

1. `git init -b main` if not already a repo. Optional `--gitdir <path>` to place the `.git` outside the wiki dir (the keep-git-out-of-iCloud trick).
2. Write `.gitattributes` with `index.md merge=union` and `log.md merge=union`.
3. Seed from templates/empties: `CLAUDE.md` (from `assets/wiki-CLAUDE.md`), `index.md`, `log.md`, `raw/.gitkeep`.
4. Initial commit if the repo has no commits yet.

## Command (commands/wiki-ingest.md)

Same orchestration flow as the current command: preprocess → dup-check → classify (repo vs regular) → background `wiki-ingest-run` per URL → collect exit-3 failures → surf fallback → report. The surf section is retained under an "Optional: browser fallback (requires the `surf` CLI)" heading, with the note that without surf, unfetchable URLs are recorded in `ingest-queue.md`. Absolute `~/Source/wiki/...` paths become bare `bin/` command names (`wiki-ingest-run`, `wiki-ingest-dupcheck`).

## Marketplace integration

Add an entry to `powerups-marketplace/.claude-plugin/marketplace.json` (`source: url → github.com/njt/powerups-wiki-ingest.git`, v1.0.0, strict) and a README section, then commit and push the marketplace repo.

## Nat's migration

- Add to `~/.claude/settings.json` env: `WIKI_PATH` = the iCloud wiki path, `WIKI_INGEST_CLI` = the dscldy wrapper path.
- Retire the `~/.claude/commands/wiki-ingest.md` symlink (the plugin owns `/wiki-ingest`).
- Leave `~/Source/wiki` as an archive with a short "moved to powerups-wiki-ingest" note in its README.
- Interactive `/plugin install` is the one step Nat runs himself.

## Testing

- **wiki-ingest-setup** end-to-end against a fresh scratch directory (fresh init; re-run to prove idempotence; `--gitdir` variant).
- **wiki-ingest-dupcheck** and **wiki-ingest-run --dry-run** against the real wiki through the new `WIKI_PATH`/`WIKI_INGEST_CLI` plumbing, confirming zero-trace.
- One **real URL** ingested end-to-end through the installed plugin — this run also confirms the `bin/`-on-PATH mechanism works on the real machine (the load-bearing item that can't be unit-tested).

## Out of scope

- Rewriting dscldy or changing Nat's keychain/skip-permissions setup.
- CI, changelog, or versioning automation beyond the manual template checklist.
- Any change to the wiki *content* repo (`njt/wiki`).
