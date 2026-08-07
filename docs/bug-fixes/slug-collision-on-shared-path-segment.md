---
id: jcpfnk0aasbcqxz52ej6cvk1
title: Slug collision silently overwrites another source's raw, summary and topic files
status: backlog
source: kata:pxf4
started:
completed:
verdict:
score: 0.6
worktree:
issue:
pr:
mod-block:
gates:
    version: 1
    records:
        - id: gate:jcpfnk0aasbcqxz52ej6cvk1:backlog
          stage: backlog
          attempts:
            - id: gate-attempt:jcpfnk0aasbcqxz52ej6cvk1-backlog-1
              briefing:
                id: briefing:jcpfnk0aasbcqxz52ej6cvk1:backlog:attempt-1:revision-1
                digest: sha256:ba4a07b53987615a7ba75837a82a291fedc59eb4d40b3aa86ad535dbe641d1ba
                request-digest: sha256:809900c947c41b37daea594955bcc1d0e329908f8173bc3d4d0ae617d6a43a4f
                room-ref: ./slug-collision-on-shared-path-segment/review/backlog/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:jcpfnk0aasbcqxz52ej6cvk1:backlog:1
                briefing: briefing:jcpfnk0aasbcqxz52ej6cvk1:backlog:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T14:00:53.024093Z"
                decision: approve
                reason: Real defect with a first-hand 2026-08-06 instance naming both colliding URLs and the three files they fight over. Caught only by an unrelated merge conflict, and dupcheck misses it structurally by comparing source URLs rather than target slugs. Same silent-data-loss family as the two fixes already through. Slot freed by dw2f merging; sequenced third because it touches slug derivation adjacent to wiki-ingest-run. Captain delegated gate decisions in-conversation.
              application:
                target-stage: ideation
                state: pending
---

## Problem

The slug is derived from the last path segment of the URL alone, so two unrelated sources whose URLs end in the same segment collide on every file they write.

Observed 2026-08-06 during a 37-URL batch ingest. Both of these were in the batch:

    https://blog.cloudflare.com/cloudflare-os/
    https://github.com/cloudflare/cloudflare-os

Both slug to `cloudflare-os`, so both wanted `raw/cloudflare-os.md`, `summary/cloudflare-os.md` and `topic/Cloudflare OS.md`. They are genuinely different sources — an announcement post and a codebase — and both deserved pages.

Only a merge conflict on an unrelated file (`topic/Security and Sandboxing.md`) stopped the second ingest and surfaced this. Had that merge gone clean, the repo analysis would have silently clobbered the blog post's raw and summary, and `log.md` would have carried two entries pointing at one file whose content matched only one of them.

The duplicate-detection step does not catch this: `wiki-ingest-dupcheck` compares source URLs, and neither URL matched the other. It has no notion of target-path collision.

Resolved by hand that time — the blog post kept `raw/cloudflare-os.md` and `summary/cloudflare-os.md`, the repo analysis moved to `raw/cloudflare-os-repo.md` and `summary/cloudflare-os-repo.md`, the two topic pages were merged into one, the duplicate `index.md` entry was collapsed and the repo's `log.md` entry repointed.

## Proposed approach

Two options from the kata issue, to be chosen at ideation:

- detect the target-path collision before writing, and on collision suffix by source type (`cloudflare-os-repo`) or by host (`cloudflare-os-github`); or
- derive the slug from host plus path rather than the last segment alone.

The first is narrower and preserves every existing slug in the live wiki. The second is cleaner but renames roughly 700 existing files, which makes it a migration rather than a fix. Ideation should weigh that explicitly — the live wiki already carries the current scheme's output.

Whichever is chosen, `wiki-ingest-dupcheck` gaining target-slug awareness alongside its URL comparison is likely part of the answer.

## Acceptance criteria

To be written at ideation. Repro is cheap and deterministic: ingest any blog post and any GitHub repo whose URLs end in the same path segment, and assert both sources survive with distinct files and correctly-pointed `log.md` entries.

## Test plan

To be written at ideation.

## Out of scope

Retroactively finding collisions already in the live wiki. If the fix implies a sweep, that is a separate task filed at the time.
