#!/bin/bash
# Live-fire test of bin/wiki-migrate-topics against a THROWAWAY legacy wiki.
#
# Builds a small 2.x-shaped wiki in a temp dir (per-source pages in topic/,
# an index.md with old section headings and a page count, summaries without
# topics:, a CLAUDE.md with the wiki's own tail sections), runs the real
# script, and asserts on real git state: what is on the branch, what is NOT
# on main, and that the live checkout never moves. No network, no LLM, and
# WIKI_PATH is never a real wiki.
#
# What each fixture page is for is written beside it. The shape mirrors the
# live wiki's measured facts: compiled pages cite `*Compiled from N sources:
# [[summary/...]]*`, per-source pages cite `*Sources: [[raw/x]], [[summary/x]]*`,
# titles carry em-dashes and accents, and one filename is NFD on disk while
# its index link is NFC.
#
# Targets bash 3.2 (macOS /bin/bash): no mapfile, no associative arrays, no
# negative indexing.

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
MIGRATE="$BIN/wiki-migrate-topics"
ASSET_SCHEMA="$DIR/../assets/wiki-CLAUDE.md"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-migrate-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
# NEVER a real wiki. Everything below writes into this temp dir only.
export WIKI_PATH="$SANDBOX/wiki"
W="$WIKI_PATH"

cleanup_all() {
  if [ -d "$W/.git" ]; then
    git -C "$W" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{print $2}' \
      | while read -r wt; do
          [ "$wt" = "$W" ] && continue
          git -C "$W" worktree remove --force "$wt" >/dev/null 2>&1 || true
        done
    git -C "$W" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$SANDBOX"
  return 0
}
trap cleanup_all EXIT

