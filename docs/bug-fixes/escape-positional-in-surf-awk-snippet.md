---
id: ypjex7e2gedwvx040yf97pw1
title: Bare $2 in the surf awk snippet is replaced by the user's second URL argument
status: implementation
source: kata:dw2f
started: 2026-08-07T13:23:50Z
completed:
verdict:
score: 0.5
worktree: .worktrees/spacedock-ensign-escape-positional-in-surf-awk-snippet
issue:
pr:
mod-block:
gates:
    version: 1
    records:
        - id: gate:ypjex7e2gedwvx040yf97pw1:backlog
          stage: backlog
          attempts:
            - id: gate-attempt:ypjex7e2gedwvx040yf97pw1-backlog-1
              briefing:
                id: briefing:ypjex7e2gedwvx040yf97pw1:backlog:attempt-1:revision-1
                digest: sha256:722a3c30af687b70b6f64191575cbd2f20955d7a7688c97b0030c9435cfb6b53
                request-digest: sha256:1f56e391f7d382fe31b4d452a5eb67b2773684014ebebbfdbda05c16b21df46f
                room-ref: ./escape-positional-in-surf-awk-snippet/review/backlog/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:ypjex7e2gedwvx040yf97pw1:backlog:1
                briefing: briefing:ypjex7e2gedwvx040yf97pw1:backlog:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T13:21:48.240849Z"
                decision: approve
                reason: 2026-08-07 observation captures the exact corrupted awk expansion; defect is real and silently disables the surf fallback for multi-URL batches. Smallest diff, zero file overlap with the concurrent guard fix. Captain delegated gate decisions in-conversation.
              application:
                target-stage: ideation
                state: consumed
        - id: gate:ypjex7e2gedwvx040yf97pw1:ideation
          stage: ideation
          attempts:
            - id: gate-attempt:ypjex7e2gedwvx040yf97pw1-ideation-1
              briefing:
                id: briefing:ypjex7e2gedwvx040yf97pw1:ideation:attempt-1:revision-1
                digest: sha256:505f99e78a2654808f0d5216e9cb88b01b2d3fe8ec5ca095c2b125ee91a8a599
                request-digest: sha256:bc8c08007ba9a92989a1fb0ed216da4e0b84e48e2f869b0ed1e1215f33d8f964
                room-ref: ./escape-positional-in-surf-awk-snippet/review/ideation/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:ypjex7e2gedwvx040yf97pw1:ideation:1
                briefing: briefing:ypjex7e2gedwvx040yf97pw1:ideation:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T13:41:38.119555Z"
                decision: approve
                reason: 'Expander measured directly rather than assumed: 0-based indexing means the bug needs three or more URLs, correcting both the kata issue and the FO''s own earlier summary. $NF chosen over the escape with verified reasoning — a literal backslash-$2 read without expansion reproduces the identical empty-TAB_ID failure. NF=2 structural in surf''s YAML, confirmed end-to-end. Bail-out exit 1 approved in scope as the silence mechanism per the README''s fail-closed-and-loudly rule. AC-1 accepted as an offline manual command driving the real binary; offline harness correctly refused as a second implementation of the thing under test. AC-2''s inability to go red on the expansion defect disclosed rather than dressed up. Captain delegated gate decisions in-conversation.'
              application:
                target-stage: implementation
                state: consumed
---

## Problem

`commands/wiki-ingest.md` line 70 documents the surf tab-id extraction as:

    TAB_ID=$(surf tab new ... | grep "tabId:" | awk '{printf "%.0f\n", $2}')

Claude Code substitutes positional parameters when expanding the command body, so that bare `$2` is replaced with one of the URLs the user passed. Observed 2026-08-07 running `/wiki-ingest` with 26 URLs, the snippet arrived as:

    ... | awk '{printf "%.0f\n", https://keel-iot.eu/blog/state-oriented-consistency.html}'

which is not a valid awk program. An agent that pastes the documented snippet verbatim gets an empty `TAB_ID`, and the guidance immediately above it says to bail out of the surf fallback entirely when `TAB_ID` is empty — so the whole browser-fallback path dies for large batches. Single-URL invocations are unaffected, which is presumably why it went unnoticed.

