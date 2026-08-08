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
mkdir -p "$W/topic/nested" "$W/summary" "$W/raw"

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

# case 6 (single-source): one digest cited vs two.
printf '# Multi Source Page\n\nBuilt from [[summary/multi-a]] and [[summary/multi-b]].\n' \
  > "$W/topic/Multi Source Page.md"

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
expect_stat "index: 7 archived sources" 7 "$INDEX" archive
expect_stat "index: 7 digests" 7 "$INDEX" digests
expect_stat "index: 19 topic pages" 19 "$INDEX" topics
expect_stat "index: 15 wikilinks found in authored pages" 15 "$INDEX" wikilinks
expect_stat "index: 5 of them dead" 5 "$INDEX" dead_wikilinks
expect_stat "index: 4 topics declare sources" 4 "$INDEX" topics_declaring_sources
expect_stat "index: 1 topic is multi-source" 1 "$INDEX" topics_multi_source
expect_stat "index: 1 topic has reconstructed provenance" 1 "$INDEX" topics_provenance_reconstructed

# case 8's negative half needs the fixture to stay small enough that a claim of
# 20 is inside the max(25, 5%) tolerance. Assert that premise rather than assume
# it: grow the fixture past ~45 topics and this fires instead of the negative
# case quietly becoming vacuous.
topics=$(stat_of "$INDEX" topics)
if [ "$topics" -lt 45 ]; then
  echo "ok: fixture is small enough for the stale-count tolerance premise ($topics topics)"
else
  echo "FAIL: fixture has $topics topics — a claim of 20 is no longer inside tolerance"
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
expect_count "single-source: three such pages in the fixture" 3 "$AUDIT" single-source

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
expect_count "stale-counts: the finding carries the real count" 1 "$AUDIT" \
  stale-self-counts "page=topic/Stale Count Claim.md" "actual=$topics"
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

[ "$fail" = 0 ] && echo "test-curate: ALL PASS"
exit $fail
