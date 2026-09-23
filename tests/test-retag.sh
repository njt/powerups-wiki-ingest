#!/bin/bash
# Live-fire test of bin/wiki-retag against a THROWAWAY wiki.
#
# Builds a sandbox wiki in a temp dir with a topics.md and six digests whose
# `topics:` come in every shape the corpus has (block, flow, scalar, missing),
# points WIKI_INGEST_CLI at a stub "LLM" whose answer envelope and side effects
# are selected per invocation, and asserts on real git state: the branch's
# commits, the bytes of each digest on the branch, and — after every case —
# that the live checkout has not moved (HEAD ref, main's SHA, working tree).
#
# The properties this file protects, in order:
#   * the live checkout never moves: every write happens in a detached
#     throwaway worktree and the branch ref is moved with update-ref;
#   * only `topics:` lines ever change: a model that writes a stray file or
#     edits a digest body has its batch rejected (exit 5) and nothing of that
#     batch is committed, while earlier batches stay on the branch;
#   * the JSON is extracted tolerantly (a fence, or an object buried in prose),
#     and every answer goes through wiki-meta's normaliser: titles become
#     slugs, unknown slugs are dropped, and an answer that leaves nothing
#     leaves the digest UNCHANGED rather than writing misc.
#
# Targets bash 3.2 (macOS /bin/bash): no mapfile, no associative arrays, no
# negative indexing.

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
RETAG="$BIN/wiki-retag"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-retag-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
# NEVER a real wiki. Everything below writes into this temp dir only.
export WIKI_PATH="$SANDBOX/wiki"
W="$WIKI_PATH"

cleanup_all() {
  if [ -d "$W/.git" ]; then
    git -C "$W" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{print $2}' \
      | while read -r w; do
          [ "$w" = "$W" ] && continue
          git -C "$W" worktree remove --force "$w" >/dev/null 2>&1 || true
        done
    git -C "$W" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$SANDBOX"
  return 0
}
trap cleanup_all EXIT

# --- stub LLM ----------------------------------------------------------------
# wiki-retag pipes its prompt to $WIKI_INGEST_CLI with the throwaway worktree
# as cwd. The stub learns which digests are in the batch from the prompt's
# "## SUMMARY: <slug>" lines, looks each one up in $STUB_ANSWERS (lines of
# "slug|json-list"; a slug with no line gets no answer), and emits the map in
# the envelope its mode dictates. Modes come from $STUB_MODES, a comma list
# consumed one per invocation (the last one repeats), so a three-batch run can
# behave on batch 2 alone.
#
# Side channels, both OUTSIDE the worktree so they cannot trip the validation:
#   $STUB_LOG — one line per invocation: "<n>|<mode>|<slugs in the batch>".
#   $STUB_PROMPT — the last prompt, verbatim.
STUB="$SANDBOX/stub-cli"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
set -u
if [ -n "${STUB_ARGV:-}" ]; then printf '%s\n' "$@" > "$STUB_ARGV"; fi   # argv, via wiki-agent
prompt=$(cat)
[ -n "${STUB_PROMPT:-}" ] && printf '%s' "$prompt" > "$STUB_PROMPT"
slugs=$(printf '%s\n' "$prompt" | sed -n 's/^## SUMMARY: //p')

n=0; [ -f "$STUB_LOG" ] && n=$(wc -l < "$STUB_LOG" | tr -d ' ')
n=$((n + 1))
mode=$(printf '%s' "${STUB_MODES:-json-fence}" | awk -F, -v k="$n" '{ if (k > NF) k = NF; print $k }')
printf '%s|%s|%s\n' "$n" "$mode" "$(printf '%s' "$slugs" | tr '\n' ' ')" >> "$STUB_LOG"

# The JSON body: one "slug": [...] pair per answered digest.
body=""
for s in $slugs; do
  a=$(awk -F'|' -v k="$s" '$1 == k {print $2}' "${STUB_ANSWERS:-/dev/null}" | head -1)
  [ -n "$a" ] || continue
  [ -n "$body" ] && body="$body, "
  body="$body\"$s\": $a"
done
obj="{$body}"