The irony is that this line is itself the fix for an earlier bug — the comment above it warns not to sed-strip at the dot. The correct value never survives to the reader.

### Correction to the original report (established at ideation, 2026-08-08)

The original report says `$2` becomes the *second* URL and that the bug fires "for every batch of two or more URLs". Both are wrong, and the second one matters: **a two-URL reproduction passes cleanly and would have been read as "not reproducible".**

Measured directly against Claude Code's own expander (probe command, four distinct URL arguments, expansion read back out of the session transcript at
`~/.claude/projects/-private-tmp-…-scratchpad-probe/02d0faea-d2d9-4981-a845-e285e63a4000.jsonl`):

| written in the command body | expanded to | note |
|---|---|---|
| `$0` | `https://a.example/1` | argument **0-based** |
| `$1` | `https://b.example/2` | |
| `$2` | `https://c.example/3` | the defect |
| `$3` | `https://d.example/4` | |
| `$4`, `$9` | unchanged | index out of range → left literal |
| `\$0`, `\$1`, `\$2` | `$0`, `$1`, `$2` | backslash consumed, no substitution |
| `$NF` | `$NF` | unchanged |
| `$(NF)` | `$(NF)` | unchanged |
| `${2}` | `${2}` | unchanged (but `${…}` is not valid awk) |
| `$$2` | `$https://c.example/3` | **not** an escape |
| `$ARGUMENTS` | all four URLs | |

So: indices are **0-based**, `$2` is the **third** argument, and out-of-range indices survive untouched. The bug therefore requires **three or more URLs**, not two. The same substitution table holds when the command is reached through the `Skill` tool rather than as a slash command (session `080da444-dc2f-4f3c-94b8-b1e5715b0eff`), so both invocation paths are affected.

`commands/wiki-ingest.md` was re-grepped for every `$` (lines 18, 63, 70, 71, 80, 82, 84, 85, 86, 90, 98). Line 70's `$2` is the only digit-indexed form; the rest are `$WIKI_PATH`, `$GRAB_DIR`, `$TAB_ID`, `$n`, `$((n+1))` and `$(…)` command substitutions, none of which the expander touches. The report's claim that line 70 is the only site is confirmed.

## Reproduction

Deterministic, and it does not require the live wiki, the marketplace copy, or the Captain. It copies the repo's own `commands/wiki-ingest.md` — byte-identical, verified with `cmp` — into a throwaway project as a **uniquely named** command, expands it with three URLs, and reads the expansion back out of the session transcript that Claude Code writes.

```bash
SB=$(mktemp -d)
mkdir -p "$SB/.claude/commands"
cp commands/wiki-ingest.md "$SB/.claude/commands/wi-expansion-probe.md"
cmp "$SB/.claude/commands/wi-expansion-probe.md" commands/wiki-ingest.md || echo "COPY DRIFTED"
cd "$SB"
SID=$(claude -p "/wi-expansion-probe https://a.example/1 https://b.example/2 https://c.example/3" \
  --model claude-haiku-4-5-20251001 --max-turns 1 \
  --disallowedTools "Bash Write Edit Read WebFetch WebSearch Task Glob Grep" \
  --output-format json | python3 -c "import json,sys; print(json.load(sys.stdin)['session_id'])")
python3 - "$SID" <<'PY'
import json, sys, glob, os
p = glob.glob(os.path.expanduser("~/.claude/projects/*/%s.jsonl" % sys.argv[1]))[0]
for line in open(p):
    for b in (json.loads(line).get("message", {}).get("content") or []):
        if isinstance(b, dict) and b.get("type") == "text":
            for ln in b.get("text", "").split("\n"):
                if "TAB_ID=" in ln and "awk" in ln:
                    print(ln)
PY
```

Observed on the unfixed file (session `e83758e6-3874-4100-9818-18668b3eb988`), exactly one matching line:

    TAB_ID=$(surf tab new --args-json '{"url":"about:blank"}' 2>/dev/null | grep "tabId:" | awk '{printf "%.0f\n", https://c.example/3}')

Three details are load-bearing and were each learned the hard way:

