#!/bin/bash
# Live-fire test of the post-LLM completeness guard in wiki-ingest-run.
#
# Bootstraps a THROWAWAY wiki in a temp dir, points WIKI_INGEST_CLI at a stub
# "LLM" that writes exactly the files each case needs, and asserts that
# wiki-ingest-run commits only when the ingest actually produced the tiers it
# promised. No network: every case uses --content with a local text file.
#
# Also covers --summary-only (backfill), which has its own completeness check.
#
# Targets bash 3.2 (macOS /bin/bash).

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-guard-test.XXXXXX")
export WIKI_PATH="$SANDBOX/wiki"

cleanup_all() {
  # Reap any worktrees/branches this test left behind before deleting the wiki.
  if [ -d "$WIKI_PATH/.git" ]; then
    git -C "$WIKI_PATH" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{print $2}' \
      | while read -r w; do
          [ "$w" = "$WIKI_PATH" ] && continue
          git -C "$WIKI_PATH" worktree remove --force "$w" >/dev/null 2>&1 || true
        done
  fi
  rm -rf "$SANDBOX"
}
trap cleanup_all EXIT

# --- stub LLM ----------------------------------------------------------------
# wiki-ingest-run invokes $WIKI_INGEST_CLI with the worktree as CWD and the
# prompt on stdin. The stub ignores both and writes whatever STUB_MODE says.
#
# Two families of mode live here. The STUB_SLUG modes hard-code the filename the
# stub writes, which is what the completeness-guard cases need. The *-autoslug
# modes instead read the slug out of the prompt they were handed, so they track
# whatever slug wiki-ingest-run actually chose — required by the collision cases,
# where the slug IS the thing under test and a hard-coded name could not observe
# the script picking a different one.
STUB="$SANDBOX/stub-cli"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
set -u
prompt=$(cat)    # drain the prompt (the *-autoslug modes also read it)
s="${STUB_SLUG:-unknown}"

# "saved verbatim to raw/<slug>.md" appears in every ingest prompt.
prompt_slug() {
  local p
  p=$(printf '%s' "$prompt" | sed -n 's|.*raw/\([A-Za-z0-9._-]*\)\.md.*|\1|p' | head -1)
  [ -n "$p" ] || { echo "stub: could not find a slug in the prompt" >&2; exit 1; }
  printf '%s' "$p"
}

# A complete, well-formed result whose topic page is named after the slug, so
# each case stages a genuinely new topic/ path. (The fixed "topic/Test Page.md"
# of the `good` mode is already committed on main by case 4; a second ingest
# writing identical content stages nothing and trips the completeness guard
# before the auto-commit is ever reached.)
write_good_slug() {
  printf -- '---\nurl: x\n---\n\nprecis\n' > "summary/$s.md"
  printf '# %s\n\nbody\n' "$s" > "topic/$s.md"
  printf -- '- entry\n' >> index.md
  printf -- '- entry\n' >> log.md
}

case "${STUB_MODE:-nothing}" in
  nothing) ;;
  raw-only) ;;                      # leave the pipeline-staged raw/ file alone
  no-summary)
    printf '# Test Page\n\nbody\n' > "topic/Test Page.md"
    printf -- '- entry\n' >> index.md
    printf -- '- entry\n' >> log.md
    ;;
  root-page)
    printf -- '---\nurl: x\n---\n\nprecis\n' > "summary/$s.md"
    printf '# Test Page\n\nbody\n' > "topic/Test Page.md"
    printf '# Stray Title\n\nbody\n' > "Stray Title.md"
    printf -- '- entry\n' >> index.md
    printf -- '- entry\n' >> log.md
    ;;
  good)
    printf -- '---\nurl: x\n---\n\nprecis\n' > "summary/$s.md"
    printf '# Test Page\n\nbody\n' > "topic/Test Page.md"
    printf -- '- entry\n' >> index.md
    printf -- '- entry\n' >> log.md
    ;;
  summary-good)
    printf -- '---\nurl: x\n---\n\nprecis\n' > "summary/$s.md"
    ;;
  summary-overreach)
    printf -- '---\nurl: x\n---\n\nprecis\n' > "summary/$s.md"
    printf '# Extra\n\nbody\n' > "topic/Extra.md"
    printf -- '- entry\n' >> log.md
    ;;
  autoslug)
    # A complete, correct ingest under whatever slug the script chose. The url
    # is copied out of the staged raw/ file so every tier and every log pointer
    # agrees with the archive that actually holds the source.
    s=$(prompt_slug)
    url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    printf -- '---\nurl: %s\n---\n\nprecis of %s\n' "$url" "$url" > "summary/$s.md"
    # Vary the body across re-ingests: a byte-identical rewrite stages nothing,
    # and the completeness guard would then reject for want of a topic/ page.
    printf '# %s\n\nbody rev %s\n' "${TOPIC_TITLE:-Auto Page}" "${TOPIC_REV:-1}" \
      > "topic/${TOPIC_TITLE:-Auto Page}.md"
    printf -- '- entry for %s -> raw/%s.md\n' "$url" "$s" >> index.md
    printf -- '- entry for %s -> raw/%s.md\n' "$url" "$s" >> log.md
    ;;
  summary-autoslug)
    # Backfill under whatever slug --summary-only resolved to. summary/ only.
    s=$(prompt_slug)
    url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    printf -- '---\nurl: %s\n---\n\nprecis of %s\n' "$url" "$url" > "summary/$s.md"
    ;;
  good-slug)
    write_good_slug
    ;;
  # The three mid-operation modes below leave $WIKI_PATH part-way through a git
  # operation at exactly the moment the 2026-08-06 incident did: the captain
  # starts a hand-merge while an ingest is still running. The stub is the
  # natural hook — wiki-ingest-run invokes it partway through, so no sleeps and
  # no flakiness are needed to hit the race.
  mid-merge)
    write_good_slug
    git -C "$WIKI_PATH" merge conflicting --no-edit >/dev/null 2>&1
    ;;
  mid-cherry-pick)
    write_good_slug
    git -C "$WIKI_PATH" cherry-pick conflicting >/dev/null 2>&1
    ;;
  mid-rebase)
    write_good_slug
    git -C "$WIKI_PATH" rebase conflicting >/dev/null 2>&1
    ;;
  *) echo "stub: unknown STUB_MODE ${STUB_MODE:-}" >&2; exit 1 ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB"
