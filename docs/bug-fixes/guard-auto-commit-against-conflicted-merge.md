---
id: 2enq6rq17z4ykkecg15y810w
title: Guard auto-commit against in-progress and conflicted merges
status: backlog
source: kata:cntt
started:
completed:
verdict:
score: 0.9
worktree:
issue:
pr:
mod-block:
---

## Problem

`wiki-ingest-run` has a step that emits "Auto-commit local changes before ingest merge" (landed as commit `a60c1d8` in the wiki repo). It runs `git add` / `git commit` over whatever is in the working tree without checking whether a merge is in progress.

Observed 2026-08-06 during a 37-URL batch ingest. While Nat was hand-resolving a merge in `$WIKI_PATH`, a late-finishing ingest reached that step and committed the conflicted working tree — literal `<<<<<<< HEAD`, `=======`, `>>>>>>>` markers — into `topic/Context Graphs.md` on main. It then completed its own merge on top, so the corruption was several commits deep before anyone could notice. Nothing failed loudly; the ingest reported success.

Impact: silent corruption of wiki content. Conflict markers in a topic page stay invisible until a human reads that page.

The contributing factor was starting a hand-merge in a shared repo while an ingest was still running, but the tool should be safe against that regardless — ingests are launched in parallel by design and their finish times are not predictable. This is the highest-priority item in the backlog because it is the only one that corrupts data already committed to main.

## Proposed approach

Guard the auto-commit. It exists as a convenience for stray local edits and should never absorb a broken merge state. The kata issue proposes three checks, cheapest first:

- refuse if mid-merge: `test -e "$(git rev-parse --git-dir)/MERGE_HEAD"` → abort
- refuse on unmerged paths: `git ls-files -u | grep -q .` → abort
- belt and braces: reject any staged file whose content matches `^(<<<<<<<|=======|>>>>>>>)` before committing

Abort must mean abort — fail closed with a non-zero exit and a message naming the repo state, not a warning followed by a commit.

Worth checking whether `wiki-ingest-backfill` or any other script in `bin/` reaches the same auto-commit path, and whether the rebased/cherry-pick equivalents (`REBASE_HEAD`, `CHERRY_PICK_HEAD`) deserve the same treatment.

## Acceptance criteria

To be written at ideation, with a `Verified by:` clause each. The shape they need to take: a throwaway wiki left in a conflicted merge state, `wiki-ingest-run` driven at its auto-commit step, and the assertion that it exits non-zero having committed nothing — plus the negative case, where reverting the guard makes that test go red.

## Test plan

To be written at ideation. `tests/test-guard.sh` already builds a throwaway wiki with a stubbed `WIKI_INGEST_CLI` and seeds it with pre-existing `summary/` and `topic/` pages, which is most of the fixture this needs.

## Out of scope

The concurrency model itself. Making ingests not race each other is `serialise-topic-page-merges` and, further out, kata `87sc`. This fix only stops the auto-commit from laundering a broken tree into main.
