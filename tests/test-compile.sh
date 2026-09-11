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
# REGRESSION GUARDS. Four bugs this file was written to expose have since been
# fixed in bin/, and the cases that caught them are now ordinary hard checks —
# the suite goes red if any of them comes back:
#   * a compile onto a branch that is checked out in ANOTHER worktree succeeds,
#     and the branch ref advances (git update-ref, not `git branch -f`);
#   * a model that writes nothing exits 6 instead of reporting success, while a
#     GENUINE no-op still exits 0 — both directions are asserted, and they are
#     only distinguishable because the page's mtime is back-dated first;
#   * the dropped-cross-link count is exact, not one short;
#   * an all-blank --themes-file exits 3 with "nothing to compile" instead of
#     dying silently under `set -e`.
# Each case below carries the evidence of the original failure, because that is
# what says which detail of the assertion is load-bearing.
#
# TOPICS (3.0). The second half runs against a second throwaway wiki that has
# topics.md, `topics:` on its digests and a note/ tier. It asserts the compile
# is list-driven: a listed topic with no page is bootstrapped, an unlisted
# theme is refused with exit 3, the source set is `topics:` membership (a
# secondary tag counts, and it is read from the BRANCH so a retag branch is
# seen), wiki-recompile with no arguments walks the list in order and nothing
# else, and wiki-review reports a topic/ -> note/ move as moved, not as a
# deleted page that dropped every link it had. The migration-shaped case (a
# legacy wiki whose topics.md exists only on the branch) runs first, while the
# legacy fixture is still current.
#
# Targets bash 3.2 (macOS /bin/bash): no mapfile, no associative arrays, no
# negative indexing.

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
fail=0

# Resolved through `pwd -P`: git worktree list reports resolved paths, so an
# unresolved $TMPDIR (/var -> /private/var, plus its trailing slash) would make
# the self-exclusion guard in cleanup_all never match. Resolve in a second step,
# not as `cd "$(mktemp -d ...)"`: `cd ""` succeeds in bash and returns the cwd,
# so a failed mktemp would point SANDBOX -- and cleanup_all's rm -rf -- here.
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-compile-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
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
  for wk in "$SANDBOX/wiki" "$SANDBOX/wiki-topics"; do
    [ -d "$wk/.git" ] || continue
    git -C "$wk" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{print $2}' \
      | while read -r w; do
          [ "$w" = "$wk" ] && continue
          git -C "$wk" worktree remove --force "$w" >/dev/null 2>&1 || true
        done
    git -C "$wk" worktree prune >/dev/null 2>&1 || true
  done
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
# The whole prompt, for cases that assert on what the model was TOLD.
[ -n "${STUB_PROMPT:-}" ] && printf '%s' "$prompt" > "$STUB_PROMPT"

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
# work on a page that would otherwise pass, and the "LLM wrote nothing" case
# (gate/silent) is invisible against a stub fixture page.
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
# The two pages the pristine check pins. Paths, because the topics-mode fixture
# below keeps its control page in note/.
THEME_REL="topic/Test Theme.md"
CONTROL_REL="topic/Untouched Page.md"
ORIG_TEST_THEME=$(git -C "$W" rev-parse "main:$THEME_REL")
ORIG_UNTOUCHED=$(git -C "$W" rev-parse "main:$CONTROL_REL")

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
  [ "$(blob_of main "$THEME_REL")" = "$ORIG_TEST_THEME" ] \
    || { echo "FAIL: $1 — $THEME_REL on main is not the original"; fail=1; }
  [ "$(blob_of main "$CONTROL_REL")" = "$ORIG_UNTOUCHED" ] \
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
# The tool appends the authoritative provenance footer itself, so the branch
# page is the model's output plus that footer -- never byte-identical.
# The tool strips any model-written footer and appends the authoritative one,
# so compare the model's body (minus its own footer) rather than raw bytes.
# Ignore blank lines and horizontal rules: the tool normalises the footer onto
# the wiki's house page format (rule, then provenance), so a rule may be added.
prose() { grep -v '^\*Compiled from \|^\*Last compiled:' "$1" \
          | grep -v '^[[:space:]]*$' | grep -v '^-\{3,\}$'; }
