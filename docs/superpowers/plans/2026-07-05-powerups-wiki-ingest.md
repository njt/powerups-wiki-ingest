# powerups-wiki-ingest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repackage the personal wiki-ingest command + scripts as a public, marketplace-installable Powerups plugin (`powerups-wiki-ingest`) that runs against any user's Obsidian wiki via `WIKI_PATH`/`WIKI_INGEST_CLI` env config.

**Architecture:** A standard `powerups-*` plugin. Three bash scripts live in `bin/` (added to the Bash tool's PATH when the plugin is enabled — the documented mechanism, since `${CLAUDE_PLUGIN_ROOT}` is broken in command markdown per issue #9354). The command file is orchestration only; it invokes the `bin/` scripts by bare name. Scripts are ported near-verbatim from `~/Source/wiki/{ingest.sh,dup-check.sh}` with config generalized off hardcoded paths.

**Tech Stack:** bash 3.2 (macOS-compatible), git worktrees, Claude Code plugin format (plugin.json + marketplace.json), an LLM CLI (`claude` by default).

**Reference source (port FROM these, they are the tested originals):**
- `~/Source/wiki/ingest.sh` → becomes `bin/wiki-ingest-run`
- `~/Source/wiki/dup-check.sh` → becomes `bin/wiki-ingest-dupcheck`
- `~/Source/wiki/wiki-ingest.md` → becomes `commands/wiki-ingest.md`
- The wiki's own `CLAUDE.md` (schema) → becomes `assets/wiki-CLAUDE.md`

**Spec:** `docs/superpowers/specs/2026-07-05-powerups-wiki-ingest-design.md`

**Working location:** all work happens in a NEW repo at `~/Source/Powerups/powerups-wiki-ingest/`. Do not modify `~/Source/wiki` except the final archive note (Task 11).

---

### Task 1: Scaffold the repo

**Files:**
- Create: `~/Source/Powerups/powerups-wiki-ingest/` (dir tree)

- [ ] **Step 1: Make the directory tree and init git**

```bash
mkdir -p ~/Source/Powerups/powerups-wiki-ingest/{.claude-plugin,commands,bin,assets}
cd ~/Source/Powerups/powerups-wiki-ingest
git init -b main
```

- [ ] **Step 2: Add .gitignore**

Create `~/Source/Powerups/powerups-wiki-ingest/.gitignore`:

```
.DS_Store
```

- [ ] **Step 3: Commit the skeleton**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add .gitignore
git commit -m "Scaffold powerups-wiki-ingest repo"
```

---

### Task 2: Plugin metadata

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write plugin.json**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "powerups-wiki-ingest",
  "description": "Fetch a URL (or GitHub repo), analyze it with an LLM, and file it as cross-linked pages in an Obsidian wiki",
  "version": "1.0.0",
  "author": {
    "name": "Nat Torkington",
    "email": "nat@torkington.com"
  },
  "homepage": "https://github.com/njt/powerups-wiki-ingest",
  "repository": "https://github.com/njt/powerups-wiki-ingest",
  "license": "MIT",
  "keywords": ["obsidian", "wiki", "ingest", "knowledge-base", "web-clipping"]
}
```

- [ ] **Step 2: Write the local-dev marketplace.json**

Create `.claude-plugin/marketplace.json`:

```json
{
  "name": "powerups-wiki-ingest-dev",
  "description": "Development marketplace for the wiki-ingest plugin",
  "owner": {
    "name": "Nat Torkington",
    "email": "nat@torkington.com"
  },
  "plugins": [
    {
      "name": "powerups-wiki-ingest",
      "description": "Fetch a URL (or GitHub repo), analyze it with an LLM, and file it as cross-linked pages in an Obsidian wiki",
      "version": "1.0.0",
      "source": "./"
    }
  ]
}
```

- [ ] **Step 3: Validate JSON and commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
python3 -m json.tool .claude-plugin/plugin.json >/dev/null && echo "plugin.json OK"
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null && echo "marketplace.json OK"
git add .claude-plugin/
git commit -m "Add plugin.json and dev marketplace.json"
```

Expected: both print `OK`.

---

### Task 3: assets/wiki-CLAUDE.md (schema template)

**Files:**
- Create: `assets/wiki-CLAUDE.md`

This is the page-format/conventions file the LLM reads via `--add-dir`. It is a generalized copy of the current wiki's `CLAUDE.md` (no personal section names).

- [ ] **Step 1: Write assets/wiki-CLAUDE.md**

Create `assets/wiki-CLAUDE.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add assets/wiki-CLAUDE.md
git commit -m "Add wiki schema template"
```

---

### Task 4: bin/wiki-ingest-dupcheck

**Files:**
- Create: `bin/wiki-ingest-dupcheck` (port of `~/Source/wiki/dup-check.sh`)

- [ ] **Step 1: Copy the source verbatim**

```bash
cp ~/Source/wiki/dup-check.sh ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-dupcheck
```

- [ ] **Step 2: Apply the config edit**

In `bin/wiki-ingest-dupcheck`, replace the WIKI line. Change:

```bash
WIKI="${WIKI:-$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Nat/Wiki}"
```

to:

```bash
WIKI="${WIKI_PATH:-}"
if [ -z "$WIKI" ] || [ ! -d "$WIKI" ]; then
  echo "wiki-ingest-dupcheck: set WIKI_PATH to your wiki directory (currently: '${WIKI_PATH:-unset}')" >&2
  exit 64
fi
```

- [ ] **Step 3: Update the usage string and header comment**

Change the two `dup-check.sh` mentions (header comment line 2 and the `usage:` echo) to `wiki-ingest-dupcheck`.

- [ ] **Step 4: chmod, syntax-check, and functional-test**

```bash
chmod +x ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-dupcheck
/bin/bash -n ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-dupcheck && echo "syntax OK"
# Point it at the real wiki via the new env var and confirm a known dup + a clean URL:
WIKI_PATH="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Nat/Wiki" \
  ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-dupcheck "https://youtu.be/ef568d0CrRY"; echo "dup exit=$? (expect 0)"
WIKI_PATH="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Nat/Wiki" \
  ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-dupcheck "https://example.com/nope"; echo "clean exit=$? (expect 1)"
# Confirm the required-var guard:
~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-dupcheck "https://example.com/x"; echo "no-var exit=$? (expect 64)"
```

Expected: syntax OK; dup exit=0 with file/title/date printed; clean exit=1 silent; no-var exit=64 with the setup message.

- [ ] **Step 5: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-dupcheck
git commit -m "Add wiki-ingest-dupcheck (WIKI_PATH-configured dup check)"
```

---

### Task 5: bin/wiki-ingest-run

**Files:**
- Create: `bin/wiki-ingest-run` (port of `~/Source/wiki/ingest.sh`)

- [ ] **Step 1: Copy the source verbatim**

```bash
cp ~/Source/wiki/ingest.sh ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run
```

- [ ] **Step 2: Config edit — WIKI from WIKI_PATH**

Replace:

```bash
WIKI="${WIKI:-$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Nat/Wiki}"
DSCLDY="$HOME/Source/AI Experiments/dscldy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
```

with:

```bash
WIKI="${WIKI_PATH:-}"
if [ -z "$WIKI" ] || [ ! -d "$WIKI" ]; then
  echo "wiki-ingest-run: set WIKI_PATH to your wiki directory (currently: '${WIKI_PATH:-unset}'). Run wiki-ingest-setup first if you haven't created it." >&2
  exit 64
fi
CLI="${WIKI_INGEST_CLI:-claude}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
```

- [ ] **Step 3: Sibling dup-check reference**

Replace both occurrences of `"$SCRIPT_DIR/dup-check.sh"` with `"$SCRIPT_DIR/wiki-ingest-dupcheck"`, and in the error message change `dup-check.sh missing` to `wiki-ingest-dupcheck missing`.

- [ ] **Step 4: LLM invocation — use $CLI, no hardcoded skip-permissions**

Replace both dscldy invocation lines. Change each:

```bash
  cat <<INGEST_EOF | (cd "$WT" && "$DSCLDY" -p --allowedTools "Read,Write,Edit,Bash,WebFetch,WebSearch" --add-dir "$WT") || dscldy_failed
```

to:

```bash
  cat <<INGEST_EOF | (cd "$WT" && "$CLI" -p --allowedTools "Read,Write,Edit,Bash,WebFetch,WebSearch" --add-dir "$WT") || llm_failed
```

- [ ] **Step 5: Rename the failure helper and update its comment**

Replace:

```bash
# NB: the dscldy wrapper passes --dangerously-skip-permissions, which
# auto-approves every tool call — the --allowedTools list here is advisory,
# not a guardrail. See the comment in dscldy itself.
#
# A dscldy failure must exit 1: exit codes 2 and 3 are reserved contract
# values (duplicate / no-changes) and dscldy's own exit code must never be
# mistaken for them.
dscldy_failed() {
  echo "ingest.sh: dscldy failed for $INGEST_URL" >&2
  exit 1
}

# dscldy MUST run with the worktree as CWD: with the caller's CWD it picks up
# whatever project CLAUDE.md lives there (e.g. the wiki-ingest repo's, which
# documents this whole pipeline) and starts recursively orchestrating —
# observed 2026-07-05: a dscldy whose fetch failed ran surf and re-invoked
# ingest.sh itself.
```

with:

```bash
# $CLI (default: claude) runs with --allowedTools as a real guardrail — no
# --dangerously-skip-permissions here. If a user points WIKI_INGEST_CLI at a
# wrapper that adds skip-permissions internally, that is their choice.
#
# An LLM failure must exit 1: exit codes 2 and 3 are reserved contract values
# (duplicate / no-changes) and the CLI's own exit code must never be mistaken
# for them.
llm_failed() {
  echo "wiki-ingest-run: LLM CLI ($CLI) failed for $INGEST_URL" >&2
  exit 1
}

# $CLI MUST run with the worktree as CWD: with the caller's CWD it picks up
# whatever project CLAUDE.md lives there and can start recursively
# orchestrating the pipeline (observed 2026-07-05). The in-prompt guardrails
# below reinforce this.
```

- [ ] **Step 6: Commit author**

Replace all three `--author="dscldy <dscldy@deepseek>"` occurrences with `--author="wiki-ingest <noreply@wiki-ingest>"`.

- [ ] **Step 7: Neutralize prompt self-references**

In the two heredoc prompts, replace the recursion-guard sentence. Change both:

```
Do NOT run ingest.sh or dup-check.sh, do NOT use surf or any browser automation, and do NOT run git branch/commit/merge/push — the caller owns all orchestration, commits, and retries.
```

to:

```
Do NOT run the wiki-ingest scripts, do NOT use surf or any browser automation, and do NOT run git branch/commit/merge/push — the caller owns all orchestration, commits, and retries.
```

- [ ] **Step 8: Update the top-of-file usage/header comment**

Change the header's `ingest.sh [options]` and the `usage()` echo `usage: ingest.sh ...` to `wiki-ingest-run`. Change the line `# file, wiki page, index, log), the script commits...` reference to `dscldy` (in the top comment "dscldy does all the work") to "the LLM CLI does all the work".

- [ ] **Step 9: chmod, syntax-check, shellcheck if present**

```bash
chmod +x ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run
/bin/bash -n ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run && echo "syntax OK"
command -v shellcheck >/dev/null && shellcheck -s bash ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run || echo "shellcheck not installed — skipped"
```

Expected: syntax OK.

- [ ] **Step 10: Functional test — dry-run against the real wiki, zero trace**

```bash
WIKI="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Nat/Wiki"
BEFORE=$(git -C "$WIKI" rev-parse main)
WIKI_PATH="$WIKI" ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run --dry-run "https://example.com/powerup-plan-test"; echo "rc=$?"
AFTER=$(git -C "$WIKI" rev-parse main)
[ "$BEFORE" = "$AFTER" ] && echo "main unchanged" || echo "MAIN MOVED"
git -C "$WIKI" branch --list 'ingest-*' 'throwaway-*'
```

Expected: `DRY-RUN OK: ...`, rc=0, `main unchanged`, and no leftover branches printed (a live concurrent ingest branch, if any, is fine — just none named throwaway-*).

- [ ] **Step 11: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-run
git commit -m "Add wiki-ingest-run (WIKI_PATH + WIKI_INGEST_CLI, no hardcoded paths)"
```

---

### Task 6: bin/wiki-ingest-setup

**Files:**
- Create: `bin/wiki-ingest-setup` (new)

- [ ] **Step 1: Write the script**

Create `bin/wiki-ingest-setup`:

```bash
#!/bin/bash
# wiki-ingest-setup [--gitdir <path>] — bootstrap an Obsidian wiki for ingestion.
#
# Idempotent: only creates what is missing, never overwrites existing files.
# Sets up the git repo, the merge=union gitattributes, and seed files.
#
# Reads WIKI_PATH for the target directory. --gitdir places the .git outside
# the wiki dir (useful when the wiki lives in a cloud-synced folder).
#
# Targets bash 3.2 (macOS /bin/bash).

set -eu

WIKI="${WIKI_PATH:-}"
if [ -z "$WIKI" ]; then
  echo "wiki-ingest-setup: set WIKI_PATH to the wiki directory you want to create/bootstrap" >&2
  exit 64
fi

GITDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --gitdir) [ $# -ge 2 ] || { echo "wiki-ingest-setup: --gitdir needs a path" >&2; exit 64; }; GITDIR="$2"; shift 2 ;;
    *) echo "wiki-ingest-setup: unknown argument: $1" >&2; exit 64 ;;
  esac
