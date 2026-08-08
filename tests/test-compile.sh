#!/bin/bash
# Live-fire test of bin/wiki-compile and bin/wiki-recompile.
#
# Builds a THROWAWAY wiki in a temp dir, points WIKI_INGEST_CLI at a stub "LLM"
# that writes exactly the file each case needs, and asserts on real files and
# real git state: branch refs, commit contents, the live checkout's index and
# working tree. No network, no real model, and WIKI_PATH is never a real wiki.
#
# The property this file exists to protect is the one in wiki-compile's header:
# THE LIVE CHECKOUT NEVER MOVES. Every compile happens in a detached throwaway
# worktree and the branch ref is moved afterwards; Nat's Obsidian window stays
# on main with the pre-compile page still on disk. Case 2 asserts that directly,
# and every other case re-checks it in passing via assert_live_checkout_pristine.
#
# KNOWN BUGS. Cases marked `known_bug` assert the behaviour wiki-compile is
# SUPPOSED to have and are currently failing. They print loudly but do not turn
# the suite red, so the suite still has a green baseline to mutation-test
# against. When one is fixed, the case reports "KNOWN BUG APPEARS FIXED" and
# should be promoted to a hard `check`. See the comment on each for the
# evidence. Do not delete a known_bug case to make the output quieter.
#
# Targets bash 3.2 (macOS /bin/bash): no mapfile, no associative arrays, no
# negative indexing.

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
fail=0
known=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-compile-test.XXXXXX")
# NEVER a real wiki. Everything below writes into this temp dir only.
export WIKI_PATH="$SANDBOX/wiki"
HOLDER="$SANDBOX/holder-worktree"    # the extra worktree case 3 stands up

# `wiki-compile --dry-run` writes its context to this FIXED path by design
# (bin/wiki-compile:103), outside anything this test controls. Reap it on the
# way out, but only if the dry-run case is what created it — never delete a
# file that was already there.
DRY_CTX="${TMPDIR:-/tmp}/wiki-compile-context.md"
DRY_CTX_PREEXISTED=0
[ -e "$DRY_CTX" ] && DRY_CTX_PREEXISTED=1

# Reap every worktree this test (or the scripts under test) created before the
# temp dir goes away, so no stale worktree metadata is left in the sandbox repo
# and no directory survives the run.
cleanup_all() {
  if [ -d "$WIKI_PATH/.git" ]; then
    git -C "$WIKI_PATH" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{print $2}' \
      | while read -r w; do
          [ "$w" = "$WIKI_PATH" ] && continue
          git -C "$WIKI_PATH" worktree remove --force "$w" >/dev/null 2>&1 || true
        done
    git -C "$WIKI_PATH" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$SANDBOX"
  [ "$DRY_CTX_PREEXISTED" = 0 ] && rm -f "$DRY_CTX"
  return 0
}
trap cleanup_all EXIT

# --- stub LLM ----------------------------------------------------------------
# wiki-compile pipes its prompt into $WIKI_INGEST_CLI with the throwaway
# worktree as CWD. The stub reads the prompt only to learn which file it has
# been told to write — deriving that from the prompt rather than hard-coding it
# means the stub tracks whatever path wiki-curate resolved for the theme, so a
# case can never pass by writing a file nobody asked for.
#
# Modes are selected by STUB_MODE, or per-theme by a STUB_MODE_MAP file of
# "<page basename>|<mode>" lines — wiki-recompile drives several themes through
# one process environment, and case 7 needs one of them to fail.
#
# Two side-channels, both OUTSIDE the worktree so they cannot themselves trip
# the collateral-file check:
#   $STUB_LOG   — one line per invocation. Empty means the CLI never ran.
#   $STUB_WROTE — a copy of the page as written, for byte-exact comparison
#                 against what actually landed on the branch.
STUB="$SANDBOX/stub-cli"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
set -u
prompt=$(cat)

# "Then write exactly one file: <path>" appears in every compile prompt.
page=$(printf '%s' "$prompt" | sed -n 's/^Then write exactly one file: //p' | head -1)
[ -n "$page" ] || { echo "stub: no target page in the prompt" >&2; exit 1; }
base=$(basename "$page" .md)

mode="${STUB_MODE:-good}"
if [ -n "${STUB_MODE_MAP:-}" ] && [ -f "$STUB_MODE_MAP" ]; then
  m=$(awk -F'|' -v k="$base" '$1 == k {print $2}' "$STUB_MODE_MAP" | head -1)
  [ -n "$m" ] && mode="$m"
fi

[ -n "${STUB_LOG:-}" ] && printf '%s|%s\n' "$page" "$mode" >> "$STUB_LOG"