case "$mode" in
  json-fence)  printf 'Filed.\n\n```json\n%s\n```\n' "$obj" ;;
  # No fence at all, a decoy brace pair first, and the real object mid-sentence.
  prose-json)  printf 'Sure! Here is the mapping {as requested} you wanted: %s and that is all.\n' "$obj" ;;
  # Overrides: an unknown slug plus a real one; a title instead of a slug.
  bad-slug)    printf '```json\n{"s1": ["not-a-topic", "beta"], "s2": ["Beta Things"]}\n```\n' ;;
  empty-list)  printf '```json\n{"s1": [], "s2": ["alpha"]}\n```\n' ;;
  # A correct answer AND an overreach: the batch must be rejected for the file.
  stray-write) printf '```json\n%s\n```\n' "$obj"; printf 'scratch\n' > "summary/stray-digest.md" ;;
  stray-root)  printf '```json\n%s\n```\n' "$obj"; printf 'scratch\n' > "NOTES.md" ;;
  edits-body)  printf '```json\n%s\n```\n' "$obj"; printf '\nAn extra line the model added.\n' >> "summary/s6.md" ;;
  edits-meta)  printf '```json\n%s\n```\n' "$obj"; sed -i.bak 's/^title: .*/title: Renamed by the model/' "summary/s6.md"; rm -f "summary/s6.md.bak" ;;
  garbage)     printf 'I could not decide. Sorry.\n' ;;
  crash)       exit 7 ;;
  *) echo "stub: unknown mode $mode" >&2; exit 1 ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB"
export WIKI_INGEST_CLI="$STUB"
export STUB_ARGV="$SANDBOX/argv"
export STUB_LOG="$SANDBOX/stub.log"
export STUB_PROMPT="$SANDBOX/stub-prompt.txt"
export STUB_ANSWERS="$SANDBOX/answers.txt"
export STUB_MODES="json-fence"

# --- fixture wiki --------------------------------------------------------------
mkdir -p "$W/summary" "$W/raw" "$W/topic" "$W/note"
git init -q "$W"
git -C "$W" symbolic-ref HEAD refs/heads/main
git -C "$W" config user.email "test@wiki-ingest.invalid"
git -C "$W" config user.name "wiki-ingest test"

cat > "$W/topics.md" <<'EOF'
# Topics

Prose around the table is allowed and ignored.

| slug | title | scope |
|---|---|---|
| alpha | Alpha Things | Everything alphabetical. |
| beta | Beta Things | Everything about betas. |
| misc | Miscellany | Anything that fits none of the above. |
EOF

words() {  # words <count> <prefix>
  i=0; while [ "$i" -lt "$1" ]; do printf '%s%d ' "$2" "$i"; i=$((i + 1)); done
}
# digest <slug> <topics-frontmatter-lines...>: url, title, the given topics
# lines, a trailing frontmatter key AFTER topics (so an in-place rewrite that
# swallowed the next key would show), then a body long enough to be truncated
# to 200 words in the prompt.
digest() {
  s=$1; shift
  { printf -- '---\nurl: https://example.invalid/%s\ntitle: "Digest %s: a title"\n' "$s" "$s"
    for ln in "$@"; do printf '%s\n' "$ln"; done
    printf 'date_fetched: 2026-09-11\n---\n\n# %s\n\nA precis of %s. ' "$s" "$s"; words 260 "w"; printf '\n\n## Section\n\nMore body.\n'; } > "$W/summary/$s.md"
}
digest s1 'topics:' '  - alpha'                 # block, one entry
digest s2 'topics: [misc]'                       # flow
digest s3                                        # no topics key at all
digest s4 'topics:' '  - misc' '  - alpha'      # block, misc primary
digest s5 'topics: misc'                         # scalar
digest s6 'topics:' '  - beta'                   # the control: no case retags it
printf '# Alpha Things\n\nA compiled page.\n' > "$W/topic/Alpha Things.md"
: > "$W/index.md"
git -C "$W" add -A
git -C "$W" commit -q -m "Seed the fixture wiki"
MAIN_AT_START=$(git -C "$W" rev-parse main)

# --- helpers -------------------------------------------------------------------
check() {  # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then echo "ok: $1 (rc=$3)"; else echo "FAIL: $1 — expected rc=$2, got rc=$3"; fail=1; fi
}
assert() {  # assert <label> <condition-already-evaluated:0|1>
  if [ "$2" = 0 ]; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi
}
branch_exists() { git -C "$W" rev-parse --verify --quiet "refs/heads/$1" >/dev/null 2>&1; }
commits_over_main() { git -C "$W" rev-list --count "main..$1" 2>/dev/null || echo "-"; }
# The topics: value as the branch has it, one item per line, via wiki-meta so
# the assertion reads the same bytes the tools do.
topics_on() {  # topics_on <ref> <slug>
  git -C "$W" show "$1:summary/$2.md" > "$SANDBOX/shown.md" 2>/dev/null || { echo "-"; return; }
  "$BIN/wiki-meta" get "$SANDBOX/shown.md" topics 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}
