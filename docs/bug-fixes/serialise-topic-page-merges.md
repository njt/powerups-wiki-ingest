---
id: ghyj7yz18wnypbvkfa84vq0f
title: Stop concurrent ingests conflicting on shared topic pages (interim mitigation)
status: backlog
source: kata:87sc (interim mitigation only)
started:
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
---

## Problem

Concurrent ingests routinely conflict on the same `topic/` page. Evidence from the 2026-08-06 batch: 37 URLs in parallel produced 6 merge failures (16%), every one a content conflict on a topic page — Context Graphs, Guardrails and Feedback Loops (twice), Agent Memory and Context, Loop Engineering, Security and Sandboxing.

The pattern is the racing-peers problem. `index.md` and `log.md` survive because they carry `merge=union`; `topic/` pages have no such driver, and concurrent ingests routinely append a paragraph or list item to the same popular page. The busier the topic, the likelier the collision — Guardrails and Feedback Loops was hit twice in one batch.

The existing 5x retry loop cannot help. The conflict is deterministic, so retrying the same merge five times just delays the failure. Retry is the right remedy for lock contention and the wrong one for content conflict, and the two cases are not currently distinguished.

All 6 resolved cleanly by hand as "keep both sides" — purely additive edits landing in the same slot.

## Proposed approach

This entity is the **interim mitigation only**, not the full rearchitecture. Kata `87sc` proposes flipping the execution model to a single SQLite-orchestrated process; that remains open and is not in this workflow's scope. Nat's own comment on `87sc` names the cheaper fix, and that is what this covers:

- give `topic/` pages a union-ish merge driver, so additive edits in the same slot merge instead of conflicting; **or**
- serialise just the merge step behind a lock, keeping fetch and analysis parallel so the expensive stages stay concurrent.

A likely third component regardless of which is chosen: distinguish content conflict from lock contention so the retry loop stops burning five attempts on a deterministic failure.

Ideation should pick one primary approach with reasons. The union-driver route is smaller but has to be right about what "keep both sides" means for a topic page's structure; the lock route is more predictable but adds a serialisation point to a design whose whole premise is parallel ingests.

## Acceptance criteria

To be written at ideation. The property worth proving: two concurrent ingests appending to the same topic page both land, without hand resolution and without either losing content.

## Test plan

To be written at ideation. This one needs genuinely concurrent ingests against a throwaway wiki, which is a heavier fixture than the other three fixes need — worth scoping the cost at ideation rather than discovering it at implementation.

## Out of scope

The full single-writer SQLite orchestrator from `87sc`. That issue stays open in kata after this fix lands; this is the band-aid Nat asked for if `87sc` is a way off, and the fix body should say so plainly so nobody later mistakes it for the rearchitecture.
