#!/bin/bash
# Live-fire test of wiki-ingest-run's single-call path (WIKI_INGEST_MODE=single).
#
# Bootstraps a THROWAWAY topics-mode wiki with wiki-ingest-setup, seeds a few
# notes, and points WIKI_LLM at a stub that reads the prompt on stdin and prints
# a delimited reply the way bin/wiki-llm would. Every case ingests with
# --content (no network) and asserts on what actually landed on main: the three
# tiers, the index.md entry under the primary topic's section, the log.md line,
# what the model was TOLD (archive, topics, titles, nearest notes), and that the
# existing guard and topics repair still govern a single-call ingest. The last
# case runs the real bin/wiki-llm against a loopback HTTP server.
# No network beyond 127.0.0.1, no real model, WIKI_PATH is never a real wiki.
#
# Targets bash 3.2 (macOS /bin/bash).

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-ingest-single-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
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

check() { if [ "$2" = "$3" ]; then echo "ok: $1 (rc=$3)"; else echo "FAIL: $1 — expected rc=$2, got rc=$3"; fail=1; fi; }
ok()  { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# --- stubs ---------------------------------------------------------------------
CLI_STUB="$SANDBOX/agentic-cli"
printf '#!/bin/bash\ncat >/dev/null\necho ran >> "%s/cli.log"\nexit 1\n' "$SANDBOX" > "$CLI_STUB"
chmod +x "$CLI_STUB"
export WIKI_INGEST_CLI="$CLI_STUB"

LLM_STUB="$SANDBOX/llm-stub"
cat > "$LLM_STUB" <<'STUB_EOF'
#!/bin/bash
set -u
: > "$STUB_DIR/args"; sys=""
while [ $# -gt 0 ]; do
  printf '%s\n' "$1" >> "$STUB_DIR/args"
  case "$1" in --system) sys="$2"; printf '%s\n' "$2" >> "$STUB_DIR/args"; shift 2 ;; *) shift ;; esac
done
prompt=$(cat); printf '%s' "$prompt" > "$STUB_DIR/prompt"
[ -n "$sys" ] && cp "$sys" "$STUB_DIR/system"
slug=$(printf '%s' "$prompt" | sed -n 's|.*saved verbatim to raw/\([A-Za-z0-9._-]*\)\.md.*|\1|p' | head -1)
url=$(printf '%s' "$prompt" | sed -n 's|^Source URL: ||p' | head -1)
topics="${STUB_TOPICS:-topics:
  - agent-orchestration}"
reply() {
  printf '=== FILE: summary.md ===\n---\nurl: %s\ntitle: "%s"\nauthor: Ada Example\ndate_fetched: 2026-09-13\n%s\n---\n\n' "$url" "${STUB_SOURCE_TITLE:-Queues for Agents}" "$topics"
  printf 'The source argues that agent fleets need queues. It measures three schedulers. It ends with a warning.\n\nA second paragraph.\n'
  printf '=== FILE: note.md ===\n# %s\n\n' "$1"
  printf 'Agent fleets need durable queues, not chat. More detail follows.\n\n## Key quotes\n\n> "a quote"\n\n## Related\n\n'
  printf -- '- [[Orchestrating Fleets]] — this source strengthens it.\n- [[Agent Orchestration]] — and nuances this.\n\n'
  printf -- '---\n*Sources: [[raw/%s]], [[summary/%s]]*\n=== END ===\n' "$slug" "$slug"
}
case "${STUB_MODE:-good}" in
  good)     reply "${STUB_TITLE:-Queues for Agents}" ;;
  blocked)  printf '=== BLOCKED ===\n' ;;
  garbage)  printf 'I could not do this.\n' ;;
  fail)     exit 1 ;;
  truncated) exit 4 ;;
  *) echo "llm-stub: unknown STUB_MODE" >&2; exit 9 ;;
esac
STUB_EOF
chmod +x "$LLM_STUB"
export STUB_DIR="$SANDBOX/stub"; mkdir -p "$STUB_DIR" "$SANDBOX/tmp"