export WIKI_INGEST_CLI="$STUB"

# --- scratch wiki -------------------------------------------------------------
"$BIN/wiki-ingest-setup" >/dev/null || { echo "FAIL: wiki-ingest-setup failed"; exit 1; }
git -C "$WIKI_PATH" config user.email "test@wiki-ingest.invalid"
git -C "$WIKI_PATH" config user.name "wiki-ingest test"

# Seed pre-existing pages in every tier. This is load-bearing: the bug being
# tested (kata x04s) was a guard that globbed the whole worktree, so it only
# ever failed on an EMPTY wiki. Against a populated wiki — the real condition —
# the old guard passed unconditionally. Without these seeds the test would look
# green against the broken guard too.
printf -- '---\nurl: https://example.invalid/seeded\n---\n\nseed precis\n' \
  > "$WIKI_PATH/summary/seeded.md"
printf '# Seeded Page\n\nseed body\n' > "$WIKI_PATH/topic/Seeded Page.md"
git -C "$WIKI_PATH" add -A
git -C "$WIKI_PATH" commit -q -m "Seed pre-existing summary/ and topic/ pages"

SRC="$SANDBOX/source.txt"
printf 'This is a plausible article body with enough characters to pass the length check.\n' > "$SRC"

check() {  # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then
    echo "ok: $1 (rc=$3)"
  else
    echo "FAIL: $1 — expected rc=$2, got rc=$3"
    fail=1
  fi
}

head_subject() { git -C "$WIKI_PATH" log -1 --format=%s; }

# --- case 1: LLM writes nothing but raw/ → guard must fire --------------------
before=$(head_subject)
STUB_MODE=raw-only STUB_SLUG=case-one \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-one >/dev/null 2>"$SANDBOX/e1"
check "raw-only ingest is rejected" 1 $?
grep -q "no summary/case-one.md staged" "$SANDBOX/e1" \
  || { echo "FAIL: raw-only — wrong message: $(cat "$SANDBOX/e1")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: raw-only — main advanced to '$(head_subject)'"; fail=1; }

# --- case 2: summary but no topic/ page → guard must fire ---------------------
before=$(head_subject)
STUB_MODE=no-summary STUB_SLUG=case-two \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-two >/dev/null 2>"$SANDBOX/e2"
check "ingest with no summary/ is rejected" 1 $?
grep -q "no summary/case-two.md staged" "$SANDBOX/e2" \
  || { echo "FAIL: no-summary — wrong message: $(cat "$SANDBOX/e2")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: no-summary — main advanced"; fail=1; }

# --- case 3: page written to the wiki root → guard must fire ------------------
before=$(head_subject)
STUB_MODE=root-page STUB_SLUG=case-three \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-three >/dev/null 2>"$SANDBOX/e3"
check "root-written page is rejected" 1 $?
grep -q "wrote new file(s) to the wiki root" "$SANDBOX/e3" \
  || { echo "FAIL: root-page — wrong message: $(cat "$SANDBOX/e3")"; fail=1; }
