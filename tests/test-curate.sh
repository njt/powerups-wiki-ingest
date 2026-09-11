#!/bin/bash
# Live-fire test of bin/wiki-curate against a THROWAWAY fixture wiki.
#
# wiki-curate is deterministic and read-only — no network, no LLM — so every
# case here builds real files on disk, runs the real binary, and asserts on its
# real `--json` output. The fixture is purpose-built: each case has a positive
# and (where the check can silently do nothing) a negative page, so a regression
# that stops a check firing, or makes it fire on the wrong thing, turns the
# suite red rather than leaving it green and empty.
#
# Targets bash 3.2 (macOS /bin/bash).

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-curate-test.XXXXXX")
# NEVER a real wiki: everything below writes into this temp dir only.
export WIKI_PATH="$SANDBOX/wiki"
trap 'rm -rf "$SANDBOX"' EXIT

W="$WIKI_PATH"
mkdir -p "$W/topic/nested" "$W/note" "$W/summary" "$W/raw"

# --- fixture -----------------------------------------------------------------
# Every file below exists to make exactly one assertion possible. Comments name
# which case owns it, so a later edit can tell what it would break.

# case 1 (code is not markup): bash `[[ -z "$TMUX" ]]` and Swift `[[String: Any]]`
# are code, not wikilinks. This page must yield ZERO dead links.
cat > "$W/topic/Code Not Markup.md" <<'EOF'
# Code Not Markup

Guarding a shell snippet:

```bash
[[ -z "$TMUX" ]] && exec tmux new-session
[[ -f ~/.zshrc ]] && source ~/.zshrc
```

And Swift generics inline: `[[String: Any]]` is a nested dictionary type, while
`[[Int]]` is an array of arrays.
EOF

# case 1, negative half: the SAME code, plus one genuine prose wikilink. Without
# this page, "zero dead links" above would also pass if link scanning broke
# entirely. Here exactly one dead link must survive the code stripping.
cat > "$W/topic/Code And Prose.md" <<'EOF'
# Code And Prose

```bash
[[ -z "$TMUX" ]] && exec tmux new-session
```

Inline `[[String: Any]]`, and a real link in prose to [[Prose Link Absent]].
EOF

# case 2 (raw/ is not link-audited): verbatim source, so its brackets belong to
# the original document and must contribute no dead link.
cat > "$W/raw/raw-with-brackets.md" <<'EOF'
---
url: https://example.invalid/raw-with-brackets
date_fetched: 2026-08-01
---

Quoted verbatim from the source article: see [[Some Nonexistent Page]] for the
full derivation, and note that `[[ -n "$X" ]]` is the portable spelling.
EOF
printf -- '---\nurl: https://example.invalid/raw-with-brackets\n---\n\nA precis of the bracket-laden source.\n' \
  > "$W/summary/raw-with-brackets.md"

# case 3 (dead links in authored content): exactly one, and it is this one.
printf '# Dead Link Page\n\nThis page points at [[Definitely Absent Page]] and nothing else.\n' \
  > "$W/topic/Dead Link Page.md"

# case 4 (provenance reconstruction): a hub that declares no sources of its own
# but links to two children, each citing a different digest.
printf '# Hub Page\n\nSee [[Child One]] and [[Child Two]].\n' > "$W/topic/Hub Page.md"
printf '# Child One\n\nSource: [[summary/child-one-src]]\n' > "$W/topic/Child One.md"
printf '# Child Two\n\nSource: [[summary/child-two-src]]\n' > "$W/topic/Child Two.md"
for s in child-one-src child-two-src multi-a multi-b link-forms-src; do
  printf -- '---\nurl: https://example.invalid/%s\n---\n\nPrecis of %s.\n' "$s" "$s" \
    > "$W/summary/$s.md"
  printf -- '---\nurl: https://example.invalid/%s\ndate_fetched: 2026-08-01\n---\n\nArchived body of %s.\n' \
    "$s" "$s" > "$W/raw/$s.md"
done

# case 5 (wanted-pages threshold): two pages want the same absent page; one page
# wants a different absent page on its own.
printf '# Wanted A\n\nWe should write [[Much Wanted Page]].\n' > "$W/topic/Wanted A.md"
printf '# Wanted B\n\nAlso wants [[Much Wanted Page]].\n' > "$W/topic/Wanted B.md"
printf '# Lonely Linker\n\nOnly this page wants [[Barely Wanted Page]].\n' \
  > "$W/topic/Lonely Linker.md"

# case 6 (single-source): one digest cited vs two. The multi-source page also
# links the note below (case 11), which changes nothing about its own
# provenance: declared sources are not extended by outbound links.
printf '# Multi Source Page\n\nBuilt from [[summary/multi-a]] and [[summary/multi-b]].\nSee also [[Noted Analysis]].\n' \
  > "$W/topic/Multi Source Page.md"

# case 11 (note/ is an authored tier): a per-source analysis under note/ is
# audited exactly like one under topic/ -- it cites a digest (single-source),
# it can be linked to (not an orphan), and an unlinked one IS an orphan with no
# provenance. Drop "note" from WIKI_DIRS and every assertion on these turns red.
printf '# Noted Analysis\n\nSource: [[summary/note-src]]\n' > "$W/note/Noted Analysis.md"
printf '# Orphan Note\n\nNothing links here and it cites nothing.\n' > "$W/note/Orphan Note.md"
printf -- '---\nurl: https://example.invalid/note-src\n---\n\nPrecis of note-src.\n' \
  > "$W/summary/note-src.md"
printf -- '---\nurl: https://example.invalid/note-src\ndate_fetched: 2026-08-01\n---\n\nArchived body.\n' \
  > "$W/raw/note-src.md"

# case 7 (orphans / duplicate titles).
printf '# Orphan Page\n\nNothing links here and it links nowhere.\n' > "$W/topic/Orphan Page.md"
printf '# Dupe Title\n\nThe first of two pages with this title.\n' > "$W/topic/Dupe Title.md"
printf '# Dupe Title\n\nThe second, in a subdirectory.\n' > "$W/topic/nested/Dupe Title.md"