# --- helpers -----------------------------------------------------------------
check() {  # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then echo "ok: $1 (rc=$3)"; else echo "FAIL: $1 — expected rc=$2, got rc=$3"; fail=1; fi
}
assert() {  # assert <label> <condition-rc:0|1>
  if [ "$2" = 0 ]; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi
}
on_branch() {  # on_branch <branch> <path>  -> prints the file, rc 0 if it exists
  git -C "$W" show "$1:$2" 2>/dev/null
}
has_on_branch() { git -C "$W" cat-file -e "$1:$2" 2>/dev/null; }
branch_exists() { git -C "$W" rev-parse --verify --quiet "refs/heads/$1" >/dev/null 2>&1; }
branch_tip() { git -C "$W" rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null || echo "-"; }
topics_of() {  # topics_of <branch> <summary-slug>  -> comma-joined topics: list
  on_branch "$1" "summary/$2.md" > "$SANDBOX/t.md"
  "$BIN/wiki-meta" get "$SANDBOX/t.md" topics 2>/dev/null | paste -sd, -
}
# Entries under one `## Heading` of an index text, as sorted [[targets]].
section_entries() {  # section_entries <file> <heading>
  awk -v h="## $2" '
    /^## / { on = ($0 == h); next }
    on && /^- \[\[/ { sub(/^- \[\[/, ""); sub(/\]\].*$/, ""); print }
  ' "$1" | sort
}
expect_section() {  # expect_section <label> <file> <heading> <expected sorted newline list>
  got=$(section_entries "$2" "$3")
  if [ "$got" = "$4" ]; then echo "ok: $1"; else
    echo "FAIL: $1 — under '## $3' got: $(printf '%s' "$got" | tr '\n' '|') expected: $(printf '%s' "$4" | tr '\n' '|')"; fail=1
  fi
}
W_REAL=$(cd "$W" 2>/dev/null && pwd -P || echo "$W")
assert_no_stray_worktrees() {
  extra=$(git -C "$W" worktree list --porcelain | awk '/^worktree /{print $2}' \
          | grep -v "^$W_REAL\$" | grep -v "^$W\$" | tr '\n' ' ')
  [ -z "$extra" ] || { echo "FAIL: $1 — worktrees left behind: $extra"; fail=1; }
}
assert_live_checkout_pristine() {
  [ "$(git -C "$W" rev-parse --abbrev-ref HEAD)" = "main" ] \
    || { echo "FAIL: $1 — live checkout is not on main"; fail=1; }
  [ "$(git -C "$W" rev-parse main)" = "$MAIN_AT_START" ] \
    || { echo "FAIL: $1 — main moved"; fail=1; }
  [ -z "$(git -C "$W" status --porcelain)" ] \
    || { echo "FAIL: $1 — live working tree is dirty: $(git -C "$W" status --porcelain | tr '\n' ' ')"; fail=1; }
  [ -f "$W/topic/Plain Note.md" ] && [ ! -d "$W/note" ] && [ ! -f "$W/topics.md" ] \
    || { echo "FAIL: $1 — the live checkout's files changed shape"; fail=1; }
  assert_no_stray_worktrees "$1"
}
run_migrate() {  # run_migrate <tag> <args...>; sets RC; output in $SANDBOX/out.<tag>, err.<tag>
  tag="$1"; shift
  "$MIGRATE" --wiki "$W" --topics-file "$TOPICS" "$@" >"$SANDBOX/out.$tag" 2>"$SANDBOX/err.$tag"
  RC=$?
  cat "$SANDBOX/out.$tag" "$SANDBOX/err.$tag" > "$SANDBOX/all.$tag"
}

# --- the topics file the migration seeds ---------------------------------------
# Four topics: one that already has a compiled page (Alpha Topic), two the old
# index sections map onto (Agent Coding Workflow, Developer Tools), and misc.
# The mapping table also names slugs that are NOT here (ideas-and-culture), so
# the "mapped slug not in the list" warning path is exercised.
TOPICS="$SANDBOX/topics.md"
cat > "$TOPICS" <<'EOF'
# Topics

Prose around the table is ignored by the tools.

| slug | title | scope |
|---|---|---|
| alpha-topic | Alpha Topic | The alpha scope line. |
| agent-coding-workflow | Agent Coding Workflow | How people work with coding agents. |
| developer-tools | Developer Tools | Tools a developer picks up. |
| misc | Miscellany | Anything that fits none of the above. |
EOF

# --- the legacy wiki -----------------------------------------------------------
mkdir -p "$W/topic" "$W/summary" "$W/raw"
git init -q "$W"
git -C "$W" symbolic-ref HEAD refs/heads/main
git -C "$W" config user.email "test@wiki-ingest.invalid"
git -C "$W" config user.name "wiki-ingest test"
# The live wiki's setting (design ledger A14): git records names NFC.
git -C "$W" config core.precomposeunicode true

summary() {  # summary <slug> [title]
  printf -- '---\nurl: https://example.invalid/%s\ntitle: "%s"\ndate_fetched: 2026-08-01\n---\n\nA precis of %s.\n' \
    "$1" "${2:-$1}" "$1" > "$W/summary/$1.md"
  printf -- '---\nurl: https://example.invalid/%s\ndate_fetched: 2026-08-01\n---\n\nVerbatim %s.\n' \
    "$1" "$1" > "$W/raw/$1.md"
}
note() {  # note <title> <footer-line>
  printf '# %s\n\nAn analysis of one source.\n\n---\n%s\n*Last updated: 2026-08-01*\n' "$1" "$2" > "$W/topic/$1.md"
}

for s in s-a s-b s-plain s-cafe s-dash s-shared s-odd s-lonely s-foot s-ideas; do summary "$s"; done
# Pre-tagged, block form: step 3 must leave it exactly alone.
summary s-pre "Pre-tagged source"
printf -- '---\nurl: https://example.invalid/s-pre\ntitle: "Pre-tagged source"\ntopics:\n  - developer-tools\ndate_fetched: 2026-08-01\n---\n\nA precis of s-pre.\n' > "$W/summary/s-pre.md"

# A LISTED compiled page: stays in topic/; its provenance is signal (a).
printf '# Alpha Topic\n\nThe compiled thesis.\n\nSee [[Plain Note]] and [[Both Note]].\n\n---\n\n*Compiled from 2 sources: [[summary/s-a]], [[summary/s-b]]*\n*Last compiled: 2026-08-10*\n' \
  > "$W/topic/Alpha Topic.md"
# Unlisted per-source pages: every one of these moves to note/.
note "Plain Note"       '*Sources: [[raw/s-plain]], [[summary/s-plain]]*'
note "Dash — Note"      '*Sources: [[summary/s-dash]]*'                      # em-dash title
note "Shared Note One"  '*Sources: [[summary/s-shared]]*'                    # two notes cite s-shared;
note "Shared Note Two"  '*Sources: [[summary/s-shared]]*'                    # the first by title wins
note "Odd Synthesis"    '*Sources: [[summary/s-odd]]*'                       # in Synthesis, unlisted -> misc
note "Both Note"        '*Sources: [[summary/s-a]]*'                         # s-a: (a) alpha + (b) index section
note "Pre Note"         '*Sources: [[summary/s-pre]]*'                       # its summary is already tagged
note "Ideas Note"       '*Sources: [[summary/s-ideas]]*'                     # section maps to an absent slug
printf '# Footerless Note\n\nCites nothing at all.\n' > "$W/topic/Footerless Note.md"
# NFD on disk, NFC in every link -- the live wiki has two of these.
NFD_TITLE=$(python3 -c 'print("Café Note")')
NFC_TITLE=$(python3 -c 'print("Café Note")')
note "$NFD_TITLE" '*Sources: [[summary/s-cafe]]*'

cat > "$W/index.md" <<'EOF'
# Wiki Index

11 pages across 4 sections. Synthesis pages provide cross-cutting analysis.

## Synthesis

Cross-cutting analysis that pulls threads across individual pages.

- [[Alpha Topic]] — The compiled page; listed, so this entry is dropped
- [[Odd Synthesis]] — An unlisted synthesis page; goes to misc

## Agentic Development

Practices and workflows. **Hub: [[Alpha Topic]]**

- [[Plain Note]] — A plain per-source note
- [[Shared Note Two]] — The second of two notes citing one summary
- [[Footerless Note]] — A note with no provenance at all
- [[Pre Note]] — Its summary was tagged developer-tools before the migration

## Developer Tools

CLIs, utilities, and the like.

- [[Café Note]] — An accented title, NFC here and NFD on disk
- [[Shared Note One]] — The first of two notes citing one summary
- [[Both Note]] — Cited by the compiled Alpha Topic AND filed here

## Ideas & Culture

Maps to a slug the test topics file does not have.

- [[Ideas Note]] — Falls through to misc with a warning

## Weird Section

Not in the mapping table at all.

- [[Dash — Note]] — An em-dash title in an unknown section
EOF

cat > "$W/CLAUDE.md" <<'EOF'
# Wiki Schema

The 2.x schema text, to be replaced.

## Structure

Old structure section.

## Page Format

```markdown
# Page Title

## Not A Real Heading Either
```

## Workflows

### Ingest

Nat's own ingest notes. Kept verbatim.

## Relationship to the Rest of the Vault

Also kept.

## Principles

- Keep it.
EOF
printf -- '- 2026-08-01: Ingested something.\n' > "$W/log.md"

git -C "$W" add -A
git -C "$W" commit -q -m "Seed the legacy wiki"
MAIN_AT_START=$(git -C "$W" rev-parse main)
ORIG_INDEX_ENTRIES=$(grep -c '^- \[\[' "$W/index.md")

echo "=== wiki-migrate-topics ==="

# =============================================================================
# Case 1 — --all on a new branch: five commits, one per step, each asserted.
# =============================================================================
BR=curate/topics-test
run_migrate all --branch "$BR" --all
check "all: the migration runs" 0 "$RC"
assert "all: branch $BR was created" "$(branch_exists "$BR"; echo $?)"
assert_live_checkout_pristine "all"
n_commits=$(git -C "$W" rev-list --count "main..$BR" 2>/dev/null || echo 0)
[ "$n_commits" = 5 ] && echo "ok: all: five commits, one per step" \
  || { echo "FAIL: all — expected 5 commits on $BR, got $n_commits"; fail=1; }
grep -q "^== step 3" "$SANDBOX/out.all" && grep -q "Agentic Development" "$SANDBOX/out.all" \
  && echo "ok: all: the section mapping table is printed" \
  || { echo "FAIL: all — section mapping table not printed"; fail=1; }

# Each commit touches only its own step's paths.
i=0
for sha in $(git -C "$W" rev-list --reverse "main..$BR"); do
  i=$((i + 1))
  files=$(git -C "$W" -c core.quotePath=false show --name-only --format= "$sha" | grep -v '^$')
  case "$i" in
    1) bad=$(printf '%s\n' "$files" | grep -v '^topic/\|^note/') ;;
    2) bad=$(printf '%s\n' "$files" | grep -v '^topics\.md$') ;;
    3) bad=$(printf '%s\n' "$files" | grep -v '^summary/') ;;
    4) bad=$(printf '%s\n' "$files" | grep -v '^index\.md$') ;;
    5) bad=$(printf '%s\n' "$files" | grep -v '^CLAUDE\.md$') ;;
  esac
  [ -z "$bad" ] && echo "ok: all: commit $i touches only step $i's paths" \
    || { echo "FAIL: all — commit $i touches: $(printf '%s' "$bad" | tr '\n' ' ')"; fail=1; }
