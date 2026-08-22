---
id: 6a5wjaf19gdem9ca30m9b0cc
title: Worktree-cleanup self-exclusion guard never fires on macOS (/tmp and $TMPDIR are symlinks)
status: backlog
source: kata:1dvt
started:
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
                state: pending
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

Affected call sites:

- `tests/test-guard.sh:25`
- `tests/test-compile.sh:56`
- `docs/bug-fixes/serialise-topic-page-merges/repro/repro-topic-conflict.sh:20`

**Damage.** In the two test suites the failure is currently invisible: the loop
calls `git worktree remove --force` on the sandbox's own main worktree, git
refuses, and `|| true` swallows it; `rm -rf "$SANDBOX"` then cleans up anyway.
So the guard is dead code that has never protected anything — it is fail-safe
only because git happens to refuse. Removing the `|| true`, or reaching a case
with a genuine sibling worktree that must be kept, turns it into a real fault.

In the repro script the same defect is already visible: it has no `|| true`, so
the failed removal aborts the `EXIT` trap under `set -e` and the script exits
**128**. The entity documents it as exiting 0. Anyone wiring that repro into CI
sees a false failure.

**Why now.** It is three instances of one mistake, the fix is one line per site,
and the currently-benign cases are benign by accident rather than by design.

## Proposed approach

Resolve the sandbox path once, at creation, so both sides of the comparison are
in the same form:

    SANDBOX=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wiki-...-test.XXXXXX")" && pwd -P)

`pwd -P` collapses the symlink and the double slash together. Apply at all three
sites. Do not resolve at comparison time in the loop — one canonical value at
creation is the narrower change and cannot drift between uses.

Do not remove the `|| true` in the test suites as part of this fix; that is a
separate decision about how loudly cleanup should fail.

## Acceptance criteria

**AC-1 — The self-exclusion guard actually skips the main worktree.**
The `continue` branch is reached on macOS, rather than being reached-never and
covered by git's refusal.
Verified by: a case that creates a sandbox wiki plus one real sibling worktree,
runs the cleanup loop, and asserts the sibling was removed while the main
worktree was never passed to `worktree remove` (assert on a traced/logged call
list, not on the end state — the end state is identical either way today, which
is exactly why this bug survived).
*Concrete failing edit:* revert the `pwd -P` at creation; the main worktree is
passed to `worktree remove` again and the assertion goes red.

**AC-2 — The repro exits 0, as its own documentation claims.**
`docs/bug-fixes/serialise-topic-page-merges/repro/repro-topic-conflict.sh`
prints `REPRODUCED: ingest B failed to merge (exit 1)` **and** exits 0.
Verified by: running it from the repo root with no `BIN` set and checking `$?`
is 0. Today it prints the line and exits 128.
*Concrete failing edit:* revert the `pwd -P`; exit returns to 128.

**AC-3 — Both suites still pass, and leave nothing behind.**
`tests/test-guard.sh` and `tests/test-compile.sh` end green, and no
`wiki-*-test.*` directory survives under `$TMPDIR`.
Verified by: running both suites and listing `$TMPDIR` afterwards.
*Concrete failing edit:* break the `SANDBOX` assignment so it is empty; `rm -rf`
cleans the wrong path and the leftover check goes red.

## Test plan

`tests/test-guard.sh` gains the AC-1 case; it already builds sandbox wikis and
worktrees, so the fixture cost is small. The red run must be watched before the
fix — this is a bug whose end state is identical whether or not the guard works,
so a case written after the fix would pass for the wrong reason and prove
nothing. Assert on which paths the loop *attempts to remove*, not on what is
left on disk.

AC-2 needs no new script: it is the exit code of an existing committed repro.

## Out of scope

- Whether cleanup should fail loudly (the `|| true`) — separate decision.
- The superseded bounded-union design itself; this only touches its repro's
  path handling.
- Any non-macOS behaviour. On Linux the comparison already matches; the fix
  must not regress that, but no new Linux-specific coverage is required.
