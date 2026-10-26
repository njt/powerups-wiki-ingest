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

# Resolved through `pwd -P`: git worktree list reports resolved paths, so an
# unresolved $TMPDIR (/var -> /private/var, plus its trailing slash) would make
# the self-exclusion guard in cleanup_all never match. Resolve in a second step,
# not as `cd "$(mktemp -d ...)"`: `cd ""` succeeds in bash and returns the cwd,
# so a failed mktemp would point SANDBOX -- and cleanup_all's rm -rf -- here.
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-guard-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
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
if [ -n "${STUB_ARGV:-}" ]; then printf '%s\n' "$@" > "$STUB_ARGV"; fi   # argv, via wiki-agent
prompt=$(cat)    # drain the prompt (the *-autoslug modes also read it)
s="${STUB_SLUG:-unknown}"
# Optionally keep the prompt, so a case can assert what the LLM was told.
if [ -n "${STUB_PROMPT_OUT:-}" ]; then printf '%s\n' "$prompt" > "$STUB_PROMPT_OUT"; fi

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

# Topics-mode helpers; $s and $url are set by the caller. NOTE_REV varies the
# body across re-ingests of one source: a byte-identical rewrite stages
# nothing, and the guard then (rightly) sees no summary and no note.
write_topics_summary() {  # write_topics_summary <frontmatter line>...
  { printf -- '---\nurl: %s\n' "$url"; printf '%s\n' "$@"; printf -- '---\n\nprecis of %s, rev %s\n' "$url" "${NOTE_REV:-1}"; } \
    > "summary/$s.md"
}
write_note() {  # write_note <title> — an analysis page whose footer cites $s
  printf '# %s\n\nbody rev %s\n\n---\n*Sources: [[raw/%s]], [[summary/%s]]*\n' \
    "$1" "${NOTE_REV:-1}" "$s" "$s" > "note/$1.md"
}
note_index_log() {
  printf -- '- [[%s]] — entry for %s\n' "${NOTE_TITLE:-Note $s}" "$url" >> index.md
  printf -- '- entry for %s -> raw/%s.md\n' "$url" "$s" >> log.md
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
  # --- topics-mode modes (main carries topics.md from the topics cases on) ---
  # The analysis page is note/<NOTE_TITLE>.md, so a case can collide with an
  # existing note on purpose; its footer cites the slug the script chose, which
  # is what the --force guard reads back from HEAD. The topics: lines are the
  # variable under test and are passed in verbatim.
  note-good|note-overwrites-other-note)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics:' '  - alpha' '  - beta'
    write_note "${NOTE_TITLE:-Note $s}"
    note_index_log
    ;;
  note-flow-topics)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics: [alpha, beta]'
    write_note "${NOTE_TITLE:-Note $s}"
    note_index_log
    ;;
  note-title-case)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics:' '  - Beta Topic'
    write_note "${NOTE_TITLE:-Note $s}"
    note_index_log
    ;;
  note-bad-topic)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics:' '  - nonesuch'
    write_note "${NOTE_TITLE:-Note $s}"
    note_index_log
    ;;
  note-writes-topic-dir)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics:' '  - alpha'
    write_note "${NOTE_TITLE:-Note $s}"
    printf '# Alpha Topic\n\nan additive edit to a compiled page\n' > "topic/Alpha Topic.md"
    note_index_log
    ;;
  note-edits-topics-md)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics:' '  - gamma'
    write_note "${NOTE_TITLE:-Note $s}"
    printf '| gamma | Gamma Topic | A topic the LLM invented. |\n' >> topics.md
    note_index_log
    ;;
  note-two-notes)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics:' '  - alpha'
    write_note "${NOTE_TITLE:-Note $s}"
    write_note "Second Note $s"
    note_index_log
    ;;
  # A parallel peer that took the same slug and note title and merged FIRST
  # (kata 925f). The stub commits that peer straight onto main of the wiki while
  # our worktree, cut before it, still shows both free — the race, with no
  # timing involved. note-peer-once does it while $PEER_ONCE exists (one-shot);
  # note-peer-always does it on every run, so the re-run budget runs out. Like
  # a real LLM, the stub picks a different note title when its first choice is
  # visibly taken, which is what the fresh worktree of a re-run lets it see.
  note-peer-once|note-peer-always)
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    title="${NOTE_TITLE:-Note $s}"
    [ ! -e "note/$title.md" ] || title="$title ($s)"
    [ -z "${STUB_COUNT:-}" ] || echo "$s" >> "$STUB_COUNT"
    if [ "$STUB_MODE" = note-peer-always ] || { [ -n "${PEER_ONCE:-}" ] && [ -e "$PEER_ONCE" ]; }; then
      [ -z "${PEER_ONCE:-}" ] || rm -f "$PEER_ONCE"
      purl="https://peer.example.invalid/$s"
      ( cd "$WIKI_PATH" || exit 1
        printf -- '---\nurl: %s\ndate_fetched: 2026-10-11\n---\n\nPEER BODY for %s\n' "$purl" "$purl" > "raw/$s.md"
        printf -- '---\nurl: %s\ntopics:\n  - alpha\n---\n\npeer precis\n' "$purl" > "summary/$s.md"
        printf '# %s\n\npeer note\n\n---\n*Sources: [[raw/%s]], [[summary/%s]]*\n' "$title" "$s" "$s" > "note/$title.md"
        printf -- '- [[%s]] — peer entry for %s\n' "$title" "$purl" >> index.md
        printf -- '- peer entry for %s -> raw/%s.md\n' "$purl" "$s" >> log.md
        git add -A && git commit -q -m "Ingest: $purl" ) >/dev/null 2>&1 \
        || { echo "stub: could not commit the peer onto main" >&2; exit 1; }
    fi
    write_topics_summary 'topics:' '  - alpha'
    write_note "$title"
    NOTE_TITLE="$title" note_index_log
    ;;
  summary-topics-flow)
    # --summary-only in topics mode: summary/ only, topics: in flow form.
    s=$(prompt_slug); url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
    write_topics_summary 'topics: [alpha]'
    ;;
  *) echo "stub: unknown STUB_MODE ${STUB_MODE:-}" >&2; exit 1 ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB"
export WIKI_INGEST_CLI="$STUB"
export STUB_ARGV="$SANDBOX/argv"