prose "$STUB_WROTE" > "$SANDBOX/body-want"
prose "$SANDBOX/on-branch.md" > "$SANDBOX/body-got"
if cmp -s "$SANDBOX/body-want" "$SANDBOX/body-got"; then
  echo "ok: happy: the branch page preserves the compiler's prose verbatim"
else
  echo "FAIL: happy — the branch page altered the compiler's prose"; fail=1
  diff "$SANDBOX/body-want" "$SANDBOX/body-got" | head -12 | sed "s/^/      /"
fi
foot=$(grep '^\*Compiled from ' "$SANDBOX/on-branch.md")
[ "$(printf '%s\n' "$foot" | wc -l | tr -d ' ')" = "1" ] \
  && echo "ok: happy: exactly one tool-written provenance footer" \
  || { echo "FAIL: happy — expected exactly one footer, got: $foot"; fail=1; }
case "$foot" in
  "*Compiled from 2 sources: [[summary/"*"]], [[summary/"*"]]*")
    echo "ok: happy: the footer names both digests" ;;
  *) echo "FAIL: happy — footer does not name 2 digests: $foot"; fail=1 ;;
esac
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

# 3b — the second half of the same regression, and the reason the detached build
# alone was not enough. `git branch -f` REFUSES to move a branch that is checked
# out in another worktree, so wiki-compile used to build the commit and then exit
# 5 with "could not move curate/happy", leaving the branch where it was: for a
# batch run that is the same outcome as the bug the detach was meant to cure —
# every theme fails and the branch never advances. It now moves the ref with
# `git update-ref refs/heads/$BRANCH`, which has no such restriction
# (bin/wiki-compile:277).
check "held-branch: a compile onto a branch held elsewhere succeeds" 0 "$RC"
assert "held-branch: the branch ref advances even though it is checked out elsewhere" \
  "$([ "$(branch_tip curate/happy)" != "$held_tip" ]; echo $?)"
# Should it ever fail again, say whether it at least failed the documented way.
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
# The no-footer gate is retired: the tool now writes the footer itself, so a
# model that omits one can no longer produce a footerless page. What replaces
# it is stronger -- a model that FABRICATES a footer must have it overwritten
# with the authoritative source list. (A 188-source page once came back with
# 117 invented [[summary/...]] slugs; that is what this pins.)
br="curate/footer-authority"
rm -f "$STUB_WROTE"
STUB_MODE="no-footer" run_compile footerauth --theme "Test Theme" --branch "$br"
check "footer: a page whose model wrote no footer still compiles" 0 "$RC"
git -C "$W" show "$br:topic/Test Theme.md" > "$SANDBOX/fa.md" 2>/dev/null
fafoot=$(grep '^\*Compiled from ' "$SANDBOX/fa.md")
case "$fafoot" in
  "*Compiled from 2 sources: [[summary/"*"]], [[summary/"*"]]*")
    echo "ok: footer: the tool supplied the authoritative provenance footer" ;;
  *) echo "FAIL: footer — tool did not append the correct footer: $fafoot"; fail=1 ;;
esac
[ "$(grep -c '^\*Compiled from' "$SANDBOX/fa.md")" = "1" ] \
  && echo "ok: footer: exactly one provenance footer" \
  || { echo "FAIL: footer — expected exactly one footer, got $(grep -c '^\*Compiled from' "$SANDBOX/fa.md")"; fail=1; }
assert_live_checkout_pristine "footer"
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

# The dropped-link COUNT must be exact, not merely non-zero. It used to be one
# short: `printf '%s' "$LOST" | tr ';' '\n' | wc -l` counted newlines in a string
# printf deliberately leaves unterminated, so N dropped links were reported as
# N-1 and a single dropped link read "dropped 0 cross-link(s)" — the names right,
# the number wrong, which is the shape of report a reader dismisses. The count is
# now emitted by the python helper that computes it (bin/wiki-compile:235).
assert "gate/droplink: one dropped link is reported as 'dropped 1'" \
  "$(grep -q 'dropped 1 cross-link' "$SANDBOX/all.droplink"; echo $?)"
assert "gate/droplinks: two dropped links are reported as 'dropped 2'" \
  "$(grep -q 'dropped 2 cross-link' "$SANDBOX/all.droplinks"; echo $?)"