# case 8 (stale-self-counts): 9999 is far outside the max(25, 5%) tolerance for
# a fixture this size; 20 is inside it. Both sentences have the identical shape,
# so if the regex matches one it matches the other — the negative case cannot
# pass merely by failing to be recognised.
printf '# Stale Count Claim\n\nAs of writing, the wiki has 9999 pages of material.\n' \
  > "$W/topic/Stale Count Claim.md"
printf '# Honest Count Claim\n\nAs of writing, the wiki has 20 pages of material.\n' \
  > "$W/topic/Honest Count Claim.md"

# case 9 (archive-digest-mismatch): one of each direction. Every other slug
# above is correctly paired, so a check that reported pairs too would blow the
# exact-count assertion.
printf -- '---\nurl: https://example.invalid/lonely-archive\n---\n\nArchive with no digest.\n' \
  > "$W/raw/lonely-archive.md"
printf -- '---\nurl: https://example.invalid/lonely-digest\n---\n\nDigest with no archive.\n' \
  > "$W/summary/lonely-digest.md"

# case 10 (link resolution): four spellings, each aimed at a DIFFERENT page, so
# "the target is not an orphan" proves that spelling resolved to that page and
# not to something else.
#
# link-forms-src deliberately exists in BOTH raw/ and summary/, as every ingested
# slug does. Bare [[link-forms-src]] would resolve by basename, and the tie-break
# is sorted()[0] — "raw/..." sorts before "summary/...", so the archive wins and
# the citation yields no provenance. Path-qualifying is what makes the digest
# reachable, and that is what this case pins down.
cat > "$W/topic/Link Forms.md" <<'EOF'
# Link Forms

