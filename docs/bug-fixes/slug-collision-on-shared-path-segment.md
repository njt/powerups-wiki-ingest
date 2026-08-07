---
id: jcpfnk0aasbcqxz52ej6cvk1
title: Slug collision silently overwrites another source's raw, summary and topic files
status: ideation
source: kata:pxf4
started: 2026-08-07T14:00:53Z
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
                state: consumed
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

## Reproduction

    bash docs/bug-fixes/slug-collision-on-shared-path-segment/repro.sh

Self-contained and offline: throwaway wiki under `mktemp -d`, stubbed `WIKI_INGEST_CLI`, both ingests via `--content` so nothing is fetched. Against main at `f8616a2` it exits 1:

    FAIL: no raw/ archive holds the BLOG url — it was clobbered
    FAIL: raw/cloudflare-os.md changed when the second source was ingested
    FAIL: summary/cloudflare-os.md changed when the second source was ingested
    FAIL: log.md says https://blog.cloudflare.com/cloudflare-os/ lives in
          raw/cloudflare-os.md, but that file's url is
          https://github.com/cloudflare/cloudflare-os
    REPRO: FAIL (collision reproduced)

The second ingest exits **0** and fast-forwards main with `raw/cloudflare-os.md | 4 ++--` — a clean in-place modification, no conflict, no warning. That is the silent clobber; the `topic/` conflict that surfaced it on 2026-08-06 was luck, not a safety net.

Two properties of the script matter for the later stages:

- The stub reads the slug out of the prompt it is handed rather than hard-coding a filename, so the script stays valid after the fix and does not have to be rewritten to go green.
- Its last case is a **control**: a `--force` re-ingest of an already-archived URL must not mint a second file. It passes today and must still pass after the fix. That is the regression this fix is most likely to cause.

## Root cause

There is exactly **one** slug derivation, confirmed by reading: `url_slug()` at `bin/wiki-ingest-run:65-78`. It strips the query and fragment, takes the **last path segment**, lowercases it and maps non-alphanumerics to hyphens. The host is consulted only as a fallback when the path is empty. Exercising the real function text:

    https://blog.cloudflare.com/cloudflare-os/       -> cloudflare-os
    https://github.com/cloudflare/cloudflare-os      -> cloudflare-os
    https://github.com/otherowner/cloudflare-os      -> cloudflare-os
    https://news.ycombinator.com/item?id=123         -> item

The third line shows the collision is not limited to cross-host cases — two repos of the same name under different owners collide too, so a host-based suffix alone does not close it. The fourth shows the class is wider than the incident suggested: because the query string is stripped, **every** URL with a generic terminal segment collapses to the same slug. A disambiguator that cannot repeat is therefore load-bearing, not decorative.

Call sites, all of them:

- `bin/wiki-ingest-run:261` — the ingest path. `--repo`, `--content`, `--verbatim-only` and the default all pass through this one line; **none of them derive differently**.
- `bin/wiki-ingest-run:124` — `--summary-only`, when its argument looks like a URL rather than a bare slug.
- `--dry-run` leaves `SLUG` empty and writes no `raw/` file, so it has no collision surface.
- `bin/wiki-ingest-backfill` derives no slug from a URL at all: it takes slugs from existing `summary/*.md` filenames (line 50) and skips any slug that already has a `raw/` file (line 51). No change needed there.

### What `wiki-ingest-dupcheck` actually does today

It canonicalizes the incoming URL and every `url:` frontmatter value under `raw/` and `summary/`, then compares for exact equality. Its canonicalization folds protocol, leading `www.`, `#fragment`, tracking query params, trailing `/` and trailing `.git`, and lowercases the host. Verified:

    https://blog.cloudflare.com/cloudflare-os/    -> blog.cloudflare.com/cloudflare-os
    https://blog.cloudflare.com/cloudflare-os     -> blog.cloudflare.com/cloudflare-os
    https://github.com/cloudflare/cloudflare-os.git -> github.com/cloudflare/cloudflare-os

On a match it exits 0 and prints the **owning file path(s)**; on no match it exits 1. It has no notion of target-path collision — correctly, as argued below.

## Proposed approach

**Recommendation: (a) — resolve the target slug before writing.** Narrow, ships without touching the live wiki, and needs no migration.

