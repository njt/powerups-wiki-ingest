---
id: 2enq6rq17z4ykkecg15y810w
title: Guard auto-commit against in-progress and conflicted merges
status: validation
source: kata:cntt
started: 2026-08-07T13:23:49Z
completed:
verdict:
score: 0.9
worktree: .worktrees/spacedock-ensign-guard-auto-commit-against-conflicted-merge
issue:
pr:
mod-block:
gates:
    version: 1
    records:
        - id: gate:2enq6rq17z4ykkecg15y810w:backlog
          stage: backlog
          attempts:
            - id: gate-attempt:2enq6rq17z4ykkecg15y810w-backlog-1
              briefing:
                id: briefing:2enq6rq17z4ykkecg15y810w:backlog:attempt-1:revision-1
                digest: sha256:1c2a3ba0e6936a089bbb993999ed525fa9920b50510ade66d69010edee5dff9d
                request-digest: sha256:2a09fef14571d7de822022b41076ccd630ca86f965daee4ab9833d5b0655be01
                room-ref: ./guard-auto-commit-against-conflicted-merge/review/backlog/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:2enq6rq17z4ykkecg15y810w:backlog:1
                briefing: briefing:2enq6rq17z4ykkecg15y810w:backlog:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T13:21:38.148442Z"
                decision: approve
                reason: First-hand 2026-08-06 evidence names the corrupted file, the mechanism and the commit; only backlog item that has damaged committed data on main. Scope is a bounded guard on an existing step. Captain delegated ordering and gate decisions in-conversation.
              application:
                target-stage: ideation
                state: consumed
        - id: gate:2enq6rq17z4ykkecg15y810w:ideation
          stage: ideation
          attempts:
            - id: gate-attempt:2enq6rq17z4ykkecg15y810w-ideation-1
              briefing:
                id: briefing:2enq6rq17z4ykkecg15y810w:ideation:attempt-1:revision-1
                digest: sha256:49fa0e2b3485786b86433a34db6a71fa9cec6112d36184ff645ba51ba9fe2241
                request-digest: sha256:82ce470bd7243aa066c79ebe57520efd905b85154bf50dc11428d7c9ecf3bd84
                room-ref: ./guard-auto-commit-against-conflicted-merge/review/ideation/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:2enq6rq17z4ykkecg15y810w:ideation:1
                briefing: briefing:2enq6rq17z4ykkecg15y810w:ideation:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T13:38:48.321467Z"
                decision: approve
                reason: Mechanism confirmed first-hand with a runnable reproduction that exits 0 unguarded and 1 guarded. All three kata-proposed checks disproved with evidence (relative --git-dir, ls-files -u empty after add -A, setext-heading false positive). Guard placement and exit-not-skip both justified by observed damage. Seven offline ACs, each with a named test case and falsifying edit; AC5 guards against over-firing. Backfill kept in scope per Captain's standing rhyming-bugs practice in CLAUDE.md. Captain delegated gate decisions in-conversation.
              application:
                target-stage: implementation
                state: consumed
---

## Problem

`wiki-ingest-run` has a step that emits "Auto-commit local changes before ingest merge" (landed as commit `a60c1d8` in the wiki repo). It runs `git add` / `git commit` over whatever is in the working tree without checking whether a merge is in progress.

Observed 2026-08-06 during a 37-URL batch ingest. While Nat was hand-resolving a merge in `$WIKI_PATH`, a late-finishing ingest reached that step and committed the conflicted working tree — literal `<<<<<<< HEAD`, `=======`, `>>>>>>>` markers — into `topic/Context Graphs.md` on main. It then completed its own merge on top, so the corruption was several commits deep before anyone could notice. Nothing failed loudly; the ingest reported success.

Impact: silent corruption of wiki content. Conflict markers in a topic page stay invisible until a human reads that page.

The contributing factor was starting a hand-merge in a shared repo while an ingest was still running, but the tool should be safe against that regardless — ingests are launched in parallel by design and their finish times are not predictable. This is the highest-priority item in the backlog because it is the only one that corrupts data already committed to main.

### Confirmed mechanism

The step is `bin/wiki-ingest-run:657-660`, exactly as reported:

```bash
git -C "$WIKI" add -A 2>/dev/null || true
git -C "$WIKI" diff --cached --quiet 2>/dev/null || \
  git -C "$WIKI" commit -m "Auto-commit local changes before ingest merge" 2>/dev/null || true
```

Replayed against a conflicted merge, the two commands do this:

1. `git add -A` stages the marker-laden working-tree file **and thereby marks every conflicted path resolved**. After it, `git ls-files -u` is empty.
2. `git commit` then sees `MERGE_HEAD` with no unmerged entries, so it succeeds and **creates a merge commit** — the captain's merge, concluded by the ingest, with `<<<<<<<` / `=======` / `>>>>>>>` in the content. Exit 0.

That ordering is the whole bug, and it dictates where the guard goes: the unmerged-path check is only meaningful **before** the `add -A`.

### Reproduction