- **Three URLs, not two.** With two, `$2` is out of range and survives; the repro goes green on an unfixed file.
- **The copy must be renamed.** A copy left at `wiki-ingest.md` collides with the installed `powerups-wiki-ingest` plugin, and the transcript then carries *two* expansions — the sandbox copy and the marketplace copy — so the check reads whichever it happens to hit. Observed in session `6b011bac-331f-40d5-99c4-0949a5b5774a`, which returned an intact line *and* a corrupted line. The command name comes from the filename, not the `name:` frontmatter, so renaming the file leaves the bytes untouched (`cmp` above proves it).
- **The sandbox copy, not the installed plugin.** The marketplace cache is a separate copy that lags the repo. It happens to be identical today (`diff` against `~/.claude/plugins/cache/powerups-marketplace/powerups-wiki-ingest/2.0.0/commands/wiki-ingest.md` is empty), but after the fix lands it will lag, and a repro run against it would report the bug still present.

That the corrupted line actually breaks — rather than merely looking wrong — is confirmed separately:

```
$ printf 'tabId: 3.59286798e+08\n' | awk '{printf "%.0f\n", https://c.example/3}'
awk: syntax error at source line 1
awk: illegal statement at source line 1
   → exit 2, no stdout, so TAB_ID=""
```

## Proposed approach

**Change one token on line 70: `$2` → `$NF`.**

```
-TAB_ID=$(surf tab new --args-json '{"url":"about:blank"}' 2>/dev/null | grep "tabId:" | awk '{printf "%.0f\n", $2}')
+TAB_ID=$(surf tab new --args-json '{"url":"about:blank"}' 2>/dev/null | grep "tabId:" | awk '{printf "%.0f\n", $NF}')
```

Why `$NF` and not the escape `\$2`, which is a smaller diff and preserves the exact field index:

- **`\$2` is only correct in front of one particular consumer.** It relies on Claude Code stripping the backslash. Wherever the file is read *without* that expansion — the `Read` tool during development, GitHub's markdown view, a future doc build, a person copying the block — the reader gets a literal `\$2`, and `awk '{printf "%.0f\n", \$2}'` is a syntax error that exits 2 with no stdout. That is the *same* empty-`TAB_ID` failure this fix exists to remove, reintroduced through a different door. Verified: the literal form errors with `syntax error … >>> \ <<< $2`.
- **`$NF` is correct on every path.** The expander leaves it untouched (measured above), and it is valid awk when read raw. There is no reading of the file that yields a broken program.
- **It is not a semantic gamble here.** `surf tab new` prints YAML. Captured live:

  ```
  success: true
  tabId: 3.5932251e+08
  url: about:blank
  ```

  `grep "tabId:"` isolates one line; awk reports `NF=2` on it, so `$NF` and `$2` name the same field. This is structural, not incidental — a YAML scalar float can never contain whitespace, so the `tabId:` line is two fields by construction. End-to-end: `grep "tabId:" | awk '{printf "%.0f\n", $NF}'` returned `359322510`, and `surf tab close --tab-id 359322510` answered `success: true` against that exact tab.

Runner-up, recorded so the gate can overrule: `awk -v k=2 '{printf "%.0f\n", $k}'` is also expansion-safe (`$k` is untouched — no digit after the `$`), is valid awk when read raw, and keeps field index 2 literally, so it would survive surf ever appending a field to the `tabId:` line. It was not chosen because it adds indirection to buy insurance against a drift that YAML's structure already rules out. Rejected outright: `${2}` survives expansion but is not awk syntax, and `$$2` is not an escape at all — it expands to `$https://c.example/3`.

### Second change: make the bail-out actually bail

Lines 71–74 are the reason this failed quietly rather than loudly:

```bash
if [ -z "$TAB_ID" ]; then
  echo "surf tab creation failed — Chrome running? extension loaded in the active profile?" >&2
  # bail out of the surf fallback entirely; do NOT fall back to grabbing an existing tab
fi
```

