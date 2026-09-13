#!/bin/bash
# Live-fire test of wiki-compile's single-call path (WIKI_COMPILE_MODE=single).
#
# Builds a THROWAWAY topics-mode wiki in a temp dir and points WIKI_LLM at a stub
# that reads the prompt on stdin and prints a reply, the way bin/wiki-llm does.
# Asserts on real git state: what landed on the branch, what the model was TOLD
# (the whole context and the current page, inlined), that the agentic CLI never
# ran, and that every existing gate still guards the single-call page. The last
# case swaps the stub for the real bin/wiki-llm talking to a loopback HTTP
# server, so the wiring between the two scripts is exercised end to end.
# No network beyond 127.0.0.1, no real model, WIKI_PATH is never a real wiki.
#
# Targets bash 3.2 (macOS /bin/bash).

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-compile-single-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
export WIKI_PATH="$SANDBOX/wiki"
SERVER_PID=""
cleanup_all() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
  if [ -d "$WIKI_PATH/.git" ]; then
    git -C "$WIKI_PATH" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' \
      | while read -r w; do
          [ "$w" = "$WIKI_PATH" ] && continue
          git -C "$WIKI_PATH" worktree remove --force "$w" >/dev/null 2>&1 || true
        done
  fi
  rm -rf "$SANDBOX"
  return 0
}
trap cleanup_all EXIT

check() {  # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then echo "ok: $1 (rc=$3)"; else echo "FAIL: $1 — expected rc=$2, got rc=$3"; fail=1; fi
}
ok()  { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# --- stubs ---------------------------------------------------------------------
# The agentic CLI must never run in single mode: it only leaves a mark.
CLI_STUB="$SANDBOX/agentic-cli"
printf '#!/bin/bash\ncat >/dev/null\necho ran >> "%s/cli.log"\nexit 1\n' "$SANDBOX" > "$CLI_STUB"
chmod +x "$CLI_STUB"
export WIKI_INGEST_CLI="$CLI_STUB"

LLM_STUB="$SANDBOX/llm-stub"
cat > "$LLM_STUB" <<'STUB_EOF'
#!/bin/bash
set -u
sys=""
: > "$STUB_DIR/args"
while [ $# -gt 0 ]; do
  printf '%s\n' "$1" >> "$STUB_DIR/args"
  case "$1" in --system) sys="$2"; printf '%s\n' "$2" >> "$STUB_DIR/args"; shift 2 ;; *) shift ;; esac
done
cat > "$STUB_DIR/prompt"
[ -n "$sys" ] && cp "$sys" "$STUB_DIR/system"
filler() { i=0; while [ "$i" -lt 300 ]; do printf 'word%d ' "$i"; i=$((i + 1)); done; printf '\n'; }
page() {
  printf '# Test Theme\n\nA single-call thesis.\n\n---\n\n## The Argument\n\n'
  printf 'It sits beside [[Untouched Page]] and [[Neighbour Page]], and draws on [[Delta Note]].\n\n'
  filler
  printf '\n## What'"'"'s Missing\n\nSome gaps.\n'
}
case "${STUB_MODE:-good}" in
  good)       page ;;
  fenced)     printf 'Here is the page:\n\n```markdown\n'; page; printf '```\n' ;;
  preamble)   printf 'Sure, here is the compiled page.\n\n'; page ;;
  footer)     page; printf '\n---\n\n*Compiled from 99 sources: [[summary/invented]]*\n' ;;
  blank)      printf '   \n\n' ;;
  drop-link)  printf '# Test Theme\n\nThesis.\n\nOnly [[Untouched Page]] survives.\n\n'; filler ;;
  truncated)  exit 4 ;;
  fail)       exit 1 ;;
  *) echo "llm-stub: unknown STUB_MODE" >&2; exit 9 ;;
esac
STUB_EOF
chmod +x "$LLM_STUB"
export STUB_DIR="$SANDBOX/stub"; mkdir -p "$STUB_DIR" "$SANDBOX/tmp"

