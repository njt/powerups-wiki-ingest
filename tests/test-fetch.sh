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

[ "$fail" = 0 ] && echo "test-fetch: ALL PASS"
exit $fail
