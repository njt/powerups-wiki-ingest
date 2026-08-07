---
id: jcpfnk0aasbcqxz52ej6cvk1
title: Slug collision silently overwrites another source's raw, summary and topic files
status: validation
source: kata:pxf4
started: 2026-08-07T14:00:53Z
completed:
verdict:
score: 0.6
worktree: .worktrees/spacedock-ensign-slug-collision-on-shared-path-segment
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
        - id: gate:jcpfnk0aasbcqxz52ej6cvk1:ideation
          stage: ideation
          attempts:
            - id: gate-attempt:jcpfnk0aasbcqxz52ej6cvk1-ideation-1
              briefing:
                id: briefing:jcpfnk0aasbcqxz52ej6cvk1:ideation:attempt-1:revision-1
                digest: sha256:279ca0a1369894976f719d1992206de51079258270bcefc1188e6bcf0c752b26
                request-digest: sha256:417bdef5053f45b4cad63bf4fb27152af85ea37ff29818db6527023603cbf706
                room-ref: ./slug-collision-on-shared-path-segment/review/ideation/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:jcpfnk0aasbcqxz52ej6cvk1:ideation:1
                briefing: briefing:jcpfnk0aasbcqxz52ej6cvk1:ideation:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T14:14:36.269074Z"
                decision: approve
                reason: 'Mechanism confirmed first-hand: url_slug at bin/wiki-ingest-run:65-78 is the sole derivation, call sites enumerated. Establishes that the kata''s proposed fix (teach dupcheck target-slug awareness) would make it reject genuinely new sources — worse than the bug — and instead reuses dupcheck as a URL-to-owning-file lookup that structurally separates --force re-ingest from collision, verified including a hand-renamed slug. Defect shown wider than reported (same-host collisions, query-stripping), justifying the numeric tail. --summary-only in scope as the change''s own second-order consequence. Option (b) costed as a five-step migration and declined without smuggling a live-wiki rename into a bug fix. AC6 (suffix shape) correctly declared interactive and carried forward UNSATISFIED for the Captain; mechanism is token-independent, nothing is renamed, no ingest runs before he wakes. Captain delegated gate decisions in-conversation but this specific taste call is reserved to him. Ensign also corrected a factual error in the FO''s own dispatch brief.'
              application:
                target-stage: implementation
                state: consumed
        - id: gate:jcpfnk0aasbcqxz52ej6cvk1:validation
          stage: validation
          attempts:
            - id: gate-attempt:jcpfnk0aasbcqxz52ej6cvk1-validation-1
              briefing:
                id: briefing:jcpfnk0aasbcqxz52ej6cvk1:validation:attempt-1:revision-1
                digest: sha256:32630c0ed198f58c291470834c2aa13295643a1709a03c03a6b7b6e651c82013
                request-digest: sha256:57093002fe52ee72d0ded1bb2e8d8f83b140dcb45a5d273a90bc67df7316c715
                room-ref: ./slug-collision-on-shared-path-segment/review/validation/briefing-1
              resolution:
                type: Resolution
                id: resolution:spacedock:jcpfnk0aasbcqxz52ej6cvk1:validation:1
                briefing: briefing:jcpfnk0aasbcqxz52ej6cvk1:validation:attempt-1:revision-1
                by: agent:first-officer
                at: "2026-08-07T14:57:36.706039Z"
                decision: revise
                reason: 'REJECTS DIRECTION on F1, test-file only. Shipped behaviour verified sound: AC1-AC5 reproduced green and each watched failing under its own falsifier in a scratch tree, 27/27 merged-tree green, duplicate-generator fires at 9->10 where step 1 is removed, .git variant and --verbatim-only probed though untested, cntt orthogonality reproduces at 19/0 and 0/16. F1 material: the AC6 cost claim is false — the suffix token is encoded in four test literals across two cases, and changing it alone makes the suite report the fail-closed guard broken and main advanced on a refused source. All four evidence fields hold against value-ac[AC6], because answering AC6 is this entity''s declared next Captain action and the misleading output lands where he will look while the correcting note sits where he may not. Accept-with-note considered and declined on that asymmetry. Authorized: fix the four literals to derive from the token, correct the AC6 cost sentence, and fold in F2''s stale 5->6 figure while the report is open. F3 confirmed pre-existing, no action. F4 residual declined and filed as its own kata issue. Captain delegated gate decisions in-conversation.'
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