done

SELF="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SELF/../assets/wiki-CLAUDE.md"

mkdir -p "$WIKI/raw"

# git init (with optional external gitdir)
if [ ! -e "$WIKI/.git" ]; then
  if [ -n "$GITDIR" ]; then
    mkdir -p "$GITDIR"
    git init -b main --separate-git-dir "$GITDIR" "$WIKI"
  else
    git init -b main "$WIKI"
  fi
fi

# merge=union so parallel ingests never conflict on the append-only files
if [ ! -f "$WIKI/.gitattributes" ]; then
  printf 'index.md merge=union\nlog.md merge=union\n' > "$WIKI/.gitattributes"
fi

# Seed files (only if absent)
[ -f "$WIKI/CLAUDE.md" ] || cp "$TEMPLATE" "$WIKI/CLAUDE.md"
[ -f "$WIKI/index.md" ]  || printf '# Wiki Index\n\n' > "$WIKI/index.md"
[ -f "$WIKI/log.md" ]    || printf '# Wiki Log\n\n' > "$WIKI/log.md"
[ -f "$WIKI/raw/.gitkeep" ] || : > "$WIKI/raw/.gitkeep"

# Initial commit if the repo has no commits yet
if ! git -C "$WIKI" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$WIKI" add -A
  git -C "$WIKI" commit -q -m "Bootstrap wiki" || true
