#!/bin/bash
# Deterministic reproduction of the topic/-page merge conflict.
#
# No network, no real LLM, no real concurrency, no sleeps. The stub CLI for
# ingest B invokes ingest A synchronously mid-run, which makes B's worktree base
# stale by exactly one merge -- the same branch topology two genuinely-parallel
# ingests produce, but forced rather than raced.
#
# Exits 0 if the conflict reproduced (i.e. the bug is present).

set -u
BIN="${BIN:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/bin}"
SELF="$(cd "$(dirname "$0")" && pwd)"

WIKI=$(mktemp -d /tmp/wiki-repro-XXXXXX)
export WIKI_PATH="$WIKI"
PATH="$BIN:$PATH"; export PATH

cleanup() {
  git -C "$WIKI" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | \
    while read -r w; do [ "$w" = "$WIKI" ] || git -C "$WIKI" worktree remove --force "$w" 2>/dev/null; done
  rm -rf "$WIKI"
}
trap cleanup EXIT

wiki-ingest-setup >/dev/null

# Seed a POPULATED wiki: the shared topic page both ingests will edit.
cat > "$WIKI/topic/Shared Topic.md" <<'EOF'
# Shared Topic

## What's Missing

**Existing gap.** Something already written here.
EOF
if [ "${UNION:-0}" = "1" ]; then printf 'topic/*.md merge=union\n' >> "$WIKI/.gitattributes"; fi
printf -- '---\nurl: https://example.com/seed\n---\n\nseed\n' > "$WIKI/raw/seed.md"
printf -- '---\nurl: https://example.com/seed\n---\n\nseed precis\n' > "$WIKI/summary/seed.md"
git -C "$WIKI" add -A
git -C "$WIKI" commit -q -m "Seed populated wiki"

ALPHA_CONTENT=$(mktemp /tmp/repro-alpha-XXXXXX)
BETA_CONTENT=$(mktemp /tmp/repro-beta-XXXXXX)
printf 'Alpha source body, long enough to clear the forty-character length check.\n' > "$ALPHA_CONTENT"
printf 'Beta source body, long enough to clear the forty-character length check.\n'  > "$BETA_CONTENT"
export ALPHA_CONTENT SELF

echo "== ingest B starts; its stub runs ingest A to completion mid-flight =="
set +e
WIKI_INGEST_CLI="$SELF/stub-beta.sh" wiki-ingest-run --content "$BETA_CONTENT" https://example.com/beta-source
rc=$?
set -e
echo "== wiki-ingest-run (B) exit code: $rc =="

echo "== unmerged paths left in \$WIKI: [$(git -C "$WIKI" diff --name-only --diff-filter=U | tr '\n' ' ')]"
echo "== surviving ingest branches: [$(git -C "$WIKI" branch --list 'ingest-*' | tr -d ' *' | tr '\n' ' ')]"
echo "== shared page after run =="; sed -n '1,12p' "$WIKI/topic/Shared Topic.md" | sed 's/^/   | /'
echo "== synthesis paragraphs on the shared page: $(grep -c 'New from ' "$WIKI/topic/Shared Topic.md" 2>/dev/null || echo 0) (want 2)"
echo "== conflict markers committed on main: $(git -C "$WIKI" grep -cE '^(<<<<<<<|>>>>>>>) ' HEAD -- 'topic/*' 2>/dev/null | tr '\n' ' ')"

rm -f "$ALPHA_CONTENT" "$BETA_CONTENT"
if [ "$rc" -ne 0 ]; then
  echo "REPRODUCED: ingest B failed to merge (exit $rc)"
  exit 0
fi
echo "NOT REPRODUCED: ingest B merged cleanly"
exit 1
