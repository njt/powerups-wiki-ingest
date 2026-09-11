#!/bin/bash
# Live-fire test of bin/wiki-meta against THROWAWAY fixture files.
#
# wiki-meta is deterministic — no network, no LLM, no git — so every case here
# writes real files into a temp dir, runs the real binary, and asserts on its
# real output and on the bytes it leaves behind. The byte-level assertions are
# the point: `set` promises to touch one key and nothing else, and the ingest
# guard relies on normalize-topics' exit code, so both are checked exactly.
#
# Targets bash 3.2 (macOS /bin/bash).

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
META="$BIN/wiki-meta"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-meta-test.XXXXXX")
# NEVER a real wiki: everything below writes into this temp dir only.
export WIKI_PATH="$SANDBOX/wiki"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$WIKI_PATH"
W="$WIKI_PATH"

# --- helpers -----------------------------------------------------------------

expect_rc() {  # expect_rc <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then
    echo "ok: $1 (rc=$3)"
  else
    echo "FAIL: $1 — expected rc=$2, got rc=$3"
    fail=1
  fi
}

expect_out() {  # expect_out <label> <expected-string> <actual-string>
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    echo "  expected: $(printf '%s' "$2" | od -c | head -5)"
    echo "  actual:   $(printf '%s' "$3" | od -c | head -5)"
    fail=1
  fi
}

expect_same_file() {  # expect_same_file <label> <expected-file> <actual-file>
  if cmp -s "$2" "$3"; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — files differ:"
    diff "$2" "$3" | sed 's/^/    /'
    fail=1
  fi
}

expect_grep() {  # expect_grep <label> <pattern> <file>
  if grep -q -- "$2" "$3"; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected /$2/ in: $(cat "$3")"
    fail=1
  fi
}

# --- fixture: a digest with every value shape --------------------------------
# Odd spacing, a comment, single and double quotes, `key:value` with no space,
# a flow list with a quoted item, a block list, a trailing blank line. The
# round-trip cases below require every one of these bytes to survive a `set`.
cat > "$W/digest.md" <<'EOF'
---
url: https://example.com/a?b=1
title: "Paperclip: an agent company"
author: 'Labs, Inc.'
# a comment inside the frontmatter
tags: [a, "b c", d]
topics:
  - agent-orchestration
  - misc
date_published:   2026
odd:value
empty:

---

# Body

Body text with a [[Link]] and a `[[code]]` span.

---

A horizontal rule in the body, not frontmatter.
EOF
cp "$W/digest.md" "$W/digest.orig.md"

# --- get -----------------------------------------------------------------------
out=$("$META" get "$W/digest.md" title); expect_out "get: double-quoted scalar is unquoted" "Paperclip: an agent company" "$out"
out=$("$META" get "$W/digest.md" author); expect_out "get: single-quoted scalar is unquoted" "Labs, Inc." "$out"
out=$("$META" get "$W/digest.md" url); expect_out "get: bare scalar with a colon in it" "https://example.com/a?b=1" "$out"
out=$("$META" get "$W/digest.md" date_published); expect_out "get: extra spaces after the colon are not part of the value" "2026" "$out"
out=$("$META" get "$W/digest.md" odd); expect_out "get: key:value with no space (wiki-curate accepts it)" "value" "$out"
out=$("$META" get "$W/digest.md" tags); expect_out "get: flow list, one item per line, quoted item unquoted" "$(printf 'a\nb c\nd')" "$out"
out=$("$META" get "$W/digest.md" topics); expect_out "get: block list, one item per line" "$(printf 'agent-orchestration\nmisc')" "$out"
"$META" get "$W/digest.md" empty >/dev/null; expect_rc "get: a key with no value is present" 0 $?
"$META" get "$W/digest.md" nope >/dev/null; expect_rc "get: absent key" 1 $?
# The comment line must not read as a key.
"$META" get "$W/digest.md" a >/dev/null; expect_rc "get: a comment is not a key" 1 $?

printf '# No frontmatter\n\nJust a body.\n' > "$W/plain.md"
"$META" get "$W/plain.md" title >/dev/null; expect_rc "get: file without frontmatter" 1 $?