done

# --- step 1: the move -----------------------------------------------------------
for t in "Plain Note" "Dash — Note" "Shared Note One" "Shared Note Two" "Odd Synthesis" \
         "Both Note" "Pre Note" "Ideas Note" "Footerless Note" "$NFC_TITLE"; do
  has_on_branch "$BR" "note/$t.md" && ! has_on_branch "$BR" "topic/$t.md" \
    && echo "ok: step 1: '$t' is in note/, not topic/" \
    || { echo "FAIL: step 1 — '$t' not moved"; fail=1; }
done
has_on_branch "$BR" "topic/Alpha Topic.md" && ! has_on_branch "$BR" "note/Alpha Topic.md" \
  && echo "ok: step 1: the listed 'Alpha Topic' stayed in topic/" \
  || { echo "FAIL: step 1 — Alpha Topic moved or duplicated"; fail=1; }
has_on_branch "$BR" "note/.gitkeep" && echo "ok: step 1: note/.gitkeep added" \
  || { echo "FAIL: step 1 — no note/.gitkeep"; fail=1; }
# git records the accented name composed (precomposeunicode), and as a rename.
tracked=$(git -C "$W" -c core.quotePath=false ls-tree --name-only "$BR" note/ | grep 'Caf')
[ "$tracked" = "note/$NFC_TITLE.md" ] && echo "ok: step 1: the NFD-on-disk page is tracked NFC under note/" \
  || { echo "FAIL: step 1 — accented page tracked as: $tracked"; fail=1; }
