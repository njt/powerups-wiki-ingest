# Backlog gate — `resolve-tmp-symlink-in-worktree-cleanup-guards`

**Fix:** `6a5wjaf19gdem9ca30m9b0cc` · **Stage:** `backlog` · **Score:** 0.4
**Question:** Does this fix advance to `ideation`?

## Recommendation

**Approve — advance to ideation**, with one scope caution the ideation stage must
resolve before it proposes a harness (see *Risk* below).

## Against the stage's declared outputs

| Backlog requires | Status |
|---|---|
| Problem stated as **observed damage**, not suspicion | **Met.** The mismatch was measured, not argued: `git` reports `/private/var/...`, `$WIKI_PATH` holds `/var/...`. The repro's exit 128 was reproduced against an unmodified copy extracted from `HEAD`. |
| kata ref in `source` | **Met, as of this gate.** Filed as `kata:1dvt` in the `powerups-wiki-ingest` project. It was missing at filing time — that was my omission, now closed. |
| *Good:* a reader who never saw the kata understands what broke and who got hurt | **Met.** Three named call sites with line numbers, the measured mismatch inline, and the damage split into "invisible today" vs "already visible in the repro". |
| *Bad:* advancing a proposal or an epic rather than a defect | **Avoided.** `1dvt` is a specific defect with a one-line-per-site fix, not a redesign. |

## AC cross-check

Three acceptance criteria, each with a `Verified by:` clause and a named
falsifying edit — the shape the workflow asks for. At `backlog` these are not
yet evidenced, and should not be: evidence is `ideation`'s and `validation`'s
job. What is checkable now is that they are **end-state properties** rather than
stage actions, and they are.

- **AC-1** — the guard actually skips the main worktree.
- **AC-2** — the repro exits 0, as its own documentation claims.
- **AC-3** — both suites still pass and leave nothing behind.

AC-1 is the load-bearing one: AC-2 and AC-3 would both pass today on a broken
guard, because git's refusal masks it.

## Risk the gate should look at rather than take on trust

**The test may cost more than the fix.** The fix is one line at each of three
sites. But AC-1 deliberately requires asserting on *which paths the loop attempts
to remove*, not on the end state — because the end state is byte-identical
whether or not the guard works. That is exactly why this survived unnoticed, and
it means a test written after the fix would pass for the wrong reason.

Satisfying it honestly needs call-tracing scaffolding in `test-guard.sh`. That is
a real risk of the workflow's own *"Bad: proposing a rewrite where a guard would
do"*. **Ideation should decide explicitly whether AC-1 is worth its harness, or
whether the honest answer is a narrower AC plus a recorded limitation.** Better
to decide that at design time than to discover it mid-implementation.

## One staleness in the fix body

Line 39 cites the third call site as
`docs/bug-fixes/serialise-topic-page-merges/repro/repro-topic-conflict.sh:20`.
That file moved to `docs/bug-fixes/_archive/...` when the superseded fix was
archived, after this entity was filed. The path no longer resolves. Cosmetic,
but it should be corrected during ideation so a worker does not chase it.

## Why advance rather than decline

Impact today is genuinely low, and the score reflects that. The case for doing
it anyway:

- It is **three instances of one mistake**, which is the cheapest moment to fix
  a class rather than an instance.
- The currently-benign behaviour is benign **by accident** — git's refusal, plus
  a `|| true` — not by design. Nothing records that the safety is incidental, so
  a future edit removing the `|| true` would look harmless and would not be.
- The repro case is not benign: it exits 128 against a doc claiming 0, which is
  a live trap for anyone wiring it into CI.

The case for declining, stated fairly: nothing is broken for a user today, and
the fix consumes a cycle that a higher-scoring defect could have. If the board
had contention, this would lose. It does not — it is the only open fix.

## Decision

Approve to advance to `ideation` · Revise · Hold