The comment says bail; the code does not. Pasted verbatim — which is how a fenced `bash` block gets used — execution falls through to `surf navigate --tab-id ""`. And the diagnostic names only Chrome and the extension, so the one agent who did hit this was sent hunting for a browser problem that did not exist. Proposed: an explicit `exit 1` inside the `if`, and a third clause in the message naming a malformed tab-id extraction.

This is the half that satisfies the workflow's bar — "a fix that detects the bad state and proceeds with a warning does not close its bug". It is nonetheless separable: **if the gate reads it as scope creep, drop it and AC-1/AC-2 still stand unchanged.**

### Recurrence, and what is deliberately left alone

Line 70 is the only `$N` in the file today (re-verified, table above), but any future shell example can reintroduce the trap. `CLAUDE.md` already carries the exactly analogous rule for `${CLAUDE_PLUGIN_ROOT}` under **Conventions** — "Scripts must NOT reference `${CLAUDE_PLUGIN_ROOT}`" — so that section is the established home for one more line: command-markdown bodies must not contain `$0`–`$9`, which Claude Code replaces with the user's arguments (0-based); use `$NF`, `$k` via `-v`, or a non-`$` form. No inline warning comment in the fenced block: it would be pasted into the shell along with the code, and the convention belongs where editors already look for this class of rule.

No AC is written for that line. Asserting that `CLAUDE.md` contains a sentence we just wrote is precisely the prose-grep the README bans; it is a documentation deliverable, not a verifiable property.

Left alone deliberately: the polling loop, the thinness heuristic, `surf navigate`, Phase 2, and every script in `bin/`. Nothing in `bin/` is touched by this fix.

## Acceptance criteria

All three are **offline** — a fresh agent reproduces each from a named command with no input from the Captain. No AC is interactive, and no AC is proved by a text match over `commands/wiki-ingest.md`.

One caveat, stated here rather than buried: AC-1 is offline but is **not** "no network, no LLM". It drives the real `claude` binary and costs one API call, so it cannot join `tests/test-fetch.sh` or `tests/test-guard.sh`, both of which the workflow requires to run offline and LLM-free. AC-1 is a re-runnable manual command recorded in this file, not committed CI. AC-2 and AC-3 are committed tests and do run with no network and no LLM.

**AC-1 — Expanding `commands/wiki-ingest.md` with three or more arguments yields a `TAB_ID=` line whose awk program is intact.**
Verified by: the **Reproduction** command above, run against the fixed file. Green means the single matched line ends `awk '{printf "%.0f\n", $NF}')` and contains no `http`. The evidence is Claude Code's own session transcript — a value produced by the expander, not by the file under test.
Falsified by: reverting line 70 to `$2`. The same command then prints the third URL inside the awk program — already observed on the unfixed file, session `e83758e6-3874-4100-9818-18668b3eb988`. Also falsified by dropping to two URLs, which is why the argument count is pinned at three.

**AC-2 — The documented tab-id pipeline, executed as written, extracts `359286798` from real `surf tab new` output.**
Verified by: a new case in `tests/test-fetch.sh` that extracts the `TAB_ID=` line from `commands/wiki-ingest.md`, runs it under `/bin/bash` with a stub `surf` on `PATH` replaying the captured fixture, and asserts the resulting `TAB_ID` equals `359286798`. The expected value comes from the fixture, not from the markdown, so this is an execution check rather than prose-grep.
Falsified by: changing `%.0f` back to a `sed` strip at the dot (yields `3`), or leaving a literal `\$2` in the file (awk exits 2, `TAB_ID` empty). Both were confirmed to fail this way at ideation.

**AC-3 — When `surf tab new` returns no `tabId:`, the documented guard block exits non-zero instead of falling through.**
Verified by: a second case in the same test, running the same extracted span under `/bin/bash` with a stub `surf` that emits output containing no `tabId:` line. Asserts exit status is non-zero and stderr is non-empty.
Falsified by: removing the `exit 1` from the guard. Today's file exits **0** with the warning on stderr — measured, not assumed:

```
$ PATH=<stub>:$PATH /bin/bash block.sh
surf tab creation failed — Chrome running? extension loaded in the active profile?   [stderr]
exit=0
```

