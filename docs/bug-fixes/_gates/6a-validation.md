# Validation gate — `resolve-tmp-symlink-in-worktree-cleanup-guards`

**Fix:** `6a5wjaf19gdem9ca30m9b0cc` · **Stage:** `validation` · **Score:** 0.4
**Question:** Does this fix pass validation and go terminal (merge to `main`)?

## Recommendation

**Approve — verdict PASSED, merge to `main`.** All three ACs verified red-then-
green by a fresh agent running its own commands, and the one weakness found is in
an AC's *recipe*, not in the fix.

## Verdict per AC

| AC | Verdict | Green | Red (guard reverted) |
|---|---|---|---|
| **AC-1** attempted removals | PASS | compile 1, guard 0 | compile 2, guard 1 |
| **AC-2** repro exit / leak | PASS | `exit=0`, 0 leaked | `exit=128`, 1 leaked |
| **AC-3** four suites, no residue | PASS | all `exit=0`, `ALL PASS`, no `$TMPDIR` leftovers | `mktemp` forced to fail → test-guard exits 1 |

Each red case was watched going red by the validator itself, not inherited from
the implementation report. The decisive AC-1 evidence is the xtrace *inside*
`cleanup_all`: green shows `[ /private/…/wiki = /private/…/wiki ]` → `+ continue`;
red shows `[ /private/…/wiki = /var/…/T//…/wiki ]` → `worktree remove --force` on
the main worktree. Both filed faults — the `/var` symlink and the `T//` double
slash — are visible in the red trace.

## Scope against the ideation estimate

Three functional lines at three sites, as designed. `git diff --numstat`:
`test-guard.sh` 6/1, `test-compile.sh` 6/1, the repro 7/1 — 19 insertions, 3
deletions, the surplus being a comment at each site recording why the resolution
exists and why it is two steps. No test case added, no `tests/lib`, nothing in
`bin/`. AC unchanged, no narrowing.

## The finding that matters — and it lands on my own gate presentation

**Finding 1 — AC-1's `Verified by` recipe does not discriminate.**
*Deferred risk. FO-authorized disposition: DECLINE, record only.*

At the ideation gate I put this command in front of the Captain as the load-
bearing check:

    bash -x tests/test-compile.sh 2>&1 | grep -c -- 'worktree remove --force'   # want 1

It does not test what I said it tests. The surviving count-1 comes from case 3's
own inline teardown at `tests/test-compile.sh:404` (trace line 5681), while
`cleanup_all` does not begin until trace 6419 — so in the green run the cleanup
loop attempts **zero** removals and the one counted attempt is not its. Measured:
mutating the guard to an unconditional `continue`, so the loop skips everything,
still yields count **1** and `ALL PASS`.

The validator closed the gap directly rather than accepting it: suppressing line
404 so a genuine sibling survives to trap time, it observed the loop removing
`holder-worktree` at trace 6428 — *after* `cleanup_all` at 6419 — and skipping
the main worktree, with the skip-everything mutant scoring **0**.

**So AC-1's claim is true and now proven; the recipe I presented is not what
proved it.** Promote-to-material if the cleanup loops are restructured or the
`|| true` is dropped — as written, the AC would pass a regression through.
Declined rather than fixed because the trigger is hypothetical today, and because
ideation deliberately rejected adding test cases, which the Captain approved.
Only the Captain may change an AC, so AC-1's text is untouched.

**Finding 2 — dead `HOLDER_REAL`/`W_REAL` redundancy at `test-compile.sh:273-277`.**
*Polish. FO-authorized disposition: DECLINE.* A pre-existing workaround for this
same symlink mismatch; with `$SANDBOX` resolved they now compare equal. Harmless
and self-documenting, and removing it would widen a three-line fix into unrelated
cleanup. Worth noting as context: the codebase already knew about this trap at
the assertion site, but not at the guard site.

## A decision that has been removed rather than deferred

The implementation flagged a residual "Path B" — `mktemp` succeeds but the
following `cd` is refused — where the shipped form leaks a temp dir and pre-fix
would not, and offered a `|| echo "$S"` fallback to close it. I was going to put
that trade to the Captain.

The validator re-measured and **corrected it**: with a stubbed `mktemp` that
chmods the directory to 000, the chained form leaks it — but pre-fix leaks it
too, because the same lost execute bit that refuses `cd` also refuses `rm -rf`
(`rm rc=1`). Any mechanism that refuses `cd` into a fresh self-owned directory
refuses `rm -rf` as well. **There is no residual difference on Path B**, so the
fallback buys nothing and would swallow the `cd` diagnostic. Not offered.

## The deviation, ruled

The Captain approved `SANDBOX=$(cd "$(mktemp -d ...)" && pwd -P)` at ideation.
The shipped form chains instead. Measured from a sacrificial directory holding a
canary, with `TMPDIR=/nonexistent-xyz`: the shipped form leaves the canary intact
and the suite red; **the approved literal destroys the sacrificial directory and
the canary**, and returns rc 0 while doing it. The deviation is not merely
acceptable, it is a correction — and the form it corrects is one I wrote into the
dispatch notes.

## What I verified myself

- The code under review never moved during validation: `git diff
  d0e3ea0..HEAD -- tests/ docs/bug-fixes/_archive/` is empty. A report revision
  landed mid-run; I froze the branch and had the validator re-read it.
- The full three-line diff, read directly rather than via either report.
- Scope via `--numstat` against the ideation estimate.

I did not re-run the suites. That check is the validation stage's own and its
report shows it green, red-then-green, under its own commands.

## Decision

Approve → `verdict: PASSED`, merge to `main`, archive, close `kata:1dvt` ·
Revise → route findings back to implementation · Hold
