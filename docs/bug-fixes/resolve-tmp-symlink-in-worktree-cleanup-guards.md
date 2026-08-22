---
id: 6a5wjaf19gdem9ca30m9b0cc
title: Worktree-cleanup self-exclusion guard never fires on macOS (/tmp and $TMPDIR are symlinks)
status: validation
source: kata:1dvt
started: 2026-08-22T13:48:45Z
completed:
verdict:
score: 0.4
worktree: .worktrees/spacedock-ensign-resolve-tmp-symlink-in-worktree-cleanup-guards
issue:
pr:
mod-block:
gates:
    version: 1
    records:
        - id: gate:6a5wjaf19gdem9ca30m9b0cc:backlog
          stage: backlog
          attempts:
            - id: gate-attempt:6a5wjaf19gdem9ca30m9b0cc-backlog-1
              briefing:
                id: briefing:6a5wjaf19gdem9ca30m9b0cc:backlog:attempt-1:revision-1
                digest: sha256:fbd69c4da99dbe7fc2cedb3ec2ec90524463884b6a02f71ecaa5c7acbc21b38d
                request-digest: sha256:a79e47f43da6ef1ac608e454a865245daf69801f3597fba7ffd94181e5503890
                room-ref: ./resolve-tmp-symlink-in-worktree-cleanup-guards/review/backlog/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:6a5wjaf19gdem9ca30m9b0cc:backlog:1
                briefing: briefing:6a5wjaf19gdem9ca30m9b0cc:backlog:attempt-1:revision-1
                by: person:captain
                at: "2026-08-22T13:48:18.057597Z"
                decision: approve
                reason: 'Captain approved in chat. Defect measured rather than asserted (path mismatch reproduced directly; repro exit 128 reproduced against an unmodified copy from HEAD). Meets both backlog outputs: damage-based Problem section, and kata:1dvt now in source. Three ACs carry Verified-by clauses and named falsifying edits. Ideation is asked to decide whether AC-1''s call-tracing harness is proportionate, and to correct the stale _archive path at line 39.'
              application:
                target-stage: ideation
                state: consumed
        - id: gate:6a5wjaf19gdem9ca30m9b0cc:ideation
          stage: ideation
          attempts:
            - id: gate-attempt:6a5wjaf19gdem9ca30m9b0cc-ideation-1
              briefing:
                id: briefing:6a5wjaf19gdem9ca30m9b0cc:ideation:attempt-1:revision-1
                digest: sha256:0e7c02db3cbaf9baf59492e1f6c63e66b9be3f5c35bc8f84a8b635135ce97cd7
                request-digest: sha256:d1eb8c6ba45114f959f8464b137606633b65703b031e4fca6199e9cf2797e70e
                room-ref: ./resolve-tmp-symlink-in-worktree-cleanup-guards/review/ideation/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:6a5wjaf19gdem9ca30m9b0cc:ideation:1
                briefing: briefing:6a5wjaf19gdem9ca30m9b0cc:ideation:attempt-1:revision-1
                by: person:captain
                at: "2026-08-22T14:34:04.457561Z"
                decision: approve
                reason: 'Captain approved in chat, having been shown the AC-1 external-command trade explicitly. Proportionality risk resolved by measurement rather than argument: bash -x already traces the trap''s removal calls, so AC-1 stands unnarrowed with zero new code, no test-file changes and no new mode in load-bearing cleanup paths. Red run watched on all three ACs against HEAD, green numbers taken from throwaway copies. FO independently confirmed the blast radius (grep -rn ''worktree list'' bin/ returns nothing) and that test-compile.sh is the load-bearing AC-1 site. Accepted cost: AC-1 runs as an external command, not an in-suite case, so it does not fire on a normal suite run.'
              application:
                target-stage: implementation
                state: consumed
        - id: gate:6a5wjaf19gdem9ca30m9b0cc:validation
          stage: validation
          attempts:
            - id: gate-attempt:6a5wjaf19gdem9ca30m9b0cc-validation-1
              briefing:
                id: briefing:6a5wjaf19gdem9ca30m9b0cc:validation:attempt-1:revision-1
                digest: sha256:5df585d6d14fe2ad14effbd088ddaa6694a065be33dd5f3d74d246159ec84654
                request-digest: sha256:0e1595428d88a9a20b35b25ea8304daa52d821b3c5114d93f684ed479ea0665e
                room-ref: ./resolve-tmp-symlink-in-worktree-cleanup-guards/review/validation/briefing-1
