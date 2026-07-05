# Archival Layer — Phase 1: Forward Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New ingests produce three tiers — a verbatim archive (`raw/<slug>.md`), a summary (`summary/<slug>.md`), and analysis (`topic/<Title>.md`) — with fetching moved into the script (trafilatura) and an LLM CONTENT/BLOCKED verdict gating what gets kept.

**Architecture:** The script fetches and writes the verbatim `raw/<slug>.md` deterministically (trafilatura → cleaned Markdown; the LLM never retypes it, guaranteeing fidelity). The script also owns the slug so `raw/` and `summary/` stay in sync. The LLM then judges the staged source CONTENT-or-BLOCKED and, if CONTENT, writes `summary/` + `topic/` + index/log; if BLOCKED it deletes `raw/<slug>.md` and writes nothing, which the script reads as exit 3 → surf. A `--verbatim-only` mode writes just `raw/` (Phase 3 reuses it).

**Tech Stack:** bash 3.2, trafilatura (pipx CLI at `~/.local/bin/trafilatura`), git worktrees, an LLM CLI.

**Spec:** `docs/superpowers/specs/2026-07-05-archival-layer-design.md`

**Reference — current engine:** `bin/wiki-ingest-run` (the file being modified). Read it before starting. Key current structure: arg parse (~L48–73), main-branch guard, reap, dup-check, worktree add (~L198), `--content` staging (~L200–203), dry-run block (~L205–227), EXTRA_NOTES (~L229–243), LLM run in two heredocs repo/non-repo (~L259–), commit/exit-3 (`git diff --cached --quiet` → exit 3), merge+push.