The assertion is deliberately on the exit status and not on the wording of the message: checking that stderr contains a phrase we wrote ourselves would be the prose-grep the README bans. It is also deliberately not "and `surf navigate` is never called" — `surf navigate` sits outside the extracted span, so that assertion would pass vacuously.

## Test plan

`tests/test-fetch.sh` gains both cases. It is the fixture-based, no-network script, and these are fixture-based no-network checks; `tests/test-guard.sh` is about the completeness guard against a seeded throwaway wiki and is the wrong home. No new test file is warranted, and **no change is made to the `tests/test-guard.sh` seed.**

Fixture — captured live from `surf tab new --args-json '{"url":"about:blank"}'` on 2026-08-08, with the tab-id digits replaced by the canonical `3.59286798e+08` already used in the file's comment:

```
success: true
tabId: 3.59286798e+08
url: about:blank
```

The stub `surf` is a shell script on `PATH` that prints this fixture for `tab new` and exits 0. No real Chrome, no network.

Extraction is a fixed span, prototyped and confirmed working at ideation against the current file:

```bash
sed -n '/^TAB_ID=\$(surf tab new/,/^fi$/p' commands/wiki-ingest.md > block.sh
PATH="$STUBDIR:$PATH" /bin/bash block.sh
```

which yields the `TAB_ID=` assignment plus the guard `if … fi` and nothing else. Bash 3.2 clean — no `mapfile`, no associative arrays, no negative indexing. If a future edit breaks the anchors, `block.sh` comes out empty and both cases fail loudly rather than passing on nothing; implementation should assert the extracted file is non-empty so that failure is unmistakable.

Red run, watched before the fix: with line 70 still `$2`, the extracted block runs `awk '{printf "%.0f\n", $2}'` against the fixture and **passes** AC-2 — because the on-disk text is fine; it is the expansion that corrupts it. That is the honest shape of this bug and the reason AC-1 exists at all: **AC-2 cannot go red on the expansion defect, and must not be presented as if it could.** The red run that matters for AC-2 is the literal-`\$2` variant — exactly the failure the rejected escape would have introduced — and it does go red (`awk: syntax error`, empty `TAB_ID`).

AC-3's red run is unambiguous: against today's file the block exits 0 and logs a `navigate` call.

Negative case for AC-1: re-run the Reproduction against a copy with line 70 reverted, and confirm the URL reappears inside the awk program. Implementation records both transcript session IDs.

Both test scripts run at validation, not only the one this fix touches.

## Out of scope

The surf fallback's own behaviour once `TAB_ID` is correct. This fix restores the documented snippet to working order; it does not audit the rest of the fallback path.

Not attempted: any standing/CI check on the expansion. AC-1 needs a live `claude` invocation, so committing it as a test would put a network- and LLM-dependent case into a suite the workflow requires to run without either. It stays a recorded manual command.

Also not attempted: a harness that reimplements Claude Code's `$N` substitution so AC-1 could run offline and free. Such a harness would be a second implementation of the thing under test and would go green whether or not the real expander behaves — the reason AC-1 drives the real binary instead.

## Stage Report: ideation

- DONE: A reproduction that actually fails, named as the exact command or scenario a fresh agent can re-run — not a description of one.
  `## Reproduction` carries the runnable block; run on the unfixed file it returned `awk '{printf "%.0f\n", https://c.example/3}'` (session `e83758e6-3874-4100-9818-18668b3eb988`).
- DONE: The expansion acceptance criterion explicitly declared offline or interactive, with no harness proposed to fake an interactive one.
  AC-1 declared **offline**; it drives the real `claude` binary, and `## Out of scope` records the refusal to reimplement the expander to make it free.
- DONE: Each acceptance criterion's evidence external to `commands/wiki-ingest.md`, naming the concrete edit that would make it fail.
  AC-1 evidence is Claude Code's session transcript; AC-2/AC-3 are execution against a captured `surf` fixture. Each carries a measured `Falsified by:`.

### Summary