# The gate's negative half: links that MOVED — realiased, anchored, resited in
# the prose — have not been dropped. Without this, the gate could be "the page
# must still contain these literal strings" and the suite would not notice.
rm -f "$STUB_WROTE"
STUB_MODE=alias-links run_compile alias --theme "Test Theme" --branch curate/alias
check "gate/alias: realiased and anchored links are not 'dropped'" 0 "$RC"
assert_live_checkout_pristine "gate/alias"

# A compiler that writes NOTHING must be reported as a failure, not as success.
#
# The `[ -f "$WT/$PAGE_REL" ]` check cannot fire in the situation it is named
# for: the throwaway worktree is checked out from BASE, so the theme page is
# already on disk before the compiler is invoked. A compiler that writes nothing
# therefore leaves a valid, long, provenance-carrying page, passes every gate,
# stages an empty diff — and wiki-compile used to print "no change (already
# current)" and exit 0, so a batch run of a silently broken model reported 30/30
# compiled. Nothing is committed either way, so this was never a corruption bug;
# what it cost was the ability to tell a dead model from a genuine no-op.
#
# Content cannot make that distinction, and mtime resolution here is whole
# seconds, so the checkout and a legitimate rewrite can land in the same one.
# wiki-compile therefore back-dates the page to 2000-01-01 before invoking the
# model: any write at all moves the mtime to now, so "file untouched" is
# unambiguous, and the untouched case exits 6 (bin/wiki-compile:120,257).
# The other direction — a genuine no-op still exiting 0 — is case 6 below, and
# both halves have to hold or the check is worthless.
rm -f "$STUB_WROTE"
STUB_MODE=nothing run_compile silent --theme "Test Theme" --branch curate/gate-silent
if branch_exists curate/gate-silent; then
  echo "FAIL: gate/silent — a compiler that wrote nothing still produced a commit"; fail=1
else
  echo "ok: gate/silent: a compiler that writes nothing commits nothing"
fi
check "gate/silent: a compiler that writes nothing exits 6" 6 "$RC"
assert "gate/silent: it says the model never wrote the page" \
  "$(grep -q 'the model never wrote topic/Test Theme.md (file untouched)' "$SANDBOX/all.silent"; echo $?)"
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
# empty commit. This is the other half of gate/silent above: the model DID write,
# it just wrote what was already there, and that must still exit 0. An
# untouched-file check that fires here would be indistinguishable from one that
# never fires at all.
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

# An empty (or all-blank) --themes-file must be refused, and must SAY so. It used
# to die silently: `grep -v '^[[:space:]]*$' file > LIST` exits 1 when it matches
# nothing, and under `set -euo pipefail` that killed wiki-recompile before the
# "nothing to compile" branch could be reached — rc=1 and not a word of output,
# which in an unattended run is indistinguishable from a crash. The grep now
# carries `|| true` (bin/wiki-recompile:44), so the empty list reaches the check
# that explains it.
printf '\n\n' > "$SANDBOX/blank.txt"
"$BIN/wiki-recompile" --themes-file "$SANDBOX/blank.txt" --branch curate/blank \
  >"$SANDBOX/out.blank" 2>&1
RC=$?
check "recompile-blank: an all-blank themes-file is refused" 3 "$RC"
assert "recompile-blank: it says why" \
  "$(grep -q 'nothing to compile' "$SANDBOX/out.blank"; echo $?)"

# --- branch fixtures -----------------------------------------------------------
# make_branch <wiki> <branch> <fn>: run <fn> with a detached worktree of main as
# CWD, commit everything it did, and point <branch> at the result. The live
# checkout is never touched, the same way the tools under test never touch it.
make_branch() {
  mk_wiki="$1"; mk_br="$2"; mk_fn="$3"
  mk_name="${mk_br//\//-}"; mk_wt="$SANDBOX/mk-$mk_name"
  git -C "$mk_wiki" worktree add --quiet --detach "$mk_wt" main \
    || { echo "FAIL: fixture — could not open a worktree for $mk_br"; fail=1; return; }
  ( cd "$mk_wt" && "$mk_fn" )
  git -C "$mk_wt" add -A
  git -C "$mk_wt" commit -q -m "fixture: $mk_br"
  git -C "$mk_wiki" update-ref "refs/heads/$mk_br" "$(git -C "$mk_wt" rev-parse HEAD)"
  git -C "$mk_wiki" worktree remove --force "$mk_wt"
}