# 300 filler words: comfortably over wiki-compile's 250-word floor, so the
# short-page case fails for its own reason and not by accident.
filler() { i=0; while [ "$i" -lt 300 ]; do printf 'word%d ' "$i"; i=$((i + 1)); done; printf '\n'; }
# The footer wiki-compile greps for, plus one deliberately dead wikilink. The
# dead link is load-bearing for case 7: it moves an audit count, which is what
# makes the before/after table render a row rather than an empty header.
footer() {
  printf '\nSee also [[Deliberately Absent Page]].\n\n'
  printf '*Compiled from 2 sources: [[summary/alpha]], [[summary/beta]]*\n'
  printf '*Last compiled: 2026-01-01*\n'
}
# The cross-links every seeded theme page already carries. wiki-compile REJECTS
# a compile that drops any of them, so every mode that is meant to fail for some
# OTHER reason has to reproduce these, or it would fail here first.
crosslinks() { printf 'It sits beside [[Untouched Page]] and [[Neighbour Page]].\n\n'; }
good_page() {
  printf '# %s\n\nCompiled thesis, revision %s.\n\n' "$base" "${STUB_REV:-1}"
  crosslinks; filler; footer
}

case "$mode" in
  good)      good_page > "$page" ;;
  nothing)   ;;                      # writes nothing at all; the page survives from BASE
  delete)    rm -f "$page" ;;        # the page genuinely does not exist afterwards
  short)     { printf '# %s\n\nA stub of a page.\n' "$base"; crosslinks; footer; } > "$page" ;;
  conflict)  { printf '# %s\n\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> curate/other\n\n' "$base"
               crosslinks; filler; footer; } > "$page" ;;
  no-footer) { printf '# %s\n\nCompiled thesis.\n\n' "$base"; crosslinks; filler; } > "$page" ;;
  # Good prose that quietly strands a page: one of the two cross-links survives,
  # the other does not.
  drop-one-link) { printf '# %s\n\nCompiled thesis.\n\n' "$base"
               printf 'It sits beside [[Untouched Page]].\n\n'; filler; footer; } > "$page" ;;
  drop-both-links) { printf '# %s\n\nCompiled thesis.\n\n' "$base"; filler; footer; } > "$page" ;;
  # Links may be MOVED (alias, anchor, different sentence) without being lost —
  # the gate compares normalised targets, and this is what stops it from being
  # widened into "the page must contain these literal strings".
  alias-links) { printf '# %s\n\nCompiled thesis.\n\n' "$base"
               printf 'Beside [[Untouched Page|the control]] and [[Neighbour Page#top]].\n\n'
               filler; footer; } > "$page" ;;
  extra)     good_page > "$page"; printf '# Stray\n\nnobody asked for this\n' > "topic/Stray Page.md" ;;
  # The same overreach under a non-ASCII name. git C-quotes such paths in
  # --porcelain output, and the collateral check both excludes and reports by
  # pathspec, so this is the case that proves quoting cannot make it fail open.
  extra-emdash) good_page > "$page"
               printf '# Stray\n\nnobody asked for this\n' > "topic/Stray — Uninvited.md" ;;
  extra-root) good_page > "$page"; printf 'scratch\n' > "NOTES.md" ;;
  crash)     exit 7 ;;
  *) echo "stub: unknown mode $mode" >&2; exit 1 ;;
esac

if [ -n "${STUB_WROTE:-}" ] && [ -f "$page" ]; then
  cat "$page" > "$STUB_WROTE"
fi
exit 0
STUB_EOF
chmod +x "$STUB"
export WIKI_INGEST_CLI="$STUB"
export STUB_LOG="$SANDBOX/stub.log"
export STUB_WROTE="$SANDBOX/stub-wrote.md"

# --- fixture wiki --------------------------------------------------------------
W="$WIKI_PATH"
mkdir -p "$W/topic" "$W/summary" "$W/raw"
git init -q "$W"
# `git init -b` is 2.28+; this spelling works on any git and never touches a
# repo other than the one just created.
git -C "$W" symbolic-ref HEAD refs/heads/main
git -C "$W" config user.email "test@wiki-ingest.invalid"
git -C "$W" config user.name "wiki-ingest test"

words() {  # words <count> <prefix>
  i=0; while [ "$i" -lt "$1" ]; do printf '%s%d ' "$2" "$i"; i=$((i + 1)); done
}

: > "$W/index.md"
: > "$W/log.md"
for s in alpha beta gamma delta epsilon; do
  { printf -- '---\nurl: https://example.invalid/%s\n---\n\n' "$s"
    printf 'A precis of %s. ' "$s"; words 60 "s"; printf '\n'; } > "$W/summary/$s.md"
  { printf -- '---\nurl: https://example.invalid/%s\n---\n\n' "$s"
    printf 'Verbatim source for %s.\n' "$s"; } > "$W/raw/$s.md"
