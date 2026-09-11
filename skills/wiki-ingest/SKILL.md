---
name: wiki-ingest
description: Ingest a URL or GitHub repo into an Obsidian wiki — fetches the source, analyzes it with an LLM CLI, and files it as a verbatim archive, a précis tagged with one or two topics from the wiki's fixed topic list, and a cross-linked note, with index + append-only log updates. Use when the user asks to ingest, clip, or file a web page or GitHub repo into their wiki, or to backfill a missing summary. Handles duplicate detection, repo deep-analysis, batch ingestion, and a browser fallback for JS-heavy/unfetchable pages.
argument-hint: <url> [url ...]
allowed-tools: Bash, Read
---

# wiki-ingest — Ingest a source into the Obsidian wiki

This skill is a port of the `powerups-wiki-ingest` Claude Code plugin. The
plumbing is unchanged: all the real work lives in bundled scripts in this
plugin's `bin/` directory. **Do not write your own worktree/merge/commit bash** —
call the scripts.

## Setup (once per session that uses this skill)

The scripts are NOT on PATH by default. Derive `bin/` from this skill's own
directory — Claude Code replaces `${CLAUDE_SKILL_DIR}` with the absolute path of
the directory holding this `SKILL.md`, and `bin/` sits two levels above it. Then
confirm the two required environment variables:

```bash
WIKI_INGEST_BIN="${CLAUDE_SKILL_DIR}/../../bin"
if [ ! -x "$WIKI_INGEST_BIN/wiki-ingest-run" ]; then
  # Skill copied out of the plugin, or the substitution did not happen.
  # Fall back to an install that is already on PATH.
  WIKI_INGEST_BIN="$(command -v wiki-ingest-run 2>/dev/null)"
  WIKI_INGEST_BIN="${WIKI_INGEST_BIN%/*}"
fi
if [ -z "$WIKI_INGEST_BIN" ] || [ ! -x "$WIKI_INGEST_BIN/wiki-ingest-run" ]; then
  echo "wiki-ingest: cannot locate the plugin's bin/ directory." >&2
  echo "  Looked in ${CLAUDE_SKILL_DIR}/../../bin, then on PATH." >&2
  echo "  Enable the powerups-wiki-ingest plugin (that puts bin/ on PATH), or" >&2
  echo "  add its bin/ to PATH by hand, then re-run this block." >&2
  echo "  STOP HERE — do NOT hand-roll the fetch/worktree/merge work instead." >&2
  exit 1
fi
export PATH="$WIKI_INGEST_BIN:$PATH"

: "${WIKI_PATH:?Set WIKI_PATH to your Obsidian wiki directory (the one with raw/ summary/ note/ topic/ topics.md index.md log.md)}"
: "${WIKI_INGEST_CLI:=claude}"   # the nested LLM CLI that writes the pages; must support -p --allowedTools --add-dir
```

If a later `bash` call reports `wiki-ingest-run: command not found`, that shell
did not inherit the export — re-run this block at the top of that same call.

**Configuration:**

- `WIKI_PATH` (required) — the wiki directory. If unset, every script stops with
  instructions; tell the user to set it and run `wiki-ingest-setup` once if the
  wiki doesn't yet exist.
- `WIKI_INGEST_CLI` (optional, default `claude`) — the CLI the pipeline shells
  out to *for the page-writing analysis*. It must accept `-p`, `--allowedTools`,
  and `--add-dir`. `claude` works. `pi` does NOT (it lacks `--allowedTools`/
  `--add-dir`), so leave this as `claude` or point it at a wrapper.
- `trafilatura` must be installed (`pipx install trafilatura`) — the fetch step
  is `curl | trafilatura` (readability extraction, no browser).

Sanity check before first run:

```bash
command -v wiki-ingest-run wiki-ingest-dupcheck wiki-ingest-setup trafilatura "$WIKI_INGEST_CLI"
```

## The scripts (call these, don't reimplement)

- `wiki-ingest-run [options] <url>` — the whole ingest: reaps stale branches,
  dup-checks, worktree, fetch + extract (`curl` into `trafilatura`, staged
  verbatim to `raw/<slug>.md`), LLM analysis, commit, merge (retry), best-effort
  push, cleanup. The LLM never fetches — it only reads the staged archive.
