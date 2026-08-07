#!/bin/bash
# Reproduction for kata pxf4 — slug collision on a shared last path segment.
#
# Throwaway wiki, stubbed LLM, no network. Ingests two DIFFERENT sources whose
# URLs end in the same path segment and asserts both survive.
#
# Run:  BIN=/path/to/repo/bin bash repro-slug-collision.sh
# Exit: 0 = both sources survived (fixed), 1 = one clobbered the other (bug)

set -u
BIN="${BIN:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/bin}"
fail=0
sum() { md5 -q "$1" 2>/dev/null || md5sum "$1" | awk '{print $1}'; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-collide.XXXXXX")
export WIKI_PATH="$SANDBOX/wiki"
cleanup_all() {
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

# Stub LLM: reads the slug out of the prompt it is given, so it tracks whatever
# slug wiki-ingest-run actually chose (this is what makes the test fix-agnostic).
STUB="$SANDBOX/stub-cli"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
set -u
prompt=$(cat)
# "saved verbatim to raw/<slug>.md" appears in every ingest prompt.
s=$(printf '%s' "$prompt" | sed -n 's|.*raw/\([A-Za-z0-9._-]*\)\.md.*|\1|p' | head -1)
[ -n "$s" ] || { echo "stub: could not find slug in prompt" >&2; exit 1; }
url=$(sed -n 's/^url: //p' "raw/$s.md" | head -1)
printf -- '---\nurl: %s\n---\n\nprecis of %s\n' "$url" "$url" > "summary/$s.md"
# Vary the body: a byte-identical rewrite stages nothing and trips the
# completeness guard, which would mask what the control case is testing.
printf '# %s\n\nbody rev %s\n' "$TOPIC_TITLE" "${TOPIC_REV:-1}" > "topic/$TOPIC_TITLE.md"
printf -- '- entry for %s -> raw/%s.md\n' "$url" "$s" >> index.md
printf -- '- entry for %s -> raw/%s.md\n' "$url" "$s" >> log.md
exit 0
STUB_EOF
chmod +x "$STUB"
export WIKI_INGEST_CLI="$STUB"

"$BIN/wiki-ingest-setup" >/dev/null || { echo "FAIL: setup"; exit 1; }
git -C "$WIKI_PATH" config user.email "test@wiki-ingest.invalid"
git -C "$WIKI_PATH" config user.name "wiki-ingest test"

SRC_BLOG="$SANDBOX/blog.txt"
SRC_REPO="$SANDBOX/repo.txt"
printf 'BLOG BODY. Cloudflare announces its new operating system in a blog post, at length.\n' > "$SRC_BLOG"
printf 'REPO BODY. The cloudflare-os repository README describing how to build the OS.\n' > "$SRC_REPO"

URL_BLOG="https://blog.cloudflare.com/cloudflare-os/"
URL_REPO="https://github.com/cloudflare/cloudflare-os"

echo "--- ingest 1: $URL_BLOG"
TOPIC_TITLE="Cloudflare OS Blog" \
  "$BIN/wiki-ingest-run" --content "$SRC_BLOG" "$URL_BLOG" 2>&1 | sed 's/^/    /'

# Fingerprint the first source's archive: a colliding ingest must leave the
# incumbent byte-identical, not merely "still mentioning the right words".
raw1=$(sum "$WIKI_PATH/raw/cloudflare-os.md")
sum1=$(sum "$WIKI_PATH/summary/cloudflare-os.md")

echo "--- ingest 2: $URL_REPO"
TOPIC_TITLE="Cloudflare OS Repo" \
  "$BIN/wiki-ingest-run" --content "$SRC_REPO" "$URL_REPO" 2>&1 | sed 's/^/    /'

echo
echo "--- resulting raw/ and summary/ ---"
ls -1 "$WIKI_PATH/raw" "$WIKI_PATH/summary"

# --- assertions: one archive per source, each holding its own body -----------
blog_file=$(grep -rl "^url: $URL_BLOG$" "$WIKI_PATH/raw" 2>/dev/null | head -1)
repo_file=$(grep -rl "^url: $URL_REPO$" "$WIKI_PATH/raw" 2>/dev/null | head -1)

[ -n "$blog_file" ] || { echo "FAIL: no raw/ archive holds the BLOG url — it was clobbered"; fail=1; }
[ -n "$repo_file" ] || { echo "FAIL: no raw/ archive holds the REPO url"; fail=1; }
if [ -n "$blog_file" ] && [ -n "$repo_file" ] && [ "$blog_file" = "$repo_file" ]; then
  echo "FAIL: both urls resolved to the same file $blog_file"; fail=1
fi
if [ -n "$blog_file" ]; then
  grep -q "BLOG BODY" "$blog_file" || { echo "FAIL: $blog_file does not hold the blog body"; fail=1; }
fi
# The incumbent's two archives must be untouched by the colliding ingest.
[ "$(sum "$WIKI_PATH/raw/cloudflare-os.md" 2>/dev/null)" = "$raw1" ] \
  || { echo "FAIL: raw/cloudflare-os.md changed when the second source was ingested"; fail=1; }
[ "$(sum "$WIKI_PATH/summary/cloudflare-os.md" 2>/dev/null)" = "$sum1" ] \
  || { echo "FAIL: summary/cloudflare-os.md changed when the second source was ingested"; fail=1; }
if [ -n "$repo_file" ]; then
  grep -q "REPO BODY" "$repo_file" || { echo "FAIL: $repo_file does not hold the repo body"; fail=1; }
fi
# Every log.md pointer must name a raw file that exists and carries that url.
while IFS= read -r line; do
  case "$line" in *"-> raw/"*) ;; *) continue ;; esac
  u=$(printf '%s' "$line" | sed -n 's/^- entry for \(.*\) -> raw\/.*/\1/p')
  f=$(printf '%s' "$line" | sed -n 's/^.* -> raw\/\(.*\)\.md$/\1/p')
  [ -f "$WIKI_PATH/raw/$f.md" ] || { echo "FAIL: log.md points at missing raw/$f.md"; fail=1; continue; }
  grep -q "^url: $u\$" "$WIKI_PATH/raw/$f.md" \
    || { echo "FAIL: log.md says $u lives in raw/$f.md, but that file's url is $(sed -n 's/^url: //p' "$WIKI_PATH/raw/$f.md" | head -1)"; fail=1; }
done < "$WIKI_PATH/log.md"

# --- control: re-ingesting the SAME url must NOT mint a second archive -------
before_n=$(ls -1 "$WIKI_PATH/raw" | wc -l | tr -d ' ')
echo "--- control: re-ingest (--force) of $URL_BLOG"
TOPIC_TITLE="Cloudflare OS Blog" TOPIC_REV=2 \
  "$BIN/wiki-ingest-run" --force --content "$SRC_BLOG" "$URL_BLOG" 2>&1 | sed 's/^/    /'
after_n=$(ls -1 "$WIKI_PATH/raw" | wc -l | tr -d ' ')
[ "$before_n" = "$after_n" ] \
  || { echo "FAIL: re-ingest of the same url added an archive ($before_n -> $after_n) — re-ingest must update in place"; fail=1; }

echo
[ "$fail" = 0 ] && echo "REPRO: PASS (no collision)" || echo "REPRO: FAIL (collision reproduced)"
exit $fail