Save as `repro-cntt.sh` and run `BIN=/path/to/powerups-wiki-ingest/bin bash repro-cntt.sh`. It builds a throwaway wiki (never touches `$WIKI_PATH` from your environment — it sets its own), uses a stub LLM that leaves the wiki mid-merge at exactly the moment the 2026-08-06 race did, and drives the real `wiki-ingest-run`. **Exit 0 = bug reproduced. Exit 1 = guard held.**

```bash
#!/bin/bash
set -u
BIN="${BIN:?set BIN to the bin directory of powerups-wiki-ingest}"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/cntt-repro.XXXXXX")
export WIKI_PATH="$SANDBOX/wiki"
trap 'git -C "$WIKI_PATH" worktree prune 2>/dev/null; rm -rf "$SANDBOX"' EXIT

STUB="$SANDBOX/stub-cli"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
set -u
cat >/dev/null
s="${STUB_SLUG:-unknown}"
printf -- '---\nurl: x\n---\n\nprecis\n' > "summary/$s.md"
printf '# Test Page\n\nbody\n' > "topic/Test Page.md"
printf -- '- entry\n' >> index.md
printf -- '- entry\n' >> log.md
# Leave $WIKI_PATH mid-merge, as a hand-merge racing an ingest does.
git -C "$WIKI_PATH" merge conflicting --no-edit >/dev/null 2>&1
exit 0
STUB_EOF
chmod +x "$STUB"
export WIKI_INGEST_CLI="$STUB"

"$BIN/wiki-ingest-setup" >/dev/null || { echo "setup failed"; exit 2; }
git -C "$WIKI_PATH" config user.email "test@wiki-ingest.invalid"
git -C "$WIKI_PATH" config user.name "wiki-ingest test"

printf '# Context Graphs\n\nseed body\n' > "$WIKI_PATH/topic/Context Graphs.md"
git -C "$WIKI_PATH" add -A
git -C "$WIKI_PATH" commit -q -m "Seed topic page"
git -C "$WIKI_PATH" checkout -q -b conflicting
printf '# Context Graphs\n\nTHEIR VERSION\n' > "$WIKI_PATH/topic/Context Graphs.md"
git -C "$WIKI_PATH" commit -qam "their edit"
git -C "$WIKI_PATH" checkout -q main
printf '# Context Graphs\n\nOUR VERSION\n' > "$WIKI_PATH/topic/Context Graphs.md"
git -C "$WIKI_PATH" commit -qam "our edit"

SRC="$SANDBOX/source.txt"
printf 'A plausible article body with enough characters to pass the length check.\n' > "$SRC"

STUB_SLUG=cntt "$BIN/wiki-ingest-run" --content "$SRC" https://example.invalid/cntt \
  >"$SANDBOX/out" 2>"$SANDBOX/err"
rc=$?

echo "run exit code : $rc"
echo "run stdout    : $(grep '^INGESTED' "$SANDBOX/out" || echo '(no INGESTED line)')"
echo "main HEAD     : $(git -C "$WIKI_PATH" log -1 --format=%s main)"
git -C "$WIKI_PATH" show "main:topic/Context Graphs.md"

if git -C "$WIKI_PATH" show "main:topic/Context Graphs.md" | grep -q '^<<<<<<< '; then
  echo "BUG REPRODUCED: conflict markers committed to main; run exited $rc"; exit 0
else
  echo "GUARD HELD: no conflict markers on main; run exited $rc"; exit 1
fi
```

Against `bin/` as it stands today this prints:

```
run exit code : 0
run stdout    : INGESTED: https://example.invalid/cntt (branch ingest-…, merged, push-failed)
main HEAD     : Merge branch 'ingest-…'
# Context Graphs

<<<<<<< HEAD
OUR VERSION
=======
THEIR VERSION
>>>>>>> conflicting
BUG REPRODUCED: conflict markers committed to main; run exited 0
```

Same file name, same silent success, same burial under a merge commit as the live incident. (`push-failed` is expected — the throwaway wiki has no remote.)

Against a prototype carrying the guard below, the same script prints `GUARD HELD: no conflict markers on main; run exited 1` and exits 1.

## Proposed approach

Guard the auto-commit. It exists as a convenience for stray local edits and should never absorb a broken merge state. The kata issue's three checks are the right three ideas, but **all three are wrong as written**. Each defect was reproduced:

| Kata's check | Defect | Evidence |
|---|---|---|
| `test -e "$(git rev-parse --git-dir)/MERGE_HEAD"` | `--git-dir` returns the **relative** `.git`, resolved against the *script's* cwd, not `$WIKI`. The test silently never fires. | Ran it from `/` against a repo with `MERGE_HEAD` set: `--git-dir` → `.git`, check → MISSES. `--absolute-git-dir` → correct path. |
| `git ls-files -u \| grep -q .` | Correct, but **only before `git add -A`**. After the add it is empty. It is also insufficient alone: a captain who has staged their resolutions has `MERGE_HEAD` set and *no* unmerged paths. | Both states reproduced directly. |
| `^(<<<<<<<\|=======\|>>>>>>>)` | `=======` is a legal **markdown setext heading underline**. On a markdown wiki this false-positives on ordinary content. | `printf 'My Heading\n=======\n\nbody\n'` matches the kata regex; does not match the anchored form. |