printf -- '---\nlist: ["x", '"'"'y z'"'"', w]\nname: "He said \\"hi\\""\n---\n' > "$W/quoted.md"
out=$("$META" get "$W/quoted.md" list); expect_out "get: flow list with mixed quoting" "$(printf 'x\ny z\nw')" "$out"
out=$("$META" get "$W/quoted.md" name); expect_out "get: escaped quotes inside a double-quoted scalar" 'He said "hi"' "$out"

# --- set: replace in the middle, preserving every other byte --------------------
cp "$W/digest.orig.md" "$W/digest.md"
"$META" set "$W/digest.md" author "Someone Else"; expect_rc "set: replace a scalar mid-frontmatter" 0 $?
sed "s/^author: 'Labs, Inc.'\$/author: Someone Else/" "$W/digest.orig.md" > "$W/expect.md"
expect_same_file "set: only the author line changed, every other byte intact" "$W/expect.md" "$W/digest.md"

cp "$W/digest.orig.md" "$W/digest.md"
"$META" set "$W/digest.md" title "Note: things"
sed 's/^title: .*$/title: "Note: things"/' "$W/digest.orig.md" > "$W/expect.md"
expect_same_file "set: a value containing ': ' is quoted, nothing else moves" "$W/expect.md" "$W/digest.md"
out=$("$META" get "$W/digest.md" title); expect_out "set/get: the quoted value reads back unquoted" "Note: things" "$out"

# Replacing a block list with a scalar must take the continuation lines with it.
cp "$W/digest.orig.md" "$W/digest.md"
"$META" set "$W/digest.md" topics misc
awk 'BEGIN{skip=0} /^topics:$/{print "topics: misc"; skip=1; next} skip && /^  - /{next} {skip=0; print}' \
  "$W/digest.orig.md" > "$W/expect.md"
expect_same_file "set: block list -> scalar removes the old item lines" "$W/expect.md" "$W/digest.md"

# Replacing a scalar with two values writes a block list, in place.
cp "$W/digest.orig.md" "$W/digest.md"
"$META" set "$W/digest.md" tags one two
awk '/^tags: /{print "tags:"; print "  - one"; print "  - two"; next} {print}' "$W/digest.orig.md" > "$W/expect.md"
expect_same_file "set: two VALUEs replace a flow list with a block list in place" "$W/expect.md" "$W/digest.md"
out=$("$META" get "$W/digest.md" tags); expect_out "set/get: the block list reads back" "$(printf 'one\ntwo')" "$out"

# One value with --list is still a list.
cp "$W/digest.orig.md" "$W/digest.md"
"$META" set --list "$W/digest.md" topics misc
awk 'BEGIN{skip=0} /^topics:$/{print "topics:"; print "  - misc"; skip=1; next} skip && /^  - /{next} {skip=0; print}' \
  "$W/digest.orig.md" > "$W/expect.md"
expect_same_file "set: --list with one VALUE writes a one-item block list" "$W/expect.md" "$W/digest.md"

# Appending a missing key goes just before the closing ---, after the blank line.
cp "$W/digest.orig.md" "$W/digest.md"
"$META" set "$W/digest.md" added yes
awk 'NR>1 && /^---$/ && !done {print "added: \"yes\""; done=1} {print}' "$W/digest.orig.md" > "$W/expect.md"
expect_same_file "set: a missing key is appended before the closing --- (and 'yes' is quoted)" "$W/expect.md" "$W/digest.md"

# A file with no frontmatter gets one; the body is untouched.
printf '# No frontmatter\n\nJust a body.\n' > "$W/plain.md"
"$META" set "$W/plain.md" topics a b
printf -- '---\ntopics:\n  - a\n  - b\n---\n# No frontmatter\n\nJust a body.\n' > "$W/expect.md"
expect_same_file "set: a file without frontmatter gets one prepended" "$W/expect.md" "$W/plain.md"

# An empty file is the degenerate case of that.
: > "$W/empty.md"
"$META" set "$W/empty.md" k v
printf -- '---\nk: v\n---\n' > "$W/expect.md"
expect_same_file "set: an empty file gets frontmatter and nothing else" "$W/expect.md" "$W/empty.md"

# Duplicate keys: the first is replaced, the later one removed, so a reader
# that takes the last value (as wiki-curate does) sees the new one.
printf -- '---\nk: old\nother: x\nk: older\n---\nbody\n' > "$W/dup.md"
"$META" set "$W/dup.md" k new
printf -- '---\nk: new\nother: x\n---\nbody\n' > "$W/expect.md"
expect_same_file "set: duplicate keys collapse to the one replaced value" "$W/expect.md" "$W/dup.md"

