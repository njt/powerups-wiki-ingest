# Backlog gate — guard-auto-commit-against-conflicted-merge

**Entity:** `guard-auto-commit-against-conflicted-merge` (`2e`) · **Stage:** `backlog` → `ideation`
**Source:** kata `cntt` (P1) · **Score:** 0.9

## Question

Does this advance to ideation, and is it first?

## Is it a real defect

Yes, and it is the only one in the backlog that has already damaged committed data. Observed 2026-08-06 during a 37-URL batch: `wiki-ingest-run`'s auto-commit step ran `git add`/`commit` over a working tree that was mid-hand-merge, committing literal `<<<<<<< HEAD` / `=======` / `>>>>>>>` markers into `topic/Context Graphs.md` on main. It then completed its own merge on top, burying the corruption several commits deep. The ingest reported success.

The evidence is a first-hand observation with a named file, a named commit (`a60c1d8` in the wiki repo), and a described mechanism — not a suspicion.

## Is it correctly scoped as a bug

Yes. The kata issue proposes a bounded three-check guard on an existing step, not a redesign. The contributing factor (a hand-merge racing an ingest) is a trigger, not the cause; the cause is an unguarded commit over an arbitrary working tree, and it stays a cause whether or not anyone hand-merges again, because ingests run in parallel by design and their finish times are not predictable.

## Why first

1. It is the only backlog item that corrupts data already on main. Everything else either loses work that has not landed yet or disables a fallback path.
2. It is self-contained — one guard on one step.
3. `serialise-topic-page-merges` touches the same `wiki-ingest-run` git machinery. Landing this first means that fix builds on a committed guard rather than racing it in the same file.

## Risks accepted at this gate

The fix must fail closed. A guard that detects the broken state and proceeds with a warning does not close this bug, because the entire failure mode is "proceeded when it should have stopped, and said it was fine." Ideation must produce an AC that proves the abort, and a negative case that reds when the guard is reverted.

## Recommend

**Approve** — advance to ideation, dispatched first alongside `escape-positional-in-surf-awk-snippet` (no file overlap between the two).