# Digest with a `topics:` list. digest <slug> <form:block|flow> <slug...>
digest() {
  d_slug="$1"; d_form="$2"; shift 2
  { printf -- '---\nurl: https://example.invalid/%s\ntitle: "%s"\n' "$d_slug" "$d_slug"
    if [ "$d_form" = flow ]; then
      printf 'topics: [%s]\n' "$(printf '%s, ' "$@" | sed 's/, $//')"
    else
      printf 'topics:\n'; for t in "$@"; do printf '  - %s\n' "$t"; done
    fi
    printf -- '---\n\nA precis of %s. ' "$d_slug"; words 60 "s"; printf '\n'; } \
    > "summary/$d_slug.md"
}

echo ""
echo "=== topics: migration-shaped branch on the legacy wiki ==="

# =============================================================================
# Case 8 — topics.md exists only on the BRANCH. This is the migration: main has
# no topics.md, the branch has one plus `topics:` on two digests, and
# wiki-recompile onto that branch must select from the branch (the listed topic
# and nothing else), not from main's legacy theme list. Selecting from main
# would have compiled Other Theme / Fail Theme / ARIES here.
# =============================================================================
mig_fixture() {
  printf '| slug | title | scope |\n|---|---|---|\n' > topics.md
  printf '| test-topic | Test Theme | Scope sentence for the test topic. |\n' >> topics.md
  printf '| misc | Miscellany | Anything else. |\n' >> topics.md
  digest alpha block test-topic
  digest beta  block test-topic
}
make_branch "$W" curate/mig mig_fixture
: > "$STUB_LOG"
STUB_REV=21 "$BIN/wiki-recompile" --branch curate/mig >"$SANDBOX/out.mig" 2>&1
check "migration-branch: recompile onto a branch that carries topics.md" 0 "$?"
[ "$(tr '\n' ' ' < "$STUB_LOG")" = "topic/Test Theme.md|good " ] \
  || { echo "FAIL: migration-branch — selection did not come from the branch: $(tr '\n' ' ' < "$STUB_LOG")"; fail=1; }
grep -q '^compiled 1   skipped 1   failed 0' "$SANDBOX/out.mig" \
  || { echo "FAIL: migration-branch — wrong tally: $(grep -E '^compiled ' "$SANDBOX/out.mig")"; fail=1; }
[ ! -f "$W/topics.md" ] \
  || { echo "FAIL: migration-branch — topics.md leaked into the live checkout"; fail=1; }
echo "ok: migration-branch: only the listed topic compiled, selected from the branch"
assert_no_stray_worktrees "migration-branch"
assert_live_checkout_pristine "migration-branch"

echo ""
echo "=== topics: wiki with topics.md ==="

# --- topics fixture ------------------------------------------------------------
# A second wiki, so the legacy fixture's pristine checks stay exact. Three
# topics: one with a page (Test Theme), one without (Fresh Topic), and misc.
# Membership is declared by the digests, block and flow form both:
#   Test Theme  <- alpha, beta, delta (delta names it SECOND)
#   Fresh Topic <- gamma, delta
#   misc        <- epsilon (one member: wiki-compile must skip it)
# note/ holds the two cross-link targets and a legacy multi-source page that
# has the shape of a compiled theme but is not on the list.
W2="$SANDBOX/wiki-topics"
mkdir -p "$W2/topic" "$W2/note" "$W2/summary" "$W2/raw"
git init -q "$W2"
git -C "$W2" symbolic-ref HEAD refs/heads/main
git -C "$W2" config user.email "test@wiki-ingest.invalid"
git -C "$W2" config user.name "wiki-ingest test"
: > "$W2/index.md"; : > "$W2/log.md"
{ printf '# Topics\n\nProse the tools ignore.\n\n'
  printf '| slug | title | scope |\n|---|---|---|\n'
  printf '| test-topic | Test Theme | Scope sentence for the test topic. |\n'
  printf '| fresh-topic | Fresh Topic | A topic that has no page yet. |\n'
  printf '| misc | Miscellany | Anything else. |\n'; } > "$W2/topics.md"