**Working location:** all changes in `~/Source/Powerups/powerups-wiki-ingest/`. Do NOT modify the live wiki here (Task 7 only edits the live wiki's `CLAUDE.md`).

**Test approach:** bash has no unit framework here; tests are (a) `/bin/bash -n` syntax, (b) fixture-based tests of the fetch helper (saved HTML files, no network), and (c) end-to-end ingests into a **scratch wiki** using `WIKI_INGEST_CLI=~/Source/AI Experiments/dscldy` (real LLM, no Claude quota) and a stub CLI for deterministic verdict tests. Scratch dir base: `/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad`.

---

### Task 1: Document trafilatura dependency + fetch helper `bin/wiki-ingest-fetch`

**Files:**
- Create: `bin/wiki-ingest-fetch`
- Create: `tests/fixtures/clean-article.html`, `tests/fixtures/js-shell.html`
- Create: `tests/test-fetch.sh`

The helper isolates "URL → cleaned Markdown body" so it is testable without the rest of the pipeline.

- [ ] **Step 1: Write a failing fixture test**

Create `tests/fixtures/clean-article.html`:

```html
<!doctype html><html><head><title>Test Article</title></head><body>
<nav>HOME ABOUT — ads go here</nav>
<article><h1>Test Article</h1><p>This is the first real paragraph of the body.</p>
<h2>Section Two</h2><p>Second paragraph with <strong>bold</strong> text.</p></article>
<footer>cookie banner junk</footer></body></html>
```

Create `tests/fixtures/js-shell.html` (a JS-only shell with no article body):

```html
<!doctype html><html><head><title>Loading…</title></head><body>
<div id="root"></div><noscript>You need to enable JavaScript to run this app.</noscript>
</body></html>
```

Create `tests/test-fetch.sh`:

```bash
#!/bin/bash
# Fixture tests for wiki-ingest-fetch (no network).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
FETCH="$DIR/../bin/wiki-ingest-fetch"
fail=0

out=$("$FETCH" --file "$DIR/fixtures/clean-article.html" 2>/dev/null); rc=$?
echo "$out" | grep -q "first real paragraph" && [ "$rc" = 0 ] || { echo "FAIL: clean article body not extracted (rc=$rc)"; fail=1; }
echo "$out" | grep -qi "cookie banner\|ads go here" && { echo "FAIL: boilerplate leaked into output"; fail=1; }

out=$("$FETCH" --file "$DIR/fixtures/js-shell.html" 2>/dev/null); rc=$?
[ -z "$out" ] && [ "$rc" = 3 ] || { echo "FAIL: js-shell should yield empty output + exit 3 (got rc=$rc, bytes=$(printf '%s' "$out" | wc -c))"; fail=1; }

[ "$fail" = 0 ] && echo "test-fetch: ALL PASS"
exit $fail
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/bin/bash ~/Source/Powerups/powerups-wiki-ingest/tests/test-fetch.sh`
Expected: fails (helper doesn't exist → both cases fail).

- [ ] **Step 3: Write `bin/wiki-ingest-fetch`**

Create `bin/wiki-ingest-fetch`:

```bash
#!/bin/bash
# wiki-ingest-fetch <url> | --file <path> — fetch/extract a source to cleaned
# Markdown on stdout. Uses trafilatura (readability extraction).
#
# Exit codes:
#   0  non-empty content extracted (printed to stdout)
#   3  nothing meaningful extracted (empty) — caller treats as fetch failure
#   1  tool missing / usage error
#
# TRAFILATURA env var overrides the binary path (default: trafilatura on PATH,
# else ~/.local/bin/trafilatura).
set -u

TRAF="${TRAFILATURA:-}"
if [ -z "$TRAF" ]; then
  if command -v trafilatura >/dev/null 2>&1; then TRAF="trafilatura"
  elif [ -x "$HOME/.local/bin/trafilatura" ]; then TRAF="$HOME/.local/bin/trafilatura"
  else echo "wiki-ingest-fetch: trafilatura not found (pipx install trafilatura)" >&2; exit 1; fi
fi

MODE="url"; SRC=""
case "${1:-}" in
  --file) [ $# -ge 2 ] || { echo "usage: wiki-ingest-fetch --file <path>" >&2; exit 1; }; MODE="file"; SRC="$2" ;;
  "" ) echo "usage: wiki-ingest-fetch <url> | --file <path>" >&2; exit 1 ;;
  -* ) echo "wiki-ingest-fetch: unknown option: $1" >&2; exit 1 ;;
  * ) SRC="$1" ;;
esac

# --markdown keeps headings/lists/quotes; extraction strips nav/ads/boilerplate.
if [ "$MODE" = "file" ]; then
  out=$("$TRAF" --markdown < "$SRC" 2>/dev/null)
else
  out=$("$TRAF" -u "$SRC" --markdown 2>/dev/null)
fi

# Treat whitespace-only or trivially-short output as "nothing extracted".
trimmed=$(printf '%s' "$out" | tr -d '[:space:]')
if [ ${#trimmed} -lt 40 ]; then
  exit 3
fi
printf '%s\n' "$out"
exit 0
```

- [ ] **Step 4: chmod + run the test to verify it passes**

Run:
```bash
chmod +x ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-fetch
/bin/bash ~/Source/Powerups/powerups-wiki-ingest/tests/test-fetch.sh
```
Expected: `test-fetch: ALL PASS`. (trafilatura reads the fixture HTML from stdin; the shell has no article body → exit 3; the clean one yields the paragraph without boilerplate.)

- [ ] **Step 5: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-fetch tests/fixtures/clean-article.html tests/fixtures/js-shell.html tests/test-fetch.sh
git commit -m "Add wiki-ingest-fetch (trafilatura extraction helper) + fixture tests"
```

---

### Task 2: Slug helper + verbatim staging in wiki-ingest-run

**Files:**
- Modify: `bin/wiki-ingest-run` (add a slug function; add a fetch+stage step)

The script computes the slug (so `raw/` and `summary/` match) and stages `raw/<slug>.md` before the LLM runs.

- [ ] **Step 1: Add a deterministic slug function**

In `bin/wiki-ingest-run`, immediately after the `usage()` function (before `REPO_MODE=0`), add:

```bash
# Deterministic slug from a URL: last meaningful path segment, lowercased,
# non-alphanumerics → hyphens; fall back to the host. Same input → same slug,
# so raw/<slug>.md and summary/<slug>.md always agree.
url_slug() {
  local u="$1" seg host
  u="${u%%\?*}"; u="${u%%#*}"; u="${u#http://}"; u="${u#https://}"; u="${u#www.}"
  u="${u%/}"
  host="${u%%/*}"
  seg="${u##*/}"
  case "$seg" in
    ""|"$host") seg="$host" ;;
  esac
  seg=$(printf '%s' "$seg" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')
  seg="${seg##-}"; seg="${seg%%-}"
  [ -n "$seg" ] || seg="source"
  printf '%s' "$seg"
}
```

- [ ] **Step 2: Add the fetch+stage step (regular URLs)**

In `bin/wiki-ingest-run`, replace the current worktree/staging block:

```bash
git -C "$WIKI" worktree add "$WT" -b "$BRANCH" main

mkdir -p "$WT/raw"
if [ -n "$CONTENT_FILE" ]; then
  cp "$CONTENT_FILE" "$WT/raw/_prefetched.txt"
fi
```

with:

```bash
git -C "$WIKI" worktree add "$WT" -b "$BRANCH" main
mkdir -p "$WT/raw" "$WT/summary" "$WT/topic"

# Stage the verbatim source deterministically (dry-run skips this).
SLUG=""
if [ "$DRY_RUN" -ne 1 ]; then
  SLUG=$(url_slug "$INGEST_URL")
  FETCH="$SCRIPT_DIR/wiki-ingest-fetch"
  body=""
  if [ "$REPO_MODE" -eq 1 ]; then
    # Repo verbatim = the README (first match, case-insensitive).
    readme=$(find "$CLONE_DIR" -maxdepth 1 -iname 'readme*' 2>/dev/null | head -1)
    [ -n "$readme" ] && body=$(cat "$readme")
  elif [ -n "$CONTENT_FILE" ]; then
    # surf grab (already text/markdown) — extract if it is HTML, else pass through.
    if head -c 200 "$CONTENT_FILE" | grep -qi '<html\|<!doctype'; then
      body=$("$FETCH" --file "$CONTENT_FILE" 2>/dev/null)
    else
      body=$(cat "$CONTENT_FILE")
    fi
  else
    body=$("$FETCH" "$INGEST_URL" 2>/dev/null)
  fi

  # Empty extraction = nothing to archive → fetch failure → exit 3 (→ surf).
  trimmed=$(printf '%s' "$body" | tr -d '[:space:]')
  if [ ${#trimmed} -lt 40 ]; then
    echo "NO CONTENT — fetch/extract empty for $INGEST_URL"
    exit 3
  fi

  # Write the verbatim archive: minimal frontmatter (url is what dup-check needs)
  # + the exact extracted body. The LLM must NOT rewrite this file.
  {
    printf -- '---\n'
    printf 'url: %s\n' "$INGEST_URL"
    printf 'date_fetched: %s\n' "$INGEST_DATE"
    printf -- '---\n\n'
    printf '%s\n' "$body"
  } > "$WT/raw/$SLUG.md"
fi
```

- [ ] **Step 3: Syntax check**

Run: `/bin/bash -n ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-run
git commit -m "Stage verbatim raw/<slug>.md via trafilatura before the LLM runs"
```

---

### Task 3: Rewrite the LLM prompt for verdict + summary/ + topic/

**Files:**
- Modify: `bin/wiki-ingest-run` (both heredoc prompts; EXTRA_NOTES no longer needs the prefetch line)

The LLM stops fetching; it judges the staged `raw/<slug>.md` and writes the other two tiers.

- [ ] **Step 1: Simplify EXTRA_NOTES (drop the WebFetch/prefetch wording)**

Replace the EXTRA_NOTES block:

```bash
EXTRA_NOTES=""
if [ -n "$CONTENT_FILE" ]; then
  EXTRA_NOTES="The page content has already been fetched via browser automation and saved to raw/_prefetched.txt in the wiki directory. Read that file FIRST. Do NOT try to WebFetch the URL. Delete raw/_prefetched.txt when done.
"
fi
if [ "$FORCE" -eq 1 ]; then
  EXTRA_NOTES="${EXTRA_NOTES}This is a re-ingest — update the existing raw file and wiki page, do not duplicate them.
"
fi
if [ -n "$NOTE" ]; then
  EXTRA_NOTES="${EXTRA_NOTES}${NOTE}
"
fi
```

with:

```bash
EXTRA_NOTES=""
if [ "$FORCE" -eq 1 ]; then
  EXTRA_NOTES="This is a re-ingest — update the existing summary and topic page, do not duplicate them.
"
fi
if [ -n "$NOTE" ]; then
  EXTRA_NOTES="${EXTRA_NOTES}${NOTE}
"
fi
```

- [ ] **Step 2: Replace the non-repo LLM heredoc**

Replace the entire non-repo `cat <<INGEST_EOF | (cd "$WT" && "$CLI" ...) || llm_failed` ... `INGEST_EOF` block (the `else` branch of the repo/non-repo `if`) with:

```bash
  cat <<INGEST_EOF | (cd "$WT" && "$CLI" -p --allowedTools "Read,Write,Edit,Bash" --add-dir "$WT") || llm_failed
You are curating one source into an Obsidian wiki. The source text has ALREADY
been fetched and saved verbatim to raw/$SLUG.md (frontmatter + body). Do NOT
fetch anything. Do NOT use WebFetch, WebSearch, or any browser tool.

Wiki location: $WT
The wiki CLAUDE.md (loaded via --add-dir) defines page format and the three-tier
layout (raw/ = verbatim, summary/ = precis, topic/ = analysis). Follow it.

Source URL: $INGEST_URL
$EXTRA_NOTES
STEP 0 — VERDICT (do this first): Read raw/$SLUG.md. Decide whether its body is
the real article/content, or a login wall, paywall teaser, cookie/consent page,
bot-check, or JavaScript app shell.
- If it is NOT real content (BLOCKED): run 'rm raw/$SLUG.md', write NOTHING else,
  and stop. Do not create summary/ or topic/ files. Do not edit index.md or log.md.
- If it IS real content (CONTENT): leave raw/$SLUG.md exactly as-is (do not edit
  it) and continue.

On CONTENT, produce:
1. summary/$SLUG.md — a concise precis (frontmatter with url/title/author/dates
   + a few short paragraphs). Same slug as the raw file.
2. topic/<Title>.md — the analysis page: one-paragraph precis, key quotes
   (blockquoted, with commentary), key themes (#concept #tool #pattern #person),
   opinionated critical analysis, [[wikilinks]] to related pages, source footer
   linking [[raw/$SLUG]] and [[summary/$SLUG]]. Read index.md for cross-link
   targets and grep existing topic pages for related keywords.
3. Update index.md — add the topic page under the most appropriate section.
4. Append to log.md — exactly ONE bullet line, EXACTLY this format:
   - $INGEST_DATE: Ingested [Title]($INGEST_URL) (author, site, publication-date) — 1–3 sentence summary. → raw/$SLUG.md, [[Page Title]]. Cross-links: [[A]], [[B]].

Guidelines:
- Preserve the author's voice when quoting; be opinionated in analysis.
- Keep pages phone-readable: short paragraphs, clear headers.
- Today's date is $INGEST_DATE.
INGEST_EOF
```

- [ ] **Step 3: Replace the repo LLM heredoc similarly**

In the repo branch heredoc, keep Phase 1/2/3 repo-analysis guidance but (a) change the fetch instruction to "the README is saved verbatim at raw/$SLUG.md — do not refetch it; read the cloned repo at $CLONE_DIR for code", (b) apply the same STEP 0 verdict block, and (c) retarget outputs to `summary/$SLUG.md` + `topic/<Title>.md` and the same log format. Change the allowedTools to `"Read,Write,Edit,Bash"` (no WebFetch/WebSearch). Keep the "work only inside $WT plus reading $CLONE_DIR / do not run the wiki-ingest scripts / do not git" guardrails.

- [ ] **Step 4: Syntax check**

Run: `/bin/bash -n ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 5: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-run
git commit -m "LLM prompt: verdict-first, no fetch, writes summary/ + topic/ (three-tier)"
```

---

### Task 4: Commit/exit-3 logic for the three-tier + BLOCKED case

**Files:**
- Modify: `bin/wiki-ingest-run` (the commit section)

The subtle inversion: script pre-staged `raw/$SLUG.md`; a BLOCKED verdict means the LLM deleted it and wrote nothing → net-empty diff → exit 3.

- [ ] **Step 1: Replace the commit/no-changes block**

Replace:

```bash
# dscldy is told to delete the prefetched grab... (rm _prefetched.txt block)
rm -f "$WT/raw/_prefetched.txt"

git -C "$WT" add -A
if git -C "$WT" diff --cached --quiet -- . ":(exclude)raw/_prefetched.txt"; then
  echo "NO CHANGES — fetch likely failed for $INGEST_URL"
  exit 3
fi
if [ "$REPO_MODE" -eq 1 ]; then
  git -C "$WT" commit -m "Ingest (repo analysis): $INGEST_URL" --author="wiki-ingest <noreply@wiki-ingest>"
else
  git -C "$WT" commit -m "Ingest: $INGEST_URL" --author="wiki-ingest <noreply@wiki-ingest>"
fi
```

with:

```bash
git -C "$WT" add -A

# BLOCKED verdict: the LLM deleted the staged raw/$SLUG.md and wrote nothing,
# so there is no net change → treat as fetch failure (exit 3 → surf). CONTENT
# verdict: summary/ + topic/ (and index/log) are present → commit all tiers.
if git -C "$WT" diff --cached --quiet; then
  echo "NO CHANGES — blocked or empty for $INGEST_URL"
  exit 3
fi
# Guard: a CONTENT result must include a summary AND topic file; if only raw/
# survived (LLM misbehaved), fail loudly rather than committing a half result.
if [ "${VERBATIM_ONLY:-0}" -ne 1 ]; then
  if ! ls "$WT/summary/"*.md >/dev/null 2>&1 || ! ls "$WT/topic/"*.md >/dev/null 2>&1; then
    echo "wiki-ingest-run: incomplete result (missing summary/ or topic/) for $INGEST_URL" >&2
    exit 1
  fi
fi
if [ "$REPO_MODE" -eq 1 ]; then
  git -C "$WT" commit -m "Ingest (repo analysis): $INGEST_URL" --author="wiki-ingest <noreply@wiki-ingest>"
else
  git -C "$WT" commit -m "Ingest: $INGEST_URL" --author="wiki-ingest <noreply@wiki-ingest>"
fi
```

(`VERBATIM_ONLY` is introduced in Task 5; add the var init now so this references cleanly — see Task 5 Step 1, which must be applied together with this task if reading out of order.)

- [ ] **Step 2: Syntax check**

Run: `/bin/bash -n ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run && echo "syntax OK"`
Expected: `syntax OK` (after Task 5 Step 1 adds `VERBATIM_ONLY=0`).

- [ ] **Step 3: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-run
git commit -m "Commit logic: BLOCKED→exit 3, require summary+topic on CONTENT"
```

---

### Task 5: `--verbatim-only` mode (Phase 3 reuse)

**Files:**
- Modify: `bin/wiki-ingest-run` (arg parse, usage, var init, LLM invocation branch)

Verbatim-only fetches + judges, writes ONLY `raw/<slug>.md`, never `summary/`/`topic/`.

- [ ] **Step 1: Add the flag (var init + parse + usage)**

Add `VERBATIM_ONLY=0` next to the other flag defaults (with `FORCE=0` etc.). Add to the `usage()` string: `[--verbatim-only]`. Add to the arg `case`: `--verbatim-only) VERBATIM_ONLY=1; shift ;;`.

- [ ] **Step 2: Gate the summary/topic prompt on the flag**

Wrap the LLM invocation so verbatim-only uses a verdict-only prompt. Immediately before the repo/non-repo `if [ "$REPO_MODE" -eq 1 ]; then` LLM block, add:

```bash
if [ "$VERBATIM_ONLY" -eq 1 ]; then
  cat <<INGEST_EOF | (cd "$WT" && "$CLI" -p --allowedTools "Read,Bash" --add-dir "$WT") || llm_failed
You are validating one archived source. The text is saved verbatim at
raw/$SLUG.md. Do NOT fetch anything. Do NOT create or edit any other file.

Read raw/$SLUG.md. If its body is NOT real article/content (login wall, paywall
teaser, consent/cookie page, bot-check, or JS app shell), run 'rm raw/$SLUG.md'.
If it IS real content, do nothing (leave the file as-is). Write no other files,
do not touch summary/, topic/, index.md, or log.md.
INGEST_EOF
else
```

and close this added `if/else` with an extra `fi` after the existing repo/non-repo block's closing `fi`. (Net: `VERBATIM_ONLY` → verdict-only prompt; otherwise → the existing repo/non-repo branch.)

- [ ] **Step 3: Syntax check**

Run: `/bin/bash -n ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 4: Deterministic verdict test with a stub CLI (no LLM)**

This proves the exit-3 inversion (spec load-bearing item) without spending an LLM call.

```bash
SC="/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad/verdict-test"
rm -rf "$SC"; WIKI_PATH="$SC" ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-setup >/dev/null 2>&1
# Stub CLI that simulates a BLOCKED verdict: delete the staged raw file, write nothing.
STUB="$SC-blocked"; cat > "$STUB" <<'EOF'
#!/bin/bash
cat >/dev/null                       # consume the prompt
rm -f "$PWD"/raw/*.md                # simulate: judged BLOCKED
EOF
chmod +x "$STUB"
WIKI_PATH="$SC" WIKI_INGEST_CLI="$STUB" \
  ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run --content /etc/hostname "https://example.com/blocked"; echo "blocked rc=$? (expect 3)"
git -C "$SC" log --oneline | wc -l   # expect just the bootstrap commit (no ingest committed)
rm -rf "$SC" "$STUB"
```

Expected: `blocked rc=3`, and only the bootstrap commit exists (BLOCKED left no trace). If rc=0, the exit-3 inversion is broken — fix before proceeding.

- [ ] **Step 5: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add bin/wiki-ingest-run
git commit -m "Add --verbatim-only mode + prove BLOCKED→exit 3 with a stub CLI"
```

---

### Task 6: Update the wiki schema template

**Files:**
- Modify: `assets/wiki-CLAUDE.md`

- [ ] **Step 1: Rewrite the Structure + add a three-tier section**

In `assets/wiki-CLAUDE.md`, change the directory tree to show `raw/` (verbatim), `summary/`, `topic/`, and add a section:

```markdown
## Three-tier layout

Each source produces up to three artifacts, sharing one slug:

- `raw/<slug>.md` — the **verbatim** fetched source (frontmatter + original text). Written by the pipeline, never rewritten by the model. The `url:` line here is what duplicate detection reads.
- `summary/<slug>.md` — a concise précis of that source.
- `topic/<Title>.md` — analysis and synthesis; may draw on several sources. Cross-linked with `[[wikilinks]]` (which resolve by name regardless of folder).

`index.md` and `log.md` stay at the wiki root.
```

Update the "raw/ frontmatter" section to say the `raw/` file holds the verbatim body under the frontmatter, and that `summary/` carries the richer curated frontmatter (title/author/dates).

- [ ] **Step 2: Commit**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add assets/wiki-CLAUDE.md
git commit -m "Schema: document the three-tier raw/summary/topic layout"
```

---

### Task 7: End-to-end ingest into a scratch wiki (real LLM)

**Files:** none (verification)

- [ ] **Step 1: Seed a scratch wiki whose CLAUDE.md is the new schema**

```bash
SC="/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad/e2e-phase1"
rm -rf "$SC"; WIKI_PATH="$SC" ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-setup >/dev/null 2>&1
```

- [ ] **Step 2: Ingest a clean article (expect all three tiers)**

```bash
SC="/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad/e2e-phase1"
WIKI_PATH="$SC" WIKI_INGEST_CLI="$HOME/Source/AI Experiments/dscldy" \
  ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run "https://mattwynne.net/lean-software-production"; echo "rc=$?"
echo "raw (verbatim, should be large):"; wc -c "$SC/raw/"*.md
echo "summary:"; ls "$SC/summary/"; echo "topic:"; ls "$SC/topic/"
echo "raw has NO analysis headings (it's verbatim):"; grep -c "Critical Analysis" "$SC/raw/"*.md || true
echo "raw url present for dupcheck:"; grep -h "^url:" "$SC/raw/"*.md
```

Expected: rc=0; `raw/lean-software-production.md` is large (~8KB, the verbatim body); one file each in `summary/` and `topic/`; the raw file has a `url:` line and no analysis sections.

- [ ] **Step 3: Ingest a JS-only SPA (expect exit 3, no files)**

```bash
SC="/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad/e2e-phase1"
WIKI_PATH="$SC" WIKI_INGEST_CLI="$HOME/Source/AI Experiments/dscldy" \
  ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run "https://x.com/karpathy/status/1944435463489565119"; echo "rc=$? (expect 3)"
```

Expected: `NO CONTENT — fetch/extract empty …`, rc=3 (trafilatura returns 0 bytes → short-circuit before the LLM).

- [ ] **Step 4: Verbatim-only smoke test**

```bash
SC="/private/tmp/claude-501/-Users-gnat-Source-wiki/f1949c3f-b062-47ff-8d06-898bf2532aa6/scratchpad/e2e-phase1"
WIKI_PATH="$SC" WIKI_INGEST_CLI="$HOME/Source/AI Experiments/dscldy" \
  ~/Source/Powerups/powerups-wiki-ingest/bin/wiki-ingest-run --verbatim-only "https://ferd.ca/queues-don-t-fix-overload.html"; echo "rc=$?"
echo "raw written, NO summary/topic added by this run:"; ls "$SC/raw/" | grep queues; ls "$SC/summary/" | grep queues || echo "(no summary — correct)"
rm -rf "$SC"
```

Expected: rc=0; a `raw/queues-*.md` exists; no matching `summary/`/`topic/` file (verbatim-only is additive to `raw/` only).

---

### Task 8: Release v1.1.0

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md`, `CLAUDE.md`; then `powerups-marketplace`

- [ ] **Step 1: Bump versions to 1.1.0**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
python3 - <<'PY'
import json, pathlib
for f in [".claude-plugin/plugin.json", ".claude-plugin/marketplace.json"]:
    p=pathlib.Path(f); d=json.loads(p.read_text())
    if "version" in d: d["version"]="1.1.0"
    for pl in d.get("plugins", []):
        if pl["name"]=="powerups-wiki-ingest": pl["version"]="1.1.0"
    p.write_text(json.dumps(d, indent=2)+"\n")
print("bumped to 1.1.0")
PY
```

- [ ] **Step 2: Document the new behavior + dependency**

In `README.md` add a "Requirements" note: `trafilatura` (install `pipx install trafilatura`) and describe the three-tier output. In `CLAUDE.md` note the fetch-in-script design and that `bin/` scripts must not reference `${CLAUDE_PLUGIN_ROOT}`.

- [ ] **Step 3: Commit, push, tag**

```bash
cd ~/Source/Powerups/powerups-wiki-ingest
git add -A && git commit -m "Release v1.1.0: three-tier archival pipeline"
git push origin main
```

- [ ] **Step 4: Update the central marketplace**

```bash
cd ~/Source/Powerups/powerups-marketplace && git pull --quiet
python3 - <<'PY'
import json, pathlib
p=pathlib.Path(".claude-plugin/marketplace.json"); d=json.loads(p.read_text())
for pl in d["plugins"]:
    if pl["name"]=="powerups-wiki-ingest": pl["version"]="1.1.0"
p.write_text(json.dumps(d, indent=2)+"\n")
PY
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null && echo OK
git add .claude-plugin/marketplace.json && git commit -m "Bump powerups-wiki-ingest to 1.1.0" && git push origin main
```

- [ ] **Step 5: Note for Nat**

The live wiki `CLAUDE.md` still describes the old 2-tier layout, and Nat's installed plugin must be updated (`claude plugin update powerups-wiki-ingest`) and Claude Code restarted before `/wiki-ingest` uses v1.1.0. The live-wiki schema edit + directory migration is **Phase 2** — do not do it here.

---

## Notes for the implementer

- bash 3.2 only. `/bin/bash -n` after every script task.
- Do not touch the live wiki except reading it read-only for tests; all e2e tests use scratch wikis.
- Tasks 2, 4, 5 edit overlapping regions of `wiki-ingest-run` and reference `SLUG`/`VERBATIM_ONLY`; if executed out of order, apply the var inits (Task 5 Step 1) before Task 4's guard.
- The verbatim archive must remain byte-faithful: the script writes `raw/<slug>.md`; the LLM is instructed only to keep-or-delete it, never edit it. Any task that has the LLM rewrite raw/ is wrong.
