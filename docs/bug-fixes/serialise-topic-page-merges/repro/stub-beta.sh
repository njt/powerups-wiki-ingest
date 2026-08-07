#!/bin/bash
# Stub LLM for ingest B. cwd is the ingest worktree.
set -u
cat >/dev/null   # consume the prompt
printf -- '---\nurl: https://example.com/beta-source\n---\n\nBeta precis.\n' > summary/beta-source.md
printf '# Beta Page\n\nBeta analysis.\n' > "topic/Beta Page.md"
python3 - <<'PY'
p="topic/Shared Topic.md"
s=open(p).read()
s=s.replace("**Existing gap.**", "**New from B.** Beta weaves itself in. [[Beta Page]]\n\n**Existing gap.**")
open(p,"w").write(s)
PY
# TIMING HOOK: ingest A runs to completion (and merges to main) while B is mid-flight.
WIKI_INGEST_CLI="$SELF/stub-alpha.sh" wiki-ingest-run --content "$ALPHA_CONTENT" https://example.com/alpha-source >&2