---

## Problem

Three scripts reap stray worktrees before deleting a sandbox wiki, and each
skips the sandbox's own main worktree with the same line:

    [ "$w" = "$WIKI_PATH" ] && continue

The comparison never matches on macOS. `git worktree list --porcelain` reports
the **resolved** path, while `$WIKI_PATH` holds the **unresolved** one, because
`/tmp` is a symlink to `/private/tmp` and `$TMPDIR` sits under `/var`, itself a
symlink to `/private/var`. Measured directly:

    mktemp gave:  /var/folders/rr/.../T//rhyme-check.nfazDq
    git reports:  /private/var/folders/rr/.../T/rhyme-check.nfazDq/wiki
    MISMATCH — guard silently never fires

Two faults compound: the symlink, and a double slash from `$TMPDIR`'s trailing
slash.

Affected call sites — the guard line, and the sandbox-creation line the fix
actually lands on:

| Guard | Creation line the fix touches |
|---|---|
| `tests/test-guard.sh:28` | `tests/test-guard.sh:19` |
| `tests/test-compile.sh:59` | `tests/test-compile.sh:38` |
| `docs/bug-fixes/_archive/serialise-topic-page-merges/repro/repro-topic-conflict.sh:21` | same file:15 |

(The repro moved under `_archive/` when the superseded fix was archived, after
this fix was filed. The two suite line numbers had also drifted; all five are
re-checked against HEAD as of this stage.)

No production script is affected. `bin/wiki-compile:82`, `bin/wiki-recompile:92`
and `bin/wiki-ingest-run:307,309` all remove a worktree **by the path they
created**, never by a path read back from `git worktree list`, so there is no
comparison to get wrong. The defect is confined to the three sites above.

**Damage.** In the two test suites the failure is currently invisible: the loop
calls `git worktree remove --force` on the sandbox's own main worktree, git
refuses, and `|| true` swallows it; `rm -rf "$SANDBOX"` then cleans up anyway.
So the guard is dead code that has never protected anything — it is fail-safe
only because git happens to refuse. Removing the `|| true`, or reaching a case
with a genuine sibling worktree that must be kept, turns it into a real fault.

In the repro script the same defect is already visible, and it is worse than
filed. The script has no `|| true`, so the failed removal aborts the `EXIT` trap
under `set -e` before `rm -rf "$WIKI"` runs. Two consequences, both measured:
the script exits **128** where its own documentation claims 0, **and it leaks
its sandbox** — a `/tmp/wiki-repro-*` directory survives every run. Anyone
wiring that repro into CI sees a false failure and a growing pile of temp dirs.

**Why now.** It is three instances of one mistake, the fix is one line per site,
and the currently-benign cases are benign by accident rather than by design.

## Reproduction

This bug's end state is identical whether or not the guard fires, so a repro
that inspects what is left on disk proves nothing. Both commands below observe
the **attempted removals** instead. Run from the repo root.

**1. The loop attempts to remove the sandbox's own main worktree.** `bash -x`
traces the `git` invocation the `EXIT` trap makes, so no harness is needed:

    bash -x tests/test-compile.sh 2>&1 | grep -- 'worktree remove --force'

Today, two attempts — the suite's legitimate sibling, and the main worktree
(one xtrace line each; wrapped here for width, and middles elided):

    + git -C .../wiki-compile-test.JizO1h/wiki worktree remove --force
        /var/folders/.../T//wiki-compile-test.JizO1h/holder-worktree
    + git -C .../wiki-compile-test.JizO1h/wiki worktree remove --force
        /private/var/folders/.../T/wiki-compile-test.JizO1h/wiki   <-- main

The second line is the bug: the repo root passed to itself as a worktree to
remove. Both faults are visible in it — the `-C` path carries `T//` and an
unresolved `/var`, while the path git handed the loop is `/private/var`. The same command over `tests/test-guard.sh` prints exactly one line,
which is the main worktree (that suite has no sibling at cleanup time).