The decisive point is not that (a) is smaller. It is that a slug collision **is not a duplicate**. Both sources are legitimate and both deserve pages. Teaching `wiki-ingest-dupcheck` to report target-slug collisions — the kata's guess at the answer — would make it exit 0 ("already ingested") on a genuinely new source and *reject* it. That is a worse failure than the one being fixed, so this fix deliberately leaves `wiki-ingest-dupcheck` **unchanged**.

### The design

Replace `SLUG=$(url_slug "$INGEST_URL")` at `bin/wiki-ingest-run:261` with a `resolve_slug` that runs after the worktree exists and before the `raw/` file is written. Two steps:

**Step 1 — does an archive already hold this URL?** Run the existing duplicate checker against the worktree:

    WIKI_PATH="$WT" wiki-ingest-dupcheck "$INGEST_URL"

On exit 0 it names the owning files. Take the basenames of the un-indented output lines (the indented lines are `title:`/`date_fetched:` detail), drop the `.md`, and de-duplicate. Exactly one distinct basename → **that is the slug**; return it. This is the update path, and it must not be suffixed.

**Step 2 — otherwise pick the first free slug.** No archive holds this URL, so walk a bounded ladder and take the first candidate for which neither `raw/<c>.md` nor `summary/<c>.md` exists in the worktree:

    <base>, <base>-<host-token>, <base>-<host-token>-2 … -9

where `<base>` is today's `url_slug` output and `<host-token>` is the canonical host minus its final dot-label, sanitised the same way (`github.com` → `github`, `blog.cloudflare.com` → `blog-cloudflare`, `news.ycombinator.com` → `news-ycombinator`). Exhausting the ladder is `exit 1` with the candidates named — never a silent overwrite. Exit codes 2 and 3 are reserved contract values, so 1 is the correct failure code.

Both tiers are checked because migrated content can have a `summary/<slug>.md` with no `raw/` file; checking only `raw/` would hand out a slug whose precis belongs to someone else.

### Why this distinguishes re-ingest from collision

This is the property that decides whether the fix is a fix or a duplicate-generator, and it falls out of the two steps rather than being bolted on:

- **Same URL re-ingested** (`--force`): step 1 matches and returns the existing slug. The archive is updated in place. Verified that this survives cosmetic URL differences — dupcheck already folds trailing `/`, `www.`, `http`/`https`, `#fragment` and `.git`, so `…/cloudflare-os/` and `…/cloudflare-os` resolve to the same file.
- **Genuinely different source**: step 1 finds nothing, step 2 sees `<base>` occupied and suffixes.

Without `--force`, `wiki-ingest-run:167` has already established the URL is not in the wiki, so step 1 is a confirmation. With `--force` that check was skipped and step 1 is the only thing standing between a re-ingest and a duplicate. Running it unconditionally keeps `resolve_slug` correct without knowing which mode it is in, and costs one fork against an ingest that already forks git, find, awk and an LLM.

Delegating the comparison to `wiki-ingest-dupcheck` rather than re-implementing canonicalization inside `wiki-ingest-run` is deliberate. Two copies of that logic would drift, and the drift failure mode is exactly the re-ingest-duplication bug — the worst outcome available here.

A useful consequence, verified against a wiki seeded with the hand-resolved layout: step 1 finds an archive under a **hand-chosen** slug that the ladder would never generate. `wiki-ingest-dupcheck https://github.com/cloudflare/cloudflare-os.git` against a wiki holding `raw/cloudflare-os-repo.md` returns `cloudflare-os-repo`. So a future `--force` re-ingest of the repo updates the file Nat made by hand on 2026-08-06 instead of minting `cloudflare-os-github` beside it.

### `--summary-only`

`bin/wiki-ingest-run:124` has the same defect in mirror image: once slugs can be suffixed, `url_slug` no longer identifies which archive a URL lives in, so a URL argument could backfill the **wrong** source's precis. Same remedy, same tool — resolve the URL through `wiki-ingest-dupcheck` and use the owning file's basename; error out if nothing holds it. A bare-slug argument keeps today's behaviour byte for byte.

This is not scope creep. It is the fix's own second-order consequence: leaving it out means this change introduces a wrong-file-write path that does not exist today.

