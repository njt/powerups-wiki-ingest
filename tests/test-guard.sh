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