# --- topics fixture wiki ---------------------------------------------------------
W="$WIKI_PATH"
mkdir -p "$W/topic" "$W/note" "$W/summary" "$W/raw"
git init -q "$W"
git -C "$W" symbolic-ref HEAD refs/heads/main
git -C "$W" config user.email "test@wiki-ingest.invalid"
git -C "$W" config user.name "wiki-ingest test"
: > "$W/index.md"; : > "$W/log.md"
printf '# Wiki Schema\n\nFIXTURE-SCHEMA-MARKER: pages are phone-readable.\n' > "$W/CLAUDE.md"
{ printf '# Topics\n\n| slug | title | scope |\n|---|---|---|\n'
  printf '| test-topic | Test Theme | Scope sentence for the test topic. |\n'
  printf '| misc | Miscellany | Anything else. |\n'; } > "$W/topics.md"
for s in alpha beta delta; do
  { printf -- '---\nurl: https://example.invalid/%s\ntitle: "%s"\ntopics:\n  - test-topic\n---\n\n' "$s" "$s"
    printf 'A precis of %s with the marker DIGEST-%s-BODY.\n' "$s" "$s"; } > "$W/summary/$s.md"
  printf -- '---\nurl: https://example.invalid/%s\n---\n\nVerbatim %s.\n' "$s" "$s" > "$W/raw/$s.md"
done
{ printf '# Test Theme\n\nThe pre-compile version, CURRENT-PAGE-MARKER.\n\n'
  printf 'It sits beside [[Untouched Page]] and [[Neighbour Page]].\n\n'
  i=0; while [ "$i" -lt 300 ]; do printf 'orig%d ' "$i"; i=$((i + 1)); done; printf '\n\n'
  printf '*Compiled from 2 sources: [[summary/alpha]], [[summary/beta]]*\n'; } > "$W/topic/Test Theme.md"
printf '# Untouched Page\n\nThis page must never change.\n' > "$W/note/Untouched Page.md"
printf '# Neighbour Page\n\nThe far end of a cross-link.\n' > "$W/note/Neighbour Page.md"
printf '# Delta Note\n\nThe analysis of delta.\n\n---\n*Sources: [[raw/delta]], [[summary/delta]]*\n' > "$W/note/Delta Note.md"
git -C "$W" add -A
git -C "$W" commit -q -m "Seed the fixture wiki"
MAIN_AT_START=$(git -C "$W" rev-parse main)