### Abort must mean exit, not skip

Fail-closed here specifically means `exit 1`, not "skip the auto-commit and carry on". Skipping leaves `MERGE_HEAD` set, so the script proceeds into `merge_with_retry` (`bin/wiki-ingest-run:208-219`), whose `git merge` fails with *"Merging is not possible because you have unmerged files"* and whose **`git merge --abort` then destroys the captain's hand-resolution** — five times over, once per retry. Reproduced: a file hand-resolved to `RESOLVED BY HAND` was reverted to `OURS` by that `merge --abort`.

Exiting costs nothing that matters: the ingest's own work is already committed to `$BRANCH` in the worktree (lines 649-655), and `cleanup`'s `git branch -d` only deletes merged branches, so the branch survives for retry.

### The guard

Placed immediately before `git add -A` at `bin/wiki-ingest-run:658`, with the marker scan between the add and the commit.

```bash
# Refuse to auto-commit into a repo that is mid-operation. This MUST run before
# the `git add -A` below: add -A marks conflicted paths resolved, after which
# `git ls-files -u` is empty and the evidence is gone, and the commit then
# concludes someone else's merge with their unresolved tree in it (kata cntt).
# Exit rather than skip: skipping leaves MERGE_HEAD set, and merge_with_retry's
# `git merge --abort` would then destroy the captain's hand-resolution.
GITDIR=$(git -C "$WIKI" rev-parse --absolute-git-dir 2>/dev/null || true)
INPROGRESS=""
for st in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer; do
  if [ -n "$GITDIR" ] && [ -e "$GITDIR/$st" ]; then INPROGRESS="$INPROGRESS $st"; fi
done
if [ -n "$INPROGRESS" ]; then
  echo "wiki-ingest-run: $WIKI has a git operation in progress ($INPROGRESS) — refusing to auto-commit" >&2
  echo "wiki-ingest-run: finish or abort it, then re-run. Branch $BRANCH kept for retry." >&2
  exit 1
fi
UNMERGED=$(git -C "$WIKI" diff --name-only --diff-filter=U 2>/dev/null || true)
if [ -n "$UNMERGED" ]; then
  echo "wiki-ingest-run: $WIKI has unmerged paths — refusing to auto-commit: $(printf '%s' "$UNMERGED" | tr '\n' ' ')" >&2
  echo "wiki-ingest-run: branch $BRANCH kept for retry." >&2
  exit 1
fi

# Commit any local changes on main first (e.g. Obsidian edits) so merge doesn't fail
git -C "$WIKI" add -A 2>/dev/null || true

# Belt and braces: never commit conflict markers, even with no operation flagged
# in progress. Anchored on the <<<<<<< / >>>>>>> forms only — a bare "=======" is
# a legal setext heading underline in markdown and false-positives across a wiki.
MARKED=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if git -C "$WIKI" show ":$p" 2>/dev/null | grep -qE '^(<<<<<<<|>>>>>>>) '; then
    MARKED="$MARKED$p
"
  fi
done < <(git -C "$WIKI" diff --cached --name-only)
if [ -n "$MARKED" ]; then
  echo "wiki-ingest-run: conflict markers in staged file(s) — refusing to auto-commit: $(printf '%s' "$MARKED" | tr '\n' ' ')" >&2
  git -C "$WIKI" reset --quiet 2>/dev/null || true
  echo "wiki-ingest-run: branch $BRANCH kept for retry." >&2
  exit 1
fi
```

Notes on the choices:

- **`--diff-filter=U` rather than `ls-files -u`** — same detection, and it yields one line per path for the message instead of three stage lines. `ls-files -u --format=` would need git 2.38+; `--absolute-git-dir` needs 2.13+.
- **`rebase-merge` / `rebase-apply` / `sequencer` rather than `REBASE_HEAD`** — directory markers are stable across git versions where `REBASE_HEAD` is comparatively recent, and `sequencer/` catches a stopped multi-commit cherry-pick or revert.
- **`while IFS= read -r` over process substitution** — wiki topic filenames contain spaces (`topic/Context Graphs.md`). Word-splitting a `for` loop over `--name-only` would silently mis-scan every one of them. Verified working under `/bin/bash` 3.2.57.
- **The `git reset` in the marker branch is the one place the guard mutates the captain's repo.** It unstages what the preceding `add -A` staged; file contents are untouched. It is only reachable when no operation is in progress, i.e. when nothing was carefully staged. The alternative — scanning working-tree files before staging — needs `status --porcelain` parsing that is fragile for renamed and quoted paths, so it was rejected.

### Should `REBASE_HEAD` and `CHERRY_PICK_HEAD` get the same guard? Yes — checked directly