first=$(git -C "$W" rev-list --reverse "main..$BR" | head -1)
renames=$(git -C "$W" -c core.quotePath=false show --name-status --format= -M "$first" | grep -c '^R100')
[ "$renames" = 10 ] && echo "ok: step 1: git sees all 10 moves as pure renames" \
  || { echo "FAIL: step 1 — expected 10 R100 renames, got $renames"; fail=1; }
grep -q "moved 10 page(s) to note/; kept 1 listed" "$SANDBOX/out.all" \
  && echo "ok: step 1: reports moved/kept counts" \
  || { echo "FAIL: step 1 — counts line missing: $(grep 'moved' "$SANDBOX/out.all")"; fail=1; }

# --- step 2: topics.md ---------------------------------------------------------
on_branch "$BR" topics.md > "$SANDBOX/topics-on-branch.md"
cmp -s "$SANDBOX/topics-on-branch.md" "$TOPICS" && echo "ok: step 2: topics.md is the topics file byte for byte" \
  || { echo "FAIL: step 2 — topics.md differs from the source"; fail=1; }

# --- step 3: topics: backfill ----------------------------------------------------
expect_topics() {  # expect_topics <slug> <expected>
  got=$(topics_of "$BR" "$1")
  [ "$got" = "$2" ] && echo "ok: step 3: $1 -> $2" \
    || { echo "FAIL: step 3 — $1 got '$got', expected '$2'"; fail=1; }
}
expect_topics s-a      "alpha-topic,developer-tools"   # (a) then (b): two signals, primary first
expect_topics s-b      "alpha-topic"                   # (a) only; no note cites it
expect_topics s-plain  "agent-coding-workflow"         # (b) Agentic Development
expect_topics s-cafe   "developer-tools"               # (b) through the NFC link to an NFD file
expect_topics s-shared "developer-tools"               # (b) first citing note by title: Shared Note One
expect_topics s-odd    "misc"                          # Synthesis, unlisted
expect_topics s-dash   "misc"                          # unknown section
expect_topics s-ideas  "misc"                          # section maps to a slug the list lacks
expect_topics s-lonely "misc"                          # nothing cites it
expect_topics s-foot   "misc"                          # its note has no footer
expect_topics s-pre    "developer-tools"               # already tagged: untouched
on_branch "$BR" summary/s-pre.md > "$SANDBOX/s-pre-branch.md"
cmp -s "$SANDBOX/s-pre-branch.md" "$W/summary/s-pre.md" \
  && echo "ok: step 3: a pre-tagged summary is byte-identical" \
  || { echo "FAIL: step 3 — pre-tagged summary was rewritten"; fail=1; }