done

# Every theme page is REALISTIC: over the 250-word floor and already carrying a
# provenance footer. That matters — the validation gate can only be shown to
# work on a page that would otherwise pass, and the "LLM wrote nothing" hole
# (known bug B) is invisible against a stub fixture page.
seed_theme() {  # seed_theme <title> <src-a> <src-b>
  { printf '# %s\n\nThe pre-compile version of this page.\n\n' "$1"
    # Cross-links to other topic pages. A theme page is also a directory, and
    # wiki-compile rejects a compile that drops any of these — without them in
    # the fixture the link-preservation gate has nothing to preserve and the
    # cases below would pass against a compiler that had no gate at all.
    printf 'It sits beside [[Untouched Page]] and [[Neighbour Page]].\n\n'
    words 300 "orig"; printf '\n\n'
    if [ -n "${3:-}" ]; then
      printf '*Compiled from 2 sources: [[summary/%s]], [[summary/%s]]*\n' "$2" "$3"
    else
      printf '*Compiled from 1 source: [[summary/%s]]*\n' "$2"
    fi
  } > "$W/topic/$1.md"
}
seed_theme "Test Theme" alpha beta
seed_theme "Other Theme" delta epsilon
seed_theme "Fail Theme" alpha gamma
seed_theme "ARIES — Write-Ahead Logging" alpha delta
seed_theme "Lonely Theme" gamma                 # one source: must be skipped
# A control page no case ever compiles. If a compile ever leaks onto the live
# checkout or into a commit, this is what shows it.
printf '# Untouched Page\n\nThis page must never change.\n' > "$W/topic/Untouched Page.md"
# The other end of the seeded cross-links. Real so that the fixture starts with
# zero dead links and case 7's audit delta is unambiguous.
printf '# Neighbour Page\n\nThe far end of a cross-link.\n' > "$W/topic/Neighbour Page.md"
git -C "$W" add -A
git -C "$W" commit -q -m "Seed the fixture wiki"

MAIN_AT_START=$(git -C "$W" rev-parse main)
ORIG_TEST_THEME=$(git -C "$W" rev-parse "main:topic/Test Theme.md")
ORIG_UNTOUCHED=$(git -C "$W" rev-parse "main:topic/Untouched Page.md")

# --- assertion helpers ---------------------------------------------------------
check() {  # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then
    echo "ok: $1 (rc=$3)"
  else
    echo "FAIL: $1 — expected rc=$2, got rc=$3"
    fail=1
  fi
}

assert() {  # assert <label> <condition-already-evaluated:0|1>
  if [ "$2" = 0 ]; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi
}

# A currently-failing assertion of the behaviour wiki-compile is supposed to
# have. Loud, counted, but not fatal — see the KNOWN BUGS note at the top.
known_bug() {  # known_bug <label> <condition-already-evaluated:0|1>
  if [ "$2" = 0 ]; then
    echo "!! KNOWN BUG APPEARS FIXED — promote to a hard check: $1"
  else
    echo "known-bug (expected fail): $1"
  fi
  known=$((known + 1))
}

branch_exists() { git -C "$W" rev-parse --verify --quiet "refs/heads/$1" >/dev/null 2>&1; }
branch_tip()    { git -C "$W" rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null || echo "-"; }
blob_of()       { git -C "$W" rev-parse "$1:$2" 2>/dev/null || echo "-"; }
# quotePath=false: git C-quotes any path with a non-ASCII byte, and the fixture
# deliberately contains an em-dash page (the wiki's real title convention).
commit_files()  { git -C "$W" -c core.quotePath=false show --name-only --format="" "$1" | grep -v '^$'; }

# The safety property, re-checked after every case. Anything that moves the live
# checkout — a non-throwaway worktree, a stray checkout, an accidental merge —
# fails here even if the case's own assertions pass.
assert_live_checkout_pristine() {  # <label>
  [ "$(git -C "$W" rev-parse --abbrev-ref HEAD)" = "main" ] \
    || { echo "FAIL: $1 — live checkout is on '$(git -C "$W" rev-parse --abbrev-ref HEAD)', not main"; fail=1; }
  [ "$(git -C "$W" rev-parse main)" = "$MAIN_AT_START" ] \
    || { echo "FAIL: $1 — main advanced to $(git -C "$W" rev-parse main)"; fail=1; }
  [ -z "$(git -C "$W" status --porcelain)" ] \
    || { echo "FAIL: $1 — live working tree is dirty: $(git -C "$W" status --porcelain | tr '\n' ' ')"; fail=1; }
  [ "$(blob_of main "topic/Test Theme.md")" = "$ORIG_TEST_THEME" ] \
    || { echo "FAIL: $1 — topic/Test Theme.md on main is not the original"; fail=1; }
  [ "$(blob_of main "topic/Untouched Page.md")" = "$ORIG_UNTOUCHED" ] \
    || { echo "FAIL: $1 — the control page changed"; fail=1; }
}