# Is topics: written in block form on the branch? (The line is bare `topics:`.)
block_form_on() { git -C "$W" show "$1:summary/$2.md" | grep -q '^topics:$'; }
# Everything except the topics: key, byte for byte: strip the key and its
# item lines, then compare with main.
sans_topics() { awk 'BEGIN{skip=0} /^topics:/{skip=1; next} skip && /^  - /{next} {skip=0; print}'; }
same_but_topics() {  # same_but_topics <ref> <slug>
  git -C "$W" show "main:summary/$2.md" | sans_topics > "$SANDBOX/a.md"
  git -C "$W" show "$1:summary/$2.md" | sans_topics > "$SANDBOX/b.md"
  cmp -s "$SANDBOX/a.md" "$SANDBOX/b.md"
}

run_retag() {  # run_retag <name> <args...>; output to $SANDBOX/all.<name>, rc in $RC
  name=$1; shift
  : > "$STUB_LOG"
  "$RETAG" "$@" > "$SANDBOX/all.$name" 2>&1
  RC=$?
}

# The safety property, re-checked after every case.
assert_live_checkout_pristine() {  # <label>
  [ "$(git -C "$W" rev-parse --abbrev-ref HEAD)" = "main" ] \
    || { echo "FAIL: $1 — live checkout is on '$(git -C "$W" rev-parse --abbrev-ref HEAD)', not main"; fail=1; }
  [ "$(git -C "$W" rev-parse main)" = "$MAIN_AT_START" ] \
    || { echo "FAIL: $1 — main advanced to $(git -C "$W" rev-parse main)"; fail=1; }
  [ -z "$(git -C "$W" status --porcelain)" ] \
    || { echo "FAIL: $1 — live working tree is dirty: $(git -C "$W" status --porcelain | tr '\n' ' ')"; fail=1; }
  n=$(git -C "$W" worktree list --porcelain | grep -c '^worktree ')
  [ "$n" = 1 ] \
    || { echo "FAIL: $1 — a throwaway worktree was left behind ($n listed)"; fail=1; }
}

# =============================================================================
# Case 1 — happy path: --all in batches of 2, answers in a json fence.
# Three batches -> three commits. Every digest shape ends up as a block list,
# with every other byte of the digest intact.
# =============================================================================
cat > "$STUB_ANSWERS" <<'EOF'
s1|["beta"]
s2|["alpha", "beta"]
s3|["alpha"]
s4|["beta", "misc"]
s5|["Beta Things", "alpha", "misc"]
s6|["beta"]
EOF
run_retag all --all --batch 2 --branch curate/retag-all
check "all: exits 0" 0 "$RC"
assert "all: the CLI ran through wiki-agent (claude dialect, no session saved)" \
  "$([ "$(cat "$STUB_ARGV")" = "$(printf '%s\n' -p --no-session-persistence --allowedTools Read)" ]; echo $?)"
assert_live_checkout_pristine "all"
assert "all: three batches, three commits on the branch" "$([ "$(commits_over_main curate/retag-all)" = 3 ]; echo $?)"
assert "all: the stub ran three times" "$([ "$(wc -l < "$STUB_LOG" | tr -d ' ')" = 3 ]; echo $?)"
assert "all: s1 block one-entry -> beta" "$([ "$(topics_on curate/retag-all s1)" = "beta" ]; echo $?)"
assert "all: s2 flow -> block [alpha beta]" "$([ "$(topics_on curate/retag-all s2)" = "alpha beta" ]; echo $?)"
assert "all: s2 is in block form on the branch" "$(block_form_on curate/retag-all s2; echo $?)"
assert "all: s3 (no key) gains topics: alpha" "$([ "$(topics_on curate/retag-all s3)" = "alpha" ]; echo $?)"
assert "all: s4 -> [beta misc]" "$([ "$(topics_on curate/retag-all s4)" = "beta misc" ]; echo $?)"
assert "all: s5 title+dup+third -> [beta alpha] (title resolved, dedupe, max two)" \
  "$([ "$(topics_on curate/retag-all s5)" = "beta alpha" ]; echo $?)"
assert "all: s5 scalar is now block form" "$(block_form_on curate/retag-all s5; echo $?)"
assert "all: s6 unchanged (same answer as before) — identical blob" \
  "$([ "$(git -C "$W" rev-parse curate/retag-all:summary/s6.md)" = "$(git -C "$W" rev-parse main:summary/s6.md)" ]; echo $?)"
