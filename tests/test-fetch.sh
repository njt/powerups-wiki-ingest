#!/bin/bash
# Fixture tests for wiki-ingest-fetch (no network).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
FETCH="$DIR/../bin/wiki-ingest-fetch"
fail=0

out=$("$FETCH" --file "$DIR/fixtures/clean-article.html" 2>/dev/null); rc=$?
echo "$out" | grep -q "first real paragraph" && [ "$rc" = 0 ] || { echo "FAIL: clean article body not extracted (rc=$rc)"; fail=1; }
echo "$out" | grep -qi "cookie banner\|ads go here" && { echo "FAIL: boilerplate leaked into output"; fail=1; }

out=$("$FETCH" --file "$DIR/fixtures/js-shell.html" 2>/dev/null); rc=$?
[ -z "$out" ] && [ "$rc" = 3 ] || { echo "FAIL: js-shell should yield empty output + exit 3 (got rc=$rc, bytes=$(printf '%s' "$out" | wc -c))"; fail=1; }

# --- the surf tab-id snippet documented in skills/wiki-ingest/SKILL.md ---
# The block is extracted from the markdown and executed as written against a
# stub `surf`, so these test the documented text itself rather than a copy of
# it. The expected tab id comes from the fixture, not from the markdown.
CMD="$DIR/../skills/wiki-ingest/SKILL.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

sed -n '/^TAB_ID=\$(surf tab new/,/^fi$/p' "$CMD" > "$TMP/block.sh"
[ -s "$TMP/block.sh" ] || { echo "FAIL: tab-id block extracted empty — the sed anchors no longer match skills/wiki-ingest/SKILL.md"; fail=1; }

cat > "$TMP/run.sh" <<'RUNNER'
. "$BLOCK"
printf 'TAB_ID=%s\n' "$TAB_ID"
RUNNER

mkdir -p "$TMP/stub-ok" "$TMP/stub-notab"
cat > "$TMP/stub-ok/surf" <<'STUB'
#!/bin/bash
# Captured live from `surf tab new --args-json '{"url":"about:blank"}'`.
[ "$1 $2" = "tab new" ] || exit 0
printf 'success: true\ntabId: 3.59286798e+08\nurl: about:blank\n'
STUB
cat > "$TMP/stub-notab/surf" <<'STUB'
#!/bin/bash
[ "$1 $2" = "tab new" ] || exit 0
printf 'success: false\nerror: no browser connected\n'
exit 1
STUB
chmod +x "$TMP/stub-ok/surf" "$TMP/stub-notab/surf"

out=$(PATH="$TMP/stub-ok:$PATH" BLOCK="$TMP/block.sh" /bin/bash "$TMP/run.sh" 2>/dev/null)
[ "$out" = "TAB_ID=359286798" ] || { echo "FAIL: documented tab-id pipeline yielded '$out', want 'TAB_ID=359286798'"; fail=1; }

err=$(PATH="$TMP/stub-notab:$PATH" BLOCK="$TMP/block.sh" /bin/bash "$TMP/run.sh" 2>&1 >/dev/null); rc=$?
[ "$rc" != 0 ] || { echo "FAIL: guard block exited 0 with no tabId in surf output — it must bail, not fall through"; fail=1; }
[ -n "$err" ] || { echo "FAIL: guard block said nothing on stderr with no tabId in surf output"; fail=1; }

# --- YouTube routing through ytx (kata 9qeh) --------------------------------
# curl|trafilatura on YouTube only returns the app-shell footer, so the fetch
# must hand youtube.com / youtu.be URLs to ytx and never fall through to curl.
# The stub records its argv and prints exactly the shape ytx's
# internal/publish/publish.go FormatTranscript produces: "# <title>", the
# Channel/URL/Duration/Transcribed bullets, a rule, then the transcript.
# Nothing here runs the real ytx (it costs money via AssemblyAI).
mkdir -p "$TMP/stub-ytx"
cat > "$TMP/stub-ytx/ytx" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$YTX_ARGV_FILE"
last=""; for a in "$@"; do last="$a"; done   # the URL is the final argument
printf '# Computers are bad, actually | Kyle Kingsbury, Jepsen\n\n'
printf -- '- **Channel:** Jepsen\n- **URL:** %s\n- **Duration:** 41m\n- **Transcribed:** 2026-09-22\n\n---\n\n' "$last"
printf 'So the thing about computers is that they are, in fact, bad, and here is why.\n'
STUB
chmod +x "$TMP/stub-ytx/ytx"