**2. The repro script's exit code and its leaked sandbox.**

    bash docs/bug-fixes/_archive/serialise-topic-page-merges/repro/repro-topic-conflict.sh
    echo "exit=$?"; ls -d /tmp/wiki-repro-* 2>/dev/null | wc -l

Today: prints `REPRODUCED: ingest B failed to merge (exit 1)`, then `exit=128`
and a leak count of `1`. Documented as exiting 0 and cleaning up.

## Proposed approach

Resolve the sandbox path once, at creation, so both sides of the comparison are
in the same form:

    -  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/wiki-guard-test.XXXXXX")
    +  SANDBOX=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wiki-guard-test.XXXXXX")" && pwd -P)

`pwd -P` collapses the symlink and the double slash together — verified: the
`$TMPDIR` form becomes `/private/var/folders/.../T/...` with no `//`, matching
what `git worktree list --porcelain` reports byte for byte.

The same wrapper goes on the other two creation lines:
`tests/test-compile.sh:38` (`wiki-compile-test`) and the repro's `:15`, which
uses the variable `WIKI` and a hardcoded `/tmp` rather than `${TMPDIR:-/tmp}`.

Do not resolve at comparison time in the loop — one canonical value at creation
is the narrower change and cannot drift between uses.

**What this deliberately leaves alone.** The `|| true` in the test suites stays
(how loudly cleanup should fail is a separate decision). The cleanup loops
themselves are not restructured — no extracted helper, no shared test library,
no injectable remover. Nothing in `bin/` is touched: production code has no such
comparison, as shown above. Three creation lines change; nothing else.

## Design decision: AC-1's call-tracing harness

The backlog gate asked whether AC-1's harness is proportionate to a
one-line-per-site fix, or whether the honest answer is a narrower AC plus a
recorded limitation. **Neither: no harness is needed, and AC-1 need not be
narrowed.** `bash -x` is already a call tracer. The trap's `git worktree remove`
invocation appears in xtrace output, so "which paths does the loop attempt to
remove" is a `grep` over a traced suite run.

Measured both directions on `tests/test-compile.sh`, which is the useful site
because it stands up a genuine sibling worktree (`holder-worktree`) alongside
the main one:

| | attempted removals |
|---|---|
| today | `holder-worktree` **and** the main worktree |
| with `pwd -P` | `holder-worktree` only |

That is AC-1's original wording satisfied exactly — the sibling is still
removed, the main worktree is never passed to `worktree remove` — with zero new
code. `tests/test-guard.sh` goes from one attempt (the main worktree) to zero,
and both suites stay green.

The one concession: AC-1 is verified by an external command rather than by a
numbered case inside the suite, because a suite cannot xtrace itself. The stage
permits either; a command a fresh agent re-runs is still offline evidence.

**Considered and rejected.** The in-suite version would mean extracting each
trap's loop into a callable function and giving it a trace or dry-run mode so a
case could invoke it without destroying the sandbox mid-run — roughly twenty
lines per suite. That adds a mode in which cleanup deliberately does not clean
up, to the code whose entire job is to leave no worktrees behind, in exchange
for information xtrace already yields for free. Bad trade, and it is the
"rewrite where a guard would do" this stage is meant to catch.

## Acceptance criteria

Every AC below is **offline**: a command a fresh agent re-runs unattended, with
no network, no real LLM, and no Captain in the loop. None is interactive.



**AC-1 — The cleanup loop never attempts to remove the sandbox's own main
worktree, and still removes genuine siblings.** (offline)
The guard's `continue` is reached, rather than being reached-never and covered
by git's refusal. Asserted on the attempted-call list, not the end state — the
end state is identical either way today, which is exactly why this bug survived.
Verified by, from the repo root:

    bash -x tests/test-compile.sh 2>&1 | grep -c -- 'worktree remove --force'   # want 1
    bash -x tests/test-guard.sh   2>&1 | grep -c -- 'worktree remove --force'   # want 0

and the one surviving `test-compile.sh` attempt must name `holder-worktree`, not
the sandbox's `$WIKI_PATH`. Today the counts are 2 and 1, the extra attempt in
each being the main worktree.
*Concrete failing edit:* revert the `pwd -P` at either creation line; that
suite's count goes back up by one and the main worktree reappears in the trace.

