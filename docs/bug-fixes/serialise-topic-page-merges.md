---
id: ghyj7yz18wnypbvkfa84vq0f
title: Stop concurrent ingests conflicting on shared topic pages (interim mitigation)
status: ideation
source: kata:87sc (interim mitigation only)
started: 2026-08-07T14:28:25Z
completed:
verdict:
score: 0.7
worktree:
issue:
pr:
mod-block:
gates:
    version: 1
    records:
        - id: gate:ghyj7yz18wnypbvkfa84vq0f:backlog
          stage: backlog
          attempts:
            - id: gate-attempt:ghyj7yz18wnypbvkfa84vq0f-backlog-1
              briefing:
                id: briefing:ghyj7yz18wnypbvkfa84vq0f:backlog:attempt-1:revision-1
                digest: sha256:3581e8324ed6d9c07aee0a50033fbcbb11cea03961972820ab78aad07f7589b9
                request-digest: sha256:49f9da933b74739ceb7e1df3baf6ced9008912ebaf6722a45a9983f28ae98e29
                room-ref: ./serialise-topic-page-merges/review/backlog/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:ghyj7yz18wnypbvkfa84vq0f:backlog:1
                briefing: briefing:ghyj7yz18wnypbvkfa84vq0f:backlog:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T14:28:25.323741Z"
                decision: approve
                reason: 'Hardest failure evidence in the backlog: 6 of 37 URLs (16%) in one batch, every failure a deterministic content conflict on a topic/ page, which the 5x retry loop structurally cannot fix. Scoped as the Captain''s own named interim measure with the SQLite rearchitecture explicitly out of scope and staying open in 87sc. Sequenced last on purpose so it designs against a settled bin/wiki-ingest-run now that cntt''s guard has merged, avoiding the moving-target error the FO made in the pxf4 brief. Risk flagged forward: keep-both-sides is only obviously correct for additive edits, and six-for-six is a small sample. Captain delegated gate decisions in-conversation.'
              application:
                target-stage: ideation
                state: consumed
        - id: gate:ghyj7yz18wnypbvkfa84vq0f:ideation
          stage: ideation
          attempts:
            - id: gate-attempt:ghyj7yz18wnypbvkfa84vq0f-ideation-1
              briefing:
                id: briefing:ghyj7yz18wnypbvkfa84vq0f:ideation:attempt-1:revision-1
                digest: sha256:3d6281bc5f37e771041dd8def856f8f62463b0b8adef657716b4184b85b3d989
                request-digest: sha256:defbb657fb0edc1e71e1930f36d90261fceae537edea1ae9f920d828c8cd76dd
                room-ref: ./serialise-topic-page-merges/review/ideation/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:ghyj7yz18wnypbvkfa84vq0f:ideation:1
                briefing: briefing:ghyj7yz18wnypbvkfa84vq0f:ideation:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T14:55:14.720318Z"
                decision: approve
                reason: 'Measured the backlog''s premise and falsified it: 11 real topic/ conflicts since 2026-08-05, not 6, with 4 non-additive. Both proposed remedies falsified against that corpus — a lock prevents 0 of 11 (repro''s merges are perfectly serialised and still conflict), unbounded merge=union is silently wrong on 4. Bounded union scores 7 auto-resolved / 4 kept loud / 0 silently wrong, including producing clean text where the cntt incident commit shipped markers. Retry classification corrected to exit-code-only after the first draft rule was shown wrong on a shared index, and a live hazard found in merge_with_retry''s unconditional abort destroying a peer''s merge state. Scope holds to the Captain''s own named interim measure; rearchitecture, prompt changes and synthesis re-runs all excluded on the record. FO approves implementation and validation ONLY: this will NOT be merged without the Captain, because it rewrites the merge critical section of a scheduled tool, AC6 and AC7 are both interactive and cannot be satisfied in his absence, and the design deliberately reserves a bounded-rule-vs-one-liner choice to him. Implementation held until pxf4 merges per the test plan''s own sequencing.'
              application:
                target-stage: implementation
                state: pending
---

## Problem

Concurrent ingests routinely conflict on the same `topic/` page. Evidence from the 2026-08-06 batch: 37 URLs in parallel produced 6 merge failures (16%), every one a content conflict on a topic page — Context Graphs, Guardrails and Feedback Loops (twice), Agent Memory and Context, Loop Engineering, Security and Sandboxing.