# --- scratch wiki -------------------------------------------------------------
"$BIN/wiki-ingest-setup" >/dev/null || { echo "FAIL: wiki-ingest-setup failed"; exit 1; }
git -C "$WIKI_PATH" config user.email "test@wiki-ingest.invalid"
git -C "$WIKI_PATH" config user.name "wiki-ingest test"
# Setup seeds topics.md (3.0 wikis start in topics mode). The cases up to the
# "topics mode" marker below model a 2.x wiki, whose whole point is that it has
# NO topics.md, so take it back out here; the topics cases add their own.
git -C "$WIKI_PATH" rm -q topics.md && git -C "$WIKI_PATH" commit -q -m "Model a 2.x wiki: no topics.md"

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
[ "$(head -5 "$STUB_ARGV")" = "$(printf '%s\n' -p --no-session-persistence --allowedTools Read,Write,Edit,Bash --add-dir)" ] \
  || { echo "FAIL: good — the CLI was not run through wiki-agent's claude dialect: $(tr '\n' ' ' < "$STUB_ARGV")"; fail=1; }
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

# --- case 14b: a failed merge never aborts a PEER's merge ---------------------
# The in-progress guard runs before the auto-commit, so a peer ingest can start
# its merge in the gap between that guard and our own `git merge`. Ours then
# fails before it starts, and an unconditional `git merge --abort` resets the
# peer's merge instead: the peer's commit still lands, the working tree is left
# behind it, and the next ingest auto-commits the peer's files as deletions
# (2026-09-20: a whole ingest lost, and it had exited 0). A one-shot post-commit
# hook opens that gap deterministically: it fires on the auto-commit and leaves a
# peer merge in progress. Hooks are shared with the ingest worktree, hence the
# subject test.
git -C "$WIKI_PATH" checkout -q -b peer-ingest
printf 'peer body\n' > "$WIKI_PATH/topic/Peer Page.md"
git -C "$WIKI_PATH" add -A
git -C "$WIKI_PATH" commit -q -m "peer ingest"
git -C "$WIKI_PATH" checkout -q main
PEER_SHA=$(git -C "$WIKI_PATH" rev-parse peer-ingest)
HOOK="$(gitdir_of_wiki)/hooks/post-commit"
mkdir -p "$(dirname "$HOOK")"
cat > "$HOOK" <<HOOK_EOF
#!/bin/sh
[ -e "$SANDBOX/peer-flag" ] || exit 0
[ "\$(git log -1 --format=%s)" = "Auto-commit local changes before ingest merge" ] || exit 0
rm -f "$SANDBOX/peer-flag"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git -C "$WIKI_PATH" merge --no-commit --no-ff peer-ingest >/dev/null 2>&1
exit 0
HOOK_EOF
chmod +x "$HOOK"
: > "$SANDBOX/peer-flag"
printf '# Context Graphs\n\nOUR VERSION, edited again\n' > "$WIKI_PATH/topic/Context Graphs.md"
STUB_MODE=good-slug STUB_SLUG=case-fourteen-b \
  "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/case-fourteen-b >/dev/null 2>"$SANDBOX/e14b"
check "a peer's merge in the gap fails ours, loudly" 1 $?
[ ! -e "$SANDBOX/peer-flag" ] \
  || { echo "FAIL: peer-merge — the hook never fired, so the case tested nothing"; fail=1; }
[ "$(git -C "$WIKI_PATH" rev-parse -q --verify MERGE_HEAD)" = "$PEER_SHA" ] \
  || { echo "FAIL: peer-merge — the peer's MERGE_HEAD did not survive, stderr: $(cat "$SANDBOX/e14b")"; fail=1; }
[ -e "$WIKI_PATH/topic/Peer Page.md" ] \
  || { echo "FAIL: peer-merge — the peer's merged file was reset out of the working tree"; fail=1; }
rm -f "$HOOK"
git -C "$WIKI_PATH" merge --abort 2>/dev/null || true

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

# The disambiguator wiki-ingest-run actually appends on a collision. Learned
# from the script's own behaviour in case A, never hard-coded — see the comment
# there. Cases that need to occupy the ladder build their fixtures from it.
COLLISION_TOKEN=""
seed_raw() {  # seed_raw <slug> — an archive owned by some other source
  printf -- '---\nurl: https://seed.example.invalid/%s\ndate_fetched: 2026-08-01\n---\n\nseed %s\n' \
    "$1" "$1" > "$WIKI_PATH/raw/$1.md"
}

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
  # The suffix SHAPE, asserted structurally rather than against a literal, and
  # the point at which the suite LEARNS the token instead of encoding it.
  #
  # AC6 (the suffix scheme) is an open Captain decision. He will change the
  # derivation at bin/wiki-ingest-run:97 and re-run this file, so a hard-coded
  # `widget-os-code-example` here — and, worse, a hard-coded ladder in case E —
  # would report his taste call as a broken fail-closed guard. What is actually
  # promised is base-preserving plus a non-empty disambiguator; the token's
  # spelling is his to choose, so every later fixture derives from what the
  # script just did rather than from what it did on 2026-08-08.
  case "$b_slug" in
    widget-os-?*) COLLISION_TOKEN="${b_slug#widget-os-}" ;;
    *) echo "FAIL: collision A — second source's slug is '$b_slug', expected 'widget-os-' plus a non-empty disambiguator"; fail=1 ;;
  esac
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
if [ -z "$COLLISION_TOKEN" ]; then
  echo "FAIL: collision E — no disambiguator learned in case A, so the ladder cannot be built"
  fail=1
else
  # The ladder is <base>, <base>-<token>, <base>-<token>-2 .. -9, built from the
  # token case A observed. Occupying it by construction rather than by literal
  # is what keeps this case honest when the Captain settles AC6.
  seed_raw zed
  seed_raw "zed-$COLLISION_TOKEN"
  i=2
  while [ "$i" -le 9 ]; do
    seed_raw "zed-$COLLISION_TOKEN-$i"
    i=$((i + 1))
  done
  git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed a fully occupied slug ladder"
  zed_sum=$(csum "$WIKI_PATH/raw/zed.md")
  before=$(head_subject)
  STUB_MODE=autoslug TOPIC_TITLE="Zed" \
    "$BIN/wiki-ingest-run" --content "$SRC_A" https://code.example.invalid/q/zed \
    >/dev/null 2>"$SANDBOX/ece"
  check "collision: exhausted slug ladder is rejected" 1 $?
  grep -q "zed-$COLLISION_TOKEN-9" "$SANDBOX/ece" \
    || { echo "FAIL: collision E — candidates not named in the message: $(cat "$SANDBOX/ece")"; fail=1; }
  [ "$(head_subject)" = "$before" ] \
    || { echo "FAIL: collision E — main advanced to '$(head_subject)'"; fail=1; }
  [ "$(csum "$WIKI_PATH/raw/zed.md")" = "$zed_sum" ] \
    || { echo "FAIL: collision E — raw/zed.md was overwritten"; fail=1; }
fi

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

