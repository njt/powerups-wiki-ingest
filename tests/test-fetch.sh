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

[ "$fail" = 0 ] && echo "test-fetch: ALL PASS"
exit $fail