# wiki-compile must leave no worktree behind. `$HOLDER`, which this test creates
# itself in case 3, is the only permitted extra.
# `git worktree list` prints REALPATHs, and on macOS $TMPDIR is a symlink into
# /private — comparing against the unresolved paths would report the wiki itself
# as a stray worktree.
W_REAL=$(cd "$W" && pwd -P)
HOLDER_REAL="$(cd "$SANDBOX" && pwd -P)/$(basename "$HOLDER")"
assert_no_stray_worktrees() {  # <label>
  extra=$(git -C "$W" worktree list --porcelain | awk '/^worktree /{print $2}' \
          | grep -v "^$W_REAL\$" | grep -v "^$W\$" \
          | grep -v "^$HOLDER_REAL\$" | grep -v "^$HOLDER\$" | tr '\n' ' ')
  [ -z "$extra" ] \
    || { echo "FAIL: $1 — wiki-compile left worktrees behind: $extra"; fail=1; }
}

run_compile() {  # run_compile <tag> <args...>; sets RC, and $SANDBOX/out.<tag>, err.<tag>
  tag="$1"; shift
  : > "$STUB_LOG"
  "$BIN/wiki-compile" "$@" >"$SANDBOX/out.$tag" 2>"$SANDBOX/err.$tag"
  RC=$?
  cat "$SANDBOX/out.$tag" "$SANDBOX/err.$tag" > "$SANDBOX/all.$tag"
}

echo "=== wiki-compile ==="

# =============================================================================
# Case 1 — happy path. The compiled page reaches the branch, byte for byte.
# =============================================================================
rm -f "$STUB_WROTE"
run_compile happy --theme "Test Theme" --branch curate/happy
check "happy: a well-formed page compiles" 0 "$RC"
assert "happy: branch curate/happy was created" "$(branch_exists curate/happy; echo $?)"
[ -f "$STUB_WROTE" ] \
  || { echo "FAIL: happy — the stub was never invoked"; fail=1; }
git -C "$W" show "curate/happy:topic/Test Theme.md" > "$SANDBOX/on-branch.md" 2>/dev/null
if cmp -s "$SANDBOX/on-branch.md" "$STUB_WROTE"; then
  echo "ok: happy: the page on the branch is byte-identical to what the compiler wrote"
else
  echo "FAIL: happy — the branch page differs from the compiler's output"; fail=1
fi
[ "$(branch_tip curate/happy)" != "$MAIN_AT_START" ] \
  || { echo "FAIL: happy — the branch ref did not advance past main"; fail=1; }
[ "$(git -C "$W" rev-parse 'curate/happy^')" = "$MAIN_AT_START" ] \
  || { echo "FAIL: happy — the compile commit is not a child of main"; fail=1; }
[ "$(commit_files curate/happy)" = "topic/Test Theme.md" ] \
  || { echo "FAIL: happy — the commit touched more than the theme page: $(commit_files curate/happy | tr '\n' ' ')"; fail=1; }
git -C "$W" log -1 --format=%s curate/happy | grep -q '^Compile topic/Test Theme from 2 sources$' \
  || { echo "FAIL: happy — commit subject is '$(git -C "$W" log -1 --format=%s curate/happy)'"; fail=1; }
grep -q 'COMPILED topic/Test Theme.md' "$SANDBOX/all.happy" \
  || { echo "FAIL: happy — no COMPILED line: $(cat "$SANDBOX/all.happy")"; fail=1; }
assert_no_stray_worktrees "happy"

# A page whose NAME carries a non-ASCII byte. git C-quotes such paths in
# --porcelain output; the collateral-file check both excludes and reports by
# pathspec, and this is what proves the quoting does not make it reject a
# perfectly good compile.
rm -f "$STUB_WROTE"
run_compile emdash --theme "ARIES — Write-Ahead Logging" --branch curate/emdash
check "happy: a theme whose filename is non-ASCII compiles" 0 "$RC"
[ "$(commit_files curate/emdash)" = "topic/ARIES — Write-Ahead Logging.md" ] \
  || { echo "FAIL: emdash — commit touched: $(commit_files curate/emdash | tr '\n' ' ')"; fail=1; }

