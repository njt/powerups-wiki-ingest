#!/bin/bash
# Live-fire test of the post-LLM completeness guard in wiki-ingest-run.
#
# Bootstraps a THROWAWAY wiki in a temp dir, points WIKI_INGEST_CLI at a stub
# "LLM" that writes exactly the files each case needs, and asserts that
# wiki-ingest-run commits only when the ingest actually produced the tiers it
# promised. No network: every case uses --content with a local text file.
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
STUB="$SANDBOX/stub-cli"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
set -u
cat >/dev/null   # drain the prompt
s="${STUB_SLUG:-unknown}"
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

[ "$fail" = 0 ] && echo "test-guard: ALL PASS"
exit $fail