- **Conflicted cherry-pick**: `add -A` + `commit` writes conflict markers straight onto `main`. Identical severity to the merge case.
- **Conflicted rebase**: `add -A` + `commit` commits the markers onto a **detached HEAD**; `main` never moves. Different damage, still fail-open — the captain's rebase is silently mangled, the ingest's content never reaches `main`, and the run still prints `INGESTED … pushed`.
- **Conflicted revert** takes the cherry-pick shape (`REVERT_HEAD`), so it is included at zero extra cost.

### Does `wiki-ingest-backfill` reach the same hazard? Yes — different code path, same class

`wiki-ingest-backfill` does **not** share `wiki-ingest-run`'s code; it has its own `commit_batch` at `bin/wiki-ingest-backfill:66-74`. That path is narrower (`git add raw/` and `git add ingest-queue.md`, not `add -A`) but still exposed, reproduced twice:

- Unmerged paths present: `git add raw/` **staged a marker-laden `raw/r.md`, marking it resolved**. The commit then failed on the remaining unmerged path and was swallowed by `2>/dev/null`, so nothing was committed — but the captain's index now carries the markers, and their next `git commit` lands them.
- Captain had staged their resolutions: `commit_batch` **concluded their merge**, producing a two-parent commit titled `Backfill verbatim raw/ (batch …)`.

`wiki-ingest-dupcheck`, `wiki-ingest-fetch` and `wiki-ingest-setup` do not commit and are not exposed. **Recommended scope: both scripts.** The same in-progress/unmerged block goes at the top of `commit_batch`, with `return 1` plus a `break` out of the fetch loop rather than a bare `exit` so the run stops cleanly. Minimum acceptable scope if the gate wants this split: `wiki-ingest-run` only, with the backfill hazard filed as its own kata item — but it is a proven live hazard, not a hypothetical, and the guard is a copy-paste.

### Deliberately left alone

- **`merge_with_retry`'s `git merge --abort`.** It is dangerous in a shared checkout, but with the guard in place the script exits before reaching it. Hardening it is a separate change.
- **No pre-flight check at script start.** Tempting (it would save the LLM call) but it is a regression: a hand-merge that finishes while the ingest is still running currently produces a successful ingest, and a start-time check would kill it. The guard belongs at the moment of damage.
- **No "refuse if HEAD is detached" check.** It would catch the rebase case version-independently, but `rebase-merge`/`rebase-apply` already do, precisely — and a detached-HEAD check would also refuse in unrelated situations.
- **The concurrency model.** Unchanged; see Out of scope.
- **`--summary-only`, `--verbatim-only`, `--repo`, `--dry-run` paths.** `--dry-run` never reaches the auto-commit; the others all funnel through the same line 658 and inherit the guard unchanged.

## Acceptance criteria

**Verification split: all seven are offline.** Every property is exercisable in a throwaway wiki with no network and no real LLM, using the existing stub-CLI harness. Nothing here needs the Captain or a live drive; the live wiki is out of bounds for every stage. The one thing that does need the Captain is a scope decision, not an AC: whether `wiki-ingest-backfill` is fixed here (AC6) or split into its own item.

Every AC below was validated against a prototype guard held in a scratch copy of `bin/` — nothing in `bin/` or `tests/` was modified at this stage.

**AC1 — a merge in progress stops the ingest dead.** *(offline)* With `MERGE_HEAD` set and conflicted paths in `$WIKI_PATH`, `wiki-ingest-run` exits non-zero, `main`'s HEAD is unchanged, and no commit on `main` contains conflict markers.
Verified by: `tests/test-guard.sh` case 11. Fails if: `MERGE_HEAD` is removed from the `for st in …` list in `bin/wiki-ingest-run`.

**AC2 — the captain's in-progress merge survives untouched.** *(offline)* After AC1's run, `MERGE_HEAD` is still set, `git diff --diff-filter=U` still lists the conflicted path, and the working-tree file still contains its markers.
Verified by: `tests/test-guard.sh` case 11. Fails if: the guard is changed from `exit 1` to a warning that lets the run continue — `merge_with_retry`'s `git merge --abort` then reverts the hand-resolution.

**AC3 — a conflicted cherry-pick or rebase stops it too.** *(offline)* With `CHERRY_PICK_HEAD` set, or a stopped rebase (`rebase-merge/`), `wiki-ingest-run` exits non-zero having committed nothing to `main`.
Verified by: `tests/test-guard.sh` case 12. Fails if: `CHERRY_PICK_HEAD` / `rebase-merge` are dropped from the `for st in …` list.