# =============================================================================
# Case 2 — THE SAFETY PROPERTY. After two compiles the live checkout has not
# moved: still main, still clean, and topic/Test Theme.md on disk is still the
# pre-compile version. The compiled page exists ONLY on the branch.
# =============================================================================
assert_live_checkout_pristine "live-checkout"
disk_sum=$(git -C "$W" hash-object "$W/topic/Test Theme.md")
[ "$disk_sum" = "$ORIG_TEST_THEME" ] \
  || { echo "FAIL: live-checkout — the file ON DISK is not the original page"; fail=1; }
[ "$(blob_of curate/happy "topic/Test Theme.md")" != "$ORIG_TEST_THEME" ] \
  || { echo "FAIL: live-checkout — the branch page equals the original, so this case proves nothing"; fail=1; }
grep -q '^Compiled thesis' "$W/topic/Test Theme.md" \
  && { echo "FAIL: live-checkout — compiled content leaked into the live working tree"; fail=1; }
[ -z "$(git -C "$W" diff --cached --name-only)" ] \
  || { echo "FAIL: live-checkout — the live index was left staged"; fail=1; }
echo "ok: live-checkout: main, clean, and the original page still on disk after 2 compiles"

# =============================================================================
# Case 3 — the target branch is already checked out in ANOTHER worktree.
#
# This is the regression that cost a 30-theme run: a non-detached
# `git worktree add ... "$BRANCH"` fatals with "already used by worktree" for
# every theme once anything else holds the branch. wiki-compile now builds
# DETACHED, which fixes the add.
# =============================================================================
git -C "$W" worktree add --quiet "$HOLDER" curate/happy \
  || { echo "FAIL: fixture — could not stand up a worktree holding curate/happy"; fail=1; }
held_tip=$(branch_tip curate/happy)
rm -f "$STUB_WROTE"
STUB_REV=2 run_compile held --theme "Test Theme" --branch curate/happy

# 3a — what the detached-worktree fix actually bought, and what regresses if the
# `--detach` is taken back out.
grep -q 'already used by worktree' "$SANDBOX/all.held" \
  && { echo "FAIL: held-branch — worktree add failed with 'already used by worktree'"; fail=1; }
[ -s "$STUB_LOG" ] \
  || { echo "FAIL: held-branch — the compiler never ran; the worktree could not be created"; fail=1; }
echo "ok: held-branch: the throwaway worktree is created and the compiler runs"

# 3b — KNOWN BUG A. The compile still does not SUCCEED. `git branch -f` refuses
# to move a branch that is checked out in another worktree, so wiki-compile
# builds the commit, then exits 5 with "could not move curate/happy" and leaves
# the branch where it was. Observed 2026-08-09 against bin/wiki-compile:216.
# End result for a batch run is the same as the bug it replaced: every theme
# fails and the branch never advances. `git update-ref refs/heads/$BRANCH` has
# no such restriction and would move it.
known_bug "held-branch: a compile onto a branch held elsewhere succeeds (rc=0)" \
  "$([ "$RC" = 0 ]; echo $?)"
known_bug "held-branch: the branch ref advances even though it is checked out elsewhere" \
  "$([ "$(branch_tip curate/happy)" != "$held_tip" ]; echo $?)"
if [ "$RC" != 0 ]; then
  grep -q 'could not move curate/happy' "$SANDBOX/all.held" \
    || { echo "FAIL: held-branch — failed, but not with the documented recovery message: $(cat "$SANDBOX/all.held")"; fail=1; }
fi
git -C "$W" worktree remove --force "$HOLDER"
assert_no_stray_worktrees "held-branch"
assert_live_checkout_pristine "held-branch"

# =============================================================================
# Case 4 — the validation gate. Each must exit non-zero and commit NOTHING.
# Each uses its own fresh branch, so "committed nothing" is asserted as "the
# branch was never created" — the strongest form available.
# =============================================================================
gate_case() {  # gate_case <tag> <mode> <expected message fragment>
  br="curate/gate-$1"
  rm -f "$STUB_WROTE"
  STUB_MODE="$2" run_compile "$1" --theme "Test Theme" --branch "$br"
  if [ "$RC" = 0 ]; then
    echo "FAIL: gate/$1 — expected a non-zero exit, got 0"; fail=1
  else
    echo "ok: gate/$1 rejected (rc=$RC)"
  fi
  grep -q "$3" "$SANDBOX/all.$1" \
    || { echo "FAIL: gate/$1 — expected '$3' in the output, got: $(cat "$SANDBOX/all.$1")"; fail=1; }
  branch_exists "$br" \
    && { echo "FAIL: gate/$1 — branch $br was created; something was committed"; fail=1; }
  assert_no_stray_worktrees "gate/$1"
  assert_live_checkout_pristine "gate/$1"
}