# =============================================================================
# YouTube slug cases (kata 9qeh)
#
# url_slug takes the URL's last path segment, which for youtube.com/watch?v=ID
# is the constant "watch" — every YouTube ingest landed on raw/watch.md. For
# YouTube the slug comes from the fetched transcript's "# <title>" line, which
# means the fetch has to run before the slug is resolved. --content stands in
# for the fetch here: the file has the exact shape ytx prints (per its
# internal/publish/publish.go FormatTranscript), so no ytx is needed and none
# is run. STUB_MODE=autoslug reads the slug back out of the prompt, which is
# how these cases observe the name the script actually chose.
# =============================================================================

YT_TRANSCRIPT="$SANDBOX/yt-transcript.txt"
printf '# Computers are bad, actually | Kyle Kingsbury, Jepsen\n\n' > "$YT_TRANSCRIPT"
printf -- '- **Channel:** Jepsen\n- **URL:** https://www.youtube.com/watch?v=abc123\n- **Duration:** 41m\n- **Transcribed:** 2026-09-22\n\n---\n\n' >> "$YT_TRANSCRIPT"
printf 'So the thing about computers is that they are, in fact, bad, and here is why.\n' >> "$YT_TRANSCRIPT"

# --- youtube case A: a fresh YouTube ingest is slugged from the title --------
STUB_MODE=autoslug TOPIC_TITLE="Computers Are Bad" \
  "$BIN/wiki-ingest-run" --content "$YT_TRANSCRIPT" "https://www.youtube.com/watch?v=abc123" \
  >/dev/null 2>"$SANDBOX/eya"
check "youtube: fresh ingest slugs from the transcript title" 0 $?
git -C "$WIKI_PATH" cat-file -e "main:raw/computers-are-bad-actually-kyle-kingsbury-jepsen.md" 2>/dev/null \
  || { echo "FAIL: youtube A — raw/computers-are-bad-actually-kyle-kingsbury-jepsen.md is not on main, stderr: $(cat "$SANDBOX/eya")"; fail=1; }
git -C "$WIKI_PATH" cat-file -e "main:raw/watch.md" 2>/dev/null \
  && { echo "FAIL: youtube A — raw/watch.md exists on main: the slug came from the URL, not the title"; fail=1; }
git -C "$WIKI_PATH" cat-file -e "main:summary/computers-are-bad-actually-kyle-kingsbury-jepsen.md" 2>/dev/null \
  || { echo "FAIL: youtube A — summary/ tier does not share the title slug"; fail=1; }

# --- youtube case B: --force keeps a hand-chosen slug over the title ---------
# resolve_slug's step 1 (the archive already holding this URL owns its slug)
# must run before, and regardless of, the title rule: Nat renamed the
# mis-slugged raw/watch.md files by hand, and a re-ingest must update those in
# place rather than mint a second archive named after the title.
printf -- '---\nurl: https://www.youtube.com/watch?v=hand01\ndate_fetched: 2026-08-01\n---\n\n# Old hand-renamed body\n\nold transcript\n' \
  > "$WIKI_PATH/raw/hand-picked.md"
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed a hand-renamed YouTube archive"
YT_TRANSCRIPT2="$SANDBOX/yt-transcript-2.txt"
printf '# A Video Somebody Renamed By Hand\n\n- **Channel:** C\n- **URL:** https://www.youtube.com/watch?v=hand01\n- **Duration:** 5m\n- **Transcribed:** 2026-09-22\n\n---\n\nNew transcript body, long enough to clear the length check comfortably.\n' \
  > "$YT_TRANSCRIPT2"
before_n=$(raw_count)
STUB_MODE=autoslug TOPIC_TITLE="Hand Picked" TOPIC_REV=2 \
  "$BIN/wiki-ingest-run" --force --content "$YT_TRANSCRIPT2" "https://www.youtube.com/watch?v=hand01" \
  >/dev/null 2>"$SANDBOX/eyb"
check "youtube: --force re-ingest keeps the hand-chosen slug" 0 $?
[ "$(raw_count)" = "$before_n" ] \
  || { echo "FAIL: youtube B — re-ingest added an archive ($before_n -> $(raw_count)), stderr: $(cat "$SANDBOX/eyb")"; fail=1; }
git -C "$WIKI_PATH" show "main:raw/hand-picked.md" 2>/dev/null | grep -q "New transcript body" \
  || { echo "FAIL: youtube B — raw/hand-picked.md was not the archive updated in place"; fail=1; }
git -C "$WIKI_PATH" cat-file -e "main:raw/a-video-somebody-renamed-by-hand.md" 2>/dev/null \
  && { echo "FAIL: youtube B — the title slug was minted alongside the hand-chosen one"; fail=1; }

# --- youtube case C: the title rule is YouTube-only --------------------------
# A non-YouTube --content file that happens to start with "# Some Title" must
# still slug from its URL; otherwise every surf grab with a heading would
# silently change the slug scheme for the rest of the wiki.
TITLED_SRC="$SANDBOX/titled-article.txt"
printf '# Some Title\n\nAn ordinary article body, long enough to clear the length check.\n' > "$TITLED_SRC"
STUB_MODE=autoslug TOPIC_TITLE="Plain Article" \
  "$BIN/wiki-ingest-run" --content "$TITLED_SRC" "https://example.invalid/articles/plain-url-slug" \
  >/dev/null 2>"$SANDBOX/eyc"
check "youtube: a non-YouTube titled source still slugs from the URL" 0 $?
git -C "$WIKI_PATH" cat-file -e "main:raw/plain-url-slug.md" 2>/dev/null \
  || { echo "FAIL: youtube C — raw/plain-url-slug.md is not on main, stderr: $(cat "$SANDBOX/eyc")"; fail=1; }
git -C "$WIKI_PATH" cat-file -e "main:raw/some-title.md" 2>/dev/null \
  && { echo "FAIL: youtube C — raw/some-title.md exists: the title rule fired for a non-YouTube URL"; fail=1; }

# Topics-mode cases (fixed topics; spec docs/superpowers/specs/2026-09-11-fixed-topics-design.md)
#
# Everything above ran WITHOUT topics.md, and that is the proof legacy mode is
# intact: the `good` mode (case 4) writes topic/ and no note/, and commits.
# From here main carries topics.md, which is the gate. The analysis page moves
# to note/, the summary must carry topics:, and topic/ is off-limits to an
# ingest. Every case is a real wiki-ingest-run against committed state on main.
# =============================================================================

cat > "$WIKI_PATH/topics.md" <<'TOPICS_EOF'
# Topics

Prose around the table is for people; the tools read only the table.

| slug | title | scope |
|---|---|---|
| alpha | Alpha Topic | Things about alpha. |
| beta | Beta Topic | Things about beta. |
| misc | Miscellany | Anything that fits neither. |
TOPICS_EOF
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Add topics.md: switch the wiki to topics mode"