pristine() {  # the live checkout never moves
  [ "$(git -C "$W" rev-parse main)" = "$MAIN_AT_START" ] && [ -z "$(git -C "$W" status --porcelain)" ] \
    && [ "$(git -C "$W" worktree list | wc -l | tr -d ' ')" = 1 ] \
    || bad "$1 — live checkout moved, is dirty, or a worktree was left behind"
}
run_single() {  # run_single <tag> <branch>; sets RC
  rm -f "$STUB_DIR"/* "$SANDBOX/cli.log"
  WIKI_COMPILE_MODE=single WIKI_LLM="${LLM_UNDER_TEST:-$LLM_STUB}" TMPDIR="$SANDBOX/tmp" \
    "$BIN/wiki-compile" --theme "Test Theme" --branch "$2" > "$SANDBOX/out.$1" 2>&1
  RC=$?
}
page_on() { git -C "$W" show "$1:topic/Test Theme.md" 2>/dev/null; }

echo "=== wiki-compile WIKI_COMPILE_MODE=single ==="

# Case 1 — the whole evidence base goes into ONE request and the page lands.
STUB_MODE=good run_single good curate/s-good
check "single: a good reply compiles" 0 "$RC"
[ ! -e "$SANDBOX/cli.log" ] && ok "single: the agentic CLI never ran" || bad "single: the agentic CLI ran"
for m in DIGEST-alpha-BODY DIGEST-beta-BODY DIGEST-delta-BODY CURRENT-PAGE-MARKER 'Note page: \[\[Delta Note\]\]' \
         '## SOURCE: summary/alpha.md' 'SCOPE: Scope sentence for the test topic.' 'rebuilding it from all 3 sources'; do
  grep -q "$m" "$STUB_DIR/prompt" && ok "single: prompt carries $m" || bad "single: prompt lacks $m"
done
awk '/^=== LINKS THAT MUST APPEAR/{f=1;next} /^=== END OF INPUTS/{f=0} f && NF' "$STUB_DIR/prompt" > "$SANDBOX/linklist"
[ "$(cat "$SANDBOX/linklist")" = "[[Untouched Page]]
[[Neighbour Page]]" ] && ok "single: prompt lists exactly the current page's links, summary/ excluded" \
  || bad "single: link list was: $(tr '\n' ' ' < "$SANDBOX/linklist")"
grep -q 'LENGTH: about 1200 words' "$STUB_DIR/prompt" && ok "single: length target scales with 3 members" || bad "single: no 1200-word target"
grep -q 'FIXTURE-SCHEMA-MARKER' "$STUB_DIR/system" && ok "single: the wiki CLAUDE.md is the system prompt" \
  || bad "single: system prompt lacks the wiki CLAUDE.md"
if grep -q 'Read these two files first\|Do NOT run git' "$STUB_DIR/prompt"; then bad "single: prompt still talks about files or git"; else ok "single: no file or git instructions"; fi
tr '\n' ' ' < "$STUB_DIR/args" | grep -q -- '--model glm-5.3-flash-background --effort high --max-tokens 32000' \
  && ok "single: default model, effort and max_tokens" || bad "single: args were $(tr '\n' ' ' < "$STUB_DIR/args")"
[ "$(git -C "$W" -c core.quotePath=false show --name-only --format= curate/s-good | grep -v '^$')" = "topic/Test Theme.md" ] \
  && ok "single: the commit touches only the page" || bad "single: commit touched $(git -C "$W" show --name-only --format= curate/s-good | tr '\n' ' ')"
page_on curate/s-good | head -1 | grep -qx '# Test Theme' && ok "single: page starts with the title" || bad "single: page head $(page_on curate/s-good | head -1)"
[ "$(page_on curate/s-good | grep -c '^\*Compiled from 3 sources: \[\[summary/alpha\]\], \[\[summary/beta\]\], \[\[summary/delta\]\]\*$')" = 1 ] \
  && ok "single: the tool wrote the provenance footer" || bad "single: footer wrong: $(page_on curate/s-good | grep Compiled)"
pristine "single good"

# Case 2 — overrides reach wiki-llm.
WIKI_COMPILE_MODEL=other-model WIKI_COMPILE_EFFORT=low WIKI_COMPILE_MAX_TOKENS=999 STUB_MODE=good run_single over curate/s-over
check "single: overrides compile" 0 "$RC"
tr '\n' ' ' < "$STUB_DIR/args" | grep -q -- '--model other-model --effort low --max-tokens 999' \
  && ok "single: WIKI_COMPILE_MODEL/EFFORT/MAX_TOKENS reach wiki-llm" || bad "single: args were $(tr '\n' ' ' < "$STUB_DIR/args")"

# Case 3 — a fenced reply and a preamble are unwrapped to the page.
for mode in fenced preamble; do
  STUB_MODE=$mode run_single "$mode" "curate/s-$mode"
  check "single: $mode reply compiles" 0 "$RC"
  page_on "curate/s-$mode" | head -1 | grep -qx '# Test Theme' && ok "single: $mode unwrapped to the title" \
    || bad "single: $mode page head is '$(page_on "curate/s-$mode" | head -1)'"
  if page_on "curate/s-$mode" | grep -q '```\|Sure, here\|Here is the page'; then bad "single: $mode wrapper survived"; else ok "single: $mode wrapper gone"; fi
done

# Case 4 — a model-written footer is discarded for the authoritative one.
STUB_MODE=footer run_single footer curate/s-footer
check "single: reply with its own footer compiles" 0 "$RC"
if page_on curate/s-footer | grep -q 'summary/invented\|99 sources'; then bad "single: the invented footer survived"; else ok "single: invented footer discarded"; fi

# Case 5 — failures commit nothing and say why.
STUB_MODE=blank run_single blank curate/s-blank
check "single: a blank reply is 'the model never wrote the page'" 6 "$RC"
STUB_MODE=truncated run_single trunc curate/s-trunc
check "single: a cut-off reply is an LLM failure" 4 "$RC"
grep -q 'cut off at max_tokens' "$SANDBOX/out.trunc" && ok "single: says the reply was cut off" || bad "single: output $(cat "$SANDBOX/out.trunc")"
STUB_MODE=fail run_single failed curate/s-fail
check "single: a failed request is an LLM failure" 4 "$RC"
STUB_MODE=drop-link run_single drop curate/s-drop
check "single: the link-preservation gate still rejects" 5 "$RC"
grep -q 'dropped 1 cross-link(s): Neighbour Page' "$SANDBOX/out.drop" && ok "single: names the dropped link" || bad "single: output $(cat "$SANDBOX/out.drop")"
for b in s-blank s-trunc s-fail s-drop; do
  git -C "$W" rev-parse --verify --quiet "refs/heads/curate/$b" >/dev/null && bad "single: branch curate/$b was created" || ok "single: no branch for $b"
done
ls "$SANDBOX/tmp" 2>/dev/null | grep -q "^wiki-compile-single-" \
  && bad "single: a scratch dir survived in TMPDIR" || ok "single: scratch dirs cleaned up"
pristine "single failures"

# Case 6 — a mode that is neither agentic nor single is a usage error.
WIKI_COMPILE_MODE=singel "$BIN/wiki-compile" --theme "Test Theme" > "$SANDBOX/out.mode" 2>&1; RC=$?
check "single: an unknown WIKI_COMPILE_MODE is refused" 2 "$RC"

# Case 7 — end to end through the real wiki-llm and a loopback HTTP gateway.
cat > "$SANDBOX/server.py" <<'PY'
import http.server, json, os, sys
sb = sys.argv[1]
page = open(os.path.join(sb, "reply.md")).read()
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        open(os.path.join(sb, "request.json"), "w").write(body)
        out = json.dumps({"choices": [{"message": {"content": page}, "finish_reason": "stop"}],
                          "usage": {"prompt_tokens": 1, "completion_tokens": 1}}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(out))); self.end_headers()
        self.wfile.write(out)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(sb, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
PY
STUB_MODE=good STUB_DIR="$SANDBOX" "$LLM_STUB" --system /dev/null < /dev/null > "$SANDBOX/reply.md"
python3 "$SANDBOX/server.py" "$SANDBOX" &
SERVER_PID=$!
i=0; while [ ! -s "$SANDBOX/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
printf '{"gw": {"key": "sk-fixture"}}\n' > "$SANDBOX/auth.json"
WIKI_LLM_BASE_URL="http://127.0.0.1:$(cat "$SANDBOX/port")/v1" WIKI_LLM_KEY_FILE="$SANDBOX/auth.json" WIKI_LLM_KEY_PATH=gw.key \
  LLM_UNDER_TEST="$BIN/wiki-llm" run_single e2e curate/s-e2e
check "single e2e: compiles through the real wiki-llm" 0 "$RC"
python3 -c '
import json, sys
b = json.load(open(sys.argv[1]))
assert b["model"] == "glm-5.3-flash-background" and b["reasoning_effort"] == "high" and b["max_tokens"] == 32000, b
assert "FIXTURE-SCHEMA-MARKER" in b["messages"][0]["content"]
assert "DIGEST-delta-BODY" in b["messages"][1]["content"] and "CURRENT-PAGE-MARKER" in b["messages"][1]["content"]
' "$SANDBOX/request.json" && ok "single e2e: the request carries model, effort, cap, schema, context and page" \
  || bad "single e2e: request body wrong"
page_on curate/s-e2e | grep -q 'A single-call thesis' && ok "single e2e: the gateway reply is the page on the branch" || bad "single e2e: page not on branch"
pristine "single e2e"

echo
if [ "$fail" -eq 0 ]; then echo "test-compile-single: ALL PASS"; else echo "test-compile-single: FAILURES"; fi
exit "$fail"