gate_case delete    delete       'VALIDATION FAILED — page not written'
gate_case short     short        'VALIDATION FAILED — page suspiciously short'
gate_case conflict  conflict     'VALIDATION FAILED — conflict markers in output'
gate_case nofooter  no-footer    'VALIDATION FAILED — no provenance footer'
gate_case extra     extra        'VALIDATION FAILED — modified other files'
gate_case extraroot extra-root   'VALIDATION FAILED — modified other files'
gate_case crash     crash        'LLM failed (exit 7)'
# The collateral file under a C-quoted (non-ASCII) name. A per-path `git show`
# style check would fail open here; a pathspec-based one does not.
gate_case extraem   extra-emdash 'VALIDATION FAILED — modified other files'
grep -q 'Stray' "$SANDBOX/all.extraem" \
  || { echo "FAIL: gate/extraem — the stray file is not named in the message: $(cat "$SANDBOX/all.extraem")"; fail=1; }

# Cross-link preservation. A hub page is often the only inbound link a page has,
# so a compile that drops one strands it — measured at 48 of 104 links on one
# hub, and orphans 106 -> 114 wiki-wide.
gate_case droplink  drop-one-link 'cross-link(s)'
grep -q 'Neighbour Page' "$SANDBOX/all.droplink" \
  || { echo "FAIL: gate/droplink — the dropped link is not named: $(cat "$SANDBOX/all.droplink")"; fail=1; }
grep -q 'Untouched Page' "$SANDBOX/all.droplink" \
  && { echo "FAIL: gate/droplink — a link that was KEPT is reported as dropped"; fail=1; }
gate_case droplinks drop-both-links 'cross-link(s)'

# KNOWN BUG D — the dropped-link COUNT is one short.
# `printf '%s' "$LOST" | tr ';' '\n' | wc -l` counts newlines in a string that
# printf deliberately leaves unterminated, so N dropped links are reported as
# N-1: one dropped link reads "dropped 0 cross-link(s)". The names are right;
# only the number is wrong. bin/wiki-compile:223, observed 2026-08-09.
known_bug "gate/droplink: one dropped link is reported as 'dropped 1'" \
  "$(grep -q 'dropped 1 cross-link' "$SANDBOX/all.droplink"; echo $?)"
known_bug "gate/droplinks: two dropped links are reported as 'dropped 2'" \
  "$(grep -q 'dropped 2 cross-link' "$SANDBOX/all.droplinks"; echo $?)"

# The gate's negative half: links that MOVED — realiased, anchored, resited in
# the prose — have not been dropped. Without this, the gate could be "the page
# must still contain these literal strings" and the suite would not notice.
rm -f "$STUB_WROTE"
STUB_MODE=alias-links run_compile alias --theme "Test Theme" --branch curate/alias
check "gate/alias: realiased and anchored links are not 'dropped'" 0 "$RC"
assert_live_checkout_pristine "gate/alias"

# KNOWN BUG B — "the LLM wrote nothing" is reported as SUCCESS.
#
# The `[ -f "$WT/$PAGE_REL" ]` check cannot fire in the situation it is named
# for: the throwaway worktree is checked out from BASE, so the theme page is
# already on disk before the compiler is invoked. A compiler that writes nothing
# therefore leaves a valid, long, provenance-carrying page, passes every gate,
# stages an empty diff, and wiki-compile prints "no change (already current)"
# and exits 0. A batch run of a silently broken model reports 30/30 compiled.
# Observed 2026-08-09 against bin/wiki-compile:180. Nothing is committed, so
# this is not a corruption bug — it is a reporting bug, and it makes a dead
# model indistinguishable from a genuine no-op (case 6).
rm -f "$STUB_WROTE"
STUB_MODE=nothing run_compile silent --theme "Test Theme" --branch curate/gate-silent
if branch_exists curate/gate-silent; then
  echo "FAIL: gate/silent — a compiler that wrote nothing still produced a commit"; fail=1
else
  echo "ok: gate/silent: a compiler that writes nothing commits nothing"
fi
known_bug "gate/silent: a compiler that writes nothing exits non-zero" \
  "$([ "$RC" != 0 ]; echo $?)"
assert_live_checkout_pristine "gate/silent"

# =============================================================================
# Case 5 — too few sources. Exit 3, and the CLI is never invoked at all.
# =============================================================================
run_compile few --theme "Lonely Theme" --branch curate/few
check "few-sources: a 1-source theme is refused" 3 "$RC"
grep -q "has 1 source(s); a theme page needs 2+" "$SANDBOX/all.few" \
  || { echo "FAIL: few-sources — wrong message: $(cat "$SANDBOX/all.few")"; fail=1; }