for s in s1 s2 s3 s4 s5; do
  assert "all: $s differs from main only in topics:" "$(same_but_topics curate/retag-all $s; echo $?)"
done
assert "all: the branch touched only summary/" \
  "$(git -C "$W" diff --name-only main..curate/retag-all | grep -qv '^summary/'; [ $? = 1 ]; echo $?)"
assert "all: the commit message names the batch" \
  "$(git -C "$W" log --format=%s main..curate/retag-all | grep -q 'Retag batch 1/3: 2 of 2'; echo $?)"
assert "all: the final table has a beta row moving 1 -> 5" \
  "$(grep -qE '^beta +1 +5' "$SANDBOX/all.all"; echo $?)"
assert "all: s5's dropped third entry is reported" "$(grep -q "s5: dropped 'misc'" "$SANDBOX/all.all"; echo $?)"
# The prompt carries what the design says it carries.
assert "prompt: the topics table" "$(grep -q '^| alpha | Alpha Things | Everything alphabetical. |$' "$STUB_PROMPT"; echo $?)"
assert "prompt: the current topics" "$(grep -q '^Current topics: beta$' "$STUB_PROMPT"; echo $?)"
assert "prompt: the precis is truncated to 200 words" \
  "$(grep '^Précis' "$STUB_PROMPT" | head -1 | grep -q 'w192 .*…$' && ! grep -q 'w250' "$STUB_PROMPT"; echo $?)"

# Re-running onto the SAME branch builds on it: the base is the branch tip,
# so the prompt shows the retagged state and a no-change answer commits nothing.
run_retag again --all --batch 10 --branch curate/retag-all
check "again: exits 0" 0 "$RC"
assert "again: prompt shows s1's branch state (beta), not main's (alpha)" \
  "$(awk '/^## SUMMARY: s1$/{f=1} f && /^Current topics:/{print; exit}' "$STUB_PROMPT" | grep -q 'beta$'; echo $?)"
assert "again: nothing to change, no new commit" "$([ "$(commits_over_main curate/retag-all)" = 3 ]; echo $?)"
assert_live_checkout_pristine "again"

# =============================================================================
# Case 2 — prose around the JSON, no fence, a decoy {…} first. Same answers.
# =============================================================================
STUB_MODES=prose-json run_retag prose --all --batch 10 --branch curate/retag-prose
check "prose-json: exits 0" 0 "$RC"
assert "prose-json: one commit" "$([ "$(commits_over_main curate/retag-prose)" = 1 ]; echo $?)"
assert "prose-json: s2 -> [alpha beta]" "$([ "$(topics_on curate/retag-prose s2)" = "alpha beta" ]; echo $?)"
assert "prose-json: s3 -> alpha" "$([ "$(topics_on curate/retag-prose s3)" = "alpha" ]; echo $?)"
assert_live_checkout_pristine "prose-json"

# =============================================================================
# Case 3 — bad-slug: an unknown slug is dropped, a title is resolved.
# =============================================================================
STUB_MODES=bad-slug run_retag bad --slugs /dev/stdin --branch curate/retag-bad <<'EOF'
# the two the stub answers, one spelt the long way
summary/s1.md
s2
EOF
check "bad-slug: exits 0" 0 "$RC"
assert "bad-slug: s1 keeps only the listed slug -> beta" "$([ "$(topics_on curate/retag-bad s1)" = "beta" ]; echo $?)"
assert "bad-slug: the unknown slug is reported as dropped" "$(grep -q "s1: dropped 'not-a-topic'" "$SANDBOX/all.bad"; echo $?)"
assert "bad-slug: s2 title 'Beta Things' resolves to beta" "$([ "$(topics_on curate/retag-bad s2)" = "beta" ]; echo $?)"
assert "bad-slug: --slugs selected exactly s1 and s2" "$(grep -q '|s1 s2$' "$STUB_LOG"; echo $?)"
assert_live_checkout_pristine "bad-slug"

# =============================================================================
# Case 4 — empty-list: [] leaves the digest unchanged and is reported; the
# other answer in the same batch still lands.
# =============================================================================
STUB_MODES=empty-list run_retag empty --slugs /dev/stdin --branch curate/retag-empty <<'EOF'
s1
s2
EOF
check "empty-list: exits 0" 0 "$RC"
assert "empty-list: s1 is byte-identical to main (not written, not misc)" \
  "$([ "$(git -C "$W" rev-parse curate/retag-empty:summary/s1.md)" = "$(git -C "$W" rev-parse main:summary/s1.md)" ]; echo $?)"
