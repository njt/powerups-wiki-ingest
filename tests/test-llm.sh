#!/bin/bash
# Live-fire test of bin/wiki-llm, the single-call client behind
# WIKI_COMPILE_MODE=single and WIKI_INGEST_MODE=single.
#
# Runs a real HTTP server on 127.0.0.1 (python3 stdlib, in the sandbox) that
# speaks just enough of the OpenAI chat-completions shape, and drives wiki-llm
# against it over a real socket. No network beyond loopback, no real model.
# What is asserted is what a caller depends on: the request carries the model,
# effort, token cap, both prompts and the key; the reply reaches stdout and
# nothing else does; a cut-off or failed reply prints NOTHING (so a caller can
# never write half a page) and exits non-zero; 429/5xx are retried once and 4xx
# is not; the key never appears in output.
#
# Targets bash 3.2 (macOS /bin/bash).

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/../bin"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-llm-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
SERVER_PID=""
cleanup_all() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
  rm -rf "$SANDBOX"
  return 0
}
trap cleanup_all EXIT

pass_msg() { echo "  PASS: $1"; }
fail_msg() { echo "  FAIL: $1"; fail=1; }

# --- stub gateway ---------------------------------------------------------------
# Each request pops the first line of $SANDBOX/queue ("<status> <json body>") and
# appends {"path","auth","body"} to $SANDBOX/requests.jsonl.
cat > "$SANDBOX/server.py" <<'PY'
import http.server, json, os, sys
sb = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode()
        with open(os.path.join(sb, "requests.jsonl"), "a") as f:
            f.write(json.dumps({"path": self.path, "auth": self.headers.get("Authorization"),
                                "body": json.loads(body)}) + "\n")
        q = os.path.join(sb, "queue")
        lines = open(q).read().splitlines()
        status, resp = lines[0].split(" ", 1)
        open(q, "w").write("\n".join(lines[1:]) + ("\n" if lines[1:] else ""))
        out = resp.encode()
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(sb, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$SANDBOX/server.py" "$SANDBOX" &
SERVER_PID=$!
i=0; while [ ! -s "$SANDBOX/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$SANDBOX/port" ] || { echo "FAIL: stub server did not start"; exit 1; }

export WIKI_LLM_BASE_URL="http://127.0.0.1:$(cat "$SANDBOX/port")/v1"
export WIKI_LLM_RETRY_WAIT=0
unset WIKI_LLM_API_KEY WIKI_LLM_EFFORT WIKI_LLM_MODEL WIKI_LLM_MAX_TOKENS 2>/dev/null
SECRET="sk-test-DO-NOT-PRINT-4f1c"
printf '{"gw": {"key": "%s"}}\n' "$SECRET" > "$SANDBOX/auth.json"
export WIKI_LLM_KEY_FILE="$SANDBOX/auth.json" WIKI_LLM_KEY_PATH="gw.key"
printf 'You are a test system prompt.\n' > "$SANDBOX/system.txt"

reply() {  # reply <finish_reason> <content> -> one queue body
  python3 -c 'import json,sys; print(json.dumps({"choices":[{"message":{"content":sys.argv[2]},"finish_reason":sys.argv[1]}],"usage":{"prompt_tokens":10,"completion_tokens":5}}))' "$1" "$2"
}
queue() { : > "$SANDBOX/queue"; for l in "$@"; do printf '%s\n' "$l" >> "$SANDBOX/queue"; done; : > "$SANDBOX/requests.jsonl"; }
nreq() { wc -l < "$SANDBOX/requests.jsonl" | tr -d ' '; }
run_llm() {  # run_llm <args...>; prompt on stdin from $PROMPT
  printf '%s' "$PROMPT" | "$BIN/wiki-llm" --system "$SANDBOX/system.txt" "$@" > "$SANDBOX/out" 2> "$SANDBOX/err"
  rc=$?
}

echo "Case 1: a good reply reaches stdout, and the request carries what it must"
queue "200 $(reply stop '# Page

The reply body.')"
PROMPT="the user prompt, with the whole context inlined"
run_llm --model test-model --effort high --max-tokens 1234
[ "$rc" -eq 0 ] && pass_msg "exit 0" || fail_msg "exit $rc: $(cat "$SANDBOX/err")"
if [ "$(cat "$SANDBOX/out")" = "# Page

The reply body." ]; then pass_msg "stdout is exactly the reply"; else fail_msg "stdout: $(cat "$SANDBOX/out")"; fi
python3 - "$SANDBOX/requests.jsonl" "$SECRET" <<'PY' && pass_msg "request: path, bearer key, model, effort, max_tokens, both prompts" || fail_msg "request body wrong"
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])]
assert len(r) == 1, r
r = r[0]; b = r["body"]
assert r["path"] == "/v1/chat/completions", r["path"]
assert r["auth"] == "Bearer " + sys.argv[2]
assert b["model"] == "test-model" and b["reasoning_effort"] == "high" and b["max_tokens"] == 1234, b
assert b["messages"][0] == {"role": "system", "content": "You are a test system prompt.\n"}, b["messages"][0]
assert b["messages"][1]["content"] == "the user prompt, with the whole context inlined", b["messages"][1]
PY
if grep -q "$SECRET" "$SANDBOX/out" "$SANDBOX/err"; then fail_msg "key printed"; else pass_msg "key not printed"; fi