[ ! -s "$STUB_LOG" ] \
  || { echo "FAIL: few-sources — the CLI was invoked: $(cat "$STUB_LOG")"; fail=1; }
branch_exists curate/few \
  && { echo "FAIL: few-sources — a branch was created"; fail=1; }
echo "ok: few-sources: the model was never invoked"

run_compile nosuch --theme "No Such Theme At All" --branch curate/nosuch
check "unknown-theme: an unknown theme is refused" 3 "$RC"
[ ! -s "$STUB_LOG" ] \
  || { echo "FAIL: unknown-theme — the CLI was invoked"; fail=1; }

# --dry-run: context is assembled, the model is not invoked, nothing commits.
run_compile dry --theme "Test Theme" --branch curate/dry --dry-run
check "dry-run: exits 0" 0 "$RC"
[ ! -s "$STUB_LOG" ] \
  || { echo "FAIL: dry-run — the CLI was invoked"; fail=1; }
branch_exists curate/dry \
  && { echo "FAIL: dry-run — a branch was created"; fail=1; }
grep -q 'DRY RUN' "$SANDBOX/all.dry" \
  || { echo "FAIL: dry-run — no DRY RUN line: $(cat "$SANDBOX/all.dry")"; fail=1; }
assert_live_checkout_pristine "dry-run"

# =============================================================================
# Case 6 — no-op. A byte-identical recompile reports no change and creates no
# empty commit.
# =============================================================================
STUB_REV=7 run_compile noop1 --theme "Other Theme" --branch curate/noop
check "no-op: the first compile commits" 0 "$RC"
tip1=$(branch_tip curate/noop)
n1=$(git -C "$W" rev-list --count curate/noop)
STUB_REV=7 run_compile noop2 --theme "Other Theme" --branch curate/noop
check "no-op: an identical recompile exits 0" 0 "$RC"
grep -q 'no change to topic/Other Theme.md (already current)' "$SANDBOX/all.noop2" \
  || { echo "FAIL: no-op — wrong message: $(cat "$SANDBOX/all.noop2")"; fail=1; }
[ "$(branch_tip curate/noop)" = "$tip1" ] \
  || { echo "FAIL: no-op — the branch ref moved on an identical recompile"; fail=1; }
[ "$(git -C "$W" rev-list --count curate/noop)" = "$n1" ] \
  || { echo "FAIL: no-op — an empty commit was created ($n1 -> $(git -C "$W" rev-list --count curate/noop))"; fail=1; }
echo "ok: no-op: no empty commit, branch ref unmoved"
# The negative half: a DIFFERENT output on the same branch must still commit,
# or "no empty commit" would also pass against a compiler that never commits.
STUB_REV=8 run_compile noop3 --theme "Other Theme" --branch curate/noop
check "no-op: a changed recompile does commit" 0 "$RC"
[ "$(git -C "$W" rev-list --count curate/noop)" = "$((n1 + 1))" ] \
  || { echo "FAIL: no-op — a changed recompile did not add a commit"; fail=1; }
[ "$(git -C "$W" rev-parse 'curate/noop^')" = "$tip1" ] \
  || { echo "FAIL: no-op — the second commit is not stacked on the first"; fail=1; }
assert_no_stray_worktrees "no-op"
assert_live_checkout_pristine "no-op"

echo ""
echo "=== wiki-recompile ==="

# =============================================================================
# Case 7 — the driver. Several themes onto one branch; a mid-list failure does
# not abort the run; the tallies are right; the audit table renders.
# =============================================================================
MODES="$SANDBOX/modes.txt"
printf 'Fail Theme|short\n' > "$MODES"      # theme 2 of 4 fails validation
THEMES="$SANDBOX/themes.txt"
printf 'Test Theme\nFail Theme\nLonely Theme\nOther Theme\n' > "$THEMES"

: > "$STUB_LOG"
STUB_MODE_MAP="$MODES" STUB_REV=11 \
  "$BIN/wiki-recompile" --themes-file "$THEMES" --branch curate/run \
  >"$SANDBOX/out.run" 2>&1
RC=$?
check "recompile: the run completes" 0 "$RC"

grep -q '^compiled 2   skipped 1   failed 1' "$SANDBOX/out.run" \
  || { echo "FAIL: recompile — wrong tally: $(grep -E '^compiled ' "$SANDBOX/out.run")"; fail=1; }
echo "ok: recompile: compiled 2 / skipped 1 / failed 1"

