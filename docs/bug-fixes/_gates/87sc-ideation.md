# Ideation gate — serialise-topic-page-merges

**Entity:** `serialise-topic-page-merges` (`gh`) · **Stage:** `ideation` → `implementation`
**Source:** kata `87sc`, interim mitigation · **Score:** 0.7

## Question

Is this still the interim mitigation, and does it build tonight?

## The backlog's premise did not survive measurement

This is the headline, and it invalidates part of what both the kata issue and this gate's own backlog review asserted.

Replaying every merge in the live wiki since 2026-08-05 finds **11** genuine `topic/` content conflicts, not the 6 recorded. And **4 of the 11 are non-additive** — three same-line revisions and one add/add. The "all six resolved by hand as keep-both-sides" observation, which this workflow's backlog gate treated as the design's foundation, was a partial sample. The six-for-six generalisation I flagged as a risk turned out to be exactly the wrong generalisation.

## Both proposed remedies were falsified against those 11

**Option (b) — serialise the merge — does not fix the defect.** Not "costs too much": *does not fix it*. The conflict is a three-way merge from a common base; a lock changes **when** the second merge runs, not **what** it merges. The committed reproduction proves it — ingest A completes and merges to main *before* B's merge starts, there is zero lock contention, and B still conflicts deterministically on every run. **Serialisation would have prevented 0 of the 11.**

For the record, the cost was never the issue either: 172 ms mean merge (max 333 ms) against a measured LLM stage of median 267 s. Serialising all 37 merges of the 2026-08-06 batch costs 6.4 s of ~1472 s. The expensive-stages-stay-parallel claim is true; it just answers a question nobody needed answered.

**Option (a) unbounded — `topic/*.md merge=union` — is silently wrong on 4 of 11.** Replayed and diffed against what the human actually committed: 1 byte-identical, 5 differing by a missing blank line (two paragraphs render as one run-on), **3 silently duplicating a paragraph** (`Software Engineering Craft` commits both "Five pages form a cluster…" and "Six pages form a cluster…", adjacent and contradictory, exit 0, pushed), and **1 duplicating an entire page** (73 lines of one body interleaved into another, `## Analysis` heading and all).

It never loses text. On a 991-page wiki the Captain reads and trusts, "never loses text" is not the bar — it converts a loud recoverable failure into a quiet undetectable one.

## The recommendation, and why I accept it

**Bounded union**: after a failed merge, auto-resolve a `topic/` conflict **iff** the path exists in the merge base (not an add/add) **and** every conflict hunk has an empty base section (both sides only added; neither revised a base line). Ours-block, blank line, theirs-block. Anything failing either test is left exactly as today — abort, keep the branch, exit 1, tell the human.

Measured on the same 11: **7 auto-resolved** (5 byte-identical to the human, 1 differing only in blank lines, 1 **strictly better** — `a60c1d8`, where the human commit shipped conflict markers and the rule produces clean text), **4 kept as today's loud failure**, **0 silently wrong**. A 64% cut in hand merges with no corruption path, and the remaining 4 are precisely the cases needing judgement a merge driver cannot have.

That `a60c1d8` row is worth pausing on: it is the `cntt` incident. The bounded rule would have produced clean text where the auto-commit shipped markers.

**Two supporting changes, both in scope.** Classify the retry on **exit code only** — `1` means this process's merge conflicted (do not retry), `128` means it never started (retry, that is what the loop was for). The first draft of that rule used "are there unmerged paths?" and was **wrong**: `$WIKI` has one index shared by every concurrent ingest, so a peer's conflict makes `--diff-filter=U` non-empty for a process whose own merge never ran. And that same demo surfaced a live hazard — `merge_with_retry` calls `git merge --abort` **unconditionally**, so a failed-to-start merge destroys a *peer's* merge state. Abort only on exit 1.

**The mutex** is enabling, not curative: the resolver writes to the shared `$WIKI` working tree, and two peers doing that concurrently is strictly worse than two peers merging. `flock` is absent on macOS (checked), so an atomic `mkdir` mutex with a staleness sweep. `git push` stays outside it.

The implementation notes already carry the `cntt` lesson forward unprompted: conflicted paths must be read with `-c core.quotePath=false`, because ~80 of the 991 topic filenames carry an em-dash.

## Is it still the interim mitigation

Yes, by the Captain's own words on `87sc` — he named "a union-ish merge driver, **or** serialize just the merge step behind a lock", and separately flagged that retry and content conflict are not distinguished. This design does the union-ish rule, adds the lock the rule needs, and does the retry classification he called out. The rearchitecture stays out, explicitly, along with any prompt change and any re-run of synthesis against new main (which is what actually reaches semantic correctness, and which is `87sc`).

The `## Out of scope` section names the blanket `merge=union` rejection *on the record*, so it is not rediscovered and re-proposed later. Good.

## Where I stop

**I am approving implementation and validation. I am not merging this to `main` without the Captain.**

Three reasons, and they are about risk rather than doubt:

1. It rewrites the merge critical section of the tool that writes his wiki on a schedule. It is the highest-blast-radius change of the night, and a mutex that leaks or a staleness sweep that misfires stops his ingests rather than corrupting one page.
2. **AC6 and AC7 are both interactive.** AC6's audit needs his actual wiki; AC7 is a real ~30-URL batch and is explicitly "not automatable — the Captain's drive". So the fix cannot be fully validated without him no matter how long I run.
3. The design itself poses him a live choice in `## The honest limit`: take the bounded rule, or take the one-line `.gitattributes` and accept a 4-in-11 silent-duplication rate. I will not recommend the one-liner — it is measurably unsafe — but the choice was surfaced deliberately and belongs to him.

**Sequencing:** the test plan asks that implementation rebase onto `pxf4` **after** it merges rather than developing in parallel, since both add large blocks to `tests/test-guard.sh` — *"this fix is about merge conflicts and should not create one."* Agreed. Implementation is held until `pxf4` lands.

## Recommend

**Approve** — enter implementation once `pxf4` merges, and hold at the validation gate for the Captain rather than merging.

Checklist: 3 done, 0 skipped, 0 failed (`docs/bug-fixes/serialise-topic-page-merges.md` lines 190–203).