# Idempotence: setting the value the file already has changes nothing.
cp "$W/digest.orig.md" "$W/digest.md"
"$META" set "$W/digest.md" url "https://example.com/a?b=1"
expect_same_file "set: re-setting the existing value is a byte-level no-op" "$W/digest.orig.md" "$W/digest.md"

# The body's own `---` rule must never be mistaken for the closing fence.
cp "$W/digest.orig.md" "$W/digest.md"
"$META" set "$W/digest.md" url "https://example.com/b"
n=$(grep -c '^---$' "$W/digest.md")
expect_out "set: the horizontal rule in the body survives (three --- lines)" "3" "$n"

# --- topics.md ---------------------------------------------------------------
# Prose around the table, a different column order, an escaped pipe in scope,
# an accented title.
cat > "$W/topics.md" <<'EOF'
# Topics

Every source is filed under one or two of these. Edit freely.

| title | scope | slug |
|---|---|---|
| Agent Orchestration | Multi-agent systems, delegation, a \| in the scope. | agent-orchestration |
| Erdős Problems | Maths done with machines. | erdos |
| Miscellany | Anything that fits none of the above. | misc |

Notes below the table are ignored by the tools.

| unrelated | table |
|---|---|
| x | y |
EOF

out=$("$META" topics); expect_rc "topics: parses with WIKI_PATH" 0 $?
expected=$(printf 'agent-orchestration\tAgent Orchestration\tMulti-agent systems, delegation, a | in the scope.\nerdos\tErdős Problems\tMaths done with machines.\nmisc\tMiscellany\tAnything that fits none of the above.')
expect_out "topics: TSV in file order, columns reordered to slug/title/scope, \\| unescaped" "$expected" "$out"

"$META" topics --json > "$SANDBOX/topics.json"; expect_rc "topics --json" 0 $?
n=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d), d[1]["slug"], d[2]["title"])' "$SANDBOX/topics.json")
expect_out "topics --json: three rows, in order, with the right keys" "3 erdos Miscellany" "$n"

mkdir -p "$SANDBOX/other"; cp "$W/topics.md" "$SANDBOX/other/topics.md"
sed -i '' 's/^| Miscellany /| Other Misc /' "$SANDBOX/other/topics.md"
out=$(WIKI_PATH="$W" "$META" topics --wiki "$SANDBOX/other" | tail -1 | cut -f2)
expect_out "topics: --wiki overrides WIKI_PATH" "Other Misc" "$out"

mkdir -p "$SANDBOX/notopics"
"$META" topics --wiki "$SANDBOX/notopics" >/dev/null 2>"$SANDBOX/err"; expect_rc "topics: absent topics.md" 3 $?
expect_grep "topics: absent topics.md names the path" "no topics.md" "$SANDBOX/err"

env -u WIKI_PATH "$META" topics >/dev/null 2>"$SANDBOX/err"; expect_rc "topics: no WIKI_PATH and no --wiki" 2 $?
expect_grep "topics: the no-WIKI_PATH message says what to do" "WIKI_PATH" "$SANDBOX/err"

