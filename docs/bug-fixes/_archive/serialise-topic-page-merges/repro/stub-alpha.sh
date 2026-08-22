#!/bin/bash
# Stub LLM for ingest A. cwd is the ingest worktree.
set -u
cat >/dev/null   # consume the prompt
printf -- '---\nurl: https://example.com/alpha-source\n---\n\nAlpha precis.\n' > summary/alpha-source.md
printf '# Alpha Page\n\nAlpha analysis.\n' > "topic/Alpha Page.md"
# SYNTHESIS: additive edit at the same anchor B will use.
python3 - <<'PY'
p="topic/Shared Topic.md"
s=open(p).read()
s=s.replace("**Existing gap.**", "**New from A.** Alpha weaves itself in. [[Alpha Page]]\n\n**Existing gap.**")
open(p,"w").write(s)
PY