The pattern is the racing-peers problem. `index.md` and `log.md` survive because they carry `merge=union`; `topic/` pages have no such driver, and concurrent ingests routinely append a paragraph or list item to the same popular page. The busier the topic, the likelier the collision — Guardrails and Feedback Loops was hit twice in one batch.

The existing 5x retry loop cannot help. The conflict is deterministic, so retrying the same merge five times just delays the failure. Retry is the right remedy for lock contention and the wrong one for content conflict, and the two cases are not currently distinguished.

**Correction from measurement (ideation).** The claim above that all six resolved as "keep both sides" does not survive contact with the wiki's own history. Replaying every merge commit in the wiki from 2026-08-05 onward and re-running each one's three-way merge finds **11 genuine content conflicts on `topic/` pages** (43 files were touched by both sides; 32 of those auto-merged cleanly and never conflicted). Of the 11:

- **7 were purely additive** — both sides inserted a new paragraph at the same anchor, neither touched a base line.
- **3 were genuine revisions of the same line.** `topic/Software Engineering Craft.md` (merge `6b1ef45`) is the clearest: one side rewrote "Four pages form a cluster" to "Five", the other to "Six", and both rewrote "the wiki has 197 pages and only 4 cover C#/.NET". The human resolution was neither side — it was "Six pages" and "Seven of the wiki's ~990 topic pages". No mechanical rule reaches that answer.
- **1 was an add/add**: two ingests both created `topic/Cloudflare OS.md` from scratch (merge `29a9ec0`).

One further finding, incidental but worth recording: merge `a60c1d8` shipped `<<<<<<< HEAD` / `=======` / `>>>>>>>` markers into `topic/Context Graphs.md` on main. They were cleaned up the same day by `26e2375` ("Resolve conflict markers committed into topic/Context Graphs.md"). That is the `cntt` failure caught in the wild; `cntt`'s guard now prevents it. No conflict markers are present in the wiki today.

## Proposed approach

This entity is the **interim mitigation only**, not the full rearchitecture. Kata `87sc` proposes flipping the execution model to a single SQLite-orchestrated process; that remains open and is not in this workflow's scope. Nat's own comment on `87sc` names the cheaper fix, and that is what this covers:

- give `topic/` pages a union-ish merge driver, so additive edits in the same slot merge instead of conflicting; **or**
- serialise just the merge step behind a lock, keeping fetch and analysis parallel so the expensive stages stay concurrent.

A likely third component regardless of which is chosen: distinguish content conflict from lock contention so the retry loop stops burning five attempts on a deterministic failure.

Ideation's answer to that choice is below, and it is not a clean pick of either: (b) does not address the defect at all, and (a) as usually written is unsafe. What is recommended is (a) bounded by a safety test, with a lock the bounded form needs for its own reasons.

### Option (b) does not fix this defect. Not "costs too much" — does not fix it.

The conflict is a three-way merge between two branches from a common base. A lock changes *when* the second merge runs, not *what* it merges. The reproduction below (`repro/repro-topic-conflict.sh`) is the proof: ingest A runs to completion and merges to main **before** ingest B's merge starts. The merges are perfectly serialised, there is zero lock contention, and B still conflicts, deterministically, on every run. Serialisation would have prevented 0 of the 11 observed conflicts.

Cost was never the problem, and for the record it is negligible: replaying 8 real ingest merges against a full-size clone of the wiki (991 topic pages, 11.6 MiB pack) gives a mean merge of **172 ms** (max 333 ms), against a measured LLM stage of **median 267 s, p90 322 s** across the 29 ingests of the 2026-08-06 batch. Serialising all 37 merges of that batch costs 6.4 s at the mean and 12.3 s at the worst-case max — under 1% of its ~1472 s wallclock. The expensive-stages-stay-parallel claim is true. It is just answering a question nobody needed answered.

### Option (a), unbounded, is not safe. Measured, not assumed.

`printf 'topic/*.md merge=union\n' >> .gitattributes` is one line and it does resolve the conflict — the reproduction passes with `UNION=1`. But replaying the union driver against all 11 real conflicts and diffing its output against what the human actually committed:

| outcome | n | what union produces |
|---|---|---|
| byte-identical to the human resolution | 1 | correct |
| differs by one missing blank line | 5 | both paragraphs land on adjacent lines, so markdown renders them as one run-on paragraph. Content preserved, silently ugly. |
| **silently duplicates a paragraph** | 3 | e.g. `Software Engineering Craft`: "Five pages form a cluster…" and "Six pages form a cluster…" both committed, adjacent and contradictory. Exit 0. Pushed. |
| **silently duplicates an entire page** | 1 | the `Cloudflare OS` add/add: 73 lines of the second page's body interleaved into the first, `## Analysis` heading and all. |

So unbounded union is silently wrong on **4 of 11** and cosmetically wrong on another 5. It never loses text, but on a 991-page wiki that Nat reads and trusts, "never loses text" is not the bar. It converts a loud, recoverable failure into a quiet, undetectable one. That is a serious mark against it and it is the reason this design does not take it.

## Recommendation: bounded union, plus a lock the bounded rule needs

**Primary — auto-resolve a `topic/` conflict only where union is provably safe.** After a failed `git merge`, for each conflicted path under `topic/`, read the three index stages (`git show :1:` base, `:2:` ours, `:3:` theirs) and auto-resolve **iff both** hold:

1. **The path exists in the merge base** (stage 1 present). An add/add is two ingests writing the same page from nothing; there is no shared structure to union and no way to tell which is right.
2. **Every conflict hunk has an empty base section** — i.e. both sides only *added* lines; neither revised or deleted a base line. Run `git merge-file --diff3 -p` over the three stages and check the `|||||||`→`=======` region of every hunk is blank.

Resolution is ours-block then theirs-block, **with a blank line inserted between them** when neither side supplies one. That separator is not cosmetic: it is the difference between two paragraphs and one run-on paragraph, and it is what makes the output match the human's.

Anything failing either test is left exactly as today: abort, keep the branch, exit 1, tell the human. No silent anything.

**Measured against the same 11 real conflicts** (`repro/bounded-union-audit.py`):

| outcome | n | detail |
|---|---|---|
| auto-resolved, byte-identical to the human | 5 | The Oracle Is the Asset; Loop Engineering; Agent Memory and Context; Guardrails and Feedback Loops; Context Graphs |
| auto-resolved, differs by one blank line only | 1 | `a79a53c` — non-blank lines identical to the human's |
| auto-resolved, **better** than what shipped | 1 | `a60c1d8` — the human commit shipped conflict markers; the rule produces clean text |
| kept as today's loud failure | 4 | the 3 same-line revisions + the 1 add/add |
| **silently wrong** | **0** | — |

That is a 64% cut in hand merges with no corruption path. The remaining 4 are exactly the cases that need judgement a merge driver cannot have.