on_branch "$BR" summary/s-a.md | grep -q '^  - alpha-topic$' \
  && echo "ok: step 3: topics: is written in block form" \
  || { echo "FAIL: step 3 — not block form: $(on_branch "$BR" summary/s-a.md | grep -A2 topics)"; fail=1; }
grep -q "cited by more than one note" "$SANDBOX/out.all" && grep -q "Shared Note One" "$SANDBOX/out.all" \
  && echo "ok: step 3: says which note was used for a multiply-cited summary" \
  || { echo "FAIL: step 3 — multi-cited notice missing"; fail=1; }
grep -q "misc: 5 newly filed" "$SANDBOX/out.all" && grep -q "summary/s-lonely" "$SANDBOX/out.all" \
  && echo "ok: step 3: lists the misc slugs" \
  || { echo "FAIL: step 3 — misc list wrong: $(grep 'misc:' "$SANDBOX/out.all")"; fail=1; }
grep -q "Weird Section.*not in the mapping table" "$SANDBOX/err.all" \
  && echo "ok: step 3: warns about an unknown section heading" \
  || { echo "FAIL: step 3 — no unknown-heading warning"; fail=1; }
grep -q "Ideas & Culture.*ideas-and-culture.*not in" "$SANDBOX/err.all" \
  && echo "ok: step 3: warns when a mapped slug is not in the topics file" \
  || { echo "FAIL: step 3 — no absent-slug warning: $(cat "$SANDBOX/err.all")"; fail=1; }

# --- step 4: index.md ----------------------------------------------------------
on_branch "$BR" index.md > "$SANDBOX/index-branch.md"
IDX="$SANDBOX/index-branch.md"
[ "$(head -1 "$IDX")" = "# Wiki Index" ] && echo "ok: step 4: title line" \
  || { echo "FAIL: step 4 — first line: $(head -1 "$IDX")"; fail=1; }
grep -q '[0-9]\+ pages' "$IDX" && { echo "FAIL: step 4 — a page count survived"; fail=1; } \
  || echo "ok: step 4: no page count in the intro"
heads=$(grep '^## ' "$IDX" | paste -sd'|' -)
[ "$heads" = "## Topics|## Alpha Topic|## Agent Coding Workflow|## Developer Tools|## Miscellany" ] \
  && echo "ok: step 4: sections are Topics then every topic title in topics.md order" \
  || { echo "FAIL: step 4 — headings: $heads"; fail=1; }
expect_section "step 4: ## Topics lists every compiled page" "$IDX" "Topics" \
  "$(printf 'Agent Coding Workflow\nAlpha Topic\nDeveloper Tools\nMiscellany')"
grep -q '^- \[\[Alpha Topic\]\] — The alpha scope line\.$' "$IDX" \
  && echo "ok: step 4: a Topics entry is '[[Title]] — scope'" \
  || { echo "FAIL: step 4 — Topics entry shape"; fail=1; }
grep -q '^\[\[Developer Tools\]\] — Tools a developer picks up\.$' "$IDX" \
  && echo "ok: step 4: each topic section opens with the page link and scope" \
  || { echo "FAIL: step 4 — section scope line missing"; fail=1; }
expect_section "step 4: Alpha Topic holds the note whose summary is primary alpha" "$IDX" "Alpha Topic" "Both Note"
expect_section "step 4: Agent Coding Workflow holds Plain Note" "$IDX" "Agent Coding Workflow" "Plain Note"
expect_section "step 4: Developer Tools gathers by primary topic, not by old section" "$IDX" "Developer Tools" \
  "$(printf 'Caf\303\251 Note\nPre Note\nShared Note One\nShared Note Two')"
expect_section "step 4: Miscellany holds the rest, including the footerless note" "$IDX" "Miscellany" \
  "$(printf 'Dash \342\200\224 Note\nFooterless Note\nIdeas Note\nOdd Synthesis')"
grep -q '^- \[\[Alpha Topic\]\] — The compiled page' "$IDX" \
  && { echo "FAIL: step 4 — the Synthesis entry for a listed title survived"; fail=1; } \
  || echo "ok: step 4: the Synthesis entry for a listed title was dropped"