The report's mechanism was wrong in a way that would have sunk the repro: substitution is **0-based**, so `$2` is the *third* argument and the bug needs **three or more** URLs — a two-URL repro passes on the unfixed file. Measured against the real expander, along with a full substitution table; the `Skill`-tool path behaves identically. Chose `$2` → `$NF` over the smaller `\$2` escape, because a literal `\$2` read without expansion is an awk syntax error producing the identical empty-`TAB_ID` failure this fix exists to remove, whereas `$NF` is correct on every reading path; `surf tab new`'s YAML makes `NF=2` structural on the `tabId:` line, confirmed against live output and an end-to-end `surf tab close`.

Two things the gate should look at rather than take on trust. First, a second change is proposed beyond the one-token fix: the bail-out guard currently warns and exits **0** (measured), so the fallback proceeds with an empty `TAB_ID` — it is flagged as separable and droppable if the gate reads it as scope creep. Second, AC-2 passes on the *unfixed* file and can never go red on the expansion defect, because the on-disk text was always fine; that is stated plainly in the test plan rather than dressed up as coverage. Only AC-1 bears on the actual bug, and it costs an API call, so it cannot join the two no-network test scripts.

## Stage Report: implementation

- DONE: The AC-1 reproduction run against the FIXED file with three URLs, its transcript session id recorded, and the negative re-run against a reverted copy showing the URL reappear inside the awk program.
  Fixed file, session `24c53798-c5e6-42ab-b34f-3f5cb3c15415` — exactly one matching line, `… | awk '{printf "%.0f\n", $NF}')`, no `http` anywhere in it. Reverted copy, session `c5a8503b-c735-430e-b0ef-9dd47f75a042` — `… | awk '{printf "%.0f\n", https://c.example/3}')`, the third URL, as predicted. The reverted copy is a one-token revert: `diff` against the fixed file reports line 70 only, `$NF` → `$2`. Probe copied as `wi-expansion-probe.md` and `cmp`-verified byte-identical each run.
- DONE: Both new tests/test-fetch.sh cases watched failing for the right reason before the fix, with the actual red output recorded — including the literal backslash-$2 variant that is AC-2's only real red.
  AC-3 went red on the genuinely unfixed file: `FAIL: guard block exited 0 with no tabId in surf output — it must bail, not fall through`. **AC-2 passed on the unfixed file**, exactly as the test plan states it must: the on-disk text was always well-formed, so AC-2 cannot go red on the expansion defect and is not coverage of it. Its real red is the literal `\$2` variant — `FAIL: documented tab-id pipeline yielded 'TAB_ID=', want 'TAB_ID=359286798'`, awk exiting 2 with `syntax error … >>> \ <<< $2`. The `sed`-strip variant is red too: `yielded 'TAB_ID=tabId: 3'`. Only AC-1 bears on the actual bug.
- DONE: tests/test-fetch.sh and tests/test-guard.sh both pass under /bin/bash 3.2, with the tests/test-guard.sh seed untouched.
  `/bin/bash` is 3.2.57(1)-release. After the fix: `test-fetch: ALL PASS` (rc=0) and `test-guard: ALL PASS` (all 10 cases). `git diff tests/test-guard.sh` is empty — the seed at lines 86–95 was never touched. The non-empty assertion on the extracted block was exercised rather than assumed: renaming the `TAB_ID=` anchor in a scratch copy yields `FAIL: tab-id block extracted empty — the sed anchors no longer match commands/wiki-ingest.md` as the first line of output.

### Summary

Commit `ef9fb96` carries the three approved changes and nothing else: `$2` → `$NF` on line 70, an explicit `exit 1` plus a third diagnostic clause ("tab id parsed out of the 'tabId:' line?") in the guard, and a Conventions line in `CLAUDE.md` recording the `$0`–`$9` trap. Nothing in `bin/` was touched, and no acceptance criterion is a text match over `commands/wiki-ingest.md` — AC-2 and AC-3 extract the documented block with `sed` and execute it against a stub `surf`, and AC-1's evidence is Claude Code's own session transcript.

One measured divergence from ideation, immaterial to the fix: the `sed`-strip falsifier for AC-2 yields `TAB_ID=tabId: 3`, not `3` as the ideation note predicted — replacing the awk call also removes the field splitting, so the `tabId: ` prefix survives. The test still goes red for the stated reason. Nothing in the approved design turned out to be wrong.