( cd "$W2" \
  && digest alpha   block test-topic \
  && digest beta    flow  test-topic \
  && digest gamma   block fresh-topic \
  && digest delta   block fresh-topic test-topic \
  && digest epsilon block misc )
for s in alpha beta gamma delta epsilon; do
  printf -- '---\nurl: https://example.invalid/%s\n---\n\nVerbatim %s.\n' "$s" "$s" > "$W2/raw/$s.md"
done
seed_page() {  # seed_page <path> <title> <src-a> <src-b>
  { printf '# %s\n\nThe pre-compile version of this page.\n\n' "$2"
    printf 'It sits beside [[Untouched Page]] and [[Neighbour Page]].\n\n'
    words 300 "orig"; printf '\n\n'
    printf '*Compiled from 2 sources: [[summary/%s]], [[summary/%s]]*\n' "$3" "$4"
  } > "$1"
}
seed_page "$W2/topic/Test Theme.md" "Test Theme" alpha beta
seed_page "$W2/note/Legacy Multi.md" "Legacy Multi" alpha gamma
printf '# Untouched Page\n\nThis page must never change.\n' > "$W2/note/Untouched Page.md"
printf '# Neighbour Page\n\nThe far end of a cross-link.\n' > "$W2/note/Neighbour Page.md"
# The note behind digest delta. Its *Sources:* footer is what ties it to the
# digest; case 11 asserts the compile context names it so the compiler can link
# it (a digest never names its note, and a first compile saw none — rehearsal
# 2026-09-11: a new 17-source page with zero cross-links).
printf '# Delta Note\n\nThe analysis of delta.\n\n---\n*Sources: [[raw/delta]], [[summary/delta]]*\n' > "$W2/note/Delta Note.md"
git -C "$W2" add -A
git -C "$W2" commit -q -m "Seed the topics fixture wiki"

# Re-point every helper at the topics wiki.
W="$W2"; export WIKI_PATH="$W2"
W_REAL=$(cd "$W" && pwd -P)
MAIN_AT_START=$(git -C "$W" rev-parse main)
THEME_REL="topic/Test Theme.md"
CONTROL_REL="note/Untouched Page.md"
ORIG_TEST_THEME=$(git -C "$W" rev-parse "main:$THEME_REL")
ORIG_UNTOUCHED=$(git -C "$W" rev-parse "main:$CONTROL_REL")
export STUB_PROMPT="$SANDBOX/stub-prompt.txt"

# =============================================================================
# Case 9 — bootstrap. A listed topic with no page compiles: the page is created
# on the branch, and the footer is exactly the tagged members (sorted), which
# is the only way it can be right because there was no page to inherit from.
# =============================================================================
rm -f "$STUB_WROTE" "$STUB_PROMPT"
run_compile boot --theme "Fresh Topic" --branch curate/boot
check "bootstrap: a listed topic with no page compiles" 0 "$RC"
grep -q 'first compile' "$SANDBOX/all.boot" \
  || { echo "FAIL: bootstrap — output does not say it was a first compile: $(cat "$SANDBOX/all.boot")"; fail=1; }
[ "$(commit_files curate/boot)" = "topic/Fresh Topic.md" ] \
  || { echo "FAIL: bootstrap — commit touched: $(commit_files curate/boot | tr '\n' ' ')"; fail=1; }
bootfoot=$(git -C "$W" show "curate/boot:topic/Fresh Topic.md" 2>/dev/null | grep '^\*Compiled from ')
[ "$bootfoot" = "*Compiled from 2 sources: [[summary/delta]], [[summary/gamma]]*" ] \
  && echo "ok: bootstrap: footer lists exactly the tagged members" \
  || { echo "FAIL: bootstrap — footer is '$bootfoot'"; fail=1; }
grep -q 'first compile of this topic' "$STUB_PROMPT" \
  || { echo "FAIL: bootstrap — the prompt did not tell the model the page is new"; fail=1; }
[ ! -e "$W/topic/Fresh Topic.md" ] \
  || { echo "FAIL: bootstrap — the new page appeared in the live checkout"; fail=1; }
assert_no_stray_worktrees "bootstrap"
assert_live_checkout_pristine "bootstrap"