# Each validation failure, one at a time, naming the row.
bad() {  # bad <label> <sed-expression-or-heredoc-file> <expected-message-pattern>
  "$META" topics --wiki "$SANDBOX/bad" >/dev/null 2>"$SANDBOX/err"
  expect_rc "topics: rejects $1" 2 $?
  expect_grep "topics: $1 message names the problem" "$2" "$SANDBOX/err"
  grep -q "Traceback" "$SANDBOX/err" && { echo "FAIL: topics: $1 — traceback instead of a message"; fail=1; }
}
mkdir -p "$SANDBOX/bad"
sed 's/| erdos |/| Erdos_Problems |/' "$W/topics.md" > "$SANDBOX/bad/topics.md"
bad "an uppercase/underscore slug" "line 8: slug 'Erdos_Problems'"
sed 's/| erdos |/| misc |/' "$W/topics.md" > "$SANDBOX/bad/topics.md"
bad "a duplicate slug" "line 9: duplicate slug 'misc' (first at line 8)"
sed 's/| Miscellany |/| AGENT ORCHESTRATION |/' "$W/topics.md" > "$SANDBOX/bad/topics.md"
bad "a duplicate title differing only in case" "line 9: duplicate title"
# Same title, decomposed on one row and composed on the other (NFD vs NFC).
python3 - "$W/topics.md" "$SANDBOX/bad/topics.md" <<'PY'
import sys, unicodedata
t = open(sys.argv[1], encoding="utf-8").read()
nfd = unicodedata.normalize("NFD", "Erdős Problems")
t = t.replace("| Miscellany |", "| " + nfd + " |")
open(sys.argv[2], "w", encoding="utf-8").write(t)
PY
bad "a duplicate title that differs only in unicode normalisation" "line 9: duplicate title"
grep -v '| misc |' "$W/topics.md" > "$SANDBOX/bad/topics.md"
bad "a table without misc" "no 'misc' row"
sed 's/| Maths done with machines. | erdos |/| erdos |/' "$W/topics.md" > "$SANDBOX/bad/topics.md"
bad "a row with too few cells" "line 8: expected 3 columns, got 2"
sed 's/| title | scope | slug |/| name | scope | slug |/' "$W/topics.md" > "$SANDBOX/bad/topics.md"
bad "a file with no slug/title/scope table" "no table with slug, title and scope"
sed 's/| Erdős Problems |/| Erdős\/Problems |/' "$W/topics.md" > "$SANDBOX/bad/topics.md"
bad "a title containing a slash" "line 8: title 'Erdős/Problems' contains '/'"

# --- normalize-topics ----------------------------------------------------------
# The fixture topics.md above is the list. Each case is one branch of the
# repair; `expect_topics` checks the resulting block list and the exit code,
# and that nothing outside topics: moved.
norm_case() {  # norm_case <label> <topics-lines...> ; expects NORM_RC, NORM_EXPECT set
  label=$1; shift
  {
    printf -- '---\nurl: https://example.com/n\ntitle: "N"\n'
    for ln in "$@"; do printf '%s\n' "$ln"; done
    printf -- 'date_fetched: 2026-09-11\n---\n\nPrécis.\n'
  } > "$W/n.md"
  "$META" normalize-topics "$W/n.md" >"$SANDBOX/out" 2>"$SANDBOX/err"
  expect_rc "normalize: $label" "$NORM_RC" $?
  got=$("$META" get "$W/n.md" topics)
  expect_out "normalize: $label -> [$NORM_EXPECT]" "$(printf '%b' "$NORM_EXPECT")" "$got"
  # The frontmatter around topics: is untouched and topics: is in block form.
  head -3 "$W/n.md" | tail -2 > "$SANDBOX/head"; printf 'url: https://example.com/n\ntitle: "N"\n' > "$SANDBOX/head.exp"
  cmp -s "$SANDBOX/head" "$SANDBOX/head.exp" || { echo "FAIL: normalize: $label — lines above topics: changed"; fail=1; }
  grep -q '^date_fetched: 2026-09-11$' "$W/n.md" || { echo "FAIL: normalize: $label — line below topics: changed"; fail=1; }
  grep -q '^topics:$' "$W/n.md" || { echo "FAIL: normalize: $label — topics: is not in block form"; fail=1; }
}

NORM_RC=0 NORM_EXPECT='agent-orchestration\nmisc' norm_case "a valid block list is left alone (exit 0)" 'topics:' '  - agent-orchestration' '  - misc'
cp "$W/n.md" "$W/n.before.md"; "$META" normalize-topics "$W/n.md" >/dev/null 2>&1
expect_same_file "normalize: exit 0 means the file is byte-identical" "$W/n.before.md" "$W/n.md"

NORM_RC=1 NORM_EXPECT='agent-orchestration\nmisc' norm_case "a valid flow list is rewritten to block form (exit 1)" 'topics: [agent-orchestration, misc]'
expect_grep "normalize: flow->block reports what it did" "rewritten in block form" "$SANDBOX/out"