grep -q "Stray Title.md" "$SANDBOX/e3" \
  || { echo "FAIL: root-page — stray file not named in the message"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: root-page — main advanced"; fail=1; }

# --- case 4: a correct ingest must NOT be rejected ----------------------------
STUB_MODE=good STUB_SLUG=case-four \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-four >/dev/null 2>"$SANDBOX/e4"
check "correct ingest commits" 0 $?
[ "$(head_subject)" = "Ingest: https://example.invalid/case-four" ] \
  || { echo "FAIL: good — HEAD is '$(head_subject)', stderr: $(cat "$SANDBOX/e4")"; fail=1; }
for f in raw/case-four.md summary/case-four.md "topic/Test Page.md"; do
  [ -f "$WIKI_PATH/$f" ] || { echo "FAIL: good — $f missing from the wiki"; fail=1; }
done

# --- case 5: --summary-only backfills an existing raw/ file -------------------
# Seed a raw file with no summary — the situation --summary-only exists for.
printf -- '---\nurl: https://example.invalid/orphan\ndate_fetched: 2026-08-01\n---\n\nOrphan body text.\n' \
  > "$WIKI_PATH/raw/orphan.md"
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed orphan raw file"

STUB_MODE=summary-good STUB_SLUG=orphan \
  "$BIN/wiki-ingest-run" --summary-only orphan >/dev/null 2>"$SANDBOX/e5"
check "--summary-only commits a summary" 0 $?
[ -f "$WIKI_PATH/summary/orphan.md" ] \
  || { echo "FAIL: summary-only — summary/orphan.md missing, stderr: $(cat "$SANDBOX/e5")"; fail=1; }
changed=$(git -C "$WIKI_PATH" show --name-only --format="" HEAD | grep -v '^$')
[ "$changed" = "summary/orphan.md" ] \
  || { echo "FAIL: summary-only — commit touched more than the summary: $changed"; fail=1; }
[ "$(head_subject)" = "Backfill summary: orphan" ] \
  || { echo "FAIL: summary-only — commit subject is '$(head_subject)'"; fail=1; }

# --- case 6: --summary-only must refuse to touch anything else ----------------
printf -- '---\nurl: https://example.invalid/orphan2\ndate_fetched: 2026-08-01\n---\n\nOrphan two body text.\n' \
  > "$WIKI_PATH/raw/orphan2.md"
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed second orphan raw file"
before=$(head_subject)
STUB_MODE=summary-overreach STUB_SLUG=orphan2 \
  "$BIN/wiki-ingest-run" --summary-only orphan2 >/dev/null 2>"$SANDBOX/e6"
check "--summary-only rejects out-of-scope writes" 1 $?
grep -q "outside summary/" "$SANDBOX/e6" \
  || { echo "FAIL: summary-overreach — wrong message: $(cat "$SANDBOX/e6")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: summary-overreach — main advanced"; fail=1; }

# --- case 7: --summary-only with no such raw file -----------------------------
STUB_MODE=summary-good STUB_SLUG=nosuch \
  "$BIN/wiki-ingest-run" --summary-only nosuch >/dev/null 2>"$SANDBOX/e7"
check "--summary-only fails on a missing raw file" 1 $?
grep -q "no such source" "$SANDBOX/e7" \
  || { echo "FAIL: missing-raw — wrong message: $(cat "$SANDBOX/e7")"; fail=1; }

# --- case 8: --summary-only when the LLM writes nothing -----------------------
before=$(head_subject)
STUB_MODE=nothing STUB_SLUG=orphan2 \
  "$BIN/wiki-ingest-run" --summary-only orphan2 >/dev/null 2>"$SANDBOX/e8"
check "--summary-only fails when the LLM writes nothing" 1 $?
grep -q "wrote nothing" "$SANDBOX/e8" \
  || { echo "FAIL: summary-empty — wrong message: $(cat "$SANDBOX/e8")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: summary-empty — main advanced"; fail=1; }

# --- case 9: a URL argument resolves to the same slug -------------------------
STUB_MODE=summary-good STUB_SLUG=orphan2 \
  "$BIN/wiki-ingest-run" --summary-only https://example.invalid/orphan2 >/dev/null 2>"$SANDBOX/e9"
check "--summary-only accepts a URL and derives the slug" 0 $?
[ -f "$WIKI_PATH/summary/orphan2.md" ] \
  || { echo "FAIL: url-slug — summary/orphan2.md missing, stderr: $(cat "$SANDBOX/e9")"; fail=1; }

# --- case 10: --summary-only rejects incompatible flags -----------------------
STUB_MODE=summary-good STUB_SLUG=orphan \
  "$BIN/wiki-ingest-run" --summary-only --repo https://github.com/o/r >/dev/null 2>"$SANDBOX/e10"
check "--summary-only --repo is a usage error" 64 $?

# =============================================================================
# Cases 11-15 — the mid-operation / conflict-marker guard on the auto-commit
# (kata cntt).
#
# The "Auto-commit local changes before ingest merge" step ran `git add -A` +
# `git commit` over $WIKI_PATH unconditionally. Against a hand-merge in
# progress the `add -A` marks every conflicted path RESOLVED, and the commit
# then concludes the captain's merge with the markers in it — exit 0, silently.
# That ordering is why the unmerged check has to precede the add.
# =============================================================================

# --- fixture: a branch that conflicts with main on a topic/ and a raw/ file ---
# topic/ is what the live incident corrupted (topic/Context Graphs.md); raw/ is
# what wiki-ingest-backfill's narrower `git add raw/` reaches (case 15).
printf '# Context Graphs\n\nseed body\n' > "$WIKI_PATH/topic/Context Graphs.md"
printf -- '---\nurl: https://example.invalid/conflicted\n---\n\nseed raw body\n' \
  > "$WIKI_PATH/raw/conflicted.md"
git -C "$WIKI_PATH" add -A
git -C "$WIKI_PATH" commit -q -m "Seed conflict fixture"
git -C "$WIKI_PATH" checkout -q -b conflicting
printf '# Context Graphs\n\nTHEIR VERSION\n' > "$WIKI_PATH/topic/Context Graphs.md"
printf -- '---\nurl: https://example.invalid/conflicted\n---\n\nTHEIR raw body\n' \
  > "$WIKI_PATH/raw/conflicted.md"
git -C "$WIKI_PATH" commit -qam "their edit"
git -C "$WIKI_PATH" checkout -q main
printf '# Context Graphs\n\nOUR VERSION\n' > "$WIKI_PATH/topic/Context Graphs.md"
printf -- '---\nurl: https://example.invalid/conflicted\n---\n\nOUR raw body\n' \
  > "$WIKI_PATH/raw/conflicted.md"
git -C "$WIKI_PATH" commit -qam "our edit"

# main's tip by name: a stopped rebase detaches HEAD, so head_subject() would
# report the rebase's replay commit rather than telling us whether main moved.
main_subject() { git -C "$WIKI_PATH" log -1 --format=%s main; }
# Any commit reachable from main that added or removed a conflict-marker line.
markers_on_main() { git -C "$WIKI_PATH" log main --oneline -S'<<<<<<< ' | head -5; }
gitdir_of_wiki() { git -C "$WIKI_PATH" rev-parse --absolute-git-dir; }

# --- case 11: a merge in progress stops the ingest dead (AC1, AC2) ------------
before=$(main_subject)
STUB_MODE=mid-merge STUB_SLUG=case-eleven \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-eleven >/dev/null 2>"$SANDBOX/e11"
check "merge in progress stops the ingest" 1 $?
grep -q "operation in progress" "$SANDBOX/e11" \
  || { echo "FAIL: mid-merge — wrong message: $(cat "$SANDBOX/e11")"; fail=1; }
[ "$(main_subject)" = "$before" ] \
  || { echo "FAIL: mid-merge — main advanced to '$(main_subject)'"; fail=1; }
[ -e "$(gitdir_of_wiki)/MERGE_HEAD" ] \
  || { echo "FAIL: mid-merge — MERGE_HEAD cleared; the captain's merge did not survive"; fail=1; }
[ -n "$(git -C "$WIKI_PATH" diff --name-only --diff-filter=U)" ] \
  || { echo "FAIL: mid-merge — no unmerged paths left; add -A marked them resolved"; fail=1; }
grep -q '^<<<<<<< ' "$WIKI_PATH/topic/Context Graphs.md" \
  || { echo "FAIL: mid-merge — markers gone from the working-tree topic/Context Graphs.md"; fail=1; }
[ -z "$(markers_on_main)" ] \
  || { echo "FAIL: mid-merge — conflict markers reached a commit on main: $(markers_on_main)"; fail=1; }
git -C "$WIKI_PATH" merge --abort 2>/dev/null || true

# --- case 12: a conflicted cherry-pick, and a stopped rebase, stop it too (AC3)
before=$(main_subject)
STUB_MODE=mid-cherry-pick STUB_SLUG=case-twelve \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-twelve >/dev/null 2>"$SANDBOX/e12"
check "cherry-pick in progress stops the ingest" 1 $?
grep -q "operation in progress" "$SANDBOX/e12" \
  || { echo "FAIL: mid-cherry-pick — wrong message: $(cat "$SANDBOX/e12")"; fail=1; }
[ "$(main_subject)" = "$before" ] \
  || { echo "FAIL: mid-cherry-pick — main advanced to '$(main_subject)'"; fail=1; }
[ -z "$(markers_on_main)" ] \
  || { echo "FAIL: mid-cherry-pick — conflict markers reached a commit on main"; fail=1; }
git -C "$WIKI_PATH" cherry-pick --abort 2>/dev/null || true

before=$(main_subject)
STUB_MODE=mid-rebase STUB_SLUG=case-twelve-b \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-twelve-b >/dev/null 2>"$SANDBOX/e12b"
check "stopped rebase stops the ingest" 1 $?
grep -q "operation in progress" "$SANDBOX/e12b" \
  || { echo "FAIL: mid-rebase — wrong message: $(cat "$SANDBOX/e12b")"; fail=1; }
[ "$(main_subject)" = "$before" ] \
  || { echo "FAIL: mid-rebase — main advanced to '$(main_subject)'"; fail=1; }
git -C "$WIKI_PATH" rebase --abort 2>/dev/null || true

# --- case 13: conflict markers refused with NO operation in progress (AC4) ----
# A distinct hole: nothing is mid-operation anywhere, so the state checks above
# all pass, and the unguarded auto-commit puts the markers straight onto main.
before=$(main_subject)
printf '# Context Graphs\n\n<<<<<<< HEAD\nOUR VERSION\n=======\nTHEIR VERSION\n>>>>>>> conflicting\n' \
  > "$WIKI_PATH/topic/Context Graphs.md"
STUB_MODE=good-slug STUB_SLUG=case-thirteen \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-thirteen >/dev/null 2>"$SANDBOX/e13"
check "conflict markers are refused with no merge in progress" 1 $?
grep -q "conflict markers" "$SANDBOX/e13" \
  || { echo "FAIL: markers-no-merge — wrong message: $(cat "$SANDBOX/e13")"; fail=1; }
[ "$(main_subject)" = "$before" ] \
  || { echo "FAIL: markers-no-merge — main advanced to '$(main_subject)'"; fail=1; }
[ -z "$(git -C "$WIKI_PATH" diff --cached --name-only)" ] \
  || { echo "FAIL: markers-no-merge — index left staged: $(git -C "$WIKI_PATH" diff --cached --name-only | tr '\n' ' ')"; fail=1; }
[ -z "$(markers_on_main)" ] \
  || { echo "FAIL: markers-no-merge — conflict markers reached a commit on main"; fail=1; }
git -C "$WIKI_PATH" checkout -q -- "topic/Context Graphs.md"

# --- case 13b: markers in a page whose NAME is non-ASCII (AC4) ----------------
# Under git's default core.quotePath, `diff --cached --name-only` C-quotes any
# path containing a non-ASCII byte — it prints
#   "topic/ARIES \342\200\224 Write-Ahead Logging Recovery.md"
# quotes, backslash escapes and all. `git show ":$p"` on that name resolves to
# nothing, fails, and the failure is swallowed by the scan's 2>/dev/null: the
# check silently cannot fire. This is not a contrived case. The wiki's dominant
# title convention separates title from subtitle with an em-dash (U+2014), and
# `git -c core.quotePath=true ls-files | grep -c '^"'` counts 80 such paths of
# 991 topic pages in the live wiki today — about one page in twelve.
#
# The censusing mistake is worth naming: `git ls-files | grep -P '[^\x00-\x7F]'`
# reports 0 and always will, because quotePath has already replaced those bytes
# with literal ASCII backslash escapes in git's own output. The quoting that
# causes the bug is exactly what makes the census read clean.
EMDASH_PAGE="topic/ARIES — Write-Ahead Logging Recovery.md"
before=$(main_subject)
printf '# ARIES\n\n<<<<<<< HEAD\nOUR VERSION\n=======\nTHEIR VERSION\n>>>>>>> conflicting\n' \
  > "$WIKI_PATH/$EMDASH_PAGE"
STUB_MODE=good-slug STUB_SLUG=case-thirteen-b \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-thirteen-b >/dev/null 2>"$SANDBOX/e13b"
check "conflict markers in a non-ASCII filename are refused" 1 $?
grep -q "conflict markers" "$SANDBOX/e13b" \
  || { echo "FAIL: markers-emdash — wrong message: $(cat "$SANDBOX/e13b")"; fail=1; }
grep -q "ARIES — Write-Ahead Logging Recovery.md" "$SANDBOX/e13b" \
  || { echo "FAIL: markers-emdash — the em-dash page is not named in the message: $(cat "$SANDBOX/e13b")"; fail=1; }
[ "$(main_subject)" = "$before" ] \
  || { echo "FAIL: markers-emdash — main advanced to '$(main_subject)'"; fail=1; }
[ -z "$(git -C "$WIKI_PATH" diff --cached --name-only)" ] \
  || { echo "FAIL: markers-emdash — index left staged: $(git -C "$WIKI_PATH" diff --cached --name-only | tr '\n' ' ')"; fail=1; }
[ -z "$(markers_on_main)" ] \
  || { echo "FAIL: markers-emdash — conflict markers reached a commit on main: $(markers_on_main)"; fail=1; }
rm -f "$WIKI_PATH/$EMDASH_PAGE"

# --- case 14: the auto-commit still does its job (AC5) ------------------------
# Ordinary Obsidian-style edits, plus a page whose body carries a markdown
# setext heading. A bare "=======" underline is legal markdown, so a marker
# regex that includes it rejects ordinary wiki content and breaks correct
# ingests — this case is what stops the regex being widened.
printf '# Context Graphs\n\nOUR VERSION, edited in Obsidian\n' > "$WIKI_PATH/topic/Context Graphs.md"
printf 'My Heading\n=======\n\nA setext underline is not a conflict marker.\n' \
  > "$WIKI_PATH/topic/Setext Page.md"
STUB_MODE=good-slug STUB_SLUG=case-fourteen \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-fourteen >/dev/null 2>"$SANDBOX/e14"
check "ordinary local edits still auto-commit" 0 $?
git -C "$WIKI_PATH" log main --format=%s \
  | grep -q '^Auto-commit local changes before ingest merge$' \
  || { echo "FAIL: auto-commit — no auto-commit on main, stderr: $(cat "$SANDBOX/e14")"; fail=1; }
for f in "topic/Context Graphs.md" "topic/Setext Page.md"; do
  git -C "$WIKI_PATH" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
    || { echo "FAIL: auto-commit — $f is not tracked"; fail=1; }
done
git -C "$WIKI_PATH" show "main:topic/Setext Page.md" | grep -q '^=======$' \
  || { echo "FAIL: auto-commit — the setext page never reached main"; fail=1; }

# --- case 15: wiki-ingest-backfill refuses the same states (AC6) --------------
# backfill does not share wiki-ingest-run's code — it has its own commit_batch,
# whose narrower `git add raw/` still stages a marker-laden raw/ file and marks
# it resolved, leaving the markers in the captain's index.
#
# The conflict gets its own fresh branch rather than reusing `conflicting`:
# against unguarded bin/, case 11's ingest CONCLUDES that merge, so by the time
# we get here `git merge conflicting` is already up to date and conflicts with
# nothing. This case must be red against unguarded bin/ too.
# The conflicted path carries an em-dash, the wiki's real title convention, so
# this case also covers the quoted-path condition that broke the marker scan
# (case 13b). backfill's guard only ever tests its path list for EMPTINESS, so
# quoting cannot make it fail open the way a per-path `git show` can — this
# case is what turns that reasoning into evidence.
BF_CONFLICT="raw/Backfill — Conflicted Source.md"
printf -- '---\nurl: https://example.invalid/backfill-conflict\n---\n\nBASE raw body\n' \
  > "$WIKI_PATH/$BF_CONFLICT"
git -C "$WIKI_PATH" add -A
git -C "$WIKI_PATH" commit -q -m "Seed backfill conflict base"
git -C "$WIKI_PATH" checkout -q -b conflicting-raw
printf -- '---\nurl: https://example.invalid/backfill-conflict\n---\n\nTHEIR raw body\n' \
  > "$WIKI_PATH/$BF_CONFLICT"
git -C "$WIKI_PATH" commit -qam "their backfill edit"
git -C "$WIKI_PATH" checkout -q main
printf -- '---\nurl: https://example.invalid/backfill-conflict\n---\n\nOUR raw body\n' \
  > "$WIKI_PATH/$BF_CONFLICT"
git -C "$WIKI_PATH" commit -qam "our backfill edit"

# Give every summary/ a raw/ so the worklist is empty: this case is about
# commit_batch, and an empty worklist keeps it offline (the fetch loop would
# otherwise go to the network).
for f in "$WIKI_PATH"/summary/*.md; do
  [ -e "$f" ] || continue
  s=$(basename "$f" .md)
  [ -f "$WIKI_PATH/raw/$s.md" ] && continue
  printf -- '---\nurl: https://example.invalid/%s\ndate_fetched: 2026-08-01\n---\n\nplaceholder\n' "$s" \
    > "$WIKI_PATH/raw/$s.md"
done
git -C "$WIKI_PATH" add -A
git -C "$WIKI_PATH" commit -q -m "Seed raw/ for every summary so the backfill worklist is empty"

before=$(main_subject)
git -C "$WIKI_PATH" merge conflicting-raw --no-edit >/dev/null 2>&1
# quotePath=false here so the fixture check reads the real name, not the
# C-quoted rendering — this assertion is about the fixture, not the guard.
git -C "$WIKI_PATH" -c core.quotePath=false diff --name-only --diff-filter=U | grep -q '^raw/' \
  || { echo "FAIL: backfill fixture — no conflicted raw/ path, so the case proves nothing"; fail=1; }
"$BIN/wiki-ingest-backfill" >/dev/null 2>"$SANDBOX/e15"
rc15=$?
if [ "$rc15" != 0 ]; then
  echo "ok: backfill refuses a merge in progress (rc=$rc15)"
else
  echo "FAIL: backfill refuses a merge in progress — expected rc!=0, got 0"; fail=1
fi
grep -q "operation in progress" "$SANDBOX/e15" \
  || { echo "FAIL: backfill — wrong message: $(cat "$SANDBOX/e15")"; fail=1; }
# Nothing staged is read off the INDEX STAGES, not `diff --cached`: a conflicted
# path shows up in `git diff --cached --name-only` whether or not anyone staged
# it, so that check cannot tell guarded from unguarded. Stages 1/2/3 mean the
# conflict is untouched; a lone stage 0 means `git add raw/` marked it resolved.
stages=$(git -C "$WIKI_PATH" ls-files -s -- "$BF_CONFLICT" | awk '{print $3}' | sort -u | tr '\n' ' ')
[ "$stages" = "1 2 3 " ] \
  || { echo "FAIL: backfill — $BF_CONFLICT index stages are [$stages], expected [1 2 3 ]: the conflict was staged/resolved"; fail=1; }
[ "$(main_subject)" = "$before" ] \
  || { echo "FAIL: backfill — main advanced to '$(main_subject)'"; fail=1; }
[ -e "$(gitdir_of_wiki)/MERGE_HEAD" ] \
  || { echo "FAIL: backfill — MERGE_HEAD cleared; the captain's merge did not survive"; fail=1; }
git -C "$WIKI_PATH" merge --abort 2>/dev/null || true
# Slug-collision cases (kata pxf4)
#
# Two DIFFERENT sources whose URLs end in the same path segment used to collide
# on raw/<slug>.md and summary/<slug>.md, the second silently overwriting the
# first. These drive real wiki-ingest-run invocations and assert on committed
# wiki state, like every case above, and all use STUB_MODE=*autoslug.
#
# Named rather than numbered on purpose: this block and the completeness cases
# above are appended to by different branches, and duplicate case numbers after
# a merge would be silent.
# =============================================================================

csum()      { md5 -q "$1" 2>/dev/null || md5sum "$1" | awk '{print $1}'; }
raw_count() { ls -1 "$WIKI_PATH/raw" | wc -l | tr -d ' '; }

SRC_A="$SANDBOX/collide-a.txt"
SRC_B="$SANDBOX/collide-b.txt"
printf 'ALPHA BODY. The blog post announcing widget-os, at a plausible length.\n' > "$SRC_A"
printf 'BETA BODY. The widget-os repository README, a different source entirely.\n' > "$SRC_B"

URL_A="https://blog.example.invalid/widget-os/"
URL_B="https://code.example.invalid/example/widget-os"

# --- collision case A: two sources sharing a last path segment (AC1) ---------
STUB_MODE=autoslug TOPIC_TITLE="Widget OS Blog" \
  "$BIN/wiki-ingest-run" --content "$SRC_A" "$URL_A" >/dev/null 2>"$SANDBOX/eca1"
check "collision: first source ingests" 0 $?
RAW_A="$WIKI_PATH/raw/widget-os.md"
if [ ! -f "$RAW_A" ]; then
  echo "FAIL: collision A — raw/widget-os.md missing, stderr: $(cat "$SANDBOX/eca1")"; fail=1
fi
a_raw=$(csum "$RAW_A" 2>/dev/null)
a_sum=$(csum "$WIKI_PATH/summary/widget-os.md" 2>/dev/null)

STUB_MODE=autoslug TOPIC_TITLE="Widget OS Repo" \
  "$BIN/wiki-ingest-run" --content "$SRC_B" "$URL_B" >/dev/null 2>"$SANDBOX/eca2"
check "collision: second source ingests without clobbering the first" 0 $?

b_file=$(grep -rl "^url: $URL_B\$" "$WIKI_PATH/raw" 2>/dev/null | head -1)
[ -n "$b_file" ] \
  || { echo "FAIL: collision A — no raw/ archive holds $URL_B, stderr: $(cat "$SANDBOX/eca2")"; fail=1; }
[ "$b_file" != "$RAW_A" ] \
  || { echo "FAIL: collision A — both sources resolved to raw/widget-os.md"; fail=1; }
if [ -n "$b_file" ]; then
  grep -q "BETA BODY" "$b_file" \
    || { echo "FAIL: collision A — $b_file does not hold the second source's body"; fail=1; }
  b_slug=$(basename "$b_file" .md)
  [ -f "$WIKI_PATH/summary/$b_slug.md" ] \
    || { echo "FAIL: collision A — second source has no summary/$b_slug.md of its own"; fail=1; }
  # The ONLY assertion on the suffix SHAPE. AC6 (the suffix scheme) is an open
  # Captain decision; if it changes, this one line changes with it.
  [ "$b_slug" = "widget-os-code-example" ] \
    || { echo "FAIL: collision A — suffix shape is '$b_slug', expected 'widget-os-code-example'"; fail=1; }
fi
[ "$(csum "$RAW_A" 2>/dev/null)" = "$a_raw" ] \
  || { echo "FAIL: collision A — raw/widget-os.md changed when the second source was ingested"; fail=1; }
[ "$(csum "$WIKI_PATH/summary/widget-os.md" 2>/dev/null)" = "$a_sum" ] \
  || { echo "FAIL: collision A — summary/widget-os.md changed when the second source was ingested"; fail=1; }

# --- collision case B: a --force re-ingest is NOT a collision (AC2) ----------
# The URL is passed in a cosmetically different form than it was ingested with:
# http vs https, leading www., no trailing slash, and a #fragment. dupcheck
# folds all four, so this must update raw/widget-os.md IN PLACE. Re-deriving
# the slug, or string-comparing the URL against stored url: values, would read
# the incumbent as a foreign occupant and mint a suffixed duplicate — the
# regression this fix is most likely to cause.
URL_A_VARIANT="http://www.blog.example.invalid/widget-os#top"
before_n=$(raw_count)
STUB_MODE=autoslug TOPIC_TITLE="Widget OS Blog" TOPIC_REV=2 \
  "$BIN/wiki-ingest-run" --force --content "$SRC_A" "$URL_A_VARIANT" >/dev/null 2>"$SANDBOX/ecb"
check "collision: --force re-ingest of a cosmetic URL variant updates in place" 0 $?
after_n=$(raw_count)
[ "$before_n" = "$after_n" ] \
  || { echo "FAIL: collision B — re-ingest added an archive ($before_n -> $after_n), stderr: $(cat "$SANDBOX/ecb")"; fail=1; }
grep -q "^url: $URL_A_VARIANT\$" "$RAW_A" 2>/dev/null \
  || { echo "FAIL: collision B — raw/widget-os.md was not the archive updated"; fail=1; }

# --- collision case C: same host, same last segment, three sources (AC3) -----
# A host-derived suffix alone does not separate these; the numeric tail does.
i=0
for owner in one two three; do
  i=$((i + 1))
  # Long enough to clear wiki-ingest-run's 40-non-whitespace-character content
  # threshold, which is otherwise the first thing these ingests trip over.
  printf 'GADGET BODY %s. Distinct article content belonging to owner %s and nobody else.\n' \
    "$i" "$owner" > "$SANDBOX/gadget-$owner.txt"
  STUB_MODE=autoslug TOPIC_TITLE="Gadget $owner" \
    "$BIN/wiki-ingest-run" --content "$SANDBOX/gadget-$owner.txt" \
    "https://code.example.invalid/$owner/gadget" >/dev/null 2>"$SANDBOX/ecc-$owner"
  check "collision: same-host source '$owner' ingests" 0 $?
done
gadget_files=""
for owner in one two three; do
  f=$(grep -rl "^url: https://code.example.invalid/$owner/gadget\$" "$WIKI_PATH/raw" 2>/dev/null | head -1)
  if [ -z "$f" ]; then
    echo "FAIL: collision C — no raw/ archive holds .../$owner/gadget"; fail=1; continue
  fi
  case "$gadget_files" in
    *" $f "*) echo "FAIL: collision C — $f holds more than one of the three sources"; fail=1 ;;
    *) gadget_files="$gadget_files $f " ;;
  esac
done

# --- collision case D: --summary-only targets by URL, not by slug (AC4) ------
# The archive's slug is NOT derivable from its URL (url_slug would say
# "widget-os", which belongs to a different source). Resolving by URL is the
# only way to backfill the right precis.
printf -- '---\nurl: https://docs.example.invalid/manual/widget-os\ndate_fetched: 2026-08-01\n---\n\nHand-named archive body.\n' \
  > "$WIKI_PATH/raw/widget-os-hand.md"
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed a hand-named archive"
incumbent_sum=$(csum "$WIKI_PATH/summary/widget-os.md" 2>/dev/null)
STUB_MODE=summary-autoslug \
  "$BIN/wiki-ingest-run" --summary-only https://docs.example.invalid/manual/widget-os \
  >/dev/null 2>"$SANDBOX/ecd"
check "collision: --summary-only resolves a URL to the archive that holds it" 0 $?
[ -f "$WIKI_PATH/summary/widget-os-hand.md" ] \
  || { echo "FAIL: collision D — summary/widget-os-hand.md missing, stderr: $(cat "$SANDBOX/ecd")"; fail=1; }
[ "$(csum "$WIKI_PATH/summary/widget-os.md" 2>/dev/null)" = "$incumbent_sum" ] \
  || { echo "FAIL: collision D — backfilled the wrong source (summary/widget-os.md changed)"; fail=1; }

# --- collision case E: an exhausted slug ladder fails loudly (AC3) -----------
# Every candidate is occupied by a different source. The one thing that must
# never happen is a silent overwrite, so this is exit 1 with the candidates
# named, and main must not advance.
for c in zed zed-code-example zed-code-example-2 zed-code-example-3 \
         zed-code-example-4 zed-code-example-5 zed-code-example-6 \
         zed-code-example-7 zed-code-example-8 zed-code-example-9; do
  printf -- '---\nurl: https://seed.example.invalid/%s\ndate_fetched: 2026-08-01\n---\n\nseed %s\n' \
    "$c" "$c" > "$WIKI_PATH/raw/$c.md"
done
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed a fully occupied slug ladder"
zed_sum=$(csum "$WIKI_PATH/raw/zed.md")
before=$(head_subject)
STUB_MODE=autoslug TOPIC_TITLE="Zed" \
  "$BIN/wiki-ingest-run" --content "$SRC_A" https://code.example.invalid/q/zed \
  >/dev/null 2>"$SANDBOX/ece"
check "collision: exhausted slug ladder is rejected" 1 $?
grep -q "zed-code-example-9" "$SANDBOX/ece" \
  || { echo "FAIL: collision E — candidates not named in the message: $(cat "$SANDBOX/ece")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: collision E — main advanced to '$(head_subject)'"; fail=1; }
[ "$(csum "$WIKI_PATH/raw/zed.md")" = "$zed_sum" ] \
  || { echo "FAIL: collision E — raw/zed.md was overwritten"; fail=1; }

# --- collision case F: an ambiguous owner fails closed -----------------------
# A wiki where ONE url is already held by TWO different slugs (the hand-resolved
# shape, where only one tier got renamed). The approved design does not say what
# to do here, and both available guesses are bad: pick wrong and a --force
# re-ingest silently rewrites the wrong archive, or backfills the wrong precis.
# So neither call site guesses.
printf -- '---\nurl: https://split.example.invalid/thing\ndate_fetched: 2026-08-01\n---\n\nsplit raw body\n' \
  > "$WIKI_PATH/raw/split-one.md"
printf -- '---\nurl: https://split.example.invalid/thing\n---\n\nsplit precis\n' \
  > "$WIKI_PATH/summary/split-two.md"
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed one url held by two slugs"
split_raw=$(csum "$WIKI_PATH/raw/split-one.md")
before=$(head_subject)
STUB_MODE=autoslug TOPIC_TITLE="Split" \
  "$BIN/wiki-ingest-run" --force --content "$SRC_A" https://split.example.invalid/thing \
  >/dev/null 2>"$SANDBOX/ecf1"
check "collision: --force re-ingest of an ambiguously-held URL is rejected" 1 $?
grep -q "held by 2 archives" "$SANDBOX/ecf1" \
  || { echo "FAIL: collision F — wrong message: $(cat "$SANDBOX/ecf1")"; fail=1; }
STUB_MODE=summary-autoslug \
  "$BIN/wiki-ingest-run" --summary-only https://split.example.invalid/thing \
  >/dev/null 2>"$SANDBOX/ecf2"
check "collision: --summary-only of an ambiguously-held URL is rejected" 1 $?
grep -q "held by 2 archives" "$SANDBOX/ecf2" \
  || { echo "FAIL: collision F — wrong --summary-only message: $(cat "$SANDBOX/ecf2")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: collision F — main advanced to '$(head_subject)'"; fail=1; }
[ "$(csum "$WIKI_PATH/raw/split-one.md")" = "$split_raw" ] \
  || { echo "FAIL: collision F — raw/split-one.md was rewritten"; fail=1; }

[ "$fail" = 0 ] && echo "test-guard: ALL PASS"
exit $fail