# By slug as well as by title.
run_compile bootslug --theme fresh-topic --branch curate/boot-slug
check "bootstrap: the topic resolves by slug too" 0 "$RC"
[ "$(commit_files curate/boot-slug)" = "topic/Fresh Topic.md" ] \
  || { echo "FAIL: bootstrap-slug — commit touched: $(commit_files curate/boot-slug | tr '\n' ' ')"; fail=1; }

# The dead-model check must work on a first compile too: a model that writes
# nothing has to read as "the model never wrote" (exit 6), not as a validation
# failure on a missing page (exit 5). Both fail, but only one names the actual
# problem. (The seed is not the only thing holding this up -- `touch -t` on the
# back-dating line creates a missing file as well -- which is why the mutation
# that skips the seed is caught by the first-compile assertions above, not here.)
rm -f "$STUB_WROTE"
STUB_MODE=nothing run_compile bootsilent --theme "Fresh Topic" --branch curate/boot-silent
check "bootstrap: a dead model on a first compile exits 6, not 5" 6 "$RC"
assert "bootstrap: it says the model never wrote the (seeded) page" \
  "$(grep -q 'the model never wrote topic/Fresh Topic.md (file untouched)' "$SANDBOX/all.bootsilent"; echo $?)"
branch_exists curate/boot-silent \
  && { echo "FAIL: bootstrap-silent — a branch was created"; fail=1; }
assert_live_checkout_pristine "bootstrap-silent"

# =============================================================================
# Case 10 — an unlisted theme is refused: exit 3, wiki-curate's message, the
# model never runs. A legacy multi-source page in note/ has exactly the shape
# the old compiler accepted, so it is the theme to try.
# =============================================================================
run_compile unlisted --theme "Legacy Multi" --branch curate/unlisted
check "unlisted: a note/ page that looks like a theme is refused" 3 "$RC"
grep -q 'not a listed topic; add it to topics.md and retag' "$SANDBOX/all.unlisted" \
  || { echo "FAIL: unlisted — wrong message: $(cat "$SANDBOX/all.unlisted")"; fail=1; }
[ ! -s "$STUB_LOG" ] \
  || { echo "FAIL: unlisted — the CLI was invoked"; fail=1; }
branch_exists curate/unlisted \
  && { echo "FAIL: unlisted — a branch was created"; fail=1; }
echo "ok: unlisted: refused with the topics.md message, model never invoked"
run_compile unlisted2 --theme "No Such Topic" --branch curate/unlisted2
check "unlisted: an unknown name is refused the same way" 3 "$RC"
grep -q 'not a listed topic' "$SANDBOX/all.unlisted2" \
  || { echo "FAIL: unlisted2 — wrong message: $(cat "$SANDBOX/all.unlisted2")"; fail=1; }
# misc has one member: the 2-source floor still applies to a listed topic.
run_compile misc1 --theme misc --branch curate/misc
check "unlisted: a listed topic with one member is skipped (exit 3)" 3 "$RC"
grep -q 'has 1 source(s); a theme page needs 2+' "$SANDBOX/all.misc1" \
  || { echo "FAIL: misc — wrong message: $(cat "$SANDBOX/all.misc1")"; fail=1; }
assert_no_stray_worktrees "unlisted"
assert_live_checkout_pristine "unlisted"

# =============================================================================
# Case 11 — the source set is `topics:` membership in either position, and the
# prompt carries the scope line. delta names test-topic SECOND; it must be in
# the context and in the footer.
# =============================================================================
run_compile ctx --theme "Test Theme" --branch curate/ctx --dry-run
check "secondary: dry-run assembles the context" 0 "$RC"
grep -q '^## SOURCE: summary/delta.md' "$DRY_CTX" \
  && echo "ok: secondary: a digest that names the topic second is in the context" \
  || { echo "FAIL: secondary — summary/delta.md is missing from the context"; fail=1; }
grep -q '^Digests: 3\.' "$DRY_CTX" \
  || { echo "FAIL: secondary — context header does not count 3 digests: $(head -3 "$DRY_CTX")"; fail=1; }
# The note behind delta is named right under delta's SOURCE heading, and a
# digest with no note gets no such line.
awk '/^## SOURCE: summary\/delta\.md/{f=1;next} f&&/^## SOURCE/{exit} f&&/^Note page: \[\[Delta Note\]\]$/{found=1} END{exit !found}' "$DRY_CTX" \
  && echo "ok: notes: the context names the note behind digest delta" \
  || { echo "FAIL: notes — no 'Note page: [[Delta Note]]' under summary/delta.md in the context"; fail=1; }