for url in "https://www.youtube.com/watch?v=abc123" "https://youtu.be/abc123"; do
  rm -f "$TMP/ytx-argv"
  out=$(PATH="$TMP/stub-ytx:$PATH" YTX_ARGV_FILE="$TMP/ytx-argv" "$FETCH" "$url" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] || { echo "FAIL: ytx: $url exited $rc with the stub on PATH"; fail=1; }
  case "$out" in
    "# Computers are bad, actually | Kyle Kingsbury, Jepsen"*) ;;
    *) echo "FAIL: ytx: $url output does not start with the transcript's '# ' title line: $(printf '%s' "$out" | head -1)"; fail=1 ;;
  esac
  argv=$(tr '\n' ' ' < "$TMP/ytx-argv" 2>/dev/null)
  [ "$argv" = "-no-gist -no-summary $url " ] \
    || { echo "FAIL: ytx: $url invoked the stub as [$argv], want [-no-gist -no-summary $url ]"; fail=1; }
done

# ytx absent: exit 3 with a hint naming ytx, NOT a fall-through to curl. A bare
# /usr/bin:/bin PATH drops ~/go/bin (where go install puts ytx). trafilatura is
# still a hard requirement, so it is pinned explicitly for this one case rather
# than relying on the ~/.local/bin fallback inside the script.
TRAF_BIN=$(command -v trafilatura 2>/dev/null || echo "$HOME/.local/bin/trafilatura")
if PATH=/usr/bin:/bin command -v ytx >/dev/null 2>&1; then
  echo "FAIL: ytx-absent: a ytx is installed in /usr/bin or /bin on this machine, so the absent case cannot run"; fail=1
else
  err=$(PATH=/usr/bin:/bin TRAFILATURA="$TRAF_BIN" "$FETCH" "https://www.youtube.com/watch?v=abc123" 2>&1 >"$TMP/ytx-absent-out"); rc=$?
  [ "$rc" = 3 ] || { echo "FAIL: ytx-absent: expected rc 3, got $rc (stderr: $err)"; fail=1; }
  [ ! -s "$TMP/ytx-absent-out" ] || { echo "FAIL: ytx-absent: stdout was not empty"; fail=1; }
  printf '%s' "$err" | grep -q ytx || { echo "FAIL: ytx-absent: stderr does not mention ytx: $err"; fail=1; }
fi

# An explicit WIKI_INGEST_YTX override that does not resolve is a loud exit 1,
# like TRAFILATURA — not a silent "nothing extracted".
err=$(WIKI_INGEST_YTX=/nonexistent/ytx "$FETCH" "https://youtu.be/abc123" 2>&1 >/dev/null); rc=$?
[ "$rc" = 1 ] || { echo "FAIL: ytx-override: expected rc 1 for an unresolvable WIKI_INGEST_YTX, got $rc"; fail=1; }
printf '%s' "$err" | grep -q WIKI_INGEST_YTX || { echo "FAIL: ytx-override: stderr does not name WIKI_INGEST_YTX: $err"; fail=1; }

# A non-YouTube URL must not touch ytx even when it is on PATH. 127.0.0.1:1 is
# refused immediately, so curl fails fast with no network.
rm -f "$TMP/ytx-argv"
PATH="$TMP/stub-ytx:$PATH" YTX_ARGV_FILE="$TMP/ytx-argv" "$FETCH" "http://127.0.0.1:1/x" >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || { echo "FAIL: non-youtube: expected rc 3 from a refused connection, got $rc"; fail=1; }
[ ! -e "$TMP/ytx-argv" ] || { echo "FAIL: non-youtube: ytx was invoked for a non-YouTube URL: $(cat "$TMP/ytx-argv" | tr '\n' ' ')"; fail=1; }

[ "$fail" = 0 ] && echo "test-fetch: ALL PASS"
exit $fail
