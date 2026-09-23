#!/bin/bash
# Test of bin/wiki-agent, the one place that knows the nested CLI's dialects.
#
# WIKI_INGEST_CLI is pointed at a stub that records its argv (one per line),
# its stdin and its cwd, and exits with a code the case chooses. The pi-dialect
# stub is literally named `pi`, in its own directory, because the dialect is
# picked by the basename of WIKI_INGEST_CLI. What is asserted is the exact argv
# each dialect gets, that the prompt reaches the CLI on stdin, that it runs in
# the caller's cwd, and that the CLI's exit code comes back.
#
# The real CLIs are exercised by live runs (see kata issue 5gaq), not
# here: this suite must run offline.
#
# Targets bash 3.2 (macOS /bin/bash).

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="$DIR/../bin/wiki-agent"
fail=0

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-agent-test.XXXXXX") && SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT

ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1"; fail=1; }

mkdir -p "$SANDBOX/claude-bin" "$SANDBOX/pi-bin" "$SANDBOX/wiki" "$SANDBOX/bare" "$SANDBOX/cwd"
cat > "$SANDBOX/claude-bin/claude" <<'STUB_EOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_DIR/argv"
cat > "$STUB_DIR/stdin"
pwd -P > "$STUB_DIR/cwd.rec"
exit "${STUB_RC:-0}"
STUB_EOF
cp "$SANDBOX/claude-bin/claude" "$SANDBOX/pi-bin/pi"
chmod +x "$SANDBOX/claude-bin/claude" "$SANDBOX/pi-bin/pi"
echo "# wiki schema" > "$SANDBOX/wiki/CLAUDE.md"
export STUB_DIR="$SANDBOX"

# expect NAME EXPECTED-ARGV — compare the recorded argv with one arg per line.
expect() {
  if [ "$(cat "$SANDBOX/argv")" = "$2" ]; then ok "$1"
  else bad "$1"; echo "    expected:"; printf '%s\n' "$2" | sed 's/^/      /'
       echo "    got:"; sed 's/^/      /' "$SANDBOX/argv"; fi
}
nl='
'
run() { (cd "$SANDBOX/cwd" && printf 'the prompt\n' | "$AGENT" "$@"); }

# --- claude dialect ---------------------------------------------------------------
echo "claude dialect"
unset WIKI_INGEST_CLI
PATH="$SANDBOX/claude-bin:$PATH" run --tools Read,Write --context "$SANDBOX/wiki"
expect "default CLI is claude; --context becomes --add-dir" \
  "-p${nl}--no-session-persistence${nl}--allowedTools${nl}Read,Write${nl}--add-dir${nl}$SANDBOX/wiki"
[ "$(cat "$SANDBOX/stdin")" = "the prompt" ] && ok "prompt arrives on stdin" || bad "prompt did not arrive on stdin"
[ "$(cat "$SANDBOX/cwd.rec")" = "$SANDBOX/cwd" ] && ok "runs in the caller's cwd" || bad "ran in $(cat "$SANDBOX/cwd.rec")"

# Any non-pi basename is the claude dialect: this is what the test stubs rely on.
cp "$SANDBOX/claude-bin/claude" "$SANDBOX/stub-cli"
WIKI_INGEST_CLI="$SANDBOX/stub-cli" run --tools Read
expect "a non-pi CLI gets the claude dialect; no --context, no --add-dir" \
  "-p${nl}--no-session-persistence${nl}--allowedTools${nl}Read"

# --- pi dialect -------------------------------------------------------------------
echo "pi dialect"
export WIKI_INGEST_CLI="$SANDBOX/pi-bin/pi"
unset WIKI_INGEST_PI_MODEL WIKI_INGEST_PI_THINKING
run --tools Read,Write,Edit,Bash --context "$SANDBOX/wiki"
expect "pi: lower-cased tools, thinking low, schema appended, no model" \
  "-p${nl}--no-session${nl}--tools${nl}read,write,edit,bash${nl}--thinking${nl}low${nl}--no-context-files${nl}--no-skills${nl}--no-prompt-templates${nl}--append-system-prompt${nl}$SANDBOX/wiki/CLAUDE.md"
[ "$(cat "$SANDBOX/stdin")" = "the prompt" ] && ok "pi: prompt arrives on stdin" || bad "pi: prompt did not arrive on stdin"

WIKI_INGEST_PI_MODEL=lunaroute/glm-5.3-flash-background WIKI_INGEST_PI_THINKING=medium \
  run --tools Read --context "$SANDBOX/bare"
expect "pi: model and thinking from env; --context without CLAUDE.md appends nothing" \
  "-p${nl}--no-session${nl}--tools${nl}read${nl}--thinking${nl}medium${nl}--model${nl}lunaroute/glm-5.3-flash-background${nl}--no-context-files${nl}--no-skills${nl}--no-prompt-templates"

PATH="$SANDBOX/pi-bin:$PATH" WIKI_INGEST_CLI=pi run --tools Read
expect "pi: a bare 'pi' on PATH is detected too" \
  "-p${nl}--no-session${nl}--tools${nl}read${nl}--thinking${nl}low${nl}--no-context-files${nl}--no-skills${nl}--no-prompt-templates"

# --- exit codes and usage ----------------------------------------------------------
echo "exit codes"
STUB_RC=7 run --tools Read; rc=$?
[ "$rc" -eq 7 ] && ok "the CLI's exit code comes back" || bad "exit $rc, expected 7"
run >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "missing --tools is a usage error (64)" || bad "missing --tools exit $rc"
run --tools Read --bogus >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "unknown argument is a usage error (64)" || bad "unknown argument exit $rc"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