# Legacy Multi cites alpha (and gamma, which is not a member), so alpha's block
# names it; beta is cited by nothing and gets no line. Exactly two lines in all.
awk '/^## SOURCE: summary\/alpha\.md/{f=1;next} f&&/^## SOURCE/{exit} f&&/^Note page: \[\[Legacy Multi\]\]$/{found=1} END{exit !found}' "$DRY_CTX" \
  || { echo "FAIL: notes — alpha's block does not name [[Legacy Multi]]"; fail=1; }
[ "$(grep -c '^Note page:' "$DRY_CTX")" = 2 ] \
  || { echo "FAIL: notes — expected exactly two Note page lines, got $(grep -c '^Note page:' "$DRY_CTX")"; fail=1; }
rm -f "$STUB_WROTE" "$STUB_PROMPT"
run_compile scope --theme "Test Theme" --branch curate/scope
check "scope: a listed topic with a page compiles" 0 "$RC"
grep -q '^SCOPE: Scope sentence for the test topic\.$' "$STUB_PROMPT" \
  && echo "ok: scope: the prompt carries the topics.md scope line" \
  || { echo "FAIL: scope — no SCOPE line in the prompt"; fail=1; }
grep -q 'names this topic second may be mentioned lightly' "$STUB_PROMPT" \
  || { echo "FAIL: scope — the secondary-source sentence is missing from the prompt"; fail=1; }
grep -q 'Note page: \[\[Title\]\]' "$STUB_PROMPT" \
  || { echo "FAIL: scope — the prompt does not explain the Note page lines"; fail=1; }
grep -q 'PRESERVE EVERY EXISTING LINK' "$STUB_PROMPT" \
  || { echo "FAIL: scope — the link-preservation rule went missing from the prompt"; fail=1; }
scopefoot=$(git -C "$W" show "curate/scope:topic/Test Theme.md" 2>/dev/null | grep '^\*Compiled from ')
[ "$scopefoot" = "*Compiled from 3 sources: [[summary/alpha]], [[summary/beta]], [[summary/delta]]*" ] \
  && echo "ok: secondary: the footer lists all three members" \
  || { echo "FAIL: secondary — footer is '$scopefoot'"; fail=1; }
assert_live_checkout_pristine "scope"

# The link-preservation gate still bites in topics mode.
gate_case topicdrop drop-one-link 'cross-link(s)'

# =============================================================================
# Case 12 — the source set is read from the BRANCH. A retag branch moves
# epsilon from misc to fresh-topic; compiling Fresh Topic onto that branch must
# see three members, which main's digests do not say.
# =============================================================================
retag_fixture() { digest epsilon block fresh-topic; }
make_branch "$W" curate/retagged retag_fixture
run_compile retag --theme "Fresh Topic" --branch curate/retagged
check "retag-branch: compile onto a branch whose digests were retagged" 0 "$RC"
retagfoot=$(git -C "$W" show "curate/retagged:topic/Fresh Topic.md" 2>/dev/null | grep '^\*Compiled from ')
[ "$retagfoot" = "*Compiled from 3 sources: [[summary/delta]], [[summary/epsilon]], [[summary/gamma]]*" ] \
  && echo "ok: retag-branch: the source set came from the branch, not the live checkout" \
  || { echo "FAIL: retag-branch — footer is '$retagfoot'"; fail=1; }
assert_no_stray_worktrees "retag-branch"
assert_live_checkout_pristine "retag-branch"

# =============================================================================
# Case 13 — wiki-recompile with no arguments: every listed topic, in topics.md
# order, and nothing else. Miscellany is offered and skipped by the compiler's
# floor; Legacy Multi in note/ is never offered at all.
# =============================================================================
: > "$STUB_LOG"
STUB_REV=31 "$BIN/wiki-recompile" --branch curate/all >"$SANDBOX/out.all" 2>&1
check "recompile-topics: no-args run completes" 0 "$?"
got=$(cut -d'|' -f1 "$STUB_LOG" | tr '\n' ' ')
[ "$got" = "topic/Test Theme.md topic/Fresh Topic.md " ] \
  && echo "ok: recompile-topics: the listed topics, in topics.md order, and nothing else" \
  || { echo "FAIL: recompile-topics — compiled: $got"; fail=1; }