**AC-2 — The repro exits 0 and leaves nothing behind, as its own documentation
claims.** (offline)
`docs/bug-fixes/_archive/serialise-topic-page-merges/repro/repro-topic-conflict.sh`
prints `REPRODUCED: ingest B failed to merge (exit 1)`, exits 0, and leaves no
`/tmp/wiki-repro-*` directory. The leak matters as much as the exit code: it is
the end-state consequence of the failed removal aborting the trap before
`rm -rf "$WIKI"`, and it is the one place in this fix where the guard's
behaviour shows up in the end state at all.
Verified by: running it from the repo root with no `BIN` set, then
`echo "exit=$?"` and `ls -d /tmp/wiki-repro-* 2>/dev/null | wc -l` — want
`exit=0` and `0`. Today: `exit=128` and `1`.
*Concrete failing edit:* revert the `pwd -P`; exit returns to 128 and the leak
count to 1.

**AC-3 — Both suites still pass, and leave nothing behind.** (offline)
`tests/test-guard.sh` and `tests/test-compile.sh` end green, and no
`wiki-*-test.*` directory survives under `$TMPDIR`.
Verified by: running both suites and listing `$TMPDIR` afterwards.
*Concrete failing edit:* break the `SANDBOX` assignment so it is empty; `rm -rf`
cleans the wrong path and the leftover check goes red.

## Test plan

**No test file changes, and no new test file.** This is the substantive outcome
of the AC-1 decision above: every AC is verified by running code that already
exists in the repo, under `bash -x` where a call trace is needed. Neither
`tests/test-guard.sh` nor `tests/test-compile.sh` gains a case, and no
`tests/lib` is created.

The red run has already been watched, at ideation, on all three ACs — the
numbers in each AC are measurements taken today against HEAD, and the green
numbers were taken by applying `pwd -P` to a throwaway copy of each script and
re-running. Implementation therefore inherits a genuine before/after, which is
what this bug needed: a case written after the fix would have passed for the
wrong reason.

Note for whoever implements: `test-compile.sh` is the load-bearing AC-1 site,
not `test-guard.sh`. Only `test-compile.sh` stands up a real sibling worktree,
so only it can distinguish "the guard fires" from "the loop removes nothing at
all". A fix that accidentally made the loop skip everything would still show
`0` on `test-guard.sh`.

`WIKI_PATH` must never point at the real wiki in any of these runs; all three
scripts build their own throwaway sandbox and must keep doing so.

## Out of scope

- Whether cleanup should fail loudly (the `|| true`) — separate decision.
- The superseded bounded-union design itself; this only touches its repro's
  path handling.
- The repro's hardcoded `/tmp` (the suites use `${TMPDIR:-/tmp}`). Leave it;
  `pwd -P` resolves either, and changing it is unrelated churn.
- Any non-macOS behaviour. On Linux the comparison already matches; the fix
  must not regress that, but no new Linux-specific coverage is required.
- Anything in `bin/`. Verified to have no equivalent comparison.

## Stage Report: ideation

- DONE: A reproduction that ACTUALLY FAILS, named as an exact runnable command in the fix body — and note the trap: this bug's end state is identical whether the guard works or not, so a repro that only checks the end state proves nothing. It must observe which paths the cleanup loop attempts to remove.
  New `## Reproduction` section. `bash -x tests/test-compile.sh 2>&1 | grep -- 'worktree remove --force'` prints the attempted-removal list directly: today the main worktree appears alongside the legitimate sibling; with `pwd -P` only the sibling does. Measured both directions.
- DONE: Decide explicitly whether AC-1's call-tracing harness is proportionate to a one-line-per-site fix, or whether the honest answer is a narrower AC plus a recorded limitation. Say which, and why, in the fix body.
  New `## Design decision` section: neither — `bash -x` is already the tracer, so AC-1 stands unnarrowed with zero new code. The ~20-line-per-suite in-suite harness is recorded as considered and rejected, with the reason.