NORM_RC=1 NORM_EXPECT='agent-orchestration' norm_case "a title becomes its slug" 'topics:' '  - Agent Orchestration'
NORM_RC=1 NORM_EXPECT='erdos' norm_case "case (and accents) fold on a title" 'topics: ["ERDŐS problems"]'
NORM_RC=1 NORM_EXPECT='agent-orchestration' norm_case "case folds on a slug" 'topics: [Agent-Orchestration]'
NORM_RC=1 NORM_EXPECT='erdos' norm_case "duplicates collapse" 'topics:' '  - erdos' '  - Erdős Problems' '  - erdos'
NORM_RC=1 NORM_EXPECT='agent-orchestration\nerdos' norm_case "more than two truncate to the first two" 'topics: [agent-orchestration, erdos, misc]'
expect_grep "normalize: truncation is reported on stderr" "dropped topic 'misc' (more than two topics)" "$SANDBOX/err"
NORM_RC=1 NORM_EXPECT='erdos' norm_case "an unknown entry is dropped" 'topics:' '  - bogus-topic' '  - erdos'
expect_grep "normalize: the drop names the entry" "dropped topic 'bogus-topic' (not a listed topic)" "$SANDBOX/err"
expect_grep "normalize: the repair is reported on stdout" "repaired \['bogus-topic', 'erdos'\] -> \['erdos'\]" "$SANDBOX/out"
NORM_RC=1 NORM_EXPECT='misc' norm_case "nothing valid -> misc" 'topics: [nonsense]'
NORM_RC=1 NORM_EXPECT='misc' norm_case "an empty list -> misc" 'topics: []'
NORM_RC=1 NORM_EXPECT='misc' norm_case "a bare key with no items -> misc" 'topics:'
NORM_RC=1 NORM_EXPECT='misc' norm_case "a missing key -> misc, appended" 'other: kept'
expect_grep "normalize: the missing key is reported as such" "was missing; set to \['misc'\]" "$SANDBOX/out"
grep -q '^other: kept$' "$W/n.md" || { echo "FAIL: normalize: missing key — neighbouring key lost"; fail=1; }
NORM_RC=1 NORM_EXPECT='agent-orchestration' norm_case "a scalar (not a list) is accepted and rewritten" 'topics: agent-orchestration'
NORM_RC=1 NORM_EXPECT='agent-orchestration\nerdos' norm_case "a comma-separated scalar is split" 'topics: agent-orchestration, erdos'

"$META" normalize-topics --wiki "$SANDBOX/notopics" "$W/n.md" >/dev/null 2>"$SANDBOX/err"
expect_rc "normalize: no topics.md is an error" 2 $?
"$META" normalize-topics "$W/does-not-exist.md" >/dev/null 2>"$SANDBOX/err"
expect_rc "normalize: a missing FILE is an error" 2 $?
grep -q "Traceback" "$SANDBOX/err" && { echo "FAIL: normalize: traceback on a missing file"; fail=1; }

# --- importable --------------------------------------------------------------
# wiki-retag and the migration import this file; the plan names the mechanism.
python3 - "$META" "$W" <<'PY' > "$SANDBOX/import.out" 2>&1
import sys
from importlib.machinery import SourceFileLoader
from importlib.util import spec_from_file_location, module_from_spec
path, wiki = sys.argv[1], sys.argv[2]
spec = spec_from_file_location("wiki_meta", path, loader=SourceFileLoader("wiki_meta", path))
m = module_from_spec(spec); spec.loader.exec_module(m)
meta, body = m.parse_frontmatter("---\na: [x, y]\nb: 'q'\n---\nbody")
assert meta == {"a": ["x", "y"], "b": "q"} and body == "body", meta
assert m.set_key("---\na: 1\n---\n", "t", ["p", "q"]) == "---\na: 1\nt:\n  - p\n  - q\n---\n"
topics = m.load_topics(wiki)
assert [t["slug"] for t in topics] == ["agent-orchestration", "erdos", "misc"]
assert m.normalize(["Miscellany", "misc", "erdos", "x"], topics) == (["misc", "erdos"], ["x"], True)
assert m.normalize(["misc"], topics) == (["misc"], [], False)
try:
    m.load_topics(wiki + "/nope")
except m.TopicsMissing as e:
    assert e.code == 3
print("import ok")
PY
expect_grep "import: the module loads and its four functions behave" "^import ok$" "$SANDBOX/import.out"
grep -q "import ok" "$SANDBOX/import.out" || cat "$SANDBOX/import.out"

[ "$fail" = 0 ] && echo "test-meta: ALL PASS"
exit $fail
