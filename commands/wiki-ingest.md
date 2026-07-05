---
name: wiki-ingest
description: Fetch a URL, save it as a wiki source, and create/update wiki pages from it
arguments:
  - name: url
    description: URL to fetch and ingest into the wiki
    required: true
allowed-tools:
  - Bash
---

# /wiki-ingest — Ingest a source into the Obsidian wiki

All the plumbing lives in bundled scripts on your PATH (this plugin's `bin/` is added to PATH while enabled) — do NOT write your own worktree/merge/commit bash:

- `wiki-ingest-run [options] <url>` — the whole ingest: reaps stale branches, dup-checks, worktree, LLM analysis, commit, merge (retry), best-effort push, cleanup.
- `wiki-ingest-dupcheck <url>` — deterministic duplicate check. Exit 0 = duplicate (prints raw file, title, date), exit 1 = clean.
- `wiki-ingest-setup [--gitdir <path>]` — one-time: bootstrap a new wiki at `$WIKI_PATH`.

**Configuration (required):** `WIKI_PATH` must point at the wiki directory. If it is unset the scripts stop with instructions — tell the user to set it (and to run `wiki-ingest-setup` once if the wiki doesn't exist yet). `WIKI_INGEST_CLI` optionally overrides the LLM CLI (default `claude`).

`wiki-ingest-run` exit codes: **0** ingested; **2** duplicate (skipped); **3** no changes — the fetch failed, retry with surf (below). Anything else: read stderr.

Your job is orchestration: preprocess URLs, classify them, invoke the script, handle failures, report.

## Step 1: URL preprocessing

Preprocess before dup-checking — an entity-encoded URL won't match its decoded form in the raw/ frontmatter.

- **x.com / twitter.com**: Replace the domain with `xcancel.com` (same path). WebFetch can't get X content but xcancel.com mirrors it without JS.
- **HTML entities**: Decode `&amp;` → `&`, `&#39;` → `'`, etc.
- **Skip non-article URLs**: Google searches, GitHub settings pages, product listing pages, local network URLs, auth-required dashboards.

## Step 2: Duplicate check

Run `wiki-ingest-dupcheck` on each preprocessed URL. For duplicates, report: **"Already ingested: *<title>* (fetched <date>). Skip or force re-ingest?"** Group all duplicates into one question so the user decides in one go. Skip by default; pass `--force` to wiki-ingest-run only if the user says to re-ingest.

## Step 3: Classify and run

- **GitHub repos** — `github.com/<owner>/<repo>` with no further path segments (or only a trailing slash): use `wiki-ingest-run --repo <url>` (clones the repo for deep architectural analysis). URLs like `.../blob/...` or `.../tree/...` are NOT repos — treat as regular URLs.
- **Everything else**: `wiki-ingest-run <url>`.

Use a 600-second timeout on every wiki-ingest-run call.

### Batch ingestion

For multiple URLs, launch each as a **separate background Bash call** — one `Bash(run_in_background=true)` per URL. This is safe by design: each ingest gets its own worktree, merges retry on lock contention, and `merge=union` on index.md/log.md prevents content conflicts.

Do NOT write a monolithic batch script with URL arrays, parallel subshells, and a shared wait/merge loop — that path has burned us before (bash 3.2 compat, PID tracking, orphaned processes).

Wait for all background tasks, then collect the exit-3 URLs (fetch failed) and retry those with surf.

## Optional: browser fallback for unfetchable URLs (requires the surf CLI)

This step needs the `surf` browser-automation CLI. If it isn't installed, skip it — report the unfetchable URLs and record them in `ingest-queue.md` at the wiki root instead.

Some URLs fail WebFetch (JS-heavy pages, anti-bot protection, Reddit, Bluesky, archive.ph, paywalled sites). For those, grab rendered content with the `surf` browser CLI, then re-run wiki-ingest-run pointing at the grab. For Reddit URLs, skip straight to surf — WebFetch never works on reddit.com.

### Phase 1: Grab content via surf

```bash
GRAB_DIR="/tmp/surf-grabs"
mkdir -p "$GRAB_DIR"

# Create a dedicated tab and take its ID straight from the output — never
# guess from `surf tab list | tail -1`, which can resolve to one of the
# user's real tabs and navigate it away. IDs print as floats in scientific
# notation (e.g. 3.59286798e+08): convert with printf %.0f — do NOT
# sed-strip at the dot (that yields "3").
TAB_ID=$(surf tab new --args-json '{"url":"about:blank"}' 2>/dev/null | grep "tabId:" | awk '{printf "%.0f\n", $2}')
if [ -z "$TAB_ID" ]; then
  echo "surf tab creation failed — Chrome running? extension loaded in the active profile?" >&2
  # bail out of the surf fallback entirely; do NOT fall back to grabbing an existing tab
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

Sanity-check the grab: real article text, not a Cloudflare interstitial. Some legitimate pages ARE short (marketing landing pages) — judge by content, not just size. If it's genuinely thin, grab a docs/features subpage too and concatenate the grabs into one file before ingesting.

### Phase 2: Ingest with the saved content

```bash
wiki-ingest-run --content "$GRAB_DIR/url-slug.txt" "<FAILED_URL>"
```

### Notes on surf

- `surf` controls Chrome via a Go native host + extension. Chrome must be running with the extension loaded.
- Commands use spaces for subcommands: `surf tab list`, `surf page text`, `surf tab new`
- Tab IDs can become invalid if Chrome closes/recreates tabs during navigation (e.g., redirects). If a tab ID stops working, create a new tab with `surf tab new --args-json '{"url":"about:blank"}'`
- The `navigate` command requires `--url` flag (not positional): `surf navigate --url "https://..." --tab-id <id>`
- YouTube URLs via Bluesky redirects: decode the redirect URL and use the direct `youtu.be` link

## Report

Tell the user: wiki page title, index placement, key cross-links, and the sharp take from the LLM's output. Note any URLs that ended up unfetchable even via surf — add those to `ingest-queue.md` at the wiki root with the failure reason.