- DONE: Declare each AC offline (a test or command a fresh agent re-runs) or interactive (needs the Captain or a live drive).
  All three declared offline, in a preamble to `## Acceptance criteria` and inline on each AC. None interactive.
- DONE: Correct the stale `_archive` path (backlog gate ask 2).
  Now `docs/bug-fixes/_archive/serialise-topic-page-merges/repro/repro-topic-conflict.sh:21`. The two suite line numbers had drifted too (guard 25→28, compile 56→59); all five re-checked against HEAD.

### Summary

The gate's proportionality question dissolved on measurement: `bash -x` traces
the trap's `git worktree remove` calls, so AC-1's "assert on the attempted-call
list, not the end state" is satisfiable by `grep` with no harness, no test-file
changes, and no new code in load-bearing cleanup paths. `tests/test-compile.sh`
is the site that matters, being the only one with a genuine sibling worktree:
today it attempts to remove `holder-worktree` **and** the main worktree; with
`pwd -P` at creation, only `holder-worktree`. Both suites stay green.

Two findings beyond the brief. The repro does not merely exit 128 — it also
leaks its `/tmp/wiki-repro-*` sandbox, because the failed removal aborts the
`EXIT` trap before `rm -rf` runs; AC-2 now asserts both, and the leak is the one
place the guard's behaviour reaches the end state. And no production script is
affected: `bin/wiki-compile:82`, `bin/wiki-recompile:92` and
`bin/wiki-ingest-run:307,309` remove worktrees by the path they created, never
by one read back from `git worktree list`, so the defect is confined to the
three cited sites. Implementation is three creation lines and no test edits.

## Stage Report: implementation

- DONE: The three creation lines changed to resolve through `pwd -P`, and AC-1's before/after re-established as your own measurement — not inherited from the ideation report. Watch each number move: test-compile 2 to 1, test-guard 1 to 0, and confirm the surviving test-compile attempt names holder-worktree and not the sandbox's own root.
  Commit d0e3ea0. Re-measured here, not inherited: `bash -x tests/test-compile.sh 2>&1 | grep -c -- 'worktree remove --force'` gave **2** at HEAD and **1** after; test-guard.sh gave **1** and **0**. The surviving compile attempt is `.../wiki-compile-test.fQrLgJ/holder-worktree` — the genuine sibling, not `$WIKI_PATH`. The red trace showed both faults in one line: `-C` path `/var/...T//`, target path `/private/var/...`. Reverting either `pwd -P` restores that suite's count and puts the main worktree back in the trace.
- DONE: AC-2 proven in both halves: the repro exits 0 AND leaves no /tmp/wiki-repro-* behind. Today it is exit 128 with one leaked directory; the leak is the only place this guard's behaviour reaches the end state, so do not let it pass on the exit code alone.
  Both halves measured. Red: `exit=128`, leak count `1` (`/tmp/wiki-repro-2HMIBS` survived and was removed by hand). Green: `exit=0`, leak count `0`. Both runs still print `REPRODUCED: ingest B failed to merge (exit 1)`, so the repro still reproduces — only its own cleanup changed. Reverting the `pwd -P` returns exit to 128 and the leak to 1.
- DONE: All four suites green — test-fetch, test-guard, test-curate, test-compile — with nothing left under $TMPDIR afterwards.
  All four exit 0 and print `ALL PASS` against the committed code; `ls -d "$TMPDIR"/wiki-*-test.*` afterwards matches nothing. Each suite's own cases are what would fail if the `SANDBOX` assignment broke: an empty `SANDBOX` puts `WIKI_PATH` at `/wiki`, and every case that writes to the sandbox wiki goes red.

### Deviation from the approved one-liner — for the gate to rule on

The Captain approved a specific literal form at the ideation gate:

    SANDBOX=$(cd "$(mktemp -d ...)" && pwd -P)

I shipped this instead — same three sites, one line each, same resolution
semantics, no new files and no new test cases:

    SANDBOX=$(mktemp -d ...) && SANDBOX=$(cd "$SANDBOX" && pwd -P)