# Every original entry line, minus that one, is present verbatim exactly once.
grep '^- \[\[' "$W/index.md" | grep -v '^- \[\[Alpha Topic\]\]' | sort > "$SANDBOX/orig-entries"
awk '/^## Topics$/{skip=1; next} /^## /{skip=0} !skip && /^- \[\[/' "$IDX" | sort > "$SANDBOX/new-entries"
cmp -s "$SANDBOX/orig-entries" "$SANDBOX/new-entries" \
  && echo "ok: step 4: every original entry line appears exactly once, verbatim" \
  || { echo "FAIL: step 4 — entry lines differ:"; diff "$SANDBOX/orig-entries" "$SANDBOX/new-entries" | head; fail=1; }
[ "$(wc -l < "$SANDBOX/new-entries" | tr -d ' ')" = "$((ORIG_INDEX_ENTRIES - 1))" ] \
  && echo "ok: step 4: $((ORIG_INDEX_ENTRIES - 1)) entries out of $ORIG_INDEX_ENTRIES" \
  || { echo "FAIL: step 4 — entry count"; fail=1; }
grep -q "$ORIG_INDEX_ENTRIES entries in" "$SANDBOX/out.all" && grep -q "1 dropped" "$SANDBOX/out.all" \
  && echo "ok: step 4: prints the in/dropped/out counts" \
  || { echo "FAIL: step 4 — counts not printed: $(grep 'entries in' "$SANDBOX/out.all")"; fail=1; }
grep -q "Footerless Note.*cites no summary" "$SANDBOX/err.all" \
  && echo "ok: step 4: warns about an entry whose note has no provenance" \
  || { echo "FAIL: step 4 — no footerless warning: $(cat "$SANDBOX/err.all")"; fail=1; }

