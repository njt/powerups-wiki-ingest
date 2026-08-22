---
id: 6a5wjaf19gdem9ca30m9b0cc
title: Worktree-cleanup self-exclusion guard never fires on macOS (/tmp and $TMPDIR are symlinks)
status: ideation
source: kata:1dvt
started: 2026-08-22T13:48:45Z
completed:
verdict:
score: 0.4
worktree:
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