**The hazard.** On `/bin/bash` 3.2.57(1)-release, **`cd ""` succeeds and leaves
you in the current directory.** So under the literal form a failed `mktemp -d`
(full disk, unwritable `$TMPDIR`) sets `SANDBOX` to the caller's cwd, and the
EXIT trap's `rm -rf "$SANDBOX"` then deletes the checkout the suite was run
from. Pre-fix, that same mktemp failure was harmless: `SANDBOX=""` and
`rm -rf ""` is a no-op.

Measured, all three forms, run from this worktree with `mktemp -d` pointed at a
nonexistent parent so it genuinely fails:

| form | statement rc | resulting `SANDBOX` |
|---|---|---|
| pre-fix | 1 | `` (empty) |
| approved literal | **0** | **the repo worktree path** |
| shipped chained | 1 | `` (empty) |

The literal form does not even report the failure — rc 0. Separately confirmed
that `rm -rf ""` is inert: rc 0, canary file and cwd both still present.

**Is the failure path identical to pre-fix? In both halves on that path, yes —
but there is one residual difference, named rather than rounded away.**

- Path A, `mktemp -d` fails (the path that matters, and the only failure path
  pre-fix had): identical in both halves. `SANDBOX` empty, statement rc 1,
  trap's `rm -rf ""` a no-op, `WIKI_PATH` becomes `/wiki` and the suite goes
  loudly red. Same as today.
- Path B, `mktemp` **succeeds** but the following `cd` is refused: this path
  does not exist pre-fix, because pre-fix never runs `cd`. Measured with an
  unsearchable parent: `SANDBOX` ends empty, rc 1, and the real temp directory
  **leaks** (`before=0 after=1`) because `rm -rf ""` cannot reach it. So on this
  one path the chained form is very slightly worse than pre-fix — a leaked
  empty directory — while still failing closed and still never deleting
  anything it should not.

Path B needs `mktemp` to create a fresh mode-700 directory we own and then `cd`
into it to be refused, so I left it rather than adding machinery. If the gate
wants it closed, `S=$(mktemp -d ...) && S=$(cd "$S" 2>/dev/null && pwd -P || echo "$S")`
falls back to the unresolved path and is then no worse than pre-fix on every
path — at the cost of swallowing the `cd` diagnostic. Captain's call; I have not
applied it.

### Summary

Three sandbox-creation lines now resolve through `pwd -P`, so the path the
script holds matches byte-for-byte what `git worktree list --porcelain` hands
back and the self-exclusion guard finally reaches its `continue`. No test file
gained a case, no `tests/lib` was created, nothing in `bin/` was touched; the
diff is 3 files, 19 insertions, 3 deletions, the extra lines being the comment
at each site explaining why the resolution is there and why it is two steps.

Every number in this report is a measurement taken in this stage against this
worktree, red then green, not carried over from ideation; the green figures come
from the code as committed at d0e3ea0 and were then re-run a second time against
that same commit to confirm them. The one judgement call is the deviation above:
the approved form as literally written turns a failed `mktemp` into `rm -rf` on
the caller's directory, which the pre-fix code did not do. It was raised to the
first officer with the falsifying one-liner before being applied, not after, and
authorised; the residual Path B difference is named rather than smoothed over,
with the variant that would close it left for the gate to choose.

## Stage Report: validation

- DONE: Each of AC-1, AC-2 and AC-3 given its own verdict, citing the command you ran and what came back — and each RED case watched going red first. AC-1: attempted-removal counts 2 to 1 and 1 to 0, with the surviving test-compile attempt naming holder-worktree, not the sandbox root.
  **AC-1 PASS.** `bash -x tests/test-compile.sh 2>&1 | grep -c -- 'worktree remove --force'` → **1**; test-guard → **0**. Red (each `pwd -P` reverted in a throwaway copy) → **2** and **1**. Counts reproduce exactly. The decisive evidence is the xtrace inside `cleanup_all`, not the count: green shows `[ /private/…/wiki = /private/…/wiki ]` → `+ continue`; red shows `[ /private/…/wiki = /var/…/T//…/wiki ]` → `worktree remove --force` on the main worktree → `+ true`. Both filed faults visible in the red `-C` path (`/var`, `T//`).