fi

echo "wiki-ingest-setup: $WIKI is ready (branch: $(git -C "$WIKI" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?'))"
```

- [ ] **Step 2: chmod and syntax-check**

```bash
chmod +x ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-setup
/bin/bash -n ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-setup && echo "syntax OK"
```

- [ ] **Step 3: Functional test — fresh init, idempotence, and a real ingest through it**

```bash
SCRATCH="/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad/wiki-setup-test"
rm -rf "$SCRATCH"
WIKI_PATH="$SCRATCH" ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-setup
ls -a "$SCRATCH"; cat "$SCRATCH/.gitattributes"
git -C "$SCRATCH" log --oneline
# Idempotence: second run must not error or duplicate
WIKI_PATH="$SCRATCH" ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-setup && echo "idempotent OK"
# --gitdir variant
SCRATCH2="$SCRATCH-ext"; GD="$SCRATCH-gitdir"; rm -rf "$SCRATCH2" "$GD"
WIKI_PATH="$SCRATCH2" ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-setup --gitdir "$GD"
test -f "$SCRATCH2/.git" && echo "--gitdir OK (.git is a file pointer)"
```

Expected: first run reports ready and creates CLAUDE.md/index.md/log.md/raw/.gitattributes with one commit; second run reports ready again, no error; `--gitdir` makes `.git` a file pointing at the external dir.

- [ ] **Step 4: End-to-end sanity — ingest one URL into the scratch wiki**

```bash
SCRATCH="/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad/wiki-setup-test"
# Use dscldy as the CLI so this doesn't burn Claude quota; any working CLI proves the plumbing.
WIKI_PATH="$SCRATCH" WIKI_INGEST_CLI="$HOME/Source/AI Experiments/dscldy" \
  ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run "https://example.com/" ; echo "rc=$?"