assert "empty-list: it is reported as unchanged" "$(grep -q 's1: answer normalised to nothing; unchanged' "$SANDBOX/all.empty"; echo $?)"
assert "empty-list: s2 -> alpha in the same batch" "$([ "$(topics_on curate/retag-empty s2)" = "alpha" ]; echo $?)"
assert_live_checkout_pristine "empty-list"

# A batch where NOTHING changes creates no branch at all.
printf 's6|["beta"]\n' > "$SANDBOX/answers-noop.txt"
STUB_ANSWERS="$SANDBOX/answers-noop.txt" run_retag noop --slugs /dev/stdin --branch curate/retag-noop <<'EOF'
s6
EOF
check "noop: exits 0" 0 "$RC"
assert "noop: no branch is created when nothing changes" "$(branch_exists curate/retag-noop; [ $? = 1 ]; echo $?)"
assert_live_checkout_pristine "noop"

# =============================================================================
# Case 5 — stray-write on batch 2 of 3: exit 5, batch 1 stays committed, the
# stray file is nowhere, batch 3 never runs.
# =============================================================================
STUB_MODES=json-fence,stray-write run_retag stray --all --batch 2 --branch curate/retag-stray
check "stray-write: exits 5" 5 "$RC"
assert "stray-write: batch 1 is on the branch, batch 2 is not" "$([ "$(commits_over_main curate/retag-stray)" = 1 ]; echo $?)"
assert "stray-write: batch 3 never ran" "$([ "$(wc -l < "$STUB_LOG" | tr -d ' ')" = 2 ]; echo $?)"
assert "stray-write: s1 (batch 1) is retagged" "$([ "$(topics_on curate/retag-stray s1)" = "beta" ]; echo $?)"
assert "stray-write: s3 (batch 2) is not" "$([ "$(topics_on curate/retag-stray s3)" = "" ]; echo $?)"
assert "stray-write: the stray file is not on the branch" \
  "$(git -C "$W" ls-tree -r --name-only curate/retag-stray | grep -q stray-digest; [ $? = 1 ]; echo $?)"
assert "stray-write: the report names the file" "$(grep -q 'summary/stray-digest.md (untracked file)' "$SANDBOX/all.stray"; echo $?)"
assert "stray-write: the report says batch 1 remains" "$(grep -q 'batches 1-1 remain on curate/retag-stray' "$SANDBOX/all.stray"; echo $?)"
assert_live_checkout_pristine "stray-write"

STUB_MODES=stray-root run_retag strayroot --all --batch 10 --branch curate/retag-strayroot
check "stray-root: a file outside summary/ is rejected too" 5 "$RC"
assert "stray-root: nothing committed" "$(branch_exists curate/retag-strayroot; [ $? = 1 ]; echo $?)"
assert_live_checkout_pristine "stray-root"

# =============================================================================
# Case 6 — the model edits a digest BODY (s6, which is also in the batch with
# an unchanged answer): rejected, nothing committed. Same for a frontmatter
# key that is not topics:.
# =============================================================================
STUB_MODES=edits-body run_retag body --all --batch 10 --branch curate/retag-body
check "edits-body: exits 5" 5 "$RC"
assert "edits-body: nothing committed" "$(branch_exists curate/retag-body; [ $? = 1 ]; echo $?)"
assert "edits-body: the report names the body" "$(grep -q 'summary/s6.md (body changed)' "$SANDBOX/all.body"; echo $?)"
assert_live_checkout_pristine "edits-body"

STUB_MODES=edits-meta run_retag meta --all --batch 10 --branch curate/retag-meta
check "edits-meta: a changed title: is rejected" 5 "$RC"
assert "edits-meta: the report names the key" "$(grep -q "summary/s6.md (frontmatter key 'title' changed)" "$SANDBOX/all.meta"; echo $?)"
assert "edits-meta: nothing committed" "$(branch_exists curate/retag-meta; [ $? = 1 ]; echo $?)"
assert_live_checkout_pristine "edits-meta"