- `wiki-ingest-dupcheck <url>` — deterministic duplicate check. Exit 0 =
  duplicate (prints raw file, title, date); exit 1 = clean.
- `wiki-ingest-setup [--gitdir <path>]` — one-time: bootstrap a new wiki at
  `$WIKI_PATH`.
- `wiki-ingest-run --summary-only <slug|url>` — backfill ONE missing
  `summary/<slug>.md` from an existing `raw/<slug>.md`; fetches/creates nothing
  else.
- Curation (read-only, deterministic, no LLM/network): `wiki-curate {index,audit,
  topics,themes,sources,dirty,classify,gaps,fixme}`, `wiki-compile --theme "X"`,
  `wiki-recompile --since <ref>`, `wiki-review --branch <branch>`, and
  `wiki-retag --topic <slug>` (LLM; re-files summaries after `topics.md` is
  edited). `wiki-meta` reads and writes summary frontmatter and `topics.md`.
  `wiki-migrate-topics` is the one-off 2.x → 3.0 migration. Use these when the
  user asks to curate, audit, retag, or rebuild the wiki — they are NOT part of
  a normal ingest.

Topics are a fixed list in `topics.md` at the wiki root (with `misc`). Each
ingest files the source under one or two of them; nothing an ingest does can
create a topic page. If the user wants a new topic, that is an edit to
`topics.md` followed by `wiki-retag` and `wiki-recompile`, not an ingest.

### `wiki-ingest-run` exit codes

- **0** ingested (or dry-run OK, or summary backfilled)
- **2** duplicate — already ingested (skipped); use `--force` to re-ingest
- **3** no changes — extraction returned nothing usable (login wall / bot
  check / JS shell); retry with the surf fallback below
- **64** usage error
- anything else — read stderr

## Your job

You are the orchestrator: preprocess URLs, classify them, invoke the script,
handle failures, report. The script owns all git, all fetching, all LLM calls.

### Step 1: URL preprocessing

Preprocess before dup-checking — an entity-encoded URL won't match its decoded
form in the `raw/` frontmatter.

- **x.com / twitter.com**: replace the domain with `xcancel.com` (same path).
  x.com serves posts through JavaScript so trafilatura gets nothing; xcancel
  mirrors the same content server-rendered.
- **HTML entities**: decode `&amp;` → `&`, `&#39;` → `'`, etc.
- **Skip non-article URLs**: Google searches, GitHub settings pages, product
  listing pages, local network URLs, auth-required dashboards.

### Step 2: Duplicate check

Run `wiki-ingest-dupcheck` on each preprocessed URL. For duplicates, report:
**"Already ingested: *<title>* (fetched <date>). Skip or force re-ingest?"**
Group all duplicates into one question so the user decides in one go. Skip by
default; pass `--force` to `wiki-ingest-run` only if the user says to re-ingest.

```bash
wiki-ingest-dupcheck "<url>"    # rc 0 = dup (prints detail), rc 1 = clean
```

### Step 3: Classify and run

- **GitHub repos** — `github.com/<owner>/<repo>` with no further path segments
  (or only a trailing slash): use `wiki-ingest-run --repo <url>` (shallow-clones
  the repo for deep architectural analysis). URLs like `.../blob/...` or
  `.../tree/...` are NOT repos — treat as regular URLs.
- **Everything else**: `wiki-ingest-run <url>`.

Use a 600-second timeout on every `wiki-ingest-run` call.

```bash
timeout 600 wiki-ingest-run "<url>"                 # regular page
timeout 600 wiki-ingest-run --repo "<github-url>"    # repo deep-analysis
```

### Batch ingestion (multiple URLs)

One `timeout 600 wiki-ingest-run "<url>"` per URL, run concurrently. How you get
that concurrency depends on the host:

- **Host supports backgrounded bash calls (Claude Code)** — launch each URL as a
  **separate background Bash call**: one `Bash(run_in_background=true)` per URL.
  Wait for all the background tasks before moving on.
- **Host does not (pi)** — emit **one `bash` tool call per URL in a single
  response block**; pi executes tool calls in the same block in parallel.

Either way this is safe by design: each ingest gets its own git worktree, merges
retry on lock contention, and `merge=union` on `index.md`/`log.md` prevents
content conflicts.