SRC_T="$SANDBOX/topics-source.txt"
printf 'TOPICS BODY. An article about alpha things, long enough to clear the content check.\n' > "$SRC_T"

# The topics: key and its list items exactly as committed on main, so the
# assertions read the merged result rather than the worktree.
topics_block() {  # topics_block <slug>
  git -C "$WIKI_PATH" show "main:summary/$1.md" 2>/dev/null \
    | awk 'p && /^  - /{print; next} p{exit} /^topics:/{p=1; print}'
}
URL_TG="https://example.invalid/topics-good"
NOTE_TG="Alpha Note — Good"

# --- topics: a correct ingest commits, and the prompt is the new one ---------
STUB_MODE=note-good NOTE_TITLE="$NOTE_TG" STUB_PROMPT_OUT="$SANDBOX/prompt-tg" \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_TG" >/dev/null 2>"$SANDBOX/etg"
check "topics: note + block topics: commits" 0 $?
[ "$(head_subject)" = "Ingest: $URL_TG" ] \
  || { echo "FAIL: topics good — HEAD is '$(head_subject)' (no repair expected), stderr: $(cat "$SANDBOX/etg")"; fail=1; }
[ -f "$WIKI_PATH/note/$NOTE_TG.md" ] \
  || { echo "FAIL: topics good — note/$NOTE_TG.md missing from the wiki"; fail=1; }
