#!/bin/bash
# Demonstrates the secondary hazard in merge_with_retry (bin/wiki-ingest-run:214):
# `git merge --abort` is called unconditionally, so an ingest whose own merge
# never started can destroy a PEER's in-progress merge state in the shared
# $WIKI checkout.
#
# Pure git plumbing, no wiki-ingest involved. Prints PASS if the hazard is real.
set -u
R=$(mktemp -d /tmp/crossabort-XXXXXX)
trap 'rm -rf "$R"' EXIT
cd "$R"
git init -q -b main .; git config user.email t@t; git config user.name t
printf 'line1\nANCHOR\nline3\n' > page.md; git add -A; git commit -qm base
BASE=$(git rev-parse HEAD)
for s in A B C; do
  git checkout -q -b "ing-$s" "$BASE"
  printf 'line1\nfrom-%s\nANCHOR\nline3\n' "$s" > page.md
  git commit -qam "$s"
done
git checkout -q main
git merge -q --no-edit ing-A

# Peer X: merges, conflicts, leaves MERGE_HEAD set (this is the ~170ms window
# between `git merge` returning 1 and merge_with_retry's own abort).
git merge --no-edit ing-B >/dev/null 2>&1
[ -e .git/MERGE_HEAD ] || { echo "SETUP FAILED: no MERGE_HEAD"; exit 1; }

# Peer Y: a different concurrent ingest reaches merge_with_retry.
git merge --no-edit ing-C >/dev/null 2>&1
rc=$?
echo "peer Y's merge exit=$rc (128 = refused, its own merge never started)"
# NOTE: these unmerged paths are peer X's, not Y's. This is why "are there
# unmerged paths?" is NOT a safe way to tell a content conflict from contention
# -- the index is shared. Only the exit code distinguishes them: 1 means THIS
# process's merge ran and conflicted; 128 means it never started.
echo "peer Y unmerged paths: [$(git diff --name-only --diff-filter=U | tr '\n' ' ')] (peer X's, not Y's)"

# merge_with_retry aborts unconditionally at this point.
git merge --abort 2>/dev/null
if [ -e .git/MERGE_HEAD ]; then
  echo "PASS(no hazard): peer X's merge survived"
  exit 1
fi
echo "PASS(hazard real): peer X's merge state was destroyed by peer Y's unconditional abort"
exit 0