Do NOT write a monolithic batch script with URL arrays, parallel subshells, and
a shared wait/merge loop — that path has burned the upstream plugin before (bash
3.2 compat, PID tracking, orphaned processes).

After the batch finishes, collect the exit-3 URLs (nothing extractable) and
retry those with surf (below).

### Optional: browser fallback for unfetchable URLs (requires the surf CLI)

This step needs the `surf` browser-automation CLI. If it isn't installed, skip
it — report the unfetchable URLs and record them in `ingest-queue.md` at the
wiki root instead.

The pipeline fetches with `curl` and extracts with `trafilatura`, so it only
ever sees server-rendered HTML — no browser, no JavaScript. Some URLs therefore
yield nothing and exit 3 (JS-heavy pages, anti-bot protection, Reddit, Bluesky,
archive.ph, paywalled sites). For those, grab rendered content with `surf`,
then re-run `wiki-ingest-run` pointing at the grab. For Reddit URLs, skip
straight to surf — reddit.com renders client-side, so extraction never gets
anything.

#### Phase 1: Grab content via surf

```bash
GRAB_DIR="/tmp/surf-grabs"
mkdir -p "$GRAB_DIR"

# Create a dedicated tab and take its ID straight from the output — never
# guess from `surf tab list | tail -1`, which can resolve to one of the
# user's real tabs and navigate it away. IDs print as floats in scientific
# notation (e.g. 3.59286798e+08): convert with printf %.0f — do NOT
# sed-strip at the dot (that yields "3").
TAB_ID=$(surf tab new --args-json '{"url":"about:blank"}' 2>/dev/null | grep "tabId:" | awk '{printf "%.0f\n", $NF}')
if [ -z "$TAB_ID" ]; then
  echo "surf tab creation failed — Chrome running? extension loaded in the active profile? tab id parsed out of the 'tabId:' line?" >&2
  # bail out of the surf fallback entirely; do NOT fall back to grabbing an existing tab
  exit 1
fi

# Sequential — reuse this one tab for every failed URL in the batch.
# Poll until the render stops being thin instead of a fixed sleep
# (JS-heavy pages can take 20s+). Sleep BEFORE grabbing so the last
# iteration's wait still contributes a capture.
surf navigate --url "<FAILED_URL>" --tab-id "$TAB_ID" 2>/dev/null
n=0
while [ $n -lt 8 ]; do
  sleep 4
  surf page text --tab-id "$TAB_ID" > "$GRAB_DIR/url-slug.txt" 2>/dev/null
  [ "$(wc -c < "$GRAB_DIR/url-slug.txt")" -gt 10000 ] && break
  n=$((n+1))
done

# After the whole batch is grabbed, close the tab:
surf tab close --tab-id "$TAB_ID"
```

Sanity-check the grab: real article text, not a Cloudflare interstitial. Some
legitimate pages ARE short (marketing landing pages) — judge by content, not
just size. If it's genuinely thin, grab a docs/features subpage too and
concatenate the grabs into one file before ingesting.

#### Phase 2: Ingest with the saved content

```bash
wiki-ingest-run --content "$GRAB_DIR/url-slug.txt" "<FAILED_URL>"
```

#### Notes on surf

- `surf` controls Chrome via a Go native host + extension. Chrome must be
  running with the extension loaded.
- Commands use spaces for subcommands: `surf tab list`, `surf page text`,
  `surf tab new`.
- Tab IDs can become invalid if Chrome closes/recreates tabs during navigation
  (e.g. redirects). If a tab ID stops working, create a new tab with
  `surf tab new --args-json '{"url":"about:blank"}'`.
- The `navigate` command requires `--url` (not positional):
  `surf navigate --url "https://..." --tab-id <id>`.
- YouTube URLs via Bluesky redirects: decode the redirect URL and use the
  direct `youtu.be` link.

## Report

Tell the user: the note's title, the topics it was filed under (read `topics:`
from `summary/<slug>.md`; the ingest output says if the model's choice was
repaired), key cross-links, and the sharp take from the LLM's output. Note any URLs that ended up unfetchable
even via surf — add those to `ingest-queue.md` at the wiki root with the
failure reason.