- DONE: The negative case actually exercised: revert each `pwd -P` in a throwaway copy and confirm the check goes red for the RIGHT reason.
  Right reason confirmed above — the red removal target is `$WIKI_PATH` itself, emitted from inside `cleanup_all`. Both suites still print `ALL PASS` in the red runs, which is the trap this bug sets: suite colour carries no signal here.
- DONE: AC-2 — the repro exits 0 and leaves nothing behind.
  **AC-2 PASS.** Green: `exit=0`, `/tmp/wiki-repro-*` count **0**, still prints `REPRODUCED: ingest B failed to merge (exit 1)`. Red (`pwd -P` reverted): `exit=128`, leak count **1** (`/tmp/wiki-repro-fdUKML`, removed by hand). Both halves measured, both directions.
- DONE: AC-3 — both suites still pass, and leave nothing behind. All four run, not only the touched one.
  **AC-3 PASS.** test-fetch, test-guard, test-curate, test-compile: all `exit=0`, all `ALL PASS`. `ls -d "$TMPDIR"/wiki-*-test.*` after → no matches. AC-3's own falsifying edit exercised for real: with `mktemp` forced to fail (`TMPDIR=/nonexistent-xyz`), `SANDBOX` is empty, `WIKI_PATH` becomes `/wiki`, and test-guard exits **1** — red, as AC-3 requires.
- DONE: A verdict on the shipped deviation from the approved one-liner, in BOTH halves.
  **Deviation: ACCEPT.** See the ruling below — measured end-to-end, not argued.

### Ruling on the deviation — accept

Both halves of the failure path measured on `/bin/bash 3.2.57`:

| | approved literal | shipped chained | pre-fix |
|---|---|---|---|
| `mktemp` fails → `SANDBOX` | **caller's cwd** | `""` | `""` |
| trap's `rm -rf "$SANDBOX"` | **deletes cwd** | `rm -rf ""`, rc 0, no-op | same |

Run from a sacrificial directory holding a canary, with `TMPDIR=/nonexistent-xyz`:
shipped form → canary **survives**, suite red; approved literal → sacrificial
directory and canary **destroyed**. So the shipped form is identical to pre-fix
on Path A, and the approved literal is strictly worse than both. The deviation is
justified.

**Correction to the implementation's Path B claim (finding, not a defect).** It
reports the chained form "very slightly worse than pre-fix" when `mktemp`
succeeds but `cd` is refused. Re-measured with a stubbed `mktemp` that chmods the
new directory to 000: chained form leaks it (`before=0 after=1`) — but pre-fix
leaks it too, because the same lost execute bit that refuses `cd` also refuses
`rm -rf` (`rm rc=1`, `before=1 after=2`). Any mechanism that refuses `cd` into a
fresh self-owned directory refuses `rm -rf` as well, so there is **no residual
difference in outcome on Path B either**. Recommend the gate does *not* apply the
offered `|| echo "$S"` fallback: it buys nothing and swallows the `cd`
diagnostic.

### Findings — triaged, none acted on

1. **AC-1's `Verified by` command does not discriminate what the test plan claims
   it does.** *Deferred risk — recommend decline, record only.* The test plan says
   test-compile.sh "can distinguish 'the guard fires' from 'the loop removes
   nothing at all'". It cannot: case 3 removes `$HOLDER` inline at
   `tests/test-compile.sh:404`, at trace line 5681, while `cleanup_all` does not
   start until 6419 — so in the green run the cleanup loop attempts **zero**
   removals and the one counted attempt is not its. Measured: mutating the guard
   to an unconditional `continue` (loop skips everything) still yields count **1**
   and `ALL PASS`. I therefore verified AC-1's second half directly instead —
   suppressing line 404 so a genuine sibling survives to trap time: the loop
   removes `holder-worktree` at trace line 6428, *after* `cleanup_all` at 6419,
   and skips the main worktree; the same probe against the skip-everything mutant
   gives **0**. AC-1's claim is true and now proven; only its recipe is weak.
   Promote-to-material if the cleanup loops are ever restructured or `|| true`
   dropped — the AC as written would pass a regression through. No code change:
   ideation deliberately rejected adding cases, and this is test scaffolding.