echo "Case 2: env supplies model and effort; no effort means no reasoning_effort key"
queue "200 $(reply stop 'ok')"
WIKI_LLM_MODEL=env-model run_llm
[ "$rc" -eq 0 ] && pass_msg "exit 0" || fail_msg "exit $rc: $(cat "$SANDBOX/err")"
python3 -c 'import json,sys; b=json.loads(open(sys.argv[1]).readline())["body"]; assert b["model"]=="env-model" and "reasoning_effort" not in b and b["max_tokens"]==32000, b' "$SANDBOX/requests.jsonl" \
  && pass_msg "model from env, no reasoning_effort, default max_tokens 32000" || fail_msg "env defaults wrong"

echo "Case 3: a reply cut off at max_tokens prints nothing and exits 4"
queue "200 $(reply length '# Half a pa')"
run_llm --model m
[ "$rc" -eq 4 ] && pass_msg "exit 4" || fail_msg "exit $rc, want 4"
[ -s "$SANDBOX/out" ] && fail_msg "printed a truncated reply: $(cat "$SANDBOX/out")" || pass_msg "nothing on stdout"

echo "Case 4: 503 then 200 is retried once and succeeds"
queue '503 {"error":"overloaded"}' "200 $(reply stop 'second time lucky')"
run_llm --model m
[ "$rc" -eq 0 ] && [ "$(cat "$SANDBOX/out")" = "second time lucky" ] && pass_msg "retried to success" || fail_msg "rc=$rc out=$(cat "$SANDBOX/out")"
[ "$(nreq)" -eq 2 ] && pass_msg "exactly two requests" || fail_msg "$(nreq) requests"

echo "Case 5: 429 twice fails after one retry, printing nothing"
queue '429 {"error":"slow down"}' '429 {"error":"slow down"}' "200 $(reply stop 'never reached')"
run_llm --model m
[ "$rc" -eq 1 ] && pass_msg "exit 1" || fail_msg "exit $rc, want 1"
[ "$(nreq)" -eq 2 ] && pass_msg "two requests, not three" || fail_msg "$(nreq) requests"
[ -s "$SANDBOX/out" ] && fail_msg "printed something" || pass_msg "nothing on stdout"

echo "Case 6: a 400 is not retried"
queue '400 {"error":"context length exceeded"}' "200 $(reply stop 'never reached')"
run_llm --model m
[ "$rc" -eq 1 ] && [ "$(nreq)" -eq 1 ] && pass_msg "exit 1 after one request" || fail_msg "rc=$rc requests=$(nreq)"
grep -q "context length exceeded" "$SANDBOX/err" && pass_msg "the gateway's error is on stderr" || fail_msg "stderr: $(cat "$SANDBOX/err")"
if grep -q "$SECRET" "$SANDBOX/out" "$SANDBOX/err"; then fail_msg "key printed on error"; else pass_msg "key not printed on error"; fi

echo "Case 7: an empty reply is a failure"
queue "200 $(reply stop '   ')"
run_llm --model m
[ "$rc" -eq 1 ] && [ ! -s "$SANDBOX/out" ] && pass_msg "exit 1, nothing printed" || fail_msg "rc=$rc"

echo "Case 8: configuration errors exit 2 before any request"
queue "200 $(reply stop 'never reached')"
( unset WIKI_LLM_BASE_URL; printf 'p' | "$BIN/wiki-llm" --system "$SANDBOX/system.txt" --model m >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 2 ] && pass_msg "no base URL -> exit 2" || fail_msg "no base URL -> exit $rc"
( unset WIKI_LLM_KEY_FILE; printf 'p' | "$BIN/wiki-llm" --system "$SANDBOX/system.txt" --model m >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 2 ] && pass_msg "no key -> exit 2" || fail_msg "no key -> exit $rc"
( printf 'p' | "$BIN/wiki-llm" --system "$SANDBOX/system.txt" >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 2 ] && pass_msg "no model -> exit 2" || fail_msg "no model -> exit $rc"
[ "$(nreq)" -eq 0 ] && pass_msg "no request was made" || fail_msg "$(nreq) requests made"

echo
if [ "$fail" -eq 0 ]; then echo "test-llm: ALL PASS"; else echo "test-llm: FAILURES"; fi
exit "$fail"
