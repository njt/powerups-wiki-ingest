# Ideation gate — `resolve-tmp-symlink-in-worktree-cleanup-guards`

**Fix:** `6a5wjaf19gdem9ca30m9b0cc` · **Stage:** `ideation` · **Score:** 0.4
**Question:** Does this fix advance to `implementation`?

## Recommendation

**Approve — advance to implementation.** The backlog gate's one open risk was
resolved by measurement rather than by argument, and resolved in the cheaper
direction.

## The risk this gate was asked to close

Backlog approval carried an explicit ask: decide whether AC-1's call-tracing
harness is proportionate to a one-line-per-site fix, or narrow AC-1 and record
the limitation.

**The answer was neither, and it is better than both options offered.** `bash -x`
is already a call tracer: the trap's `git worktree remove` invocation appears in
xtrace output, so "which paths does the loop attempt to remove" is a `grep` over
a traced suite run. AC-1 stands at its original strength with **zero new code**.

Measured both directions on `tests/test-compile.sh`:

| | attempted removals |
|---|---|
| today | `holder-worktree` **and** the main worktree |
| with `pwd -P` | `holder-worktree` only |

The rejected alternative is recorded with its reasoning: an in-suite version
needs ~20 lines per suite and adds a mode in which cleanup deliberately does not
clean up, to the code whose whole job is to leave no worktrees behind. That is
the "rewrite where a guard would do" this stage exists to catch, and it was
caught.

## Against the stage's declared outputs

| Ideation requires | Status |
|---|---|
| A reproduction that actually fails, named as an exact command | **Met.** `bash -x tests/test-compile.sh 2>&1 \| grep -- 'worktree remove --force'` — a command, not a description. |
| ACs whose evidence lives outside this file | **Met.** All three verified by commands over existing repo code; none rests on re-reading this fix's prose. |
| A test plan naming which script gains the case, or why not | **Met, unusually: none gains a case**, and the reasoning is the AC-1 decision above. No new test file, no `tests/lib`. |
| Each AC split offline / interactive | **Met.** All three offline, declared in a preamble and inline. None interactive. |
| Root cause distinguished from trigger | **Met.** The trigger is macOS symlinks; the cause is comparing a resolved path against an unresolved one. Fix is at path creation, not at comparison. |

## AC cross-check

Three ACs, each an end-state property with an exact `Verified by:` command, the
measured value **today**, and a named falsifying edit.

- **AC-1** — attempted-removal counts: want 1 / 0, today 2 / 1.
- **AC-2** — repro exits 0 **and leaks nothing**; today exit 128 and 1 leaked dir.
- **AC-3** — both suites green, nothing left under `$TMPDIR`.

**Mechanism re-anchored to end value.** AC-1 is mechanism ("the guard's
`continue` is reached"). The ensign identified the end-value anchor itself:
AC-2's sandbox leak "is the one place in this fix where the guard's behaviour
shows up in the end state at all". So the mechanism AC is paired to a value AC
that can independently fail. That pairing is what makes AC-1 more than a
tautology.

**The red run has already been watched**, at ideation, on all three ACs — today's
numbers measured against HEAD, the green numbers taken by applying `pwd -P` to
throwaway copies. Implementation inherits a genuine before/after, which is
exactly what this bug needed: a case written after the fix would have passed for
the wrong reason.

## Two findings beyond the brief

1. **The repro leaks as well as exiting 128.** The failed removal aborts the
   `EXIT` trap before `rm -rf "$WIKI"`, so `/tmp/wiki-repro-*` survives. AC-2 now
   asserts both. This strengthens the fix's value case.
2. **No production script is affected.** `bin/wiki-compile:82`,
   `bin/wiki-recompile:92` and `bin/wiki-ingest-run:307,309` remove worktrees by
   the path they created, never by one read back from `git worktree list`.

*FO verification of finding 2:* independently confirmed — `grep -rn 'worktree
list' bin/` returns nothing, so no `bin/` script can exhibit this defect. Blast
radius is genuinely the three cited sites. Also confirmed `test-compile.sh:41`
stands up the `holder-worktree` sibling and `test-guard.sh` has zero references,
which supports the ensign's warning that `test-compile.sh` is the load-bearing
AC-1 site — a fix that made the loop skip *everything* would still show `0` on
`test-guard.sh`.

## The one concession, stated plainly

AC-1 is verified by an external command rather than a numbered case inside the
suite, because a suite cannot xtrace itself. The stage permits either, and a
command a fresh agent re-runs is still offline evidence. The cost is that AC-1
will not run automatically when someone runs the suite — it must be invoked
deliberately. Worth accepting for zero new code in load-bearing cleanup paths,
but it is a real trade and should not pass unnoticed.

## What I did not independently verify

I did not re-run the suites myself. The stage report shows the measurement ran
green in both directions, and re-running a check the stage already owns is not
the FO's job. Implementation will re-establish these numbers as its own before/
after.

## Decision

Approve to advance to `implementation` · Revise · Hold