## Stage Report: ideation

- DONE: A reproduction that actually fails, named as the exact command or scenario a fresh agent can re-run — not a description of one.
  `bash docs/bug-fixes/slug-collision-on-shared-path-segment/repro.sh` (committed in 7368ec5); exits 1 against main `f8616a2`, four assertions firing, offline and network-free.
- DONE: A recommendation between collision-detect-and-suffix and host+path slugs, with the live wiki's ~700 existing files costed explicitly.
  Recommends collision-detect-and-resolve; option (b) costed as a five-step migration entity under "Option (b), costed" and declined as out of this workflow's remit.
- DONE: Each acceptance criterion's evidence external to this fix body, naming the concrete edit that would make it fail, and declared offline or interactive.
  AC1-AC5 offline (repro.sh, `tests/test-guard.sh`, `tests/test-fetch.sh`), each with a *Falsified by:* clause naming a concrete edit; AC6 declared interactive and left to the Captain.

### Summary

Confirmed the mechanism first-hand rather than from the report: `url_slug()` at `bin/wiki-ingest-run:65-78` is the sole derivation, reached from two call sites, and `--repo`/`--content`/`--verbatim-only` do not differ. Exercising the real function text showed the defect is wider than the incident implied — same-host collisions (`github.com/{a,b}/x`) also collapse, so a host suffix alone does not close it, and stripping the query collapses every `news.ycombinator.com/item?id=N` to `item`. That is why the design's ladder carries a numeric tail.

The load-bearing decision is that a slug collision is **not** a duplicate. The kata guessed that `wiki-ingest-dupcheck` should gain target-slug awareness; that would make it exit 0 on a genuinely new source and reject it, which is worse than the bug. The design therefore leaves dupcheck unchanged and instead reuses it as the URL-to-owning-file lookup that separates a legitimate `--force` re-ingest from a real collision — verified against a seeded wiki, including a hand-renamed slug (`cloudflare-os-repo`) that no derivation rule would generate. That reuse also removed the need for any new shared-canonicalization plumbing, so the fix is one new function, two changed lines, and no change to dupcheck.

Two things are flagged rather than papered over. AC6 is declared interactive: the suffix shape (`cloudflare-os-github`) is the kata's option but not what the 2026-08-06 hand resolution chose (`cloudflare-os-repo`), so it needs a Captain decision. And the dispatch brief's claim that the `cntt` guard is on main is wrong — `bd74a28` is not an ancestor of `main`; the branch is unmerged, and the real collision between the two is in `tests/test-guard.sh`, noted for the implementation stage.

## Stage Report: implementation

- DONE: Each new tests/test-guard.sh case watched failing for the right reason BEFORE the fix, with the actual red output recorded verbatim in the stage report.
  Red output below, from `86ac6fb` (tests only, unfixed `bin/`); cases 1-10 stayed green throughout.