[ "$(topics_block topics-good)" = "topics:
  - alpha
  - beta" ] \
  || { echo "FAIL: topics good — committed topics: is [$(topics_block topics-good | tr '\n' '|')]"; fail=1; }
# What the LLM was told: the table from topics.md, note/ not topic/, the index rule.
grep -q '^| alpha | Alpha Topic | Things about alpha. |$' "$SANDBOX/prompt-tg" \
  || { echo "FAIL: topics good — prompt does not embed the topics table"; fail=1; }
grep -q 'note/<Title>\.md' "$SANDBOX/prompt-tg" \
  || { echo "FAIL: topics good — prompt does not name note/<Title>.md"; fail=1; }
grep -q 'topic/<Title>\.md' "$SANDBOX/prompt-tg" \
  && { echo "FAIL: topics good — prompt still names topic/<Title>.md"; fail=1; }
grep -q "PRIMARY topic's title" "$SANDBOX/prompt-tg" \
  || { echo "FAIL: topics good — prompt lacks the index-section rule"; fail=1; }

# --- topics: a flow list is accepted and rewritten in block form -------------
# The note title carries an accent and an em-dash: the guard reads staged paths
# back by name, and git C-quotes non-ASCII paths unless told not to.
NOTE_FLOW="Café — Flow Topics"
STUB_MODE=note-flow-topics NOTE_TITLE="$NOTE_FLOW" \
  "$BIN/wiki-ingest-run" --content "$SRC_T" https://example.invalid/topics-flow >/dev/null 2>"$SANDBOX/etf"
check "topics: flow-form topics: is accepted" 0 $?
[ "$(head_subject)" = "Ingest: https://example.invalid/topics-flow (topics repaired)" ] \
  || { echo "FAIL: topics flow — HEAD is '$(head_subject)', stderr: $(cat "$SANDBOX/etf")"; fail=1; }
[ "$(topics_block topics-flow)" = "topics:
  - alpha
  - beta" ] \
  || { echo "FAIL: topics flow — not rewritten in block form: [$(topics_block topics-flow | tr '\n' '|')]"; fail=1; }
[ -f "$WIKI_PATH/note/$NOTE_FLOW.md" ] \
  || { echo "FAIL: topics flow — note/$NOTE_FLOW.md missing from the wiki"; fail=1; }

# --- topics: a title is normalised to its slug --------------------------------
STUB_MODE=note-title-case \
  "$BIN/wiki-ingest-run" --content "$SRC_T" https://example.invalid/topics-title >/dev/null 2>"$SANDBOX/ett"
check "topics: a topic title in topics: is normalised to the slug" 0 $?
[ "$(head_subject)" = "Ingest: https://example.invalid/topics-title (topics repaired)" ] \
  || { echo "FAIL: topics title — HEAD is '$(head_subject)', stderr: $(cat "$SANDBOX/ett")"; fail=1; }
[ "$(topics_block topics-title)" = "topics:
  - beta" ] \
  || { echo "FAIL: topics title — committed topics: is [$(topics_block topics-title | tr '\n' '|')]"; fail=1; }

# --- topics: an unknown slug is repaired to misc, on the record --------------
STUB_MODE=note-bad-topic \
  "$BIN/wiki-ingest-run" --content "$SRC_T" https://example.invalid/topics-bad >/dev/null 2>"$SANDBOX/etb"
check "topics: an unknown slug is repaired to misc, not rejected" 0 $?
[ "$(head_subject)" = "Ingest: https://example.invalid/topics-bad (topics repaired)" ] \
  || { echo "FAIL: topics bad — HEAD is '$(head_subject)', stderr: $(cat "$SANDBOX/etb")"; fail=1; }
[ "$(topics_block topics-bad)" = "topics:
  - misc" ] \
  || { echo "FAIL: topics bad — committed topics: is [$(topics_block topics-bad | tr '\n' '|')]"; fail=1; }
grep -q "dropped topic 'nonesuch'" "$SANDBOX/etb" \
  || { echo "FAIL: topics bad — the drop is not reported on stderr: $(cat "$SANDBOX/etb")"; fail=1; }

# --- topics: any write under topic/ is rejected ------------------------------
before=$(head_subject)
STUB_MODE=note-writes-topic-dir \
  "$BIN/wiki-ingest-run" --content "$SRC_T" https://example.invalid/topics-topicdir >/dev/null 2>"$SANDBOX/etd"
check "topics: a write under topic/ is rejected" 1 $?
grep -q "wrote under topic/" "$SANDBOX/etd" \
  || { echo "FAIL: topics topic-dir — wrong message: $(cat "$SANDBOX/etd")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: topics topic-dir — main advanced to '$(head_subject)'"; fail=1; }
[ ! -e "$WIKI_PATH/topic/Alpha Topic.md" ] \
  || { echo "FAIL: topics topic-dir — topic/Alpha Topic.md reached the wiki"; fail=1; }

# --- topics: editing topics.md is rejected ------------------------------------
before=$(head_subject)
topics_sum=$(csum "$WIKI_PATH/topics.md")
STUB_MODE=note-edits-topics-md \
  "$BIN/wiki-ingest-run" --content "$SRC_T" https://example.invalid/topics-edit >/dev/null 2>"$SANDBOX/ete"
check "topics: an edit to topics.md is rejected" 1 $?
grep -q "topics.md was edited" "$SANDBOX/ete" \
  || { echo "FAIL: topics edit — wrong message: $(cat "$SANDBOX/ete")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: topics edit — main advanced to '$(head_subject)'"; fail=1; }
[ "$(csum "$WIKI_PATH/topics.md")" = "$topics_sum" ] \
  || { echo "FAIL: topics edit — topics.md changed on main"; fail=1; }

# --- topics: two notes are rejected -------------------------------------------
before=$(head_subject)
STUB_MODE=note-two-notes \
  "$BIN/wiki-ingest-run" --content "$SRC_T" https://example.invalid/topics-two >/dev/null 2>"$SANDBOX/et2"
check "topics: two note/ pages are rejected" 1 $?
grep -q "2 note/ paths staged" "$SANDBOX/et2" \
  || { echo "FAIL: topics two-notes — wrong message: $(cat "$SANDBOX/et2")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: topics two-notes — main advanced to '$(head_subject)'"; fail=1; }

# --- topics: overwriting another source's note (kata 6ctn) -------------------
# A new source whose note title is one that already exists on main. Without
# --force that is a modified note and is rejected outright. With --force it is
# still rejected, because the note at HEAD cites a different slug — --force
# means "re-ingest THIS source", not "you may write over anything".
tg_note_sum=$(csum "$WIKI_PATH/note/$NOTE_TG.md")
before=$(head_subject)
STUB_MODE=note-overwrites-other-note NOTE_TITLE="$NOTE_TG" NOTE_REV=2 \
  "$BIN/wiki-ingest-run" --content "$SRC_T" https://example.invalid/topics-other >/dev/null 2>"$SANDBOX/eto1"
check "topics: overwriting another source's note is rejected" 1 $?
grep -q "already exists and was modified" "$SANDBOX/eto1" \
  || { echo "FAIL: topics overwrite — wrong message: $(cat "$SANDBOX/eto1")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: topics overwrite — main advanced to '$(head_subject)'"; fail=1; }

STUB_MODE=note-overwrites-other-note NOTE_TITLE="$NOTE_TG" NOTE_REV=2 \
  "$BIN/wiki-ingest-run" --force --content "$SRC_T" https://example.invalid/topics-other >/dev/null 2>"$SANDBOX/eto2"
check "topics: --force does not license overwriting another source's note" 1 $?
grep -q "footer does not cite raw/topics-other" "$SANDBOX/eto2" \
  || { echo "FAIL: topics overwrite --force — wrong message: $(cat "$SANDBOX/eto2")"; fail=1; }
[ "$(head_subject)" = "$before" ] \
  || { echo "FAIL: topics overwrite --force — main advanced to '$(head_subject)'"; fail=1; }
[ "$(csum "$WIKI_PATH/note/$NOTE_TG.md")" = "$tg_note_sum" ] \
  || { echo "FAIL: topics overwrite — note/$NOTE_TG.md changed on main"; fail=1; }

# The legitimate case: a --force re-ingest of the SAME source updates its own
# note in place. The footer at HEAD cites raw/topics-good, so it is allowed.
before_n=$(raw_count)
STUB_MODE=note-good NOTE_TITLE="$NOTE_TG" NOTE_REV=2 \
  "$BIN/wiki-ingest-run" --force --content "$SRC_T" "$URL_TG" >/dev/null 2>"$SANDBOX/eto3"
check "topics: --force re-ingest of the same source updates its own note" 0 $?
[ "$(raw_count)" = "$before_n" ] \
  || { echo "FAIL: topics re-ingest — added an archive, stderr: $(cat "$SANDBOX/eto3")"; fail=1; }
git -C "$WIKI_PATH" show "main:note/$NOTE_TG.md" | grep -q '^body rev 2$' \
  || { echo "FAIL: topics re-ingest — note/$NOTE_TG.md on main is not the updated revision, stderr: $(cat "$SANDBOX/eto3")"; fail=1; }

# --- topics: a peer that took our slug and title first is re-run past (925f) --
# Real case: atoll92.github.io/agent-standup/ and github.com/Atoll92/agent-standup
# in one parallel batch both took slug agent-standup and note "Agent Standup";
# the second to merge hit add/add on raw/, summary/ and note/ and retried a
# content conflict five times. Now it must re-run once from a fresh worktree,
# land under a suffixed slug and a distinct title, and leave nothing behind.
ingest_branches() { git -C "$WIKI_PATH" branch --list 'ingest-*' | sed 's/^[*+ ]*//' | sort; }
ingest_worktrees() { git -C "$WIKI_PATH" worktree list --porcelain | awk '/^worktree /{print $2}' | grep 'wiki-ingest-' | sort; }
no_markers() { ! git -C "$WIKI_PATH" grep -qE '^(<<<<<<<|>>>>>>>) ' main -- . 2>/dev/null; }
URL_PC="https://example.invalid/agent-standup"
NOTE_PC="Agent Standup"
br_before=$(ingest_branches); wt_before=$(ingest_worktrees)
: > "$SANDBOX/peer-once"; : > "$SANDBOX/stub-count"
STUB_MODE=note-peer-once NOTE_TITLE="$NOTE_PC" PEER_ONCE="$SANDBOX/peer-once" STUB_COUNT="$SANDBOX/stub-count" \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_PC" >/dev/null 2>"$SANDBOX/epc"
check "collision race: a peer's add/add is re-run past, not failed" 0 $?
[ ! -e "$SANDBOX/peer-once" ] \
  || { echo "FAIL: collision race — the peer was never committed, so the case tested nothing"; fail=1; }
[ "$(wc -l < "$SANDBOX/stub-count" | tr -d ' ')" = 2 ] \
  || { echo "FAIL: collision race — expected 2 LLM runs (original + one re-run), got: $(tr '\n' ' ' < "$SANDBOX/stub-count")"; fail=1; }
grep -q "collided with a peer ingest" "$SANDBOX/epc" && grep -q "re-running $URL_PC" "$SANDBOX/epc" \
  || { echo "FAIL: collision race — stderr does not report the collision re-run: $(cat "$SANDBOX/epc")"; fail=1; }
for p in raw/agent-standup.md summary/agent-standup.md "note/$NOTE_PC.md"; do
  grep -qF "$p" "$SANDBOX/epc" || { echo "FAIL: collision race — stderr does not name colliding path $p"; fail=1; }
done
git -C "$WIKI_PATH" show main:raw/agent-standup.md 2>/dev/null | grep -q '^url: https://peer.example.invalid/agent-standup$' \
  || { echo "FAIL: collision race — the peer's raw/agent-standup.md is not intact on main"; fail=1; }
pc_slug=$(git -C "$WIKI_PATH" grep -l "^url: $URL_PC\$" main -- raw/ 2>/dev/null | sed 's|^main:raw/||; s|\.md$||')
case "$pc_slug" in
  agent-standup-?*) : ;;
  *) echo "FAIL: collision race — ours should be under a suffixed slug, found '$pc_slug', stderr: $(cat "$SANDBOX/epc")"; fail=1 ;;
esac
git -C "$WIKI_PATH" cat-file -e "main:summary/$pc_slug.md" 2>/dev/null \
  || { echo "FAIL: collision race — no summary/$pc_slug.md on main"; fail=1; }
git -C "$WIKI_PATH" show "main:note/$NOTE_PC ($pc_slug).md" 2>/dev/null | grep -q "raw/$pc_slug" \
  || { echo "FAIL: collision race — our note is not on main under a distinct title citing raw/$pc_slug"; fail=1; }
no_markers || { echo "FAIL: collision race — conflict markers on main"; fail=1; }
git -C "$WIKI_PATH" rev-parse -q --verify MERGE_HEAD >/dev/null \
  && { echo "FAIL: collision race — a merge was left in progress"; fail=1; }
[ "$(ingest_branches)" = "$br_before" ] \
  || { echo "FAIL: collision race — ingest branches changed: before [$br_before] after [$(ingest_branches)]"; fail=1; }
[ "$(ingest_worktrees)" = "$wt_before" ] \
  || { echo "FAIL: collision race — ingest worktrees left behind: $(ingest_worktrees)"; fail=1; }

# --- topics: a collision on every run exhausts the re-run budget ---------------
# Three runs (original + two re-runs), then a loud exit 1 naming the collision,
# with only the last run's branch kept — never a loop.
URL_PX="https://example.invalid/always-collides"
br_before=$(ingest_branches)
: > "$SANDBOX/stub-count"
STUB_MODE=note-peer-always NOTE_TITLE="Always Collides" STUB_COUNT="$SANDBOX/stub-count" \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_PX" >/dev/null 2>"$SANDBOX/epx"
check "collision race: an exhausted re-run budget fails loudly" 1 $?
[ "$(wc -l < "$SANDBOX/stub-count" | tr -d ' ')" = 3 ] \
  || { echo "FAIL: collision budget — expected 3 LLM runs, got: $(tr '\n' ' ' < "$SANDBOX/stub-count")"; fail=1; }
grep -q "slug/title collision with peer ingests persisted through 2 re-runs" "$SANDBOX/epx" \
  || { echo "FAIL: collision budget — wrong message: $(cat "$SANDBOX/epx")"; fail=1; }
git -C "$WIKI_PATH" grep -q "^url: $URL_PX\$" main -- raw/ 2>/dev/null \
  && { echo "FAIL: collision budget — $URL_PX reached main"; fail=1; }
no_markers || { echo "FAIL: collision budget — conflict markers on main"; fail=1; }
git -C "$WIKI_PATH" rev-parse -q --verify MERGE_HEAD >/dev/null \
  && { echo "FAIL: collision budget — a merge was left in progress"; fail=1; }
new_br=$(comm -13 <(printf '%s\n' "$br_before") <(ingest_branches) | sed '/^$/d')
[ "$(printf '%s\n' "$new_br" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] \
  || { echo "FAIL: collision budget — expected exactly the last run's branch kept, got [$new_br]"; fail=1; }
for b in $new_br; do git -C "$WIKI_PATH" branch -D "$b" >/dev/null 2>&1; done
[ -z "$(ingest_worktrees)" ] \
  || { echo "FAIL: collision budget — ingest worktrees left behind: $(ingest_worktrees)"; fail=1; }

# --- topics: --summary-only writes topics: too --------------------------------
# A flow list from the stub is normalised to block form; a summary with no
# topics: at all (the legacy summary-good mode) gets misc. Both are repairs,
# both say so in the subject, and both still touch only summary/.
for s in topics-orphan topics-orphan-plain; do
  printf -- '---\nurl: https://example.invalid/%s\ndate_fetched: 2026-08-01\n---\n\nOrphan body for %s.\n' "$s" "$s" \
    > "$WIKI_PATH/raw/$s.md"
done
git -C "$WIKI_PATH" add -A && git -C "$WIKI_PATH" commit -q -m "Seed orphan raw files for topics-mode backfill"

STUB_MODE=summary-topics-flow \
  "$BIN/wiki-ingest-run" --summary-only topics-orphan >/dev/null 2>"$SANDBOX/ets1"
check "topics: --summary-only backfill with flow topics: commits" 0 $?
[ "$(head_subject)" = "Backfill summary: topics-orphan (topics repaired)" ] \
  || { echo "FAIL: topics backfill — HEAD is '$(head_subject)', stderr: $(cat "$SANDBOX/ets1")"; fail=1; }
[ "$(topics_block topics-orphan)" = "topics:
  - alpha" ] \
  || { echo "FAIL: topics backfill — committed topics: is [$(topics_block topics-orphan | tr '\n' '|')]"; fail=1; }
changed=$(git -C "$WIKI_PATH" show --name-only --format="" HEAD | grep -v '^$')
[ "$changed" = "summary/topics-orphan.md" ] \
  || { echo "FAIL: topics backfill — commit touched more than the summary: $changed"; fail=1; }

STUB_MODE=summary-good STUB_SLUG=topics-orphan-plain \
  "$BIN/wiki-ingest-run" --summary-only topics-orphan-plain >/dev/null 2>"$SANDBOX/ets2"
check "topics: --summary-only backfill without topics: gets misc" 0 $?
[ "$(topics_block topics-orphan-plain)" = "topics:
  - misc" ] \
  || { echo "FAIL: topics backfill plain — committed topics: is [$(topics_block topics-orphan-plain | tr '\n' '|')], stderr: $(cat "$SANDBOX/ets2")"; fail=1; }

# --- push: a second writer on origin (the CI runner) -----------------------------
# Every case above runs with no origin remote, so its push fails and it reports
# push-failed with exit 0 — the no-origin behaviour, unchanged. From here on the
# wiki gets a local bare repo as origin and a peer clone that pushes to it, as a
# CI runner would, between our last sync and our ingest.
ORIGIN="$SANDBOX/origin.git"; PEER="$SANDBOX/peer"
git clone -q --bare "$WIKI_PATH" "$ORIGIN"
git -C "$WIKI_PATH" remote add origin "$ORIGIN"
git -C "$WIKI_PATH" fetch -q origin
git clone -q "$ORIGIN" "$PEER"
git -C "$PEER" config user.email "peer@wiki-ingest.invalid"
git -C "$PEER" config user.name "wiki-ingest peer"
origin_has() { git -C "$ORIGIN" log --format=%s main | grep -qxF "$1"; }

# (i) The peer appends to log.md and index.md (the lines our ingest also appends
# after) and adds a page, then pushes. Our push is rejected; the engine must
# fetch, union-merge, and push both commits.
printf -- '- peer log line\n' >> "$PEER/log.md"
printf -- '- peer index line\n' >> "$PEER/index.md"
printf '# Peer Page\n\nfrom the runner\n' > "$PEER/note/Peer Page.md"
git -C "$PEER" add -A && git -C "$PEER" commit -q -m "Ingest: https://peer.example.invalid/runner"
git -C "$PEER" push -q origin main
URL_PS="https://example.invalid/push-sync"
# WIKI_INGEST_NO_SYNC=1: the start-of-ingest catch-up would otherwise merge the
# peer's commit before the push, and this case would stop testing the push path.
WIKI_INGEST_NO_SYNC=1 STUB_MODE=note-good \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_PS" >"$SANDBOX/ops" 2>"$SANDBOX/eps"
check "push: a peer's commit on origin is merged and the ingest pushed" 0 $?
grep -q "push rejected — merging origin/main" "$SANDBOX/eps" \
  || { echo "FAIL: push sync — the push was never rejected, so the push path went untested: $(cat "$SANDBOX/eps")"; fail=1; }
grep -q "merged, pushed)" "$SANDBOX/ops" \
  || { echo "FAIL: push sync — not reported pushed: $(cat "$SANDBOX/ops") stderr: $(cat "$SANDBOX/eps")"; fail=1; }
origin_has "Ingest: https://peer.example.invalid/runner" && origin_has "Ingest: $URL_PS" \
  || { echo "FAIL: push sync — origin lacks one of the two commits: $(git -C "$ORIGIN" log --format=%s -3 main | tr '\n' '|')"; fail=1; }
[ "$(git -C "$WIKI_PATH" rev-parse main)" = "$(git -C "$ORIGIN" rev-parse main)" ] \
  || { echo "FAIL: push sync — local main and origin main differ"; fail=1; }
for f in log.md index.md; do
  git -C "$ORIGIN" show "main:$f" | grep -q "^- peer ${f%.md} line\$" \
    && git -C "$ORIGIN" show "main:$f" | grep -qF "$URL_PS" \
    || { echo "FAIL: push sync — origin $f lacks the peer's line or ours"; fail=1; }
done
no_markers || { echo "FAIL: push sync — conflict markers on main"; fail=1; }

# (ii) A conflict origin cannot union away: the same line of one page, changed
# both on this clone (an unpushed local commit, e.g. an Obsidian edit) and by
# the peer. The engine must abort its catch-up merge, keep the local ingest
# commit, and report push-failed — exit 0 by default, exit 5 when strict.
git -C "$PEER" pull -q --no-rebase origin main
printf 'shared line\n' > "$PEER/note/Contested.md"
git -C "$PEER" add -A && git -C "$PEER" commit -q -m "Seed contested page" && git -C "$PEER" push -q origin main
git -C "$WIKI_PATH" pull -q --no-rebase origin main
printf 'mac version\n' > "$WIKI_PATH/note/Contested.md"
git -C "$WIKI_PATH" commit -q -am "Local edit to contested page"
printf 'runner version\n' > "$PEER/note/Contested.md"
git -C "$PEER" commit -q -am "Runner edit to contested page" && git -C "$PEER" push -q origin main
origin_before=$(git -C "$ORIGIN" rev-parse main)
URL_PC2="https://example.invalid/push-conflict"
STUB_MODE=note-good \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_PC2" >"$SANDBOX/opc" 2>"$SANDBOX/epc2"
check "push: an unresolvable conflict with origin keeps the commit, exit 0" 0 $?
grep -q "merged, push-failed)" "$SANDBOX/opc" \
  || { echo "FAIL: push conflict — not reported push-failed: $(cat "$SANDBOX/opc") stderr: $(cat "$SANDBOX/epc2")"; fail=1; }
grep -q "conflicts with main on: note/Contested.md" "$SANDBOX/epc2" \
  || { echo "FAIL: push conflict — stderr does not name the conflict: $(cat "$SANDBOX/epc2")"; fail=1; }
[ "$(git -C "$ORIGIN" rev-parse main)" = "$origin_before" ] \
  || { echo "FAIL: push conflict — origin main moved"; fail=1; }
[ "$(head_subject)" = "Ingest: $URL_PC2" ] \
  || { echo "FAIL: push conflict — local main HEAD is '$(head_subject)', not the ingest commit"; fail=1; }
[ "$(cat "$WIKI_PATH/note/Contested.md")" = "mac version" ] \
  || { echo "FAIL: push conflict — local contested page changed: $(cat "$WIKI_PATH/note/Contested.md")"; fail=1; }
git -C "$WIKI_PATH" rev-parse -q --verify MERGE_HEAD >/dev/null \
  && { echo "FAIL: push conflict — a merge was left in progress"; fail=1; }
[ -z "$(git -C "$WIKI_PATH" status --porcelain)" ] \
  || { echo "FAIL: push conflict — working tree left dirty: $(git -C "$WIKI_PATH" status --porcelain | tr '\n' '|')"; fail=1; }

URL_PC3="https://example.invalid/push-conflict-strict"
WIKI_INGEST_REQUIRE_PUSH=1 STUB_MODE=note-good \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_PC3" >"$SANDBOX/opc3" 2>"$SANDBOX/epc3"
check "push: WIKI_INGEST_REQUIRE_PUSH=1 makes push-failed exit 5" 5 $?
grep -q "merged, push-failed)" "$SANDBOX/opc3" \
  || { echo "FAIL: push strict — not reported push-failed: $(cat "$SANDBOX/opc3")"; fail=1; }
[ "$(head_subject)" = "Ingest: $URL_PC3" ] \
  || { echo "FAIL: push strict — local main HEAD is '$(head_subject)'"; fail=1; }

# --- catch-up: main meets origin/main BEFORE the dup-check ----------------------
# Until now the Mac only caught up when its own push was rejected, so a URL the
# CI runner had ingested looked new to the dup-check and was ingested twice.
# Reconcile the clones first: the conflict cases above left local main and
# origin diverged on note/Contested.md, which would make every catch-up below
# conflict and test nothing else.
git -C "$WIKI_PATH" pull -q --no-rebase -X ours origin main >/dev/null 2>&1 \
  && git -C "$WIKI_PATH" push -q origin main \
  && git -C "$PEER" pull -q --no-rebase origin main \
  || { echo "FAIL: catch-up — could not reconcile the clones before the catch-up cases"; fail=1; }
# peer_ingests <url> <slug> — the runner ingests <url> and pushes: raw/ and
# summary/ pages carrying its url:, which is all the dup-check reads.
peer_ingests() {
  printf -- '---\nurl: %s\ntitle: Cloud\n---\n\ncloud body\n' "$1" > "$PEER/raw/$2.md"
  printf -- '---\nurl: %s\ntopics:\n  - alpha\n---\n\ncloud precis\n' "$1" > "$PEER/summary/$2.md"
  git -C "$PEER" add -A && git -C "$PEER" commit -q -m "Ingest: $1" && git -C "$PEER" push -q origin main
}

# (i) The runner ingested X and pushed; this clone has not pushed since, so no
# push was ever rejected. A local ingest of X must catch up first and find the
# duplicate. A tracked file with an uncommitted (Obsidian) edit is in the tree:
# the catch-up fast-forwards over it and leaves it alone.
URL_CU="https://example.invalid/cloud-ingested"
peer_ingests "$URL_CU" cloud-ingested
PEER_CU=$(git -C "$PEER" rev-parse main)
printf '# Peer Page\n\nedited in Obsidian, not yet committed\n' > "$WIKI_PATH/note/Peer Page.md"
STUB_MODE=note-good \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_CU" >"$SANDBOX/ocu" 2>"$SANDBOX/ecu"
check "catch-up: a URL the runner already ingested is a local duplicate" 2 $?
grep -q "^DUPLICATE" "$SANDBOX/ocu" \
  || { echo "FAIL: catch-up — not reported DUPLICATE: $(cat "$SANDBOX/ocu") stderr: $(cat "$SANDBOX/ecu")"; fail=1; }
git -C "$WIKI_PATH" merge-base --is-ancestor "$PEER_CU" main \
  || { echo "FAIL: catch-up — local main lacks the runner's commit, stderr: $(cat "$SANDBOX/ecu")"; fail=1; }
grep -q "not yet committed" "$WIKI_PATH/note/Peer Page.md" \
  || { echo "FAIL: catch-up — the uncommitted local edit was lost"; fail=1; }
git -C "$WIKI_PATH" checkout -q -- "note/Peer Page.md"

# (iv) The same setup with WIKI_INGEST_NO_SYNC=1: no catch-up, so the local
# dup-check cannot see the runner's ingest and X is ingested anew (the opt-out
# really opts out). The runner's files carry another slug, so the push path's
# own catch-up merges clean and the ingest is pushed.
URL_NS="https://example.invalid/cloud-ingested-nosync"
peer_ingests "$URL_NS" runner-copy-nosync
STUB_MODE=note-good WIKI_INGEST_NO_SYNC=1 \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_NS" >"$SANDBOX/ons" 2>"$SANDBOX/ens"
check "catch-up: WIKI_INGEST_NO_SYNC=1 skips it, so the URL is ingested anew" 0 $?
grep -q "^INGESTED: $URL_NS" "$SANDBOX/ons" \
  || { echo "FAIL: no-sync — not ingested: $(cat "$SANDBOX/ons") stderr: $(cat "$SANDBOX/ens")"; fail=1; }
grep -q "caught up with origin/main" "$SANDBOX/ens" \
  && { echo "FAIL: no-sync — the catch-up ran anyway"; fail=1; }

# (ii) Origin unreachable (offline, or a broken URL): one warning line and the
# ingest proceeds on local main; the push fails too, which is exit 0 as before.
git -C "$PEER" pull -q --no-rebase origin main
GOOD_ORIGIN=$(git -C "$WIKI_PATH" remote get-url origin)
git -C "$WIKI_PATH" remote set-url origin "$SANDBOX/no-such-origin.git"
URL_OFF="https://example.invalid/catch-up-offline"
STUB_MODE=note-good \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_OFF" >"$SANDBOX/ooff" 2>"$SANDBOX/eoff"
check "catch-up: an unreachable origin warns and the ingest still succeeds" 0 $?
grep -q "not catching up with origin/main: fetch from origin failed" "$SANDBOX/eoff" \
  || { echo "FAIL: offline — no catch-up warning: $(cat "$SANDBOX/eoff")"; fail=1; }
[ "$(head_subject)" = "Ingest: $URL_OFF" ] \
  || { echo "FAIL: offline — local main HEAD is '$(head_subject)'"; fail=1; }
git -C "$WIKI_PATH" remote set-url origin "$GOOD_ORIGIN"
git -C "$WIKI_PATH" push -q origin main && git -C "$PEER" pull -q --no-rebase origin main \
  || { echo "FAIL: offline — could not re-sync the clones afterwards"; fail=1; }

# (iii) Origin conflicts with an unpushed local commit (clean tree): the
# catch-up merge is aborted — ours, so no MERGE_HEAD is left — and the ingest
# proceeds on local main. The push then hits the same conflict, as before.
printf 'shared line\n' > "$PEER/note/Contested Again.md"
git -C "$PEER" add -A && git -C "$PEER" commit -q -m "Seed second contested page" && git -C "$PEER" push -q origin main
git -C "$WIKI_PATH" pull -q --no-rebase origin main
printf 'mac version\n' > "$WIKI_PATH/note/Contested Again.md"
git -C "$WIKI_PATH" commit -q -am "Local edit to second contested page"
printf 'runner version\n' > "$PEER/note/Contested Again.md"
git -C "$PEER" commit -q -am "Runner edit to second contested page" && git -C "$PEER" push -q origin main
URL_CC="https://example.invalid/catch-up-conflict"
STUB_MODE=note-good \
  "$BIN/wiki-ingest-run" --content "$SRC_T" "$URL_CC" >"$SANDBOX/occ" 2>"$SANDBOX/ecc"
check "catch-up: a conflict with origin is aborted and the ingest proceeds" 0 $?
grep -q "not catching up with origin/main: origin/main conflicts with main on: note/Contested Again.md — merge aborted" "$SANDBOX/ecc" \
  || { echo "FAIL: catch-up conflict — no abort warning naming the path: $(cat "$SANDBOX/ecc")"; fail=1; }
[ "$(head_subject)" = "Ingest: $URL_CC" ] \
  || { echo "FAIL: catch-up conflict — local main HEAD is '$(head_subject)'"; fail=1; }
[ "$(cat "$WIKI_PATH/note/Contested Again.md")" = "mac version" ] \
  || { echo "FAIL: catch-up conflict — local page changed: $(cat "$WIKI_PATH/note/Contested Again.md")"; fail=1; }
git -C "$WIKI_PATH" rev-parse -q --verify MERGE_HEAD >/dev/null \
  && { echo "FAIL: catch-up conflict — a merge was left in progress"; fail=1; }
[ -z "$(git -C "$WIKI_PATH" status --porcelain)" ] \
  || { echo "FAIL: catch-up conflict — working tree left dirty: $(git -C "$WIKI_PATH" status --porcelain | tr '\n' '|')"; fail=1; }
no_markers || { echo "FAIL: catch-up conflict — conflict markers on main"; fail=1; }

[ "$fail" = 0 ] && echo "test-guard: ALL PASS"
exit $fail