grep -q '^compiled 2   skipped 1   failed 0' "$SANDBOX/out.all" \
  || { echo "FAIL: recompile-topics — wrong tally: $(grep -E '^compiled ' "$SANDBOX/out.all")"; fail=1; }
grep -q 'Legacy Multi' "$STUB_LOG" \
  && { echo "FAIL: recompile-topics — a legacy note/ page was compiled"; fail=1; }
changed=$(git -C "$W" diff --name-only "$MAIN_AT_START" curate/all | sort | tr '\n' '|')
[ "$changed" = "topic/Fresh Topic.md|topic/Test Theme.md|" ] \
  || { echo "FAIL: recompile-topics — branch changes the wrong set of files: $changed"; fail=1; }
assert_no_stray_worktrees "recompile-topics"
assert_live_checkout_pristine "recompile-topics"

# --top caps the list from the front.
: > "$STUB_LOG"
STUB_REV=32 "$BIN/wiki-recompile" --top 1 --branch curate/top1 >"$SANDBOX/out.top1" 2>&1
check "recompile-topics: --top 1" 0 "$?"
[ "$(cut -d'|' -f1 "$STUB_LOG" | tr '\n' ' ')" = "topic/Test Theme.md " ] \
  || { echo "FAIL: recompile-topics-top — compiled: $(cut -d'|' -f1 "$STUB_LOG" | tr '\n' ' ')"; fail=1; }

echo ""
echo "=== wiki-review ==="

# =============================================================================
# Case 14 — a page moved topic/ -> note/ is reported as MOVED. Before
# --find-renames, the migration branch (1133 such moves) read as 1133 deleted
# pages each dropping every link it had. A compile branch with a new page
# renders that page as new, and the Topics table shows membership.
# =============================================================================
move_fixture() { git mv "topic/Test Theme.md" "note/Test Theme.md"; }
make_branch "$W" curate/moved move_fixture
"$BIN/wiki-review" --branch curate/moved > "$SANDBOX/review.moved" 2>"$SANDBOX/review.moved.err"
check "review: renders the moved branch" 0 "$?"
grep -q '^Moved: 1 file' "$SANDBOX/review.moved" \
  && echo "ok: review: a topic/ -> note/ move is reported as Moved" \
  || { echo "FAIL: review — no Moved line: $(cat "$SANDBOX/review.moved" "$SANDBOX/review.moved.err")"; fail=1; }
grep -q 'Cross-links dropped' "$SANDBOX/review.moved" \
  && { echo "FAIL: review — the moved page is reported as having dropped its links"; fail=1; }
grep -q 'Test Theme (deleted)' "$SANDBOX/review.moved" \
  && { echo "FAIL: review — the moved page is listed as deleted"; fail=1; }
grep -q '^## Topics' "$SANDBOX/review.moved" \
  && echo "ok: review: the Topics section renders when the branch has topics.md" \
  || { echo "FAIL: review — no Topics section"; fail=1; }
grep -q '^| Fresh Topic | 2→2 (+0) | no |' "$SANDBOX/review.moved" \
  || { echo "FAIL: review — Fresh Topic membership row wrong: $(grep 'Fresh Topic' "$SANDBOX/review.moved")"; fail=1; }

"$BIN/wiki-review" --branch curate/boot > "$SANDBOX/review.boot" 2>&1
check "review: renders a bootstrap branch" 0 "$?"
grep -q '^| Fresh Topic (new) | 0→' "$SANDBOX/review.boot" \
  && echo "ok: review: the bootstrapped page is listed as new" \
  || { echo "FAIL: review — bootstrapped page not listed as new: $(grep 'Fresh Topic' "$SANDBOX/review.boot")"; fail=1; }
grep -q '^| Fresh Topic | 2→2 (+0) | yes |' "$SANDBOX/review.boot" \
  || { echo "FAIL: review — Topics row does not show the page now exists: $(grep 'Fresh Topic' "$SANDBOX/review.boot")"; fail=1; }
assert_no_stray_worktrees "review"
assert_live_checkout_pristine "review"

echo ""
[ "$fail" = 0 ] && echo "test-compile: ALL PASS"
exit $fail
