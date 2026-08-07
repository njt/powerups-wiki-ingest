# Backlog gate — serialise-topic-page-merges

**Entity:** `serialise-topic-page-merges` (`gh`) · **Stage:** `backlog` → `ideation`
**Source:** kata `87sc`, interim mitigation only · **Score:** 0.7

## Question

Does this advance to ideation, and is it correctly scoped as a fix rather than the rearchitecture?

## Is it a real defect

Yes, with the best failure statistics in the backlog. The 2026-08-06 batch of 37 URLs produced **6 merge failures — 16%** — and every one was a content conflict on a `topic/` page: Context Graphs, Guardrails and Feedback Loops (twice), Agent Memory and Context, Loop Engineering, Security and Sandboxing.

The mechanism is the racing-peers problem. `index.md` and `log.md` survive because they carry `merge=union`; `topic/` pages have no such driver, and concurrent ingests routinely append to the same popular page. The busier the topic, the likelier the collision — one page was hit twice in a single batch.

The existing 5× retry loop cannot help, and this is the part worth stating plainly: **the conflict is deterministic**, so retrying the same merge five times only delays the failure. Retry is the right remedy for lock contention and the wrong one for content conflict, and the two are not currently distinguished.

All six resolved by hand as "keep both sides" — purely additive edits landing in the same slot.

## Is it correctly scoped

This entity is the **interim mitigation only**. Kata `87sc` proposes flipping the whole execution model to a single SQLite-orchestrated process; that remains open and is explicitly not in scope here. The Captain's own comment on `87sc` named the cheaper remedy — *"give `topic/` pages a union-ish merge driver, or serialize just the merge step while keeping fetch and analysis parallel"* — and asked for it as an interim measure if `87sc` is a way off. That is what this is.

The line I will hold the design to: if it turns out the band-aid cannot be made correct without the rearchitecture, the honest answer is to say so and hold for the Captain, not to quietly grow this entity into `87sc`.

## Why it goes last, and why that was the right call

It targets `wiki-ingest-run`'s merge machinery — the same file and the same region as `cntt`'s guard, which was unmerged until minutes ago. Designing this earlier would have meant designing against a moving target, which is exactly the error I made in the `pxf4` dispatch brief when I told that ensign `cntt` was already on `main`. `cntt` is now merged and its `merge_with_retry` interaction is settled, so this design can read the real file.

That interaction is not incidental. `cntt`'s validation observed `merge_with_retry`'s `git merge --abort` running five times against a stopped rebase, and the `cntt` guard now exits before reaching it. Whatever this fix does to the retry loop has to account for a guard that now sits upstream of it.

## The known risk for ideation

A union-ish merge driver for `topic/` pages is the smaller change, but "keep both sides" is only obviously correct because all six observed conflicts were additive edits in the same slot. A driver that blindly keeps both sides will also duplicate content when two ingests genuinely revise the same sentence. The design has to say what happens then, and must not assume the six-for-six sample generalises.

Serialising the merge step is more predictable but adds a serialisation point to a design whose whole premise is parallel ingests. The cost has to be measured against a real batch, not asserted.

## Recommend

**Approve** — advance to ideation as the interim mitigation, with the rearchitecture explicitly out of scope.