git -C "$SCRATCH" log --oneline | head -3
ls "$SCRATCH"/*.md | head
```

Expected: `INGESTED: ...` (push-failed is fine — no remote), a new commit, and at least one topic page written. (If example.com yields nothing useful, exit 3 is acceptable — the point is the scripts wire together end-to-end under the new env.)

- [ ] **Step 5: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-setup
git commit -m "Add wiki-ingest-setup bootstrap script"
```

---

### Task 7: commands/wiki-ingest.md

**Files:**
- Create: `commands/wiki-ingest.md` (adapt from `~/Source/wiki/wiki-ingest.md`)

- [ ] **Step 1: Copy the current command as a base**

```bash
cp ~/Source/wiki/wiki-ingest.md ~/Source/Powerups/powerups-wiki-ingest/commands/wiki-ingest.md
```

- [ ] **Step 2: Rewrite the script-reference block at the top**

Replace the opening block (from "All the plumbing lives in checked-in scripts" through the exit-code line) with:

```markdown
All the plumbing lives in bundled scripts on your PATH (this plugin's `bin/` is added to PATH while enabled) — do NOT write your own worktree/merge/commit bash:

- `wiki-ingest-run [options] <url>` — the whole ingest: reaps stale branches, dup-checks, worktree, LLM analysis, commit, merge (retry), best-effort push, cleanup.
- `wiki-ingest-dupcheck <url>` — deterministic duplicate check. Exit 0 = duplicate (prints raw file, title, date), exit 1 = clean.
- `wiki-ingest-setup [--gitdir <path>]` — one-time: bootstrap a new wiki at `$WIKI_PATH`.

**Configuration (required):** `WIKI_PATH` must point at the wiki directory. If it is unset the scripts stop with instructions — tell the user to set it (and to run `wiki-ingest-setup` once if the wiki doesn't exist yet). `WIKI_INGEST_CLI` optionally overrides the LLM CLI (default `claude`).

`wiki-ingest-run` exit codes: **0** ingested; **2** duplicate (skipped); **3** no changes — the fetch failed, retry with surf (below). Anything else: read stderr.
```

- [ ] **Step 3: Replace every `ingest.sh`/`dup-check.sh` path reference**

Replace throughout the file:
- `$HOME/Source/wiki/ingest.sh` and `~/Source/wiki/ingest.sh` → `wiki-ingest-run`
- `$HOME/Source/wiki/dup-check.sh` and `~/Source/wiki/dup-check.sh` → `wiki-ingest-dupcheck`
- `"$HOME/Source/wiki/ingest.sh" --content ...` (surf Phase 2) → `wiki-ingest-run --content ...`
- bare `ingest.sh`/`dup-check.sh` in prose → `wiki-ingest-run`/`wiki-ingest-dupcheck`

- [ ] **Step 4: Mark the surf section optional**

Change the heading `## Surf fallback for unfetchable URLs` to `## Optional: browser fallback for unfetchable URLs (requires the surf CLI)` and add this sentence immediately under it:

```markdown
This step needs the `surf` browser-automation CLI. If it isn't installed, skip it — report the unfetchable URLs and record them in `ingest-queue.md` at the wiki root instead.
```

- [ ] **Step 5: Verify no stale references remain**

```bash
grep -nE "ingest\.sh|dup-check\.sh|Source/wiki|dscldy|CLAUDE_PLUGIN_ROOT" ~/Source/Powerups/powerups-wiki-ingest/commands/wiki-ingest.md; echo "grep exit=$? (1 = clean, no matches)"
```

Expected: exit 1 (no matches). If any line prints, fix it.

- [ ] **Step 6: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add commands/wiki-ingest.md
git commit -m "Add wiki-ingest command (orchestration over bin/ scripts)"
```

---

### Task 8: README, CLAUDE.md, LICENSE

**Files:**
- Create: `README.md`, `CLAUDE.md`, `LICENSE`

- [ ] **Step 1: Write LICENSE (MIT)**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
curl -fsSL https://raw.githubusercontent.com/njt/powerups-template/main/LICENSE -o LICENSE 2>/dev/null || true
# If the download failed or produced a non-MIT file, write MIT with Nat's name:
grep -q "MIT" LICENSE 2>/dev/null || cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026 Nat Torkington

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
echo "LICENSE ready"
```

- [ ] **Step 2: Write README.md**

Create `README.md`:

```markdown
# powerups-wiki-ingest

A [Claude Code](https://claude.ai/code) plugin: feed it a URL or GitHub repo, and it fetches the source, analyzes it with an LLM, and files a cross-linked page into your Obsidian wiki — updating an index and an append-only log as it goes.

## What it does

- **Regular web pages** — fetches content, saves a raw source file, writes a topic page (precis, quotes, themes, opinionated analysis), updates the index and log.
- **GitHub repos** — shallow-clones the repo and does a deep architectural read (5–10 source files) before writing.
- **JS-heavy / bot-protected pages** — optional browser fallback via the [`surf`](https://github.com/nat/surf) CLI when plain fetch can't get the content.

Each ingest runs in an isolated git worktree, so many URLs process in parallel safely (`merge=union` on the index and log prevents conflicts).

## Install

### Via Powerups Marketplace (recommended)

```
/plugin marketplace add njt/powerups-marketplace
/plugin install powerups-wiki-ingest@powerups-marketplace
```

### Manual

```bash
git clone https://github.com/njt/powerups-wiki-ingest.git
/plugin marketplace add ./powerups-wiki-ingest
/plugin install powerups-wiki-ingest@powerups-wiki-ingest-dev
```

## Configuration

Set these in your Claude Code environment (e.g. `~/.claude/settings.json` under `env`):

| Variable | Required | Default | Meaning |
|----------|----------|---------|---------|
| `WIKI_PATH` | yes | — | absolute path to your Obsidian wiki directory |
| `WIKI_INGEST_CLI` | no | `claude` | the LLM CLI used for analysis and writing |

First time? Create the wiki with one command:

```bash
WIKI_PATH=/path/to/wiki wiki-ingest-setup
```

(Add `--gitdir /path/outside/cloud` to keep the `.git` directory out of a cloud-synced folder.)

## Usage

```
/wiki-ingest https://example.com/some-article
/wiki-ingest https://github.com/owner/repo   # deep repo analysis
```

Pass several URLs at once; each ingests in parallel.

## License

MIT
```

- [ ] **Step 3: Write CLAUDE.md (how to work on this repo)**

Create `CLAUDE.md`:

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add README.md CLAUDE.md LICENSE
git commit -m "Add README, CLAUDE.md, and LICENSE"
```

---

### Task 9: Publish to GitHub

**Files:** none (remote creation)

- [ ] **Step 1: Create the public repo and push**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
gh repo create njt/powerups-wiki-ingest --public --source=. --remote=origin \
  --description "Ingest URLs and GitHub repos into an Obsidian wiki with an LLM" --push
```

- [ ] **Step 2: Verify**

```bash
gh repo view njt/powerups-wiki-ingest --json url,visibility,isPrivate -q '{url:.url,vis:.visibility}'
git -C ~/Source/Powerups/powerups-wiki-ingest log origin/main..main --oneline | wc -l
```

Expected: URL printed, visibility PUBLIC, 0 unpushed commits.

---

### Task 10: Register in powerups-marketplace

**Files:**
- Modify: `powerups-marketplace/.claude-plugin/marketplace.json`
- Modify: `powerups-marketplace/README.md`

- [ ] **Step 1: Clone the marketplace if not local**

```bash
[ -d ~/Source/Powerups/powerups-marketplace ] || gh repo clone njt/powerups-marketplace ~/Source/Powerups/powerups-marketplace
cd ~/Source/Powerups/powerups-marketplace && git pull --quiet
```

- [ ] **Step 2: Add the plugin entry to marketplace.json**

In `~/Source/Powerups/powerups-marketplace/.claude-plugin/marketplace.json`, add this object to the `plugins` array (after the last existing entry):

```json
    {
      "name": "powerups-wiki-ingest",
      "source": {
        "source": "url",
        "url": "https://github.com/njt/powerups-wiki-ingest.git"
      },
      "description": "Ingest URLs and GitHub repos into an Obsidian wiki with an LLM",
      "version": "1.0.0",
      "strict": true
    }
```

- [ ] **Step 3: Validate JSON**

```bash
python3 -m json.tool ~/Source/Powerups/powerups-marketplace/.claude-plugin/marketplace.json >/dev/null && echo "marketplace JSON OK"
```

- [ ] **Step 4: Add a README section**

Append to `~/Source/Powerups/powerups-marketplace/README.md` a short section describing `powerups-wiki-ingest` (one paragraph + the install line `/plugin install powerups-wiki-ingest@powerups-marketplace`), matching the style of the existing plugin sections.

- [ ] **Step 5: Commit and push**

```bash
cd ~/Source/Powerups/powerups-marketplace
git add .claude-plugin/marketplace.json README.md
git commit -m "Add powerups-wiki-ingest"
git push origin main
```

---

### Task 11: Nat's migration + archive note

**Files:**
- Modify: `~/.claude/settings.json` (env vars)
- Delete: `~/.claude/commands/wiki-ingest.md` (the symlink)
- Modify: `~/Source/wiki/README.md` (archive note)

- [ ] **Step 1: Add env vars to settings.json**

Use the update-config skill (or edit directly) to add to `~/.claude/settings.json` under `env`:

```json
"WIKI_PATH": "/Users/gnat/Library/Mobile Documents/iCloud~md~obsidian/Documents/Nat/Wiki",
"WIKI_INGEST_CLI": "/Users/gnat/Source/AI Experiments/dscldy"
```

Validate: `python3 -m json.tool ~/.claude/settings.json >/dev/null && echo OK`.

- [ ] **Step 2: Retire the old command symlink**

```bash
ls -l ~/.claude/commands/wiki-ingest.md   # confirm it is the symlink into ~/Source/wiki
rm ~/.claude/commands/wiki-ingest.md
```

- [ ] **Step 3: Add archive note to ~/Source/wiki/README.md**

Prepend a note to `~/Source/wiki/README.md`:

```markdown
> **Archived (2026-07-05):** the tooling here now lives in the `powerups-wiki-ingest` plugin
> (`~/Source/Powerups/powerups-wiki-ingest`, `github.com/njt/powerups-wiki-ingest`). This repo
> is kept for history. The wiki *content* repo is separate (`njt/wiki`).
```

Commit:

```bash
cd ~/Source/wiki && git add README.md && git commit -m "Archive note: tooling moved to powerups-wiki-ingest"
```

- [ ] **Step 4: Interactive install (Nat runs this)**

This step is Nat's to run in his Claude Code session — the plan cannot do it headlessly:

```
/plugin marketplace add njt/powerups-marketplace
/plugin install powerups-wiki-ingest@powerups-marketplace
```

Then confirm `/wiki-ingest <some-url>` works end-to-end — this is also the confirmation that the `bin/`-on-PATH mechanism functions on the real machine (the load-bearing item).

---

## Notes for the implementer

- Tasks 1–8 are pure file creation in the new repo and can be done by a subagent. Task 9 (gh repo create) and Task 10 (marketplace push) are irreversible-ish publishing steps — do them only after Tasks 1–8 verify clean. Task 11 changes Nat's live config and ends with a step only Nat can run.
- Every script targets bash 3.2. After each script task, `/bin/bash -n` must pass.
- Do not edit the originals in `~/Source/wiki` except Task 11 Step 3.