# --- fixture wiki ----------------------------------------------------------------
"$BIN/wiki-ingest-setup" >/dev/null || { echo "FAIL: wiki-ingest-setup failed"; exit 1; }
W="$WIKI_PATH"
git -C "$W" config user.email "test@wiki-ingest.invalid"
git -C "$W" config user.name "wiki-ingest test"
[ -f "$W/topics.md" ] || { echo "FAIL: setup did not seed topics.md"; exit 1; }
mkdir -p "$W/note" "$W/topic"
printf '# Orchestrating Fleets\n\nFleets of agents coordinate through durable queues and schedulers; ORCH-PRECIS-MARKER.\n' > "$W/note/Orchestrating Fleets.md"
printf '# Sourdough Baking\n\nFlour, water, salt and a starter; nothing about software.\n' > "$W/note/Sourdough Baking.md"
printf '# Existing Title\n\nAn unrelated note whose title a model might reuse.\n' > "$W/note/Existing Title.md"
printf '# Agent Orchestration\n\nThe compiled topic page.\n' > "$W/topic/Agent Orchestration.md"
git -C "$W" add -A && git -C "$W" commit -q -m "Seed notes"

SRC="$SANDBOX/source.md"
printf '# Queues for Agents\n\nAgent fleets need durable queues and schedulers. SOURCE-BODY-MARKER. %s\n' \
  "$(i=0; while [ "$i" -lt 60 ]; do printf 'orchestration queue scheduler fleet '; i=$((i + 1)); done)" > "$SRC"