**AC4 — conflict markers are refused even with no operation in progress.** *(offline)* With markers in a tracked file and no `MERGE_HEAD`, `wiki-ingest-run` exits non-zero, commits nothing, and leaves the index clean.
Verified by: `tests/test-guard.sh` case 13. Fails if: the marker-scan block is deleted. *(Confirmed to be a distinct hole: today's `bin/` commits those markers to `main` at exit 0 with no merge in progress anywhere.)*

**AC5 — the auto-commit still does its job.** *(offline)* With ordinary uncommitted local edits in `$WIKI_PATH` and no merge in progress, `wiki-ingest-run` exits 0, the `Auto-commit local changes before ingest merge` commit is present on `main`, and the edited files are tracked. A page whose body contains a markdown setext heading (`Title` over `=======`) is committed, not refused.
Verified by: `tests/test-guard.sh` case 14. Fails if: the marker regex is widened to the kata's `^(<<<<<<<|=======|>>>>>>>)` — the setext page is then rejected and a correct ingest fails.

**AC6 — `wiki-ingest-backfill` refuses the same states.** *(offline)* With a merge in progress in `$WIKI_PATH`, `wiki-ingest-backfill` exits non-zero without staging or committing anything, and `git diff --cached` shows no `raw/` path staged.
Verified by: `tests/test-guard.sh` case 15. Fails if: the guard is added to `wiki-ingest-run` only — `git add raw/` then stages the marker-laden file and marks it resolved.

**AC7 — no regression, and the scripts still run on stock macOS bash.** *(offline)* `tests/test-fetch.sh` and all pre-existing `tests/test-guard.sh` cases pass, and `/bin/bash -n` (3.2.57) accepts every script in `bin/`.
Verified by: `/bin/bash tests/test-guard.sh && /bin/bash tests/test-fetch.sh`, plus `for f in bin/*; do /bin/bash -n "$f"; done`. Fails if: the guard uses `mapfile`, an associative array, or `ls-files -u --format=` (git 2.38+).

## Test plan

**`tests/test-guard.sh` gains five cases (11-15).** It is the right home: it already bootstraps a throwaway wiki, stubs `WIKI_INGEST_CLI`, and asserts on exit code plus `head_subject()`. No new file is warranted, and `tests/test-fetch.sh` is fixture-based extraction only.

**The existing seed at `tests/test-guard.sh:86-95` must not be weakened.** The pre-existing `summary/` and `topic/` pages are what make the *other* guard's test meaningful (kata x04s), and the new cases have their own analogous trap: they must run against a wiki with real committed history, or `main`-HEAD-unchanged assertions prove nothing.

The mechanism for all five: **a `STUB_MODE` that leaves `$WIKI_PATH` mid-operation.** The stub LLM is invoked by `wiki-ingest-run` partway through the run, with the worktree as cwd, so it is the natural deterministic hook — `git -C "$WIKI_PATH" merge conflicting --no-edit` inside the stub reproduces the hand-merge-races-an-ingest timing with no sleeps and no flakiness. A one-time fixture block sets up a `conflicting` branch that conflicts on `topic/Context Graphs.md`.

| Case | Setup | Asserts | AC |
|---|---|---|---|
| 11 | `STUB_MODE=mid-merge` — stub merges `conflicting` into `main` | rc=1; stderr names `operation in progress`; `head_subject()` unchanged; `MERGE_HEAD` still set; `--diff-filter=U` non-empty; worktree file still has markers; no marker in any commit on `main` | AC1, AC2 |
| 12 | `STUB_MODE=mid-cherry-pick`, and again with a stopped rebase | rc=1; `head_subject()` unchanged | AC3 |
| 13 | Markers written into a tracked file, no merge started | rc=1; stderr names `conflict markers`; `head_subject()` unchanged; `git diff --cached --name-only` empty afterwards | AC4 |
| 14 | Ordinary uncommitted edit + a setext-heading page, clean repo | rc=0; `Auto-commit local changes` present in `git log main`; both files tracked on `main` | AC5 |
| 15 | Merge in progress, run `wiki-ingest-backfill` | rc≠0; nothing staged; `head_subject()` unchanged | AC6 |

Negative control, run once by hand at implementation and recorded in the implementation report rather than automated: revert the guard block, confirm cases 11-13 go red, restore it. The reproduction script above is the same control in standalone form — it returns exit 0 against unguarded `bin/` and exit 1 against guarded `bin/`.

Every case must use the sandbox `WIKI_PATH` the harness already creates. `WIKI_PATH` must never point at the real wiki.

## Out of scope

The concurrency model itself. Making ingests not race each other is `serialise-topic-page-merges` and, further out, kata `87sc`. This fix only stops the auto-commit from laundering a broken tree into main.

Also out of scope, and noted above rather than fixed here: `merge_with_retry`'s unconditional `git merge --abort` against a shared checkout, and the `2>/dev/null || true` fail-open idiom that appears throughout both scripts. The guard makes the specific `cntt` path fail closed; it does not audit that idiom generally.

## Stage Report: ideation

- DONE: A reproduction that actually fails, named as the exact command or scenario a fresh agent can re-run — not a description of one.
  `repro-cntt.sh` is embedded verbatim under **Problem → Reproduction**; extracted from this file and run under `/bin/bash` 3.2.57 it exits 0 (bug reproduced, markers on `main`, run rc=0) against today's `bin/`, and exits 1 against a guarded prototype.
- DONE: Each acceptance criterion's evidence lives outside this fix body, and names the concrete edit that would make it fail.
  AC1-AC6 cite `tests/test-guard.sh` cases 11-15; AC7 cites the two test scripts plus `/bin/bash -n`. Each carries a `Fails if:` naming the concrete edit (drop `MERGE_HEAD` from the state list; turn `exit 1` into a warning; delete the marker scan; widen the regex to the kata's `=======` form; guard `wiki-ingest-run` only; use `mapfile`/`ls-files --format=`).
- DONE: Each acceptance criterion declared offline or interactive before any harness is designed for it.
  All seven declared **offline** at the head of Acceptance criteria, with the reason (throwaway wiki, stub CLI, no network). The only interactive item is a scope decision for the Captain — backfill in scope or split — and it is explicitly not an AC.

### Summary

Confirmed the mechanism first-hand rather than trusting the report: `git add -A` marks conflicted paths resolved, so the following `git commit` concludes the captain's merge and commits the markers as a merge commit, exit 0. The reproduction lands markers in `topic/Context Graphs.md` on `main`, the same file as the 2026-08-06 incident.

All three checks the kata proposed are wrong as written, and each defect was reproduced: `rev-parse --git-dir` returns a *relative* path so that test silently never fires; `ls-files -u` is empty after `add -A` and also misses a merge whose resolutions are already staged; and `^=======` false-positives on markdown setext headings. Two further findings changed the design — the guard must `exit`, not skip (skipping reaches `merge_with_retry`'s `git merge --abort`, which was observed destroying a hand-resolution), and `wiki-ingest-backfill` reaches the same hazard by its own `commit_batch`, staging markers into the index and stealing merges. Cherry-pick and rebase both confirmed exposed, so they are in.

A prototype guard was validated in a scratch copy of `bin/` — it closes all three reproductions, preserves the captain's in-progress merge intact, keeps the auto-commit's legitimate purpose working, and leaves `test-guard.sh` and `test-fetch.sh` all-pass under bash 3.2. Nothing in `bin/` or `tests/` was modified at this stage.

## Stage Report: implementation

- DONE: Each new test case watched failing for the right reason BEFORE the guard is written, with the actual red output recorded in the stage report — not an assertion that it was red.
  Cases 11-15 were written and run against unguarded `bin/`. Verbatim red output:
  `FAIL: merge in progress stops the ingest — expected rc=1, got rc=0`
  `FAIL: mid-merge — main advanced to 'Merge branch 'ingest-1786110362-74882-28210''`
  `FAIL: mid-merge — MERGE_HEAD cleared; the captain's merge did not survive`
  `FAIL: mid-merge — no unmerged paths left; add -A marked them resolved`
  `FAIL: cherry-pick in progress stops the ingest — expected rc=1, got rc=0`
  `FAIL: mid-cherry-pick — conflict markers reached a commit on main`
  `FAIL: conflict markers are refused with no merge in progress — expected rc=1, got rc=0`
  `FAIL: markers-no-merge — conflict markers reached a commit on main`
  `FAIL: backfill refuses a merge in progress — expected rc!=0, got 0`
  `FAIL: backfill — main advanced to 'Backfill verbatim raw/ (batch through 0 ok / 0 queued)'`
  `FAIL: backfill — MERGE_HEAD cleared; the captain's merge did not survive`
- DONE: The negative control run by hand and recorded: revert the guard block, confirm cases 11-13 go red, restore it.
  `git checkout bd74a28~1 -- bin/wiki-ingest-run` (backfill guard left in place), re-ran: cases 11, 12 and 13 all red again with the same messages as above; case 14 stayed green (it must — it is the no-regression case) and case 15 stayed green (its guard was not reverted). Restored with `git checkout HEAD -- bin/wiki-ingest-run`; `git status` clean. The fix body's standalone `repro-cntt.sh` against guarded `bin/` prints `GUARD HELD: no conflict markers on main; run exited 1` and exits 1 — the outcome the fix body predicted.
- DONE: tests/test-guard.sh and tests/test-fetch.sh both pass under /bin/bash 3.2, with the pre-existing seed at tests/test-guard.sh:86-95 left intact.
  `/bin/bash tests/test-guard.sh` → `test-guard: ALL PASS`, exit 0 (16 assertions). `/bin/bash tests/test-fetch.sh` → `test-fetch: ALL PASS`, exit 0. `/bin/bash -n` clean over all five scripts in `bin/`. The seed block is byte-identical — `git diff main -- tests/test-guard.sh` contains no line touching it; it now sits at :119-128 only because the new stub modes were inserted above it.

Two further falsifications were run by hand to prove the green is not vacuous:

- Widen the marker regex to the kata's `^(<<<<<<<|=======|>>>>>>>)` → case 14 goes red exactly as AC5 predicts: `wiki-ingest-run: conflict markers in staged file(s) — refusing to auto-commit: topic/Setext Page.md`. The setext-heading page is what makes AC5 falsifiable.
- Drop `MERGE_HEAD` from the `for st in …` list → case 11's **rc stays 1**; it is the message assertion that catches it (`FAIL: mid-merge — wrong message: …`), because the unmerged-paths check is a second line of defence and fires instead. Worth knowing: AC1's stated falsification is not observable on exit code alone.

### Four places the approved design did not survive contact

Design changed in none of them — the guard is built exactly as approved. These are corrections to *test assertions* and to two factual claims in the fix body:

1. **AC6's literal assertion is unsatisfiable.** AC6 says `git diff --cached` must show no `raw/` path staged. Probed directly in a scratch repo: during *any* conflicted merge, `git diff --cached --name-only` lists the conflicted path whether or not anyone staged it — identical output before and after `git add raw/`. It cannot distinguish guarded from unguarded. Case 15 asserts on the index *stages* instead: `1 2 3` (conflict untouched) versus a lone `0` (`add raw/` marked it resolved). Same intent, actually falsifiable.
2. **Backfill's damage is worse than the fix body recorded.** The body predicted the commit would fail on a remaining unmerged path, leaving markers only in the index. With the conflict confined to `raw/`, `git add raw/` resolves everything it touches and the commit *succeeds*: observed `main` advancing to `Backfill verbatim raw/ (batch through 0 ok / 0 queued)` with `MERGE_HEAD` cleared — backfill concluded the captain's merge outright, same as `wiki-ingest-run`.
3. **The unguarded rebase case exits 1 already, for the wrong reason.** The body predicted fail-open with `INGESTED … pushed`. Observed instead: `MERGE FAILED after 5 attempts`, i.e. the run reaches `merge_with_retry` and its `git merge --abort` runs five times against the captain's stopped rebase. Same damage class, arguably worse. Case 12b therefore asserts on the guard's message, not on rc alone, which would have passed unguarded.
4. **Case 15 needs its own conflict branch.** Against unguarded `bin/`, case 11's ingest *concludes* the merge of `conflicting` into `main`, so by case 15 `git merge conflicting` is already up to date and conflicts with nothing — the case would have been green-by-vacuity in the red run. It now builds a fresh `conflicting-raw` branch. The fixture self-check that caught this (`FAIL: backfill fixture — no conflicted raw/ path, so the case proves nothing`) is kept in the test.

### Summary

Built the approved guard unchanged: the in-progress state scan (via `--absolute-git-dir`) and the unmerged-paths check before `git add -A`, the anchored marker scan between the add and the commit, all three exiting 1 rather than skipping; plus the same in-progress/unmerged block at the top of `wiki-ingest-backfill`'s `commit_batch`, returning 1 and breaking out of the fetch loop so the worklist temp file is still reaped. Committed as `bd74a28`.

Test-first was followed literally: cases 11-15 were written and watched failing against unguarded `bin/` before a line of guard was written, and the red output is quoted verbatim above rather than summarised. Two design claims turned out to be wrong on contact — AC6's `diff --cached` assertion cannot discriminate, and the unguarded rebase case already exits 1 via `merge_with_retry` — so both cases now assert on the guard's message and on index stages. Neither changes the approved design or the ACs' intent, but the validation stage should check assertion shape, not just exit codes.

Nothing here needed the Captain. `WIKI_PATH` pointed only at `mktemp -d` sandboxes throughout; the live wiki was never touched.

## Stage Report: validation

- DONE: Each of the seven acceptance criteria reproduced yourself, citing the command you ran and what came back — not the implementation's self-report.
  All seven PASS. Every falsifying edit was applied to a *scratch copy* of the tree (`git archive HEAD | tar -x`); the worktree itself was never modified.
  **AC1** — `/bin/bash tests/test-guard.sh` case 11 → `ok: merge in progress stops the ingest (rc=1)`, `main_subject()` unchanged, no marker-bearing commit reachable from `main`. Falsified by dropping `MERGE_HEAD` from the `for st` list → red (`FAIL: mid-merge — wrong message`), stderr showing the unmerged-paths check catching it instead; rc stays 1, exactly as the implementation warned.
  **AC2** — same case: `MERGE_HEAD` still present, `--diff-filter=U` still lists `raw/conflicted.md topic/Context Graphs.md`, worktree file still holds `<<<<<<< `. Falsified for real: a variant turning all three `exit 1`s into warnings that *skip* the auto-commit → `FAIL: … MERGE_HEAD cleared; the captain's merge did not survive` and `FAIL: … markers gone from the working-tree topic/Context Graphs.md`, main advanced to `Ingest: …`. Exit-not-skip is load-bearing, and now measured rather than argued.
  **AC3** — cases 12 and 12b → `ok (rc=1)` both, stderr naming `rebase-merge`. Falsified by cutting the list to `MERGE_HEAD REVERT_HEAD` → both red on the message assertion.
  **AC4** — case 13 → `ok (rc=1)`, `conflict markers` in stderr, `diff --cached --name-only` empty afterwards. Falsified by deleting the marker-scan block → fully red, including `FAIL: markers-no-merge — conflict markers reached a commit on main`.
  **AC5** — case 14 → `ok (rc=0)`, `Auto-commit local changes before ingest merge` on `main`, `topic/Setext Page.md` tracked with its `=======` intact. Falsified by widening the regex to `^(<<<<<<<|=======|>>>>>>>)` → four red assertions, the setext page rejected. The over-firing counterweight holds.
  **AC6** — case 15 → `ok (rc=1)`, index stages `1 2 3` (conflict untouched), `MERGE_HEAD` alive. Falsified by restoring pre-fix `wiki-ingest-backfill` → five red, `stages are [0 ]`, main advanced to `Backfill verbatim raw/ …`.
  **AC7** — `/bin/bash --version` → `3.2.57(1)-release`; `for f in bin/*; do /bin/bash -n "$f"; done` → 5/5 clean; both suites green (below).
  End-to-end: `repro-cntt.sh` extracted verbatim from this file (lines 91-146) prints `BUG REPRODUCED … exited 0` against merge-base `bin/` and `GUARD HELD … exited 1` against HEAD — the fix body's own claim, reproduced.
- DONE: The negative case exercised: revert the guard block, confirm cases 11-13 go red, restore it — and check each case's assertion SHAPE, since the implementation found two cases that pass unguarded on exit code alone.
  HEAD's `tests/` against merge-base `bin/`: cases 11, 12, 12b, 13 and 15 red (16 `FAIL` lines), case 14 green as it must be. Shape checked per case by asking what single edit would pass while the bug is present: 11, 13, 14 and 15 assert on-disk damage directly and cannot be faked. 12 and 12b discriminate on the guard's message alone — confirmed independently: unguarded, `main` never moves during a rebase and the run already exits 1 via `MERGE FAILED after 5 attempts`. Case 15's fixture self-check verified live by breaking the fixture → `FAIL: backfill fixture — no conflicted raw/ path, so the case proves nothing` fires.
- DONE: Both tests/test-guard.sh and tests/test-fetch.sh run under /bin/bash 3.2, with the pre-existing seed confirmed byte-unchanged.
  `test-guard: ALL PASS` (16 assertions, exit 0) and `test-fetch: ALL PASS` (exit 0). Seed: the old file's lines 86-95 are byte-identical at 119-128, and a line-level diff shows **zero** lines removed from `test-guard.sh` — the change is purely additive. Substantive diff vs merge-base is exactly `bin/wiki-ingest-run` (+48), `bin/wiki-ingest-backfill` (+34/-3), `tests/test-guard.sh` (+213) and this file; the `docs/bug-fixes/` deletions visible in `main..HEAD` are branch divergence. `WIKI_PATH` was a `mktemp -d` sandbox throughout — `tests/test-guard.sh:20` exports it unconditionally — and the live wiki is untouched (HEAD `457f657`, 0 dirty paths, read-only inspection only).

### Findings — triaged, none material, none fixed

1. **Deferred risk — the marker scan fails open on non-ASCII paths.** `git diff --cached --name-only` C-quotes them under the default `core.quotePath`, so the loop's `git show ":$p"` fails into `2>/dev/null`. Reproduced: three staged files all carrying `<<<<<<< `, `MARKED` contained only `topic/Plain Name.md` while `"topic/Caf\303\251 Culture.md"` and `"topic/M\304\201ori Language.md"` were skipped. Affects AC4 only — the in-progress and unmerged checks are path-agnostic. Not material today: the live wiki has 0 of 2889 tracked paths with a non-ASCII byte. Promote to material on the first such page title. One-token fix, verified working: `git -C "$WIKI" -c core.quotePath=false diff --cached --name-only`.
2. **Polish — cases 12/12b assert the message, not the damage.** Probed the unguarded rebase directly: the rebase survives, but `add -A` empties its unmerged paths, so a later `rebase --continue` would commit the markers; guarded, `topic/CG.md` stays unmerged. A `--diff-filter=U` non-empty assertion on 12/12b would encode the harm rather than the wording. The cases do discriminate as written.
3. **Polish — AC1/AC3's `Fails if:` text overstates observability.** Dropping a state from the list leaves rc=1 in *all three* of cases 11, 12 and 12b, not just the two the implementation recorded — the unmerged-paths check is the second line of defence in every one.

Confirmations, not findings: `git reset --quiet` does clear `MERGE_HEAD` (probed directly), but it is unreachable while `MERGE_HEAD` is set because the in-progress check exits first — the code comment's claim holds. And backfill's new hard `exit 1` on `commit_batch` failure was checked for regression on the happy path: a clean wiki with an empty worklist, and one with a pending `raw/` file, both give `BACKFILL DONE` and exit 0, identical to pre-fix.

### Summary

Recommend **PASSED**. All seven ACs were reproduced independently and all seven falsifying edits produce red, including the two the implementation honestly flagged as message-only discriminators — both confirmed to behave exactly as reported. The load-bearing design claim, that fail-closed means `exit` and not skip, is now measured: the skip variant destroys the captain's merge and its hand-resolved working tree, which is precisely the damage AC2 exists to prevent.

Three findings recorded, none material, none fixed: one deferred-risk hole in the belt-and-braces scan that the live wiki cannot currently trigger, and two test/AC-text hardening notes. Disposition is the first officer's call; none of them blocks the fix. Nothing here needed the Captain — `WIKI_PATH` pointed only at `mktemp -d` sandboxes, and the live wiki was inspected read-only and is unchanged.