### What this deliberately leaves alone

- **`topic/` pages.** The entity title names them, but they are a different defect with a different correct answer. `topic/` filenames are human titles, not slugs, and the tier is **subject**-keyed rather than source-keyed — which is why the hand resolution *merged* the two topic pages into one, and why the completeness guard at line 632 is a deliberate prefix match. Two sources about one subject sharing a topic page is the design working. The real residual is an LLM using `Write` rather than `Edit` on an existing topic page, which clobbers it whenever two sources share a title — collision or not. That is a separate defect, it wants its own entity, and it cannot ride along here: its only available proof would be a grep over prompt text, which this stage rejects.
- **`wiki-ingest-dupcheck`** — unchanged, for the reason given above.
- **`url_slug`'s base output** — unchanged. Every existing filename in the live wiki stays valid.
- **Existing collisions already in the live wiki** — see Out of scope.

### Option (b), costed

Deriving slugs from host plus path is the cleaner scheme. It is also a migration, not a fix, and this workflow ships fixes. Against ~700 live files it would require an entity of its own that must:

1. recompute a slug for every `raw/` and `summary/` file from its `url:` frontmatter, and `git mv` both tiers;
2. rewrite every `[[raw/<old>]]` and `[[summary/<old>]]` footer wikilink across `topic/` — the ingest prompts emit those on every page (lines 489, 550);
3. rewrite every `→ raw/<old>.md` pointer in `log.md`, one per ingest ever performed;
4. decide what to do with files that have **no** `url:` frontmatter and therefore cannot be re-slugged at all;
5. run against a clone with a reviewed diff before anything touches the real wiki.

It also costs readability in a vault Nat reads on a phone (`blog-cloudflare-com-cloudflare-os`), and it does not remove the need for a terminal disambiguator, since flattening host+path can still collide. Recommending (b) here would be smuggling a rename of 700 live files in as a bug fix. If the Captain wants the scheme changed, that is a separate entity and this fix does not block it — (a) leaves every existing slug untouched, so (b) remains available later.

## Acceptance criteria

Every criterion below is an end-state property. Five are **offline**; one is **interactive** and is a Captain call, not a test.

**AC1 — Two sources whose URLs share a last path segment each keep their own `raw/` and `summary/` archive, and the incumbent's files are byte-identical afterwards.**
*Verified by (offline):* `bash docs/bug-fixes/slug-collision-on-shared-path-segment/repro.sh` exits 0, plus the equivalent case in `tests/test-guard.sh`.
*Falsified by:* restoring `SLUG=$(url_slug "$INGEST_URL")` at `bin/wiki-ingest-run:261` — the second ingest then overwrites the first and the script reports `no raw/ archive holds the BLOG url`.

**AC2 — A `--force` re-ingest of an already-archived URL updates that archive in place and creates no second file, including when the URL differs only by trailing `/`, `www.`, `http`/`https`, `#fragment` or `.git`.**
*Verified by (offline):* `tests/test-guard.sh` case asserting the count of `raw/*.md` is unchanged across the re-ingest and the file's `url:` still matches; the repro's control case covers the plain form.
*Falsified by:* comparing the incoming URL against stored `url:` values as raw strings instead of through `wiki-ingest-dupcheck` — the trailing-slash variant then reads as a foreign occupant and mints a suffixed duplicate.

**AC3 — Collisions that share a host also resolve, and an unsatisfiable slug space fails loudly rather than overwriting.**
*Verified by (offline):* `tests/test-guard.sh` case ingesting `github.com/a/x`, `github.com/b/x` and `github.com/c/x`, asserting three distinct archives each holding its own URL.
*Falsified by:* dropping the numeric tail from the ladder — the second and third then collide again on `x-github` and the third clobbers the second.

**AC4 — `--summary-only <url>` backfills the archive that actually holds that URL, including one whose slug is not derivable from the URL.**
*Verified by (offline):* `tests/test-guard.sh` case seeding `raw/cloudflare-os-github.md` carrying the repo URL, then asserting `--summary-only https://github.com/cloudflare/cloudflare-os` writes `summary/cloudflare-os-github.md`.
*Falsified by:* leaving `url_slug` at `bin/wiki-ingest-run:124` — it targets `cloudflare-os` and either exits 1 `no such source` or, if that slug exists, backfills the wrong source.

