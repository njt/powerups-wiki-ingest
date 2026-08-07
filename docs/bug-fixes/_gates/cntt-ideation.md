# Ideation gate — guard-auto-commit-against-conflicted-merge

**Entity:** `guard-auto-commit-against-conflicted-merge` (`2e`) · **Stage:** `ideation` → `implementation`
**Source:** kata `cntt` (P1) · **Score:** 0.9

## Question

Is this design sound enough to build, and is `wiki-ingest-backfill` (AC6) in scope?

## What the ideation found that the kata issue did not

The ensign reproduced the bug rather than trusting the report, and the reproduction is embedded in the fix body as a runnable script that exits 0 against today's `bin/` (markers on `main`, run exit 0) and exits 1 against a guarded prototype. It lands markers in `topic/Context Graphs.md` — the same file as the live 2026-08-06 incident.

**All three checks the kata proposed are wrong as written, each disproved with evidence:**

1. `git rev-parse --git-dir` returns a **relative** `.git`, resolved against the script's cwd rather than `$WIKI`. The mid-merge test would have silently never fired. `--absolute-git-dir` is correct.
2. `git ls-files -u` is empty **after** `git add -A` — and the add is what marks conflicted paths resolved. The check is only meaningful before the add. It also misses a captain who has already staged their resolutions: `MERGE_HEAD` set, no unmerged paths.
3. `^=======` false-positives on a **markdown setext heading underline**. On a markdown wiki this would reject ordinary content. The anchored `^(<<<<<<<|>>>>>>>) ` form does not.

Had we implemented the kata's three checks as filed, we would have shipped a guard that never fires and rejects legitimate pages.

**Two further findings changed the design.** Abort must be `exit 1`, not "skip the auto-commit" — skipping leaves `MERGE_HEAD` set, the script proceeds into `merge_with_retry`, and its `git merge --abort` was *observed destroying a hand-resolution*, five times over, once per retry. And `wiki-ingest-backfill` reaches the same hazard through its own `commit_batch`, reproduced twice: staging marker-laden files into the captain's index, and concluding the captain's merge under a `Backfill verbatim raw/` title.

## The scope question

AC6 extends the guard to `wiki-ingest-backfill`. The kata issue named only `wiki-ingest-run`.

I am approving it in scope rather than splitting it, on the Captain's own standing practice, quoted from `~/.claude/CLAUDE.md`: *"then look for rhyming bugs (if we made that mistake, we might have made similar ones elsewhere) and fix them too in the same way."* This is that case exactly — same bug class, proven live rather than hypothetical, and the guard is a copy-paste into an adjacent function. The ensign offered the split as the minimum acceptable alternative; I am not taking it, because a proven hazard filed as a follow-up is a hazard that stays open.

This is the one call at this gate the Captain might have made differently. It is recorded here so it is easy to reverse.

## Evidence quality

Seven ACs, all declared **offline** with a stated reason, each citing a named `tests/test-guard.sh` case and each carrying a `Fails if:` naming the concrete falsifying edit. AC5 is the counterweight that keeps the guard from over-firing: an ordinary edit plus a setext-heading page must still commit at exit 0. The `Deliberately left alone` section rejects a start-of-script pre-flight check with a reason — it would kill ingests that currently succeed.

Checklist: 3 done, 0 skipped, 0 failed (`docs/bug-fixes/guard-auto-commit-against-conflicted-merge.md` lines 298–313).

## Recommend

**Approve** — enter implementation, with `wiki-ingest-backfill` in scope.