- DONE: The re-ingest case proven not to duplicate: a --force re-ingest of an already-archived URL, passed with a trailing slash it was not ingested with, leaves the raw/*.md count unchanged and mints no suffixed file.
  Collision case B; passes both before and after the fix, and fails (`5 -> 6`) when step 1 is disabled.
- DONE: The host-token derivation isolated at a single point so the suffix scheme is a one-line change, since AC6 is an open Captain decision.
  `bin/wiki-ingest-run:97` — `tok="${host%.*}"`, inside `slug_disambiguator()` at line 92.

### The red run (verbatim, before the fix)

    FAIL: collision A — both sources resolved to raw/widget-os.md
    FAIL: collision A — suffix shape is 'widget-os', expected 'widget-os-code-example'
    FAIL: collision A — raw/widget-os.md changed when the second source was ingested
    FAIL: collision A — summary/widget-os.md changed when the second source was ingested
    ok: collision: --force re-ingest of a cosmetic URL variant updates in place (rc=0)
    FAIL: collision C — no raw/ archive holds .../one/gadget
    FAIL: collision C — no raw/ archive holds .../two/gadget
    FAIL: collision: --summary-only resolves a URL to the archive that holds it — expected rc=0, got rc=1
    FAIL: collision D — summary/widget-os-hand.md missing, stderr: [...]
          wiki-ingest-run: --summary-only wrote nothing for raw/widget-os.md
    FAIL: collision: exhausted slug ladder is rejected — expected rc=1, got rc=0
    FAIL: collision E — candidates not named in the message: [...]
    FAIL: collision E — main advanced to 'Ingest: https://code.example.invalid/q/zed'
    FAIL: collision E — raw/zed.md was overwritten

Case B was green before the fix on purpose: it is the control, and the regression
this change was most likely to cause. One case (C) first failed for the *wrong*
reason — a 39-character fixture body against the 40-character content threshold,
`rc=3` — and the fixture was lengthened before the red was accepted.

### Falsification (each break was applied and run, not asserted)

- Restore `SLUG=$(url_slug ...)` at the ingest call site → collision A fails, all four assertions.
- Drop the numeric tail from the ladder → the third same-host source fails (`rc=1`), collision C and E fail.
- Restore `url_slug` at the `--summary-only` call site → collision D fails; it targets `raw/thing.md`, a different source.
- Make step 1 never recognise an existing owner → collision B fails, `raw/*.md` count `5 -> 6`. This is the duplicate-generator failure mode, and it is what step 1 exists to prevent.

### Summary

Built as approved: `resolve_slug` at the ingest call site, the same resolution for
`--summary-only <url>`, and `wiki-ingest-dupcheck` untouched. Verified under
`/bin/bash` 3.2.57; `test-guard.sh`, `test-fetch.sh` and the committed `repro.sh`
are all green (AC5 is a real before/after — both suites were green at the start of
this stage).

**AC6, for the Captain.** The suffix scheme is `bin/wiki-ingest-run:97`, one line
inside `slug_disambiguator()`. It currently yields `cloudflare-os-github`; the
2026-08-06 hand resolution chose `cloudflare-os-repo`. Changing it touches that
line and one deliberately-isolated test assertion (`tests/test-guard.sh`, the line
checking `widget-os-code-example`) — every other assertion is name-agnostic. The
mechanism works with any non-empty token, and nothing is renamed either way.

**One case the design did not specify, decided fail-closed and flagged.** A URL
already held by two *different* slugs (the hand-resolved shape, where only one
tier was renamed) is ambiguous. The design says step 1 succeeds on exactly one
distinct basename but not what to do otherwise; falling through to step 2 would
mint a third archive. Both call sites now exit 1 unchanged, naming the archives.
Reachable in practice only under `--force` — without it, the pre-existing dupcheck
at line 167 has already exited 2. Covered by collision case F.

**Not a regression, checked because the repro surfaced it.** `repro.sh` passes,
but the `--force` re-ingest inside its control case exits 1 with
`incomplete result — no summary/... staged`: byte-identical LLM output stages
nothing. Confirmed the same input produces the same `rc=1` and the same message
against `main`'s `bin/`, so this is pre-existing and not introduced here. The
repro's control only asserts the archive count, which is why it stayed green;
collision case B asserts `rc=0` as well and is the stronger AC2 proof.

**Merge note.** 132/6 in `bin/wiki-ingest-run`, 212/1 in `tests/test-guard.sh`.
The new test block is appended at the end and its cases are *named* (A-F) rather
than numbered, so it will not produce duplicate case numbers when it meets the
`cntt` branch's cases 11-15. A textual conflict at the trailing
`[ "$fail" = 0 ] && echo ...` lines is still expected; both blocks should be kept.

### Merge with cntt (kata cntt, now on main)

Merged `main` at `6fa6a03` with `git merge --no-ff`. `bin/wiki-ingest-run` auto-merged
cleanly — the two changes are 400 lines apart (`resolve_slug` call at line 386, cntt's
guard at 791-836) and never touch the same hunk. `tests/test-guard.sh` conflicted in
**three** places, not the one I predicted:

1. The stub helper region — my `prompt_slug()` against cntt's `write_good_slug()`.
2. The stub's `case` arms — my `autoslug`/`summary-autoslug` against cntt's
   `good-slug`/`mid-merge`/`mid-cherry-pick`/`mid-rebase`.
3. The trailing case block, as predicted.

All three were additive on both sides, so all three kept both. cntt's numbered block
stays where it was written, immediately after case 10; the named collision block A-F is
appended at the true end of the file. Verified rather than assumed: no case-identity
collision (1-15 and 13b vs A-F), all 13 stub modes distinct, every mode used by a case
is defined, and the load-bearing seed block is untouched.

Post-merge, all 27 assertions pass in one run — cntt's and mine together.
`test-fetch.sh`, `repro.sh` and `/bin/bash -n` over every script in `bin/` are green.

**The interaction check, run rather than read.** A combined green run does not by itself
show the two changes are independent — one could be masking the other's failure. So each
was disabled in turn *in the merged tree*:

- cntt's guard off, `resolve_slug` on → **19** cntt-case FAIL lines, **0** collision-case FAIL lines.
- `resolve_slug` off, cntt's guard on → **0** cntt-case FAIL lines, **16** collision-case FAIL lines.

Cleanly orthogonal in both directions: each change is still individually load-bearing for
its own cases and irrelevant to the other's. Nothing in the fix was changed for the merge.

## Stage Report: validation

- DONE: Each of the six acceptance criteria reproduced yourself, citing the command you ran and what came back — not the implementation's self-report.
  AC1–AC5 reproduced green *and* watched fail under their own *Falsified by:* edit. AC6 is the Captain's; its **cost** claim was checked and is FALSE — see Findings.
- DONE: The duplicate-generator failure mode exercised directly: disable step 1's owner lookup and confirm a --force re-ingest mints a second archive, then restore.
  Replacing the `owning_slug` call in `resolve_slug` with `orc=1` → `FAIL: collision B — re-ingest added an archive (9 -> 10)`. Restored; 27/27 green. Every falsification ran in a `cp -R` scratch tree — the fix worktree is untouched (`git status` clean at `9f28f24`).
- DONE: Both suites plus repro.sh green in the merged tree, with cntt's cases and the collision cases passing in one run and the test-guard.sh seed confirmed untouched.
  `test-guard.sh` rc=0, 27 ok / 0 FAIL (cntt's 1–15/13b and collision A–F in one run); `test-fetch.sh` rc=0 ALL PASS; `repro.sh` rc=0 `REPRO: PASS`; `bash -n` clean over all of `bin/`. All under `/bin/bash` 3.2.57. Seed block sha1 `47c4675e…` — byte-identical to `main`'s.

### Per-AC verdict

**AC1 — PASS.** `repro.sh` → `REPRO: PASS`; collision A asserts two archives, each holding its own `url:`, and the incumbent's `raw/` + `summary/` checksums unchanged. Restoring `SLUG=$(url_slug "$INGEST_URL")` at the ingest call site → 14 FAIL lines, all four collision-A assertions among them.

**AC2 — PASS, and covered beyond the suite.** Collision B asserts the `raw/*.md` count is unchanged and that `raw/widget-os.md` is the file that got the variant `url:`. The suite's single variant folds http + `www.` + no-trailing-slash + `#fragment`; **`.git` is not exercised anywhere**, so I probed all five separately plus a combined form against the unmodified `bin/`: each `--force` re-ingest kept `raw/` at 1 file and updated `cloudflare-os.md` in place. Non-vacuous — the same probe against a defeated step 1 minted six duplicates (1 → 7, including `cloudflare-os-git.md`).

**AC3 — PASS.** Collision C asserts three same-host sources land in three distinct archives; E asserts an exhausted ladder is rc=1, names the candidates, leaves `main` unmoved and `raw/zed.md` unchanged. Dropping the numeric tail → `'three' ingests — expected rc=0, got rc=1` plus C and E failing.

**AC4 — PASS.** Collision D asserts `--summary-only <url>` writes `summary/widget-os-hand.md` (a slug `url_slug` cannot derive) and leaves the incumbent `summary/widget-os.md` unchanged. Restoring `url_slug` at that call site → D fails rc=1 `no such source raw/thing.md`.

**AC5 — PASS.** Both suites and `repro.sh` green as above. Scope confirmed rather than assumed: `url_slug`'s body byte-identical to `main`, `wiki-ingest-dupcheck` and `tests/test-fetch.sh` unchanged in the diff, seed block byte-identical, all 27 case labels distinct (no numbered/named collision), all 13 stub modes defined and used. The implementation's orthogonality measurement reproduces exactly: cntt's guard off → **19** cntt FAIL / **0** collision FAIL; both fix call sites reverted → **0** cntt FAIL / **16** collision FAIL.

**AC6 — NOT SATISFIED (Captain's, as designed). The claim attached to it is false — see Findings.**

### Findings

**F1 — Material. The suffix token is encoded in four test literals across two cases, not one.** The implementation reports that changing it "touches that line and one deliberately-isolated test assertion … every other assertion is name-agnostic". Changing only `bin/wiki-ingest-run:97` (`tok="${host%.*}"` → `tok="${host%%.*}"`) produced **four** FAIL lines, not one: the isolated shape assertion at `tests/test-guard.sh:552`, plus `collision: exhausted slug ladder is rejected — expected rc=1, got rc=0`, `candidates not named in the message`, and `main advanced to 'Ingest: https://code.example.invalid/q/zed'`. Cause: case E's ladder seed at `tests/test-guard.sh:625-627` and the grep at `:638` hard-code `zed-code-example…`, which encodes the current token; change it and the seeds no longer occupy the ladder, so the ingest legitimately finds a free slug. Evidence fields — *workflow:* answering AC6 and changing that line is this entity's declared next action, not hypothetical; *harm:* a pure taste change reports the fail-closed guard as broken and `main` as having advanced on a source that should have been refused, which reads as a correctness regression in the fix rather than a stale fixture; *affected:* `value-ac[AC6]`, the one criterion carried forward unsatisfied for the Captain, whose cost estimate is the information he will act on; *trigger:* the run above. Task-owned and small — I confirmed the whole remedy is those four literals: with the token changed **and** `code-example` → `code` throughout the test file, `test-guard.sh` is 27/27 green again. That also independently confirms the *mechanism* claim (token-independent) is true; only the *cost* claim is wrong. **I did not fix it** — no candidate mutation before FO authorization.

**F2 — Not a finding against this fix, recorded for accuracy.** The implementation cites the disabled-step-1 delta as `5 -> 6`; in the merged tree it is `9 -> 10` (cntt's cases create raw files first). Same delta, stale figure.

**F3 — Confirmed pre-existing, as claimed.** A `--force` re-ingest whose LLM output is byte-identical stages nothing and exits 1 `incomplete result — no summary/… staged`. Ran the identical stub and inputs against `main`'s `bin/` and the fix's: same rc=1, same message. The "not introduced here" claim is correct.

**F4 — Residual, pre-existing, unchanged by this fix.** The documented batch pattern runs one ingest per URL in parallel; `resolve_slug` resolves against a worktree cut from `main` before the peer merges, so two colliding URLs can both take the base slug. Ran genuinely concurrent colliding ingests, three times each, against the fix and against `main`: identical outcome both trees — the loser exits **1** with `MERGE FAILED after 5 attempts … branch kept for retry`, never a silent clobber, and the retry then sees the base slug occupied and suffixes correctly. Loud and retryable; worth its own entity, not this one.

**Also checked, no finding:** `--verbatim-only` is exercised by no collision case, so I probed it directly — two colliding sources produced `widget-os.md` and `widget-os-code-example.md` under the fix, and a single clobbered `widget-os.md` under `main`. The case-F fail-closed decision is implemented at **both** call sites (`resolve_slug` maps `owning_slug`'s rc=2 → rc=1; `--summary-only`'s `*) exit 1`), and both are asserted separately by case F — each moved under a different falsification.

### Summary

The fix behaves as specified. AC1–AC5 each reproduced green and each watched fail under its own falsifying edit, in a scratch tree so the candidate was never mutated; the duplicate-generator failure mode fires exactly where step 1 is removed, and the cosmetic-variant coverage holds for `.git` too, which no test exercises. The merge with cntt is genuinely orthogonal — the 19/0 and 0/16 split reproduces exactly.

One material finding: AC6's *cost* claim is wrong. The suffix token is encoded in four test literals across two cases, and changing it makes the ladder-exhaustion case report the fail-closed guard as broken — misleading precisely the person acting on the Captain's AC6 decision. The mechanism claim underneath it is sound, and the remedy is confined to `tests/test-guard.sh:552,625-627,638`.

**Recommendation: REJECTED** — narrowly. Nothing about the shipped behaviour needs to change; the correction is those four test literals (derive them from the token instead of hard-coding it) plus the AC6 cost sentence in the implementation stage report. I flag for the FO that accept-with-note is a defensible alternative, since this report now documents the true cost directly above the claim it corrects — that is a proportionality call, and AC6 is the Captain's to answer either way.