**AC5 — Nothing else in the pipeline changed behaviour.**
*Verified by (offline):* `bash tests/test-guard.sh` and `bash tests/test-fetch.sh` both still print `ALL PASS`. Both are green on main at `f8616a2` today, so this is a real before/after comparison and not an empty baseline.
*Falsified by:* making `resolve_slug` fail closed on a wiki with no `summary/` tier, or changing `wiki-ingest-dupcheck`'s single-argument exit codes — existing cases 1–10 then fail.

**AC6 (interactive — Captain) — the suffix shape reads acceptably in the vault, and a shared `topic/` page is the intended behaviour rather than a second bug.**
*Verified by:* Nat's judgement at the review gate. `cloudflare-os-github` is the kata's own host-based option, but the 2026-08-06 hand resolution chose `cloudflare-os-repo`, so the two are not the same choice. This needs a decision, not a test — flagged rather than assumed.

## Test plan

`tests/test-guard.sh` gains the cases. It is the right home and no new file is warranted: it already bootstraps a throwaway wiki, stubs `WIKI_INGEST_CLI`, drives real `wiki-ingest-run` invocations with `--content`, and asserts on committed wiki state. `tests/test-fetch.sh` is fixture-based extraction only and is not involved.

Cases to add, appended after the existing case 10:

1. **Cross-host collision** (AC1) — ingest two URLs with the same last segment on different hosts; assert two `raw/` files, two `summary/` files, each holding its own `url:`, and the first pair byte-identical after the second ingest.
2. **Re-ingest is not a collision** (AC2) — `--force` re-ingest of an already-archived URL, passed with a trailing slash it was not ingested with; assert the `raw/*.md` count is unchanged and no suffixed file appeared.
3. **Same-host collision** (AC3) — three URLs sharing host and last segment; assert three distinct archives.
4. **`--summary-only` targets by URL, not by slug** (AC4) — seed an archive under a slug the URL does not derive, then backfill it by URL.

Two constraints on the implementation stage, both load-bearing:

- The existing stub is driven by `STUB_SLUG` from the environment, which hard-codes the expected filename and so **cannot** express "whatever slug the script chose". The new cases need a stub mode that reads the slug from the prompt, as `repro.sh` does. Extend the stub; do not repoint the existing cases at the new mode.
- **Do not touch the seed block at `tests/test-guard.sh:86-95`.** It is what makes the file's other guard tests non-vacuous.

Coordination note for the implementation stage: `tests/test-guard.sh` is also modified by the unmerged `cntt` branch (`spacedock-ensign/guard-auto-commit-against-conflicted-merge`), which appends ~213 lines of its own cases. Append at the end of the file and expect to merge with it. See Out of scope for the state of that branch.

## Out of scope

- **Retroactively finding collisions already in the live wiki.** The fix protects new ingests only; any pair that already collided still shares one file. Finding them is cheap — group `raw/*.md` and `summary/*.md` by canonicalized `url:` and report any slug holding more than one — but it is a sweep over live data and belongs in its own entity. Worth filing.
- **`topic/` page clobbering** when two sources share a title. Different cause, different correct answer; see "What this deliberately leaves alone". Worth filing separately.
- **`url_slug` discarding the query string**, which is what collapses every `news.ycombinator.com/item?id=N` to `item`. This fix makes such collisions safe rather than silent, which is the bug being fixed; making the slugs *informative* is a change to the naming scheme and belongs with option (b). Worth filing.
- **Renaming or migrating any existing file in the live wiki.** No stage of this fix does so.

### Correction to the dispatch brief

The brief stated that `bin/wiki-ingest-run` "has just changed on main (a new guard around the auto-commit, kata `cntt`)". It has not. `bd74a28` is **not** an ancestor of `main`; it lives on the unmerged branch `spacedock-ensign/guard-auto-commit-against-conflicted-merge` (worktree at `.worktrees/…`). This design is written against `main` at `f8616a2`, as instructed. The two changes do not overlap in `bin/wiki-ingest-run` — `cntt` adds guards immediately before the auto-commit at line 657, this fix touches lines 124 and 261 — but they do overlap in `tests/test-guard.sh`, hence the coordination note above.