**Secondary — classify the failure instead of retrying it.** `merge_with_retry` currently burns 5 attempts and 12 s of `sleep 3` on a deterministic conflict (visible in the reproduction's output: the same CONFLICT message five times). Classify **on the exit code, and only the exit code**:

- `git merge` exits **1** → this process's merge ran and conflicted. Do not retry; try the bounded resolve, then fail.
- exits **128** → the merge never started (index.lock held, or a peer left unmerged files in the shared index). Retry with backoff — this is what the loop was for — and do **not** abort.

Both codes were observed directly, and the first draft of this rule was wrong in a way worth recording: "are there unmerged paths?" looked like a good second signal and is not. `$WIKI` has one index shared by every concurrent ingest, so a peer's conflict makes `git diff --diff-filter=U` non-empty for a process whose own merge never ran. `repro/cross-abort-demo.sh` prints exactly that (`peer Y's merge exit=128`, unmerged paths present and belonging to X). The exit code is the only signal that is about *this* process.

That same demo shows the related hazard: `merge_with_retry` calls `git merge --abort` unconditionally (`bin/wiki-ingest-run:214`), so when a peer holds a conflicted merge, this ingest's failed-to-start merge aborts it and **destroys the peer's merge state**. Abort only on exit 1.

**Enabling — a mutex around the merge critical section.** Not because serialising fixes the defect (it does not), but because the bounded resolve *writes to the shared `$WIKI` working tree*, and two peers doing that concurrently is strictly worse than two peers merging. `flock` is not present on macOS (checked: `command -v flock` → absent); use an atomic `mkdir` mutex with a PID/age staleness sweep. The critical section is `cntt`'s in-progress guard → `add -A` → marker scan → auto-commit → merge → resolve → commit. `git push` stays **outside** it: push failure is already tolerated (`PUSH_STATUS=push-failed`) and network latency has no business inside a mutex.

Interaction with `cntt`'s guard (`bin/wiki-ingest-run:657-681`): unchanged and still upstream. Today it can fire on a *peer's* transient conflict — MERGE_HEAD is held ~170 ms per attempt, ~850 ms per conflicting ingest — turning one ingest's conflict into another's failure. Under the mutex a peer can never be mid-merge when the guard runs, so the guard fires only on a real human hand-merge, which is what it is for. The guard is not weakened or moved.

### What this deliberately leaves alone

The LLM prompts (unchanged — the "minimal, additive" synthesis instruction already does real work here). The worktree-per-ingest model. `merge=union` on `index.md`/`log.md`. The completeness guard. `cntt`'s in-progress guard. The dup-check. The 0/2/3/64 exit-code contract. And **`.gitattributes` gains nothing** — no `topic/*.md merge=union` line, deliberately. (Incidentally `wiki-ingest-setup:44` only writes `.gitattributes` when absent, so that route would not have reached the live wiki without a separate line-level append anyway.)

### The honest limit

This cannot be made *fully* correct without the rearchitecture, and it should not be sold as if it can. "Six pages" and "Seven of the wiki's ~990 topic pages" are semantic reconciliations; reaching them requires re-running synthesis against the new main, which means an LLM in the merge loop, which is `87sc`. What this fix does is make the machine handle the ~64% it can handle *safely*, and hand the rest to a human with the branch intact — instead of today's choice between 11 hand merges and 4 silent corruptions. If the Captain would rather have the one-line `.gitattributes` change and accept the 4-in-11 silent-duplication rate, that is a legitimate call, and the numbers above are what it costs.

## Reproduction

Committed, self-contained, offline, and deterministic — run three times, identical result each time:

    BIN=/Users/gnat/Source/Powerups/powerups-wiki-ingest/bin \
      docs/bug-fixes/serialise-topic-page-merges/repro/repro-topic-conflict.sh

Today it prints `REPRODUCED: ingest B failed to merge (exit 1)` and exits 0 (0 = bug present). Its output shows the five identical `CONFLICT (content): Merge conflict in topic/Shared Topic.md` lines, `MERGE FAILED after 5 attempts`, one of the two synthesis paragraphs on main instead of two, and the losing branch kept.

**How it is deterministic without real concurrency.** No network, no LLM, no `sleep`, no racing. `WIKI_PATH` is a fresh `mktemp -d`. Ingest B's stub CLI (`stub-beta.sh`) writes its outputs and then invokes ingest A *synchronously* — the "stub LLM as a timing hook" pattern the other entities used. A merges to main while B is still mid-flight, leaving B's worktree base stale by exactly one merge: the branch topology two parallel ingests produce, forced rather than raced. `UNION=1` on the same script exercises the unbounded-union variant (it passes, with the two paragraphs run together on one line — the 5-of-11 failure mode, reproduced).

**Fixture cost, scoped honestly:** ~110 lines across three files, already written and run. It reuses `--content` to bypass `trafilatura`, so nothing is fetched. It takes ~16 s today (the 5×`sleep 3` retry loop) and ~1 s once the retry loop stops retrying deterministic failures. This was the entity's biggest unknown; it is now a known ~110 lines.

`repro/bounded-union-audit.py` is the second artifact: it replays every merge in the live wiki since 2026-08-05 and reports what each rule would have produced. Read-only against the wiki, but it needs Nat's wiki present, so it is declared **interactive** below.

## Acceptance criteria

**AC1 (offline).** Two ingests whose worktrees branch from different points, both inserting a new paragraph at the same anchor of a pre-existing `topic/` page, both land on main — separated by a blank line, with no hand resolution and no conflict markers committed.
*Verified by:* new case in `tests/test-guard.sh`, asserting two `New from ` paragraphs on the shared page with a blank line between them and `git grep -E '^(<<<<<<<|>>>>>>>) ' HEAD` empty. *Concrete failing edit:* drop the blank-line insertion from the resolver → the paragraphs land adjacent → the separator assertion fails.

**AC2 (offline).** Two ingests that both **revise the same existing line** still fail loudly: exit 1, branch kept, main's copy of that page unchanged, no markers committed.
*Verified by:* new case in `tests/test-guard.sh` (both stubs rewrite the same "Four pages form a cluster" line to different values). *Concrete failing edit:* remove the empty-base-section test, i.e. degrade the rule to unbounded union → the run exits 0 and main gets both contradictory sentences → the "main unchanged" assertion fails. This is the case that stops a later agent "simplifying" the rule into `merge=union`.

**AC3 (offline).** Two ingests that both **create the same `topic/<Title>.md`** still fail loudly; add/add is never auto-resolved.
*Verified by:* new case in `tests/test-guard.sh`. *Concrete failing edit:* remove the stage-1-present test → the page is committed containing both bodies → the assertion that main's page has exactly one `# ` heading fails.

**AC4 (offline).** A merge that fails from contention is retried; a merge that fails from an unresolvable content conflict is not.
*Verified by:* new cases in `tests/test-guard.sh` — AC2's run must report exactly one merge attempt, and a run with `$WIKI/.git/index.lock` planted must report the contention classification and exhaust its retries. *Concrete failing edit:* restore the unconditional 5× loop → AC2's attempt-count assertion fails.

**AC5 (offline).** Two ingests cannot be inside the merge critical section at once.
*Verified by:* new case in `tests/test-guard.sh` — pre-create the mutex directory, run an ingest, assert it does not merge and reports the lock. *Concrete failing edit:* remove the mutex acquisition → the ingest merges immediately → the assertion fails.

**AC6 (interactive — needs Nat's wiki).** Against the wiki's real history since 2026-08-05, the bounded rule auto-resolves no conflict the human had to reconcile semantically, and every conflict it does auto-resolve matches or improves on what shipped.
*Verified by:* `repro/bounded-union-audit.py`. Current reading: 7 auto-resolved (5 byte-identical, 1 differing only in blank lines, 1 better than a commit that shipped conflict markers), 4 kept as loud failures, 0 silently wrong. *Concrete failing edit:* remove the empty-base-section test → `topic/Software Engineering Craft.md` flips to auto-resolved with the contradictory "Five pages"/"Six pages" duplicate.

**AC7 (interactive — Captain only).** A real batch of ~30 concurrent URLs against the live wiki needs no hand merge for additive conflicts, and every loud failure it does produce is a genuine same-line revision or a title collision. Not automatable; this is the Captain's drive.

## Test plan

All offline cases go in **`tests/test-guard.sh`**, not a new file. It already owns the machinery: a throwaway `WIKI_PATH`, a stubbed `WIKI_INGEST_CLI` with a `STUB_MODE` switch, and — load-bearing here — the pre-existing `summary/`+`topic/` seed block, which is exactly the populated-wiki condition these cases need. The seed block is not touched.

Two mechanics the new cases need and the existing ones do not:

- **A nested-ingest stub mode.** A new `STUB_MODE` arm that invokes `wiki-ingest-run` for a second URL before returning, per the reproduction above. This is the only new fixture concept.
- **Attempt counting.** AC4 needs the merge attempt count observable; counting `CONFLICT (content)` occurrences in captured stderr is enough and needs no new instrumentation.

**Implementation notes for bash 3.2.** The diff3 parse and the resolution write are one `awk` pass over `git merge-file --diff3 -p` output — no arrays, no `mapfile`, no negative indexing, and it sidesteps shell string-accumulation entirely. Conflicted paths must be read with `git -c core.quotePath=false diff --name-only --diff-filter=U -z`: ~80 of the wiki's 991 topic filenames contain an em-dash, and this is the exact trap `cntt` documented at `bin/wiki-ingest-run:691-694`. `git check-attr` and `git merge-file` were both verified against a `topic/Shared — Topic.md` fixture with a space and an em-dash.

**Merge order with `pxf4`.** `spacedock-ensign/slug-collision-on-shared-path-segment` adds 210 lines to `tests/test-guard.sh` — a new `STUB_MODE` arm around line 84-99, a `cleanup_all` trap change around line 36, and a 179-line block appended at the end. All three are where these cases land, so a textual conflict is near-certain. `pxf4`'s 138 lines in `bin/wiki-ingest-run` are confined to the slug/URL region (lines 18-380) and touch neither `merge_with_retry` nor the commit/merge path, so the script itself is disjoint. **Implementation should rebase onto `pxf4` after it merges rather than develop in parallel** — this fix is about merge conflicts and should not create one.

## Out of scope

The full single-writer SQLite orchestrator from `87sc`. That issue stays open in kata after this fix lands; this is the band-aid Nat asked for if `87sc` is a way off, and the fix body should say so plainly so nobody later mistakes it for the rearchitecture.

Also out of scope, and named so nobody adds them under cover of this fix:

- **Any change to the LLM prompts**, including a per-ingest "Related" append-only section. The 2026-07-05 archival-layer spec floats that as a future hardening; it changes what the LLM writes, which is a content-model change, not a merge fix.
- **Re-running synthesis against the new main after a conflict.** This is the only thing that reaches the semantically correct answer, and it puts an LLM in the merge loop. That is `87sc`.
- **Blanket `topic/*.md merge=union` in `.gitattributes`.** Considered, measured, rejected above. Recorded here so the rejection is on the record rather than rediscovered.
- **The 4-in-11 residue.** Same-line revisions and title collisions still stop and ask a human. That is the design, not a gap in it.

## Stage Report: ideation

- DONE: A reproduction that actually fails, named as the exact command or scenario a fresh agent can re-run — two concurrent ingests appending to the same topic page, conflicting deterministically.
  `BIN=<plugin>/bin docs/bug-fixes/serialise-topic-page-merges/repro/repro-topic-conflict.sh` — run 5×, identical each time; nested stub CLI as timing hook, so no real concurrency, no sleeps, no network, no LLM.
- DONE: A recommendation between a union-ish merge driver and serialising the merge step, with the non-additive case — two ingests revising the same sentence — stated explicitly rather than assumed away.
  Recommends union bounded by a present-in-base + empty-base-section test; the non-additive case is `topic/Software Engineering Craft.md` (merge `6b1ef45`, "Five pages"/"Six pages"), shown to be silently duplicated by unbounded union and correctly refused by the bounded rule.
- DONE: Each acceptance criterion's evidence external to this fix body, naming the concrete edit that would make it fail, and declared offline or interactive.
  AC1-AC5 offline (new cases in `tests/test-guard.sh`), AC6-AC7 interactive; each carries a *Concrete failing edit:* clause.

### Summary

The backlog's premise did not survive measurement. Replaying every merge in the live wiki since 2026-08-05 finds 11 genuine `topic/` content conflicts, not 6, and 4 of them are non-additive — three same-line revisions and one add/add. Simulating both proposed remedies against those 11: a lock prevents 0 of them (the reproduction proves why — its merges are perfectly serialised and it still conflicts), and unbounded `merge=union` is silently wrong on 4, including one that commits two contradictory sentences and one that duplicates 73 lines of a page.

The recommendation is union bounded by two tests — the path must exist in the merge base, and every conflict hunk must have an empty base section — plus a blank-line separator between the two added blocks. Measured on the same 11: 7 auto-resolved (5 byte-identical to the human, 1 differing only in blank lines, 1 strictly better than a commit that shipped conflict markers), 4 kept as today's loud failure, 0 silently wrong. A `mkdir` mutex is recommended alongside, not to fix the defect but because the resolver writes to the shared checkout; `flock` is absent on macOS.

Two things worth the Captain's eye. First, drafting the retry classifier surfaced a wrong assumption of my own: "are there unmerged paths?" is not a safe signal, because `$WIKI` has one index shared by every ingest — only the exit code (1 vs 128) is about this process. `repro/cross-abort-demo.sh` shows it, and shows the related hazard that `merge_with_retry`'s unconditional `git merge --abort` destroys a peer's in-progress merge. Second, this fix cannot be made fully correct: "Six pages" is a semantic reconciliation only an LLM re-run can reach, which is `87sc`. The honest claim is a 64% cut in hand merges with no corruption path, not a fix.
