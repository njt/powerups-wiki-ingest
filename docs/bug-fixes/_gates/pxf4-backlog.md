# Backlog gate — slug-collision-on-shared-path-segment

**Entity:** `slug-collision-on-shared-path-segment` (`jc`) · **Stage:** `backlog` → `ideation`
**Source:** kata `pxf4` (P2) · **Score:** 0.6

## Question

Does this advance to ideation now that a slot is free?

## Is it a real defect

Yes, with a first-hand instance. During the 2026-08-06 batch, both of these were ingested:

    https://blog.cloudflare.com/cloudflare-os/
    https://github.com/cloudflare/cloudflare-os

Both slug to `cloudflare-os` from the last path segment alone, so both wanted `raw/cloudflare-os.md`, `summary/cloudflare-os.md` and `topic/Cloudflare OS.md`. They are genuinely different sources — an announcement post and a codebase — and both deserved pages.

The severity is in *how it was caught*: only an unrelated merge conflict on `topic/Security and Sandboxing.md` stopped the second ingest. Had that merge gone clean, the repo analysis would have silently clobbered the blog post's archive, and `log.md` would have carried two entries pointing at one file whose content matched only one of them. `wiki-ingest-dupcheck` does not catch it — it compares source URLs, and neither URL matches the other.

Same family as the two fixes already through this workflow: it destroys data and reports success.

## What ideation has to weigh, and why it is not obvious

The kata issue offers two fixes, and they are not equivalent in cost:

- **Detect the target-path collision before writing**, suffixing by source type or host. Narrow, and preserves every existing slug in the live wiki.
- **Derive the slug from host plus path.** Cleaner, but renames roughly 700 existing files — that is a migration, not a fix, and this workflow ships fixes.

I am not pre-deciding this at the backlog gate; it is exactly the kind of call ideation exists to make with evidence. But the bar I will hold the design to is that the live wiki already carries the current scheme's output, and a fix that requires migrating it is a different entity.

## Why now, and why third

`cntt` and `dw2f` went first — one was corrupting committed data, the other was a one-line diff with zero file overlap. This one touches slug derivation and probably `wiki-ingest-dupcheck`, which overlaps `wiki-ingest-run`'s territory, so it waited for `cntt`'s guard to land rather than racing it. `dw2f` is now merged and `cntt` is in validation, so the slot is genuinely free.

## Recommend

**Approve** — advance to ideation.