# =============================================================================
# Case 7 — --dry-run: the model runs, the map is printed, nothing is written,
# no branch appears.
# =============================================================================
run_retag dry --all --batch 10 --branch curate/retag-dry --dry-run
check "dry-run: exits 0" 0 "$RC"
assert "dry-run: the model was consulted" "$([ -s "$STUB_LOG" ]; echo $?)"
assert "dry-run: no branch" "$(branch_exists curate/retag-dry; [ $? = 1 ]; echo $?)"
assert "dry-run: the proposed map is printed" "$(grep -q "s2: \['misc'\] -> \['alpha', 'beta'\]" "$SANDBOX/all.dry"; echo $?)"
assert "dry-run: the table shows the proposed after-count" "$(grep -qE '^beta +1 +5' "$SANDBOX/all.dry"; echo $?)"
assert "dry-run: says 'would change'" "$(grep -q '5 of 6 digest(s) would change' "$SANDBOX/all.dry"; echo $?)"
assert_live_checkout_pristine "dry-run"

# =============================================================================
# Case 8 — unusable output and a crashing CLI.
# =============================================================================
STUB_MODES=garbage run_retag garbage --all --batch 10 --branch curate/retag-garbage
check "garbage: no JSON anywhere exits 4" 4 "$RC"
assert "garbage: nothing committed" "$(branch_exists curate/retag-garbage; [ $? = 1 ]; echo $?)"
assert_live_checkout_pristine "garbage"
STUB_MODES=crash run_retag crash --all --batch 10 --branch curate/retag-crash
check "crash: a failing CLI exits 4" 4 "$RC"
assert_live_checkout_pristine "crash"

# =============================================================================
# Case 9 — selection. --topic misc picks the misc members in every spelling
# (flow, block-secondary, scalar) and nothing else; --since picks only the
# digests changed since REF; the selectors are mutually exclusive.
# =============================================================================
run_retag topic --topic misc --batch 10 --branch curate/retag-topic --dry-run
check "topic: exits 0" 0 "$RC"
assert "topic: --topic misc selects s2 s4 s5 only" "$(grep -q '|s2 s4 s5$' "$STUB_LOG"; echo $?)"
run_retag title --topic Miscellany --batch 10 --branch curate/retag-topic --dry-run
assert "topic: the title works as well as the slug" "$(grep -q '|s2 s4 s5$' "$STUB_LOG"; echo $?)"
run_retag notopic --topic nope --branch curate/retag-topic --dry-run
check "topic: an unlisted topic exits 3" 3 "$RC"

# A second commit on main touching s3 only; --since main~1 must pick s3 alone.
printf 'date_published: 2025\n' > "$SANDBOX/extra"
awk 'FNR==NR{x=x $0; next} /^date_fetched:/{print; printf "%s\n", x; next} {print}' "$SANDBOX/extra" "$W/summary/s3.md" > "$SANDBOX/s3.new" \
  && mv "$SANDBOX/s3.new" "$W/summary/s3.md"
git -C "$W" add summary/s3.md && git -C "$W" commit -q -m "Touch s3"
MAIN_AT_START=$(git -C "$W" rev-parse main)
run_retag since --since main~1 --batch 10 --branch curate/retag-since
check "since: exits 0" 0 "$RC"
assert "since: only s3 was offered to the model" "$(grep -q '|s3$' "$STUB_LOG"; echo $?)"
assert "since: s3 -> alpha on the branch" "$([ "$(topics_on curate/retag-since s3)" = "alpha" ]; echo $?)"
assert "since: s3's new date_published line survives beside the new key" \
  "$(git -C "$W" show curate/retag-since:summary/s3.md | grep -q '^date_published: 2025$'; echo $?)"
assert_live_checkout_pristine "since"

run_retag two --all --topic misc --branch curate/retag-two
check "selectors: two selectors exit 2" 2 "$RC"
run_retag none --branch curate/retag-none
check "selectors: no selector exits 2" 2 "$RC"
assert "selectors: neither created a branch" \
  "$(branch_exists curate/retag-two || branch_exists curate/retag-none; [ $? = 1 ]; echo $?)"
assert_live_checkout_pristine "selectors"

# Without topics.md there is nothing to retag against: exit 3, model not run.
git -C "$W" rm -q topics.md && git -C "$W" commit -q -m "Drop topics.md"
MAIN_AT_START=$(git -C "$W" rev-parse main)
run_retag notopics --all --branch curate/retag-notopics
check "no topics.md: exits 3" 3 "$RC"
assert "no topics.md: the model never ran" "$([ ! -s "$STUB_LOG" ]; echo $?)"
assert_live_checkout_pristine "no topics.md"

[ "$fail" = 0 ] && echo "test-retag: ALL PASS"
exit $fail