Plain [[Alpha Target]], aliased [[Bravo Target|see the bravo page]], anchored
[[Charlie Target#a-section]], and path-qualified [[summary/link-forms-src]].
EOF
printf '# Alpha Target\n\nReached by the plain form.\n' > "$W/topic/Alpha Target.md"
printf '# Bravo Target\n\nReached by the aliased form.\n' > "$W/topic/Bravo Target.md"
printf '# Charlie Target\n\nReached by the anchored form.\n' > "$W/topic/Charlie Target.md"

# A linkable non-wiki file, as Obsidian vaults really have (Agent Journals/ etc).
mkdir -p "$W/Agent Journals"
printf '# Journal 2026-08-01\n\nNot a wiki page; still linkable by basename.\n' \
  > "$W/Agent Journals/Journal 2026-08-01.md"

# --- query helper -------------------------------------------------------------
# Assertions go through the --json output rather than grepping the human format:
# the human report truncates at --show and reformats freely, so grepping it
# would test the presentation instead of the finding.
Q="$SANDBOX/count.py"
cat > "$Q" <<'PY_EOF'
#!/usr/bin/env python3
"""Count items in a wiki-curate --json document.

    count.py <file> <check-id|@> [key=value | key~substring ...]

'@' treats the top-level list as the items (themes --json); anything else
selects an audit check by id. Filters are ANDed. Values are compared as strings,
so `pages~topic/X.md` matches inside a list-valued field.
"""
import json
import sys

path, selector = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)

if selector == "@":
    items = data
else:
    sect = [c for c in data if c["id"] == selector]
    if not sect:
        print("no such check: %s" % selector, file=sys.stderr)
        sys.exit(3)
    items = sect[0]["items"]

for f in sys.argv[3:]:
    ie, it = f.find("="), f.find("~")
    if ie == -1 and it == -1:
        print("bad filter: %s" % f, file=sys.stderr)
        sys.exit(3)
    if it == -1 or (ie != -1 and ie < it):
        k, v = f[:ie], f[ie + 1:]
        items = [i for i in items if str(i.get(k)) == v]
    else:
        k, v = f[:it], f[it + 1:]
        items = [i for i in items if v in str(i.get(k, ""))]

print(len(items))
PY_EOF

stat_of() {  # stat_of <index.json> <key>
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

expect_count() {  # expect_count <label> <expected> <json> <selector> [filters...]
  local label="$1" want="$2" doc="$3" sel="$4"
  shift 4
  local got
  got=$(python3 "$Q" "$doc" "$sel" "$@" 2>&1)
  if [ "$got" = "$want" ]; then
    echo "ok: $label"
  else
    echo "FAIL: $label — expected $want item(s), got: $got"
    fail=1
  fi
}

expect_stat() {  # expect_stat <label> <expected> <json> <key>
  local got
  got=$(stat_of "$3" "$4" 2>&1)
  if [ "$got" = "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected $2, got: $got"
    fail=1
  fi
}

expect_rc() {  # expect_rc <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then
    echo "ok: $1 (rc=$3)"
  else
    echo "FAIL: $1 — expected rc=$2, got rc=$3"
    fail=1
  fi
}

# --- read-only baseline -------------------------------------------------------
# Taken BEFORE the tool has run even once. Taking it afterwards would compare
# two already-corrupted states and let a write during `audit` pass unnoticed.
#
# `find | xargs shasum` is wrong here and silently so: half these fixture pages
# have spaces in their names, xargs splits on them, and every such file drops
# out of the fingerprint. -exec {} + passes the names intact.
wiki_fingerprint() {
  (cd "$W" && find . -type f -exec shasum {} + | sort) | shasum | awk '{print $1}'
}
BASELINE=$(wiki_fingerprint)

# --- run the tool once; every assertion reads these ---------------------------
AUDIT="$SANDBOX/audit.json"
INDEX="$SANDBOX/index.json"
THEMES="$SANDBOX/themes.json"

"$BIN/wiki-curate" audit --json > "$AUDIT" 2>"$SANDBOX/audit.err"
expect_rc "audit --json succeeds on the fixture wiki" 0 $?
[ -s "$AUDIT" ] || { echo "FAIL: audit produced no output: $(cat "$SANDBOX/audit.err")"; exit 1; }

"$BIN/wiki-curate" index --json > "$INDEX" 2>"$SANDBOX/index.err"
expect_rc "index --json succeeds" 0 $?
"$BIN/wiki-curate" themes --json --min 2 > "$THEMES" 2>"$SANDBOX/themes.err"
expect_rc "themes --json succeeds" 0 $?

# The human-format report must also render without blowing up.
"$BIN/wiki-curate" audit > "$SANDBOX/audit.txt" 2>&1
expect_rc "audit (human format) succeeds" 0 $?
grep -q "findings across" "$SANDBOX/audit.txt" \
  || { echo "FAIL: human audit has no summary line: $(cat "$SANDBOX/audit.txt")"; fail=1; }

# --- case 0: the corpus census matches the fixture ----------------------------
expect_stat "index: 8 archived sources" 8 "$INDEX" archive
expect_stat "index: 8 digests" 8 "$INDEX" digests
expect_stat "index: 19 topic pages" 19 "$INDEX" topics
expect_stat "index: 2 note pages" 2 "$INDEX" notes
expect_stat "index: 21 authored pages (topic + note)" 21 "$INDEX" authored
expect_stat "index: no topics.md, so no listed_topics count" None "$INDEX" listed_topics
expect_stat "index: 17 wikilinks found in authored pages" 17 "$INDEX" wikilinks
expect_stat "index: 5 of them dead" 5 "$INDEX" dead_wikilinks
expect_stat "index: 5 authored pages declare sources (one is the note)" 5 "$INDEX" topics_declaring_sources
expect_stat "index: 1 page is multi-source" 1 "$INDEX" topics_multi_source
expect_stat "index: 1 page has reconstructed provenance" 1 "$INDEX" topics_provenance_reconstructed

# case 8's negative half needs the fixture to stay small enough that a claim of
# 20 is inside the max(25, 5%) tolerance. Assert that premise rather than assume
# it: grow the fixture past ~45 authored pages and this fires instead of the
# negative case quietly becoming vacuous.
authored=$(stat_of "$INDEX" authored)
if [ "$authored" -lt 45 ]; then
  echo "ok: fixture is small enough for the stale-count tolerance premise ($authored authored pages)"
else
  echo "FAIL: fixture has $authored authored pages — a claim of 20 is no longer inside tolerance"
  fail=1
fi

# --- case 1: code is not markup ----------------------------------------------
expect_count "code: fenced and inline code yields zero dead links" 0 "$AUDIT" \
  dead-links "page=topic/Code Not Markup.md"
expect_count "code: no dead link is ever a shell test expression" 0 "$AUDIT" \
  dead-links "target~TMUX"
expect_count "code: no dead link is ever a Swift generic" 0 "$AUDIT" \
  dead-links "target~String: Any"
# ... and the page IS being scanned: an identical page with one prose link
# yields exactly that link and nothing from the code.
expect_count "code: a prose link on the same page is still found" 1 "$AUDIT" \
  dead-links "page=topic/Code And Prose.md"
expect_count "code: and it is the prose link, not the code" 1 "$AUDIT" \
  dead-links "page=topic/Code And Prose.md" "target=Prose Link Absent"

# --- case 2: raw/ is not link-audited ----------------------------------------
expect_count "raw: no dead link is attributed to any raw/ file" 0 "$AUDIT" \
  dead-links "page~raw/"
expect_count "raw: its bracketed text does not become a dead target" 0 "$AUDIT" \
  dead-links "target=Some Nonexistent Page"
expect_count "raw: nor a wanted page" 0 "$AUDIT" \
  wanted-pages "wanted=Some Nonexistent Page"

# --- case 3: dead links in authored content ----------------------------------
expect_count "dead-links: the absent target is reported exactly once" 1 "$AUDIT" \
  dead-links "page=topic/Dead Link Page.md" "target=Definitely Absent Page"
expect_count "dead-links: that page has no other finding" 1 "$AUDIT" \
  dead-links "page=topic/Dead Link Page.md"
expect_count "dead-links: five across the whole fixture" 5 "$AUDIT" dead-links

# --- case 4: provenance reconstruction ---------------------------------------
expect_count "provenance: the hub's two sources are reconstructed" 1 "$AUDIT" \
  reconstructed-provenance "page=topic/Hub Page.md" "reconstructed=2"
expect_count "provenance: the hub is NOT reported as source-less" 0 "$AUDIT" \
  no-provenance "page=topic/Hub Page.md"
expect_count "provenance: only the hub reconstructs" 1 "$AUDIT" reconstructed-provenance
# A page with neither declared nor reconstructable sources still is reported.
expect_count "provenance: a genuinely source-less page is reported" 1 "$AUDIT" \
  no-provenance "page=topic/Orphan Page.md"
# A page that declares its own sources is not "reconstructed".
expect_count "provenance: a declaring page is not counted as reconstructed" 0 "$AUDIT" \
  reconstructed-provenance "page=topic/Multi Source Page.md"

# --- case 5: wanted-pages threshold ------------------------------------------
expect_count "wanted: a target 2 pages link to is wanted" 1 "$AUDIT" \
  wanted-pages "wanted=Much Wanted Page" "by=2"
expect_count "wanted: a target only 1 page links to is not" 0 "$AUDIT" \
  wanted-pages "wanted=Barely Wanted Page"
expect_count "wanted: exactly one target clears the threshold" 1 "$AUDIT" wanted-pages

# --- case 6: single-source classification ------------------------------------
expect_count "single-source: a page citing one digest is reported" 1 "$AUDIT" \
  single-source "page=topic/Child One.md" "source=summary/child-one-src"
expect_count "single-source: a page citing two digests is not" 0 "$AUDIT" \
  single-source "page=topic/Multi Source Page.md"
expect_count "single-source: four such pages in the fixture" 4 "$AUDIT" single-source

# --- case 7: duplicate titles and orphans ------------------------------------
expect_count "duplicates: two pages sharing a title are reported once" 1 "$AUDIT" \
  duplicate-titles "title=dupe title"
expect_count "duplicates: both paths are named" 1 "$AUDIT" \
  duplicate-titles "title=dupe title" "pages~topic/nested/Dupe Title.md"
expect_count "duplicates: a unique title is not reported" 0 "$AUDIT" \
  duplicate-titles "title=child one"
expect_count "duplicates: exactly one collision in the fixture" 1 "$AUDIT" duplicate-titles

expect_count "orphans: an unlinked topic page is reported" 1 "$AUDIT" \
  orphans "page=topic/Orphan Page.md"
expect_count "orphans: a linked topic page is not" 0 "$AUDIT" \
  orphans "page=topic/Child One.md"

# --- case 8: stale self-counts, both directions ------------------------------
expect_count "stale-counts: a wildly drifted claim is flagged" 1 "$AUDIT" \
  stale-self-counts "page=topic/Stale Count Claim.md" "claims=9999"
# "actual" is the authored census (topic + note): the same corpus must read the
# same before and after per-source pages move from topic/ to note/.
expect_count "stale-counts: the finding carries the authored count" 1 "$AUDIT" \
  stale-self-counts "page=topic/Stale Count Claim.md" "actual=$authored"
expect_count "stale-counts: a claim within tolerance is NOT flagged" 0 "$AUDIT" \
  stale-self-counts "page=topic/Honest Count Claim.md"
expect_count "stale-counts: exactly one page flagged" 1 "$AUDIT" stale-self-counts

# --- case 9: archive/digest mismatch -----------------------------------------
expect_count "mismatch: an archive with no digest is reported" 1 "$AUDIT" \
  archive-digest-mismatch "slug=lonely-archive" "issue=raw without digest"
expect_count "mismatch: a digest with no archive is reported" 1 "$AUDIT" \
  archive-digest-mismatch "slug=lonely-digest" "issue=digest without archive"
expect_count "mismatch: a correctly paired slug is not reported" 0 "$AUDIT" \
  archive-digest-mismatch "slug=child-one-src"
expect_count "mismatch: exactly the two unpaired slugs" 2 "$AUDIT" archive-digest-mismatch

# --- case 10: link resolution forms ------------------------------------------
expect_count "links: none of the four spellings is dead" 0 "$AUDIT" \
  dead-links "page=topic/Link Forms.md"
# Each form aims at a different page, so a non-orphan target proves that
# spelling resolved to that page specifically.
expect_count "links: [[Name]] resolves" 0 "$AUDIT" orphans "page=topic/Alpha Target.md"
expect_count "links: [[Name|alias]] resolves" 0 "$AUDIT" orphans "page=topic/Bravo Target.md"
expect_count "links: [[Name#anchor]] resolves" 0 "$AUDIT" orphans "page=topic/Charlie Target.md"
# The path-qualified form must land in summary/, which is only observable as
# declared provenance.
expect_count "links: [[summary/slug]] resolves as declared provenance" 1 "$AUDIT" \
  single-source "page=topic/Link Forms.md" "source=summary/link-forms-src"

# --- themes: declared and reconstructed provenance both rank -----------------
expect_count "themes: a 2-source page ranks as declared" 1 "$THEMES" @ \
  "title=Multi Source Page" "sources=2" "provenance=declared"
expect_count "themes: the hub ranks on reconstructed sources" 1 "$THEMES" @ \
  "title=Hub Page" "sources=2" "provenance=reconstructed"
expect_count "themes: a 1-source page is below --min 2" 0 "$THEMES" @ "title=Child One"
expect_count "themes: exactly two pages clear --min 2" 2 "$THEMES" @

# --- case 11: note/ is audited as an authored tier ----------------------------
expect_count "note: a note citing one digest is single-source" 1 "$AUDIT" \
  single-source "page=note/Noted Analysis.md" "source=summary/note-src"
expect_count "note: a linked note is not an orphan" 0 "$AUDIT" \
  orphans "page=note/Noted Analysis.md"
expect_count "note: an unlinked note is an orphan" 1 "$AUDIT" \
  orphans "page=note/Orphan Note.md"
expect_count "note: an unlinked note citing nothing has no provenance" 1 "$AUDIT" \
  no-provenance "page=note/Orphan Note.md"
expect_count "note: the note's digest is cited (not an uncited digest)" 0 "$AUDIT" \
  uncited-digests "page=summary/note-src.md"
expect_count "note: the multi-source page's provenance is unchanged by linking a note" 0 "$AUDIT" \
  single-source "page=topic/Multi Source Page.md"

# --- no topics.md: the topic-list layer is dormant ----------------------------
# Every topics.md-gated check must exist (count.py exits 3 on an unknown id, so
# "0" also proves presence) and report nothing on a wiki without the file.
for chk in untagged-digests unlisted-topics topic-page-missing topic-dir-stray \
           note-topic-name-clash topic-oversized index-sections-drift; do
  expect_count "no-topics: $chk is present and empty" 0 "$AUDIT" "$chk"
done
"$BIN/wiki-curate" topics >/dev/null 2>"$SANDBOX/e-topics"
expect_rc "no-topics: the topics subcommand exits 3" 3 $?
grep -q "no topics.md" "$SANDBOX/e-topics" \
  || { echo "FAIL: no-topics — topics message unhelpful: $(cat "$SANDBOX/e-topics")"; fail=1; }
# sources keeps its pre-topics contract: the theme is an existing page, the
# provenance is what the page declares, and an unknown theme is exit 4.
"$BIN/wiki-curate" sources --theme "Multi Source Page" --json > "$SANDBOX/src.json" 2>/dev/null
expect_rc "no-topics: sources resolves an existing page" 0 $?
expect_stat "no-topics: sources provenance is 'declared'" declared "$SANDBOX/src.json" provenance
expect_stat "no-topics: sources path is the page" "topic/Multi Source Page.md" "$SANDBOX/src.json" path
"$BIN/wiki-curate" sources --theme "No Such Theme" >/dev/null 2>&1
expect_rc "no-topics: an unknown theme is still exit 4" 4 $?

# --- configuration errors -----------------------------------------------------
env -u WIKI_PATH "$BIN/wiki-curate" audit >/dev/null 2>"$SANDBOX/e-nopath"
expect_rc "no WIKI_PATH is a clean error" 2 $?
grep -q "WIKI_PATH is not set" "$SANDBOX/e-nopath" \
  || { echo "FAIL: no-WIKI_PATH — unhelpful message: $(cat "$SANDBOX/e-nopath")"; fail=1; }
grep -q "Traceback" "$SANDBOX/e-nopath" \
  && { echo "FAIL: no-WIKI_PATH — traceback instead of an error message"; fail=1; }

mkdir -p "$SANDBOX/not-a-wiki"
WIKI_PATH="$SANDBOX/not-a-wiki" "$BIN/wiki-curate" audit >/dev/null 2>"$SANDBOX/e-notwiki"
expect_rc "a directory with no topic/ is a clean error" 2 $?
grep -q "no topic/ directory" "$SANDBOX/e-notwiki" \
  || { echo "FAIL: not-a-wiki — unhelpful message: $(cat "$SANDBOX/e-notwiki")"; fail=1; }
grep -q "Traceback" "$SANDBOX/e-notwiki" \
  && { echo "FAIL: not-a-wiki — traceback instead of an error message"; fail=1; }

WIKI_PATH="$SANDBOX/no-such-dir" "$BIN/wiki-curate" audit >/dev/null 2>"$SANDBOX/e-missing"
expect_rc "a missing directory is a clean error" 2 $?
grep -q "not a directory" "$SANDBOX/e-missing" \
  || { echo "FAIL: missing-dir — unhelpful message: $(cat "$SANDBOX/e-missing")"; fail=1; }

# --- read-only: the tool must not have touched the fixture --------------------
# wiki-curate promises it never writes. Every subcommand has now run, in both
# output formats; the file list and every checksum must still match the state
# the fixture builder left behind.
if [ "$BASELINE" = "$(wiki_fingerprint)" ]; then
  echo "ok: read-only — no wiki file was created, changed or removed"
else
  echo "FAIL: read-only — running wiki-curate changed the wiki"
  fail=1
fi

# =============================================================================
# Phase 2 — a wiki WITH topics.md. A separate, git-backed fixture: `dirty`
# needs commits, and everything topics.md switches on must be shown to switch
# on here while the fixture above proved it stays off without the file.
# =============================================================================
T="$SANDBOX/twiki"
mkdir -p "$T/topic" "$T/note" "$T/summary" "$T/raw"

# Three topics; misc is required by wiki-meta. A smaller table than
# assets/topics.md, same format.
cat > "$T/topics.md" <<'EOF'
# Topics

Prose around the table is for people; the tools read only the table.

| slug | title | scope |
|---|---|---|
| alpha-topic | Alpha Topic | The first topic. |
| beta-topic | Beta Topic | The second topic. |
| misc | Miscellany | Anything that fits none of the above. |
EOF

# Digests, one per shape of `topics:` the parser must read. Membership:
#   alpha-topic: s-block, s-flow, s-alpha3   (3 -> OVER at --split-at 2)
#   beta-topic:  s-block, s-scalar           (2)
#   misc:        s-misc                      (1)
tdigest() {  # tdigest <slug> <title> <topics-lines...>
  local slug="$1" title="$2"; shift 2
  { printf -- '---\nurl: https://example.invalid/%s\ntitle: "%s"\n' "$slug" "$title"
    for ln in "$@"; do printf '%s\n' "$ln"; done
    printf -- '---\n\nPrecis of %s.\n' "$slug"; } > "$T/summary/$slug.md"
  printf -- '---\nurl: https://example.invalid/%s\n---\n\nArchived %s.\n' "$slug" "$slug" \
    > "$T/raw/$slug.md"
}
tdigest s-block   "Block List Source"  'topics:' '  - alpha-topic' '  - beta-topic'
tdigest s-flow    "Flow List Source"   'topics: [alpha-topic]'
tdigest s-alpha3  "Third Alpha Source" 'topics:' '  - alpha-topic'
tdigest s-scalar  "Scalar Source"      'topics: beta-topic'
tdigest s-misc    "A Misc Source"      'topics:' '  - misc'
tdigest s-untagged "Untagged Source"   'author: Nobody'          # untagged-digests +
tdigest s-bogus   "Bogus Topic Source" 'topics: [bogus-topic]'   # unlisted-topics +

# topic/: Alpha Topic exists (compiled, with a provenance footer that names only
# TWO of its three tag members, so the topics path and the legacy path give
# different answers); Beta Topic and Miscellany have no page yet
# (topic-page-missing +); Stray Page is not on the list (topic-dir-stray +).
{ printf '# Alpha Topic\n\nA compiled page about alpha. '
  printf 'Filler word. %.0s' 1 2 3 4 5 6 7 8 9 10
  printf '\n\n---\n\n*Compiled from 2 sources: [[summary/s-block]], [[summary/s-flow]]*\n*Last compiled: 2026-08-10*\n'
} > "$T/topic/Alpha Topic.md"
printf '# Stray Page\n\nNot a listed topic; should live in note/.\n' > "$T/topic/Stray Page.md"

# note/: one whose title collides with a listed topic case-insensitively
# (note-topic-name-clash +) and one that does not (-).
printf '# beta topic\n\nA note that shadows the Beta Topic page name.\n' > "$T/note/beta topic.md"
printf '# Fine Note\n\nSource: [[summary/s-misc]]\n' > "$T/note/Fine Note.md"

# index.md, drifted: an H2 before `## Topics` (must be ignored), one right
# section, one wrong, two missing.
printf '# Wiki Index\n\n## Preamble\n\nIgnored.\n\n## Topics\n\n- [[Alpha Topic]]\n\n## Alpha Topic\n\n- x\n\n## Wrong Heading\n\n- y\n' \
  > "$T/index.md"

git init -q "$T"
git -C "$T" config user.email "test@wiki-ingest.invalid"
git -C "$T" config user.name "wiki-ingest test"
git -C "$T" add -A && git -C "$T" commit -q -m "state A"
STATE_A=$(git -C "$T" rev-parse HEAD)

twiki_fingerprint() {
  (cd "$T" && find . -path ./.git -prune -o -type f -exec shasum {} + | sort) \
    | shasum | awk '{print $1}'
}
# curate_ro <outfile> <args...>: run the real binary against the topics wiki,
# capturing stdout to <outfile>, stderr to <outfile>.err and the exit code in
# RC — and prove that invocation wrote nothing.
curate_ro() {
  local out="$1"; shift
  local before; before=$(twiki_fingerprint)
  "$BIN/wiki-curate" --wiki "$T" "$@" > "$out" 2> "$out.err"
  RC=$?
  [ "$before" = "$(twiki_fingerprint)" ] \
    || { echo "FAIL: read-only — 'wiki-curate $*' changed the topics wiki"; fail=1; }
}
jget() {  # jget <json-file> <python-expr over d>
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>&1
}
expect_j() {  # expect_j <label> <expected> <json-file> <expr>
  local got; got=$(jget "$3" "$4")
  if [ "$got" = "$2" ]; then echo "ok: $1"; else echo "FAIL: $1 — expected '$2', got: $got"; fail=1; fi
}

# --- index sees the list -----------------------------------------------------
TINDEX="$SANDBOX/t-index.json"
curate_ro "$TINDEX" index --json
expect_rc "topics-wiki: index --json succeeds" 0 $RC
expect_stat "topics-wiki: index counts the listed topics" 3 "$TINDEX" listed_topics
expect_stat "topics-wiki: index counts topic/ pages (listed or not)" 2 "$TINDEX" topics
expect_stat "topics-wiki: index counts note/ pages" 2 "$TINDEX" notes

# --- audit: the seven gated checks, positive and negative --------------------
TAUDIT="$SANDBOX/t-audit.json"
curate_ro "$TAUDIT" audit --json
expect_rc "topics-wiki: audit --json succeeds" 0 $RC
curate_ro "$SANDBOX/t-audit.txt" audit
expect_rc "topics-wiki: audit (human format) succeeds" 0 $RC

expect_count "untagged: a digest with no topics: is reported" 1 "$TAUDIT" \
  untagged-digests "page=summary/s-untagged.md"
expect_count "untagged: a tagged digest is not" 0 "$TAUDIT" \
  untagged-digests "page=summary/s-block.md"
expect_count "untagged: exactly one in the fixture" 1 "$TAUDIT" untagged-digests

expect_count "unlisted: a slug topics.md does not list is reported" 1 "$TAUDIT" \
  unlisted-topics "page=summary/s-bogus.md" "topic=bogus-topic"
expect_count "unlisted: a listed slug is not" 0 "$TAUDIT" \
  unlisted-topics "page=summary/s-block.md"
expect_count "unlisted: exactly one in the fixture" 1 "$TAUDIT" unlisted-topics

expect_count "page-missing: a listed topic with no page is reported" 1 "$TAUDIT" \
  topic-page-missing "slug=beta-topic" "title=Beta Topic" "members=2"
expect_count "page-missing: so is misc" 1 "$TAUDIT" topic-page-missing "slug=misc"
expect_count "page-missing: a listed topic with a page is not" 0 "$TAUDIT" \
  topic-page-missing "slug=alpha-topic"
expect_count "page-missing: exactly two" 2 "$TAUDIT" topic-page-missing

expect_count "dir-stray: a topic/ file not on the list is reported" 1 "$TAUDIT" \
  topic-dir-stray "page=topic/Stray Page.md"
expect_count "dir-stray: a listed topic's page is not" 0 "$TAUDIT" \
  topic-dir-stray "page=topic/Alpha Topic.md"
expect_count "dir-stray: exactly one" 1 "$TAUDIT" topic-dir-stray

expect_count "name-clash: a note titled like a listed topic (any case) is reported" 1 "$TAUDIT" \
  note-topic-name-clash "page=note/beta topic.md" "topic=Beta Topic"
expect_count "name-clash: an ordinary note is not" 0 "$TAUDIT" \
  note-topic-name-clash "page=note/Fine Note.md"
expect_count "name-clash: exactly one" 1 "$TAUDIT" note-topic-name-clash

expect_count "topic-oversized: nothing is over the default of 60" 0 "$TAUDIT" topic-oversized
curate_ro "$SANDBOX/t-audit2.json" audit --json --split-at 2
expect_rc "topics-wiki: audit --split-at 2 succeeds" 0 $RC
expect_count "topic-oversized: --split-at 2 flags the 3-member topic" 1 "$SANDBOX/t-audit2.json" \
  topic-oversized "slug=alpha-topic" "members=3" "split_at=2"
expect_count "topic-oversized: the 2-member topic is not over 2" 0 "$SANDBOX/t-audit2.json" \
  topic-oversized "slug=beta-topic"
expect_count "topic-oversized: exactly one at --split-at 2" 1 "$SANDBOX/t-audit2.json" topic-oversized

expect_count "index-drift: a listed title with no section is missing" 1 "$TAUDIT" \
  index-sections-drift "issue=missing" "heading=Beta Topic"
expect_count "index-drift: misc's title too" 1 "$TAUDIT" \
  index-sections-drift "issue=missing" "heading=Miscellany"
expect_count "index-drift: a section that is not a topic is unexpected" 1 "$TAUDIT" \
  index-sections-drift "issue=unexpected" "heading=Wrong Heading"
expect_count "index-drift: an H2 BEFORE ## Topics is not compared" 0 "$TAUDIT" \
  index-sections-drift "heading=Preamble"
expect_count "index-drift: a matching section is not reported" 0 "$TAUDIT" \
  index-sections-drift "heading=Alpha Topic"
expect_count "index-drift: exactly three findings" 3 "$TAUDIT" index-sections-drift

# The other index shapes, each a fresh audit. The one that has to stay quiet is
# the correct one; the ones that must fire are wrong in one specific way.
printf '# Wiki Index\n\n## Preamble\n\nIgnored.\n\n## Topics\n\n- x\n\n## Alpha Topic\n\n## Beta Topic\n\n## Miscellany\n' > "$T/index.md"
curate_ro "$SANDBOX/t-idx-ok.json" audit --json
expect_count "index-drift: sections after ## Topics equal to the titles in order -> quiet" 0 \
  "$SANDBOX/t-idx-ok.json" index-sections-drift
printf '# Wiki Index\n\n## Preamble\n\n## Alpha Topic\n\n## Beta Topic\n\n## Miscellany\n' > "$T/index.md"
curate_ro "$SANDBOX/t-idx-notopics.json" audit --json
expect_count "index-drift: without a ## Topics heading every H2 is compared" 1 \
  "$SANDBOX/t-idx-notopics.json" index-sections-drift "issue=unexpected" "heading=Preamble"
expect_count "index-drift: ... and that is the only finding" 1 \
  "$SANDBOX/t-idx-notopics.json" index-sections-drift
printf '# Wiki Index\n\n## Alpha Topic\n\n## Beta Topic\n\n## Miscellany\n' > "$T/index.md"
curate_ro "$SANDBOX/t-idx-plain.json" audit --json
expect_count "index-drift: no ## Topics, H2s exactly the titles -> quiet" 0 \
  "$SANDBOX/t-idx-plain.json" index-sections-drift
printf '# Wiki Index\n\n## Topics\n\n## Beta Topic\n\n## Alpha Topic\n\n## Miscellany\n' > "$T/index.md"
curate_ro "$SANDBOX/t-idx-order.json" audit --json
expect_count "index-drift: the right sections in the wrong order is one finding" 1 \
  "$SANDBOX/t-idx-order.json" index-sections-drift "issue=out of order" "position=1" "expected=Alpha Topic"
expect_count "index-drift: ... and only one" 1 "$SANDBOX/t-idx-order.json" index-sections-drift
git -C "$T" checkout -q -- index.md

# --- topics subcommand -------------------------------------------------------
TTOP="$SANDBOX/t-topics.json"
curate_ro "$TTOP" topics --json --split-at 2
expect_rc "topics: --json succeeds" 0 $RC
expect_j "topics: rows are in topics.md order" "['alpha-topic', 'beta-topic', 'misc']" "$TTOP" \
  '[r["slug"] for r in d["topics"]]'
expect_j "topics: members counted from block, flow and scalar topics:" "[3, 2, 1]" "$TTOP" \
  '[r["members"] for r in d["topics"]]'
expect_j "topics: alpha's members are the tagged digests" "['summary/s-alpha3', 'summary/s-block', 'summary/s-flow']" "$TTOP" \
  'd["topics"][0]["sources"]'
expect_j "topics: page presence" "[True, False, False]" "$TTOP" '[r["page_exists"] for r in d["topics"]]'
alpha_words=$(wc -w < "$T/topic/Alpha Topic.md" | tr -d ' ')
expect_j "topics: words of the existing page, 0 for absent" "[$alpha_words, 0, 0]" "$TTOP" \
  '[r["words"] for r in d["topics"]]'
expect_j "topics: last_compiled read from the footer" "['2026-08-10', None, None]" "$TTOP" \
  '[r["last_compiled"] for r in d["topics"]]'
expect_j "topics: over at --split-at 2 is the 3-member topic only" "[True, False, False]" "$TTOP" \
  '[r["over"] for r in d["topics"]]'
expect_j "topics: the split threshold is reported" "2" "$TTOP" 'd["split_at"]'
expect_j "topics: misc members with their digest titles" "[('summary/s-misc', 'A Misc Source')]" "$TTOP" \
  '[(m["page"], m["title"]) for m in d["misc"]]'
expect_j "topics: title is carried" "Beta Topic" "$TTOP" 'd["topics"][1]["title"]'

curate_ro "$SANDBOX/t-topics.txt" topics --split-at 2
expect_rc "topics: human format succeeds" 0 $RC
grep -q 'alpha-topic .*Alpha Topic  OVER$' "$SANDBOX/t-topics.txt" \
  || { echo "FAIL: topics — alpha row not marked OVER: $(cat "$SANDBOX/t-topics.txt")"; fail=1; }
grep -q 'beta-topic .*Beta Topic$' "$SANDBOX/t-topics.txt" \
  || { echo "FAIL: topics — beta row wrong or marked OVER"; fail=1; }
grep -q 'summary/s-misc  A Misc Source' "$SANDBOX/t-topics.txt" \
  || { echo "FAIL: topics — misc member not listed: $(cat "$SANDBOX/t-topics.txt")"; fail=1; }
echo "ok: topics: human table marks OVER and lists misc"
curate_ro "$SANDBOX/t-topics-default.txt" topics
grep -q 'OVER' "$SANDBOX/t-topics-default.txt" \
  && { echo "FAIL: topics — something is OVER at the default threshold of 60"; fail=1; }
grep -q '0 over 60 members' "$SANDBOX/t-topics-default.txt" \
  || { echo "FAIL: topics — default threshold is not 60: $(tail -5 "$SANDBOX/t-topics-default.txt")"; fail=1; }
echo "ok: topics: default --split-at is 60"

# --- sources: resolved through the list --------------------------------------
curate_ro "$SANDBOX/t-src-slug.json" sources --theme alpha-topic --json
expect_rc "sources: a slug resolves" 0 $RC
expect_stat "sources: theme is the title" "Alpha Topic" "$SANDBOX/t-src-slug.json" theme
expect_stat "sources: path is topic/<title>.md" "topic/Alpha Topic.md" "$SANDBOX/t-src-slug.json" path
expect_stat "sources: provenance is declared-topics" declared-topics "$SANDBOX/t-src-slug.json" provenance
expect_j "sources: the set is the 3 tag members, not the footer's 2" \
  "['summary/s-alpha3.md', 'summary/s-block.md', 'summary/s-flow.md']" "$SANDBOX/t-src-slug.json" 'd["sources"]'
expect_stat "sources: slug is carried" alpha-topic "$SANDBOX/t-src-slug.json" slug
expect_stat "sources: scope is carried for the compile prompt" "The first topic." "$SANDBOX/t-src-slug.json" scope

curate_ro "$SANDBOX/t-src-title.json" sources --theme "beta TOPIC" --json
expect_rc "sources: a title resolves, case-insensitively" 0 $RC
expect_stat "sources: an absent page still has its path from topics.md" "topic/Beta Topic.md" "$SANDBOX/t-src-title.json" path
expect_stat "sources: ... and page_exists false" False "$SANDBOX/t-src-title.json" page_exists
expect_stat "sources: ... and 0 words" 0 "$SANDBOX/t-src-title.json" words
expect_j "sources: the scalar-tagged digest is a member" "['summary/s-block.md', 'summary/s-scalar.md']" \
  "$SANDBOX/t-src-title.json" 'd["sources"]'

curate_ro "$SANDBOX/t-src-none.json" sources --theme "Stray Page" --json
expect_rc "sources: an existing topic/ page that is not listed is refused with 3" 3 $RC
grep -q "not a listed topic; add it to topics.md and retag" "$SANDBOX/t-src-none.json.err" \
  || { echo "FAIL: sources — wrong refusal message: $(cat "$SANDBOX/t-src-none.json.err")"; fail=1; }
[ -s "$SANDBOX/t-src-none.json" ] && { echo "FAIL: sources — refused but printed output"; fail=1; }
echo "ok: sources: the refusal names the fix"

# --- dirty: tag arithmetic ---------------------------------------------------
# State B: one alpha digest edited (body only), one new misc digest. Alpha and
# misc are dirty; beta is not. With --min 3 only alpha qualifies.
printf '\nAn extra paragraph.\n' >> "$T/summary/s-flow.md"
tdigest s-new "New Misc Source" 'topics:' '  - misc'
git -C "$T" add -A && git -C "$T" commit -q -m "state B"

curate_ro "$SANDBOX/t-dirty.txt" dirty --since "$STATE_A"
expect_rc "dirty: succeeds" 0 $RC
expect_out_dirty=$(printf 'Alpha Topic\nMiscellany')
if [ "$(cat "$SANDBOX/t-dirty.txt")" = "$expect_out_dirty" ]; then
  echo "ok: dirty: the topics the changed digests list, most-changed first, as titles"
else
  echo "FAIL: dirty — got: $(cat "$SANDBOX/t-dirty.txt" | tr '\n' '|')"; fail=1
fi
grep -q "2 digest(s) changed; 2 theme(s) dirty" "$SANDBOX/t-dirty.txt.err" \
  || { echo "FAIL: dirty — summary line: $(cat "$SANDBOX/t-dirty.txt.err")"; fail=1; }
curate_ro "$SANDBOX/t-dirty.json" dirty --since "$STATE_A" --json
expect_j "dirty: --json carries slug, member and changed counts" \
  "[('alpha-topic', 3, 1), ('misc', 2, 1)]" "$SANDBOX/t-dirty.json" \
  '[(r["slug"], r["sources"], r["changed"]) for r in d]'
curate_ro "$SANDBOX/t-dirty-min.txt" dirty --since "$STATE_A" --min 3
[ "$(cat "$SANDBOX/t-dirty-min.txt")" = "Alpha Topic" ] \
  && echo "ok: dirty: --min excludes a small dirty topic" \
  || { echo "FAIL: dirty --min 3 — got: $(cat "$SANDBOX/t-dirty-min.txt")"; fail=1; }
curate_ro "$SANDBOX/t-dirty-none.txt" dirty --since HEAD
grep -q "No digests changed" "$SANDBOX/t-dirty-none.txt" \
  && echo "ok: dirty: nothing changed is said plainly" \
  || { echo "FAIL: dirty --since HEAD — got: $(cat "$SANDBOX/t-dirty-none.txt")"; fail=1; }

# --- the same wiki with topics.md set aside: legacy behaviour ----------------
# Not deleted from git, just moved off disk for these runs, so the Vault sees
# the pre-topics world: sources come from the footer, dirty from provenance.
mv "$T/topics.md" "$SANDBOX/topics.md.aside"
curate_ro "$SANDBOX/t-legacy-src.json" sources --theme "Alpha Topic" --json
expect_rc "legacy: sources still resolves an existing page" 0 $RC
expect_stat "legacy: provenance is 'declared' (the footer)" declared "$SANDBOX/t-legacy-src.json" provenance
expect_j "legacy: the set is the footer's 2, not the tags' 3" \
  "['summary/s-block.md', 'summary/s-flow.md']" "$SANDBOX/t-legacy-src.json" 'd["sources"]'
curate_ro "$SANDBOX/t-legacy-none.json" sources --theme "Beta Topic" --json
expect_rc "legacy: a title with no page is exit 4, as before" 4 $RC
curate_ro "$SANDBOX/t-legacy-dirty.txt" dirty --since "$STATE_A"
[ "$(cat "$SANDBOX/t-legacy-dirty.txt")" = "Alpha Topic" ] \
  && echo "ok: legacy: dirty comes from the page's provenance (misc has no page)" \
  || { echo "FAIL: legacy dirty — got: $(cat "$SANDBOX/t-legacy-dirty.txt")"; fail=1; }
curate_ro "$SANDBOX/t-legacy-audit.json" audit --json
for chk in untagged-digests unlisted-topics topic-page-missing topic-dir-stray \
           note-topic-name-clash topic-oversized index-sections-drift; do
  expect_count "legacy: $chk goes quiet the moment topics.md is gone" 0 "$SANDBOX/t-legacy-audit.json" "$chk"
done
mv "$SANDBOX/topics.md.aside" "$T/topics.md"

# --- a malformed topics.md is a clean error, not a traceback -----------------
B="$SANDBOX/badwiki"; mkdir -p "$B/topic"
grep -v '| misc |' "$T/topics.md" > "$B/topics.md"
WIKI_PATH="$B" "$BIN/wiki-curate" audit >/dev/null 2>"$SANDBOX/e-badtopics"
expect_rc "bad topics.md: exit 2" 2 $?
grep -q "no 'misc' row" "$SANDBOX/e-badtopics" \
  || { echo "FAIL: bad topics.md — message: $(cat "$SANDBOX/e-badtopics")"; fail=1; }
grep -q "Traceback" "$SANDBOX/e-badtopics" \
  && { echo "FAIL: bad topics.md — traceback"; fail=1; }

[ "$fail" = 0 ] && echo "test-curate: ALL PASS"
exit $fail