# The mid-list failure must not have aborted the run: theme 4 ran after theme 2
# failed, and its commit is on the branch.
grep -q '^\[4/4\] Other Theme' "$SANDBOX/out.run" \
  || { echo "FAIL: recompile — the run stopped before theme 4"; fail=1; }
grep -q '(FAILED rc=5 — branch unchanged for this theme)' "$SANDBOX/out.run" \
  || { echo "FAIL: recompile — theme 2's failure was not reported"; fail=1; }
grep -q '(skipped: too few sources)' "$SANDBOX/out.run" \
  || { echo "FAIL: recompile — theme 3 was not reported as skipped"; fail=1; }

# Both successes on ONE branch, stacked, and the failed theme absent from it.
[ "$(git -C "$W" rev-list --count "$MAIN_AT_START..curate/run")" = 2 ] \
  || { echo "FAIL: recompile — expected 2 commits on curate/run, got $(git -C "$W" rev-list --count "$MAIN_AT_START..curate/run")"; fail=1; }
changed=$(git -C "$W" diff --name-only "$MAIN_AT_START" curate/run | sort | tr '\n' '|')
[ "$changed" = "topic/Other Theme.md|topic/Test Theme.md|" ] \
  || { echo "FAIL: recompile — branch changes the wrong set of files: $changed"; fail=1; }
[ "$(blob_of curate/run "topic/Fail Theme.md")" = "$(blob_of main "topic/Fail Theme.md")" ] \
  || { echo "FAIL: recompile — the failed theme reached the branch anyway"; fail=1; }
echo "ok: recompile: two themes on one branch, the failed one absent"

# The before/after audit table. The stub's deliberate dead wikilink is what
# moves a count, so a row must render — an empty table would mean the after-audit
# never read the branch.
grep -q 'check *before *after *delta' "$SANDBOX/out.run" \
  || { echo "FAIL: recompile — the audit table header did not render: $(cat "$SANDBOX/out.run")"; fail=1; }
grep -qE '^  dead-links +[0-9]+ +[0-9]+ +\+[0-9]+' "$SANDBOX/out.run" \
  || { echo "FAIL: recompile — no dead-links row; the after-audit did not see the branch"; fail=1; }
grep -q '(audit comparison unavailable)' "$SANDBOX/out.run" \
  && { echo "FAIL: recompile — the audit comparison was unavailable"; fail=1; }
echo "ok: recompile: the before/after audit table renders a real delta"

grep -q "adopt:   git -C \"\$WIKI_PATH\" merge curate/run" "$SANDBOX/out.run" \
  || { echo "FAIL: recompile — the review/adopt/discard footer is missing"; fail=1; }

# The driver must not have moved the live checkout either, and its own audit
# worktree must be gone.
assert_no_stray_worktrees "recompile"
assert_live_checkout_pristine "recompile"

# --min-sources selects the work: with a floor of 2 the 1-source theme is not
# even offered to the compiler.
: > "$STUB_LOG"
STUB_REV=12 "$BIN/wiki-recompile" --top 10 --min-sources 2 --branch curate/top \
  >"$SANDBOX/out.top" 2>&1
check "recompile: --top/--min-sources selects themes itself" 0 "$?"
grep -q 'Lonely Theme' "$STUB_LOG" \
  && { echo "FAIL: recompile-top — the 1-source theme was sent to the compiler"; fail=1; }
[ -s "$STUB_LOG" ] \
  || { echo "FAIL: recompile-top — nothing was compiled at all"; fail=1; }
assert_live_checkout_pristine "recompile-top"

# KNOWN BUG C — an empty (or all-blank) --themes-file dies silently.
# `grep -v '^[[:space:]]*$' file > LIST` exits 1 when it matches nothing, and
# under `set -euo pipefail` that kills wiki-recompile before the "nothing to
# compile" branch at bin/wiki-recompile:52 is ever reached: rc=1, no message.
# Observed 2026-08-09.
: > "$SANDBOX/blank.txt"
printf '\n\n' > "$SANDBOX/blank.txt"
"$BIN/wiki-recompile" --themes-file "$SANDBOX/blank.txt" --branch curate/blank \
  >"$SANDBOX/out.blank" 2>&1
RC=$?
known_bug "recompile: an all-blank themes-file exits 3 with 'nothing to compile'" \
  "$([ "$RC" = 3 ] && grep -q 'nothing to compile' "$SANDBOX/out.blank"; echo $?)"
[ "$RC" != 0 ] \
  || { echo "FAIL: recompile-blank — an empty theme list exited 0"; fail=1; }

echo ""
[ "$known" = 0 ] || echo "test-compile: $known known-bug assertion(s) still failing — see the KNOWN BUGS note at the top of this file"
[ "$fail" = 0 ] && echo "test-compile: ALL PASS"
exit $fail