run_single() {  # run_single <tag> <url> [extra args]; sets RC
  tag="$1"; url="$2"; shift 2
  rm -f "$STUB_DIR"/* "$SANDBOX/cli.log"
  WIKI_INGEST_MODE=single WIKI_LLM="${LLM_UNDER_TEST:-$LLM_STUB}" TMPDIR="$SANDBOX/tmp" \
    "$BIN/wiki-ingest-run" --content "$SRC" --date 2026-09-13 "$@" "$url" > "$SANDBOX/out.$tag" 2>&1
  RC=$?
}
head_files() { git -C "$W" -c core.quotePath=false show --name-only --format= "$1" | grep -v '^$' | sort | tr '\n' ' '; }

echo "=== wiki-ingest-run WIKI_INGEST_MODE=single ==="

# Case 1 — a good reply lands all three tiers plus index and log on main.
BEFORE=$(git -C "$W" rev-parse main)
STUB_MODE=good run_single good https://example.invalid/queues-for-agents
check "single: a good reply ingests" 0 "$RC"
[ ! -e "$SANDBOX/cli.log" ] && ok "single: the agentic CLI never ran" || bad "single: the agentic CLI ran"
ING=$(git -C "$W" log --format=%H --grep '^Ingest: https://example.invalid/queues-for-agents' -1)
[ -n "$ING" ] && [ "$(git -C "$W" rev-parse main)" != "$BEFORE" ] && ok "single: an Ingest commit merged into main" || bad "single: no ingest commit: $(cat "$SANDBOX/out.good")"
[ "$(head_files "$ING")" = "index.md log.md note/Queues for Agents.md raw/queues-for-agents.md summary/queues-for-agents.md " ] \
  && ok "single: the commit holds exactly raw, summary, note, index, log" || bad "single: commit files: $(head_files "$ING")"
grep -q 'SOURCE-BODY-MARKER' "$STUB_DIR/prompt" && ok "single: prompt carries the archive" || bad "single: prompt lacks the archive"
grep -q '^| agent-orchestration | Agent Orchestration |' "$STUB_DIR/prompt" && ok "single: prompt carries the topics table" || bad "single: no topics table"
awk '/^# Nearest existing notes/{f=1;next} /^---$/{f=0} f && NF' "$STUB_DIR/prompt" | head -1 | grep -q '^- \[\[Orchestrating Fleets\]\] — Fleets of agents coordinate.*ORCH-PRECIS-MARKER' \
  && ok "single: the nearest note, with its précis, heads the neighbours block" || bad "single: neighbours block: $(awk '/^# Nearest existing notes/{f=1;next} /^---$/{f=0} f && NF' "$STUB_DIR/prompt" | head -2)"
awk '/^# Existing note\/ and topic\/ page titles/{f=1;next} /^---$/{f=0} f && NF' "$STUB_DIR/prompt" > "$SANDBOX/titles"
[ "$(tr '\n' '|' < "$SANDBOX/titles")" = "Agent Orchestration|Existing Title|Orchestrating Fleets|Sourdough Baking|" ] \
  && ok "single: prompt lists every note and topic title" || bad "single: title list: $(tr '\n' '|' < "$SANDBOX/titles")"
grep -q 'Wiki Schema\|wiki' "$STUB_DIR/system" && ok "single: the wiki CLAUDE.md is the system prompt" || bad "single: system prompt empty"
if grep -q 'Update index.md\|Append to log.md' "$STUB_DIR/prompt"; then bad "single: prompt still asks the model for index/log"; else ok "single: index and log are not the model's job"; fi
tr '\n' ' ' < "$STUB_DIR/args" | grep -q -- '--model deepseek-4.1-flash-background --effort low --max-tokens 16000' \
  && ok "single: default model, effort and max_tokens" || bad "single: args $(tr '\n' ' ' < "$STUB_DIR/args")"
awk '/^## Agent Orchestration$/{f=1;next} /^## /{f=0} f' "$W/index.md" | grep -qx -- '- \[\[Queues for Agents\]\] — Agent fleets need durable queues, not chat.' \
  && ok "single: index entry under the primary topic's section" || bad "single: index.md is: $(cat "$W/index.md")"
tail -1 "$W/log.md" | grep -qx -- '- 2026-09-13: Ingested \[Queues for Agents\](https://example.invalid/queues-for-agents) (Ada Example, example.invalid, publication date not stated) — The source argues that agent fleets need queues. It measures three schedulers. It ends with a warning. → raw/queues-for-agents.md, \[\[Queues for Agents\]\]. Cross-links: \[\[Orchestrating Fleets\]\], \[\[Agent Orchestration\]\].' \
  && ok "single: log line in the wiki's format" || bad "single: log line: $(tail -1 "$W/log.md")"
[ -z "$(ls "$SANDBOX/tmp" | grep '^wiki-ingest-single-')" ] && ok "single: scratch dir cleaned up" || bad "single: scratch dir left"

# Case 2 — a second note on the same topic joins the existing section; a colon
# in the title becomes the wiki's em-dash, and the H1 follows the filename.
STUB_MODE=good STUB_TITLE="Queues: The Sequel" run_single colon https://example.invalid/queues-sequel
check "single: a second ingest on the same topic" 0 "$RC"
[ -f "$W/note/Queues — The Sequel.md" ] && head -1 "$W/note/Queues — The Sequel.md" | grep -qx '# Queues — The Sequel' \
  && ok "single: colon title filed as 'Queues — The Sequel' with a matching H1" || bad "single: note files: $(ls "$W/note" | tr '\n' '|')"
[ "$(grep -c '^## Agent Orchestration$' "$W/index.md")" = 1 ] && \
  awk '/^## Agent Orchestration$/{f=1;next} /^## /{f=0} f && /^- /' "$W/index.md" | tr '\n' '|' | grep -q '^- \[\[Queues for Agents\]\].*|- \[\[Queues — The Sequel\]\]' \
  && ok "single: both entries in one section, in order" || bad "single: index.md is: $(cat "$W/index.md")"

# Case 3 — flow-form topics are repaired by the existing normalize step.
STUB_MODE=good STUB_TITLE="Flow Topics Note" STUB_TOPICS="topics: [agent-orchestration]" run_single flow https://example.invalid/flow-topics
check "single: a flow topics: list still ingests" 0 "$RC"
git -C "$W" log -1 --format=%s --grep 'flow-topics' | grep -q '(topics repaired)' && ok "single: topics repaired and said so" || bad "single: subject $(git -C "$W" log -1 --format=%s --grep flow-topics)"

# Case 4 — failures leave main untouched.
for spec in "blocked|3|https://example.invalid/blocked-page" "garbage|1|https://example.invalid/garbage-reply" \
            "fail|1|https://example.invalid/failed-call" "truncated|1|https://example.invalid/cut-off"; do
  mode=${spec%%|*}; rest=${spec#*|}; want=${rest%%|*}; url=${rest#*|}
  BEFORE=$(git -C "$W" rev-parse main)
  STUB_MODE=$mode run_single "$mode" "$url"
  check "single: $mode reply" "$want" "$RC"
  [ "$(git -C "$W" rev-parse main)" = "$BEFORE" ] && [ -z "$(git -C "$W" status --porcelain)" ] \
    && ok "single: $mode leaves main and the checkout untouched" || bad "single: $mode moved main or dirtied the checkout"
done
grep -q 'cut off at max_tokens' "$SANDBOX/out.truncated" && ok "single: says the reply was cut off" || bad "single: $(cat "$SANDBOX/out.truncated")"
grep -q 'no === FILE: summary.md === and === FILE: note.md === markers' "$SANDBOX/out.garbage" && ok "single: says why the reply was unusable" || bad "single: $(cat "$SANDBOX/out.garbage")"

# Case 5 — a title that already exists is refused, not written over.
BEFORE=$(git -C "$W" rev-parse main)
STUB_MODE=good STUB_TITLE="Existing Title" run_single clash https://example.invalid/title-clash
check "single: a note title that already exists is refused" 1 "$RC"
grep -q 'note/Existing Title.md already exists' "$SANDBOX/out.clash" && ok "single: names the clash" || bad "single: $(cat "$SANDBOX/out.clash")"
[ "$(git -C "$W" rev-parse main)" = "$BEFORE" ] && ok "single: clash leaves main untouched" || bad "single: clash moved main"

# Case 6 — --force and an unknown mode.
STUB_MODE=good run_single force https://example.invalid/forced --force
[ -e "$SANDBOX/cli.log" ] && ok "single: --force takes the agentic path" || bad "single: --force did not use the agentic CLI"
WIKI_INGEST_MODE=singel "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/bad-mode > "$SANDBOX/out.mode" 2>&1; RC=$?
check "single: an unknown WIKI_INGEST_MODE is a usage error" 64 "$RC"

# Case 7 — end to end through the real wiki-llm and a loopback gateway.
cat > "$SANDBOX/server.py" <<'PY'
import http.server, json, os, sys
sb = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode())
        open(os.path.join(sb, "request.json"), "w").write(json.dumps(body))
        prompt = body["messages"][1]["content"]
        slug = prompt.split("saved verbatim to raw/", 1)[1].split(".md", 1)[0]
        url = [l for l in prompt.splitlines() if l.startswith("Source URL: ")][0][12:]
        reply = ("=== FILE: summary.md ===\n---\nurl: %s\ntitle: \"Over The Wire\"\ntopics:\n  - agent-orchestration\n---\n\n"
                 "Precis over the wire.\n=== FILE: note.md ===\n# Over The Wire\n\nArrived by HTTP.\n\n"
                 "- [[Orchestrating Fleets]] — strengthens it.\n\n---\n*Sources: [[raw/%s]], [[summary/%s]]*\n=== END ===\n") % (url, slug, slug)
        out = json.dumps({"choices": [{"message": {"content": reply}, "finish_reason": "stop"}], "usage": {}}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(out))); self.end_headers()
        self.wfile.write(out)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(sb, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$SANDBOX/server.py" "$SANDBOX" &
SERVER_PID=$!
i=0; while [ ! -s "$SANDBOX/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
printf '{"gw": {"key": "sk-fixture"}}\n' > "$SANDBOX/auth.json"
WIKI_LLM_BASE_URL="http://127.0.0.1:$(cat "$SANDBOX/port")/v1" WIKI_LLM_KEY_FILE="$SANDBOX/auth.json" WIKI_LLM_KEY_PATH=gw.key \
  LLM_UNDER_TEST="$BIN/wiki-llm" run_single e2e https://example.invalid/over-the-wire
check "single e2e: ingests through the real wiki-llm" 0 "$RC"
[ -f "$W/note/Over The Wire.md" ] && ok "single e2e: the gateway's note is on main" || bad "single e2e: $(cat "$SANDBOX/out.e2e")"
python3 -c '
import json, sys
b = json.load(open(sys.argv[1]))
assert b["model"] == "deepseek-4.1-flash-background" and b["reasoning_effort"] == "low" and b["max_tokens"] == 16000, b
assert "SOURCE-BODY-MARKER" in b["messages"][1]["content"]
' "$SANDBOX/request.json" && ok "single e2e: request carries model, effort, cap and the archive" || bad "single e2e: request wrong"

echo
if [ "$fail" -eq 0 ]; then echo "test-ingest-single: ALL PASS"; else echo "test-ingest-single: FAILURES"; fi
exit "$fail"