# --- step 5: CLAUDE.md ----------------------------------------------------------
on_branch "$BR" CLAUDE.md > "$SANDBOX/claude-branch.md"
{ sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$ASSET_SCHEMA"; printf '\n'; sed -n '/^## Workflows$/,$p' "$W/CLAUDE.md"; } > "$SANDBOX/claude-want.md"
cmp -s "$SANDBOX/claude-branch.md" "$SANDBOX/claude-want.md" \
  && echo "ok: step 5: CLAUDE.md is the template plus the wiki's tail from ## Workflows, verbatim" \
  || { echo "FAIL: step 5 — CLAUDE.md differs:"; diff "$SANDBOX/claude-want.md" "$SANDBOX/claude-branch.md" | head; fail=1; }
grep -q "Nat's own ingest notes" "$SANDBOX/claude-branch.md" && grep -q '^- Keep it\.$' "$SANDBOX/claude-branch.md" \
  && echo "ok: step 5: Workflows and Principles survive" \
  || { echo "FAIL: step 5 — the tail was lost"; fail=1; }
grep -q "The 2.x schema text" "$SANDBOX/claude-branch.md" \
  && { echo "FAIL: step 5 — old schema text survived"; fail=1; } \
  || echo "ok: step 5: the old schema text is gone"
grep -q '^## Not A Real Heading Either' "$SANDBOX/claude-branch.md" \
  && { echo "FAIL: step 5 — a heading inside a code fence was taken as the tail"; fail=1; } \
  || echo "ok: step 5: headings inside code fences are not split points"

# =============================================================================
# Case 2 — rerunning --all is a no-op: same tip, every step says "no change".
# =============================================================================
TIP1=$(branch_tip "$BR")
run_migrate again --branch "$BR" --all
check "rerun: exits 0" 0 "$RC"
[ "$(branch_tip "$BR")" = "$TIP1" ] && echo "ok: rerun: the branch tip did not move" \
  || { echo "FAIL: rerun — tip moved $TIP1 -> $(branch_tip "$BR")"; fail=1; }
n_nochange=$(grep -c '^step [1-5]: no change$' "$SANDBOX/out.again")
[ "$n_nochange" = 5 ] && echo "ok: rerun: all five steps report no change" \
  || { echo "FAIL: rerun — $n_nochange of 5 steps said no change:"; grep '^step' "$SANDBOX/out.again"; fail=1; }
grep -q "nothing to do" "$SANDBOX/out.again" && echo "ok: rerun: says so" \
  || { echo "FAIL: rerun — no 'nothing to do' line"; fail=1; }
assert_live_checkout_pristine "rerun"

# =============================================================================
# Case 3 — --all --dry-run on a fresh branch name: prints, commits nothing,
# leaves no branch and no worktree, and main is untouched.
# =============================================================================
run_migrate dry --branch curate/topics-dry --all --dry-run
check "dry-run: exits 0" 0 "$RC"
branch_exists curate/topics-dry && { echo "FAIL: dry-run — branch was created"; fail=1; } \
  || echo "ok: dry-run: no branch created"
n_dry=$(grep -c '^step [1-5]: DRY RUN — would commit' "$SANDBOX/out.dry")
[ "$n_dry" = 5 ] && echo "ok: dry-run: all five steps report what they would commit" \
  || { echo "FAIL: dry-run — $n_dry of 5 steps reported:"; grep '^step' "$SANDBOX/out.dry"; fail=1; }
grep -q "misc: 5 newly filed" "$SANDBOX/out.dry" && grep -q "## Topics" "$SANDBOX/out.dry" 2>/dev/null \
  || grep -q "1 dropped" "$SANDBOX/out.dry" \
  && echo "ok: dry-run: the same step reports as a real run" \
  || { echo "FAIL: dry-run — step reports missing"; fail=1; }
grep -q "DRY RUN — nothing committed" "$SANDBOX/out.dry" && echo "ok: dry-run: says nothing was committed" \
  || { echo "FAIL: dry-run — no closing DRY RUN line"; fail=1; }
assert_live_checkout_pristine "dry-run"

# =============================================================================
# Case 4 — single steps: --step 1 alone commits only the move; --step 3 on the
# same branch afterwards finds the notes in note/ and tags from them.
# =============================================================================
run_migrate s1 --branch curate/topics-steps --step 1
check "step 1 alone: exits 0" 0 "$RC"
[ "$(git -C "$W" rev-list --count main..curate/topics-steps)" = 1 ] \
  && echo "ok: step 1 alone: exactly one commit" \
  || { echo "FAIL: step 1 alone — commit count $(git -C "$W" rev-list --count main..curate/topics-steps)"; fail=1; }
has_on_branch curate/topics-steps "note/Plain Note.md" && ! has_on_branch curate/topics-steps topics.md \
  && echo "ok: step 1 alone: moved the notes and nothing else" \
  || { echo "FAIL: step 1 alone — unexpected branch contents"; fail=1; }
run_migrate s3 --branch curate/topics-steps --step 3
check "step 3 after step 1: exits 0" 0 "$RC"
[ "$(git -C "$W" rev-list --count main..curate/topics-steps)" = 2 ] \
  && echo "ok: step 3 after step 1: a second commit on the same branch" \
  || { echo "FAIL: step 3 — commit count"; fail=1; }
on_branch curate/topics-steps summary/s-plain.md > "$SANDBOX/t.md"
[ "$("$BIN/wiki-meta" get "$SANDBOX/t.md" topics)" = "agent-coding-workflow" ] \
  && echo "ok: step 3 after step 1: tags from notes that now live in note/" \
  || { echo "FAIL: step 3 — s-plain not tagged from note/"; fail=1; }
assert_live_checkout_pristine "steps"

# =============================================================================
# Case 5 — usage errors are clean exits, not tracebacks.
# =============================================================================
"$MIGRATE" --wiki "$W" --topics-file "$TOPICS" >/dev/null 2>"$SANDBOX/err.noargs"; rc=$?
check "usage: neither --all nor --step is exit 2" 2 "$rc"
grep -q Traceback "$SANDBOX/err.noargs" && { echo "FAIL: usage — traceback"; fail=1; }
"$MIGRATE" --wiki "$W" --topics-file "$SANDBOX/absent.md" --all >/dev/null 2>"$SANDBOX/err.notopics"; rc=$?
check "usage: a missing topics file is exit 2" 2 "$rc"
grep -v '| misc |' "$TOPICS" > "$SANDBOX/bad-topics.md"
"$MIGRATE" --wiki "$W" --topics-file "$SANDBOX/bad-topics.md" --all >/dev/null 2>"$SANDBOX/err.badtopics"; rc=$?
check "usage: a topics file without misc is exit 2" 2 "$rc"
grep -q "no 'misc' row" "$SANDBOX/err.badtopics" || { echo "FAIL: usage — bad topics message: $(cat "$SANDBOX/err.badtopics")"; fail=1; }
assert_live_checkout_pristine "usage"

[ "$fail" = 0 ] && echo "test-migrate: ALL PASS"
exit $fail