2. **Dead redundancy at `tests/test-compile.sh:273-277`.** *Polish — decline.*
   `HOLDER_REAL`/`W_REAL` plus doubled `grep -v` are a pre-existing workaround for
   this same symlink mismatch; with `$SANDBOX` now resolved they compare equal.
   Harmless and self-documenting. Notably the codebase already knew about this
   trap at the assertion site but not at the guard site.

### Summary

All three ACs PASS, each red-then-green under my own commands, and the deviation
is accepted on end-to-end evidence — the approved literal genuinely destroys the
caller's directory on a failed `mktemp` while the shipped form does not, and its
Path B residual turns out not to exist. All four suites are green with nothing
left under `$TMPDIR` and no `/tmp/wiki-repro-*`; the one leak my red run created
was removed, and the worktree is clean of my six throwaway copies.

The one thing the implementation's report overstates is AC-1's evidence, not its
fix: the surviving test-compile attempt comes from case 3's own teardown, so the
stated command cannot tell the shipped fix from a loop that removes nothing. I
closed that gap myself with a positive probe rather than by adding a test case.
Recommend **PASSED**.

### Validation addendum: deviation re-ruled against the revised report (2eff139)

Raised by the first officer: the deviation analysis was revised mid-validation.
Checked — **no rework needed, and no stale reading occurred.** `2eff139` landed
before my report commit `2f669c9`, and the Path A/Path B text I ruled on above
is the revised text, not the superseded one. Code freeze confirmed
independently: `git diff d0e3ea0..HEAD -- tests/ docs/bug-fixes/_archive/` is
**empty**; `git diff --numstat d0e3ea0..HEAD` shows only the entity markdown
(159/1). AC-1/AC-2/AC-3 were measured against an unmoved target.

**Path A — identical in both halves, confirmed, and the approved literal is
worse than the revised report says.** It reports rc 0; measured, that is right,
and it matters more than "does not signal the failure":

    approved literal:  rc=0  SANDBOX=[/Users/gnat/Source/Powerups/powerups-wiki-ingest]
    shipped chained:   rc=1  SANDBOX=[]
    pre-fix:           rc=1  SANDBOX=[]

Because `cd ""` succeeds, the approved form's `&&` never short-circuits and the
statement reports **success** while pointing `SANDBOX` at the caller's cwd. I
also ran it under `set -eu`: execution continues regardless, so no future
`set -e` retrofit would catch it either. It is not merely unsignalled — it is
indistinguishable from a normal run right up to the point the trap deletes the
caller's directory.

**Path B — the revised report's conclusion does not survive measurement.** It
claims the chained form is "slightly worse than pre-fix: a leaked empty
directory". Its `before=0 after=1` is correct for the chained form in isolation,
but pre-fix was never measured under the same conditions. Both mechanisms by
which a `cd` into a fresh mode-700 self-owned directory can be refused:

| trigger | shipped chained | pre-fix |
|---|---|---|
| EACCES — execute bit lost (stub `chmod 000`) | leaks (`before=0 after=1`) | **also leaks** — `rm -rf` refused, `rm rc=1` |
| ENOENT — directory vanishes before `cd` | no leak | no leak |

The same lost execute bit that refuses `cd` refuses `rm -rf`'s recursion, so
pre-fix leaks the directory too; and when the directory is simply gone, neither
leaks. **On every mechanism the outcome is the same as pre-fix.** There is no
residual disadvantage to trade away. (Aside: on ENOENT the approved literal also
gives rc 1 and an empty `SANDBOX` — its cwd hazard is specific to Path A, where
the failed substitution makes the `cd` argument empty.)

**Triage on Path B: correct-but-disproportionate — recommend decline, do not
fix.** Under the stage rubric this is *Deferred risk*, and field 3 is `none:` —
no value AC or protected boundary is at risk, which by the rubric cannot
establish Material. The trigger is unobserved and only reachable by stubbing
`mktemp` to sabotage its own output. Recommend the gate does **not** apply the
offered `|| echo "$S"` fallback: it closes nothing real, and it would swallow
the `cd` diagnostic that is currently the only evidence this path was taken.
Promote to material only if a real Path B occurrence is ever observed.

Verdicts unchanged: AC-1, AC-2, AC-3 all **PASS**; deviation **ACCEPT**;
recommendation **PASSED**.
