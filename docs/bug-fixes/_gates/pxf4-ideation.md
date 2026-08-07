# Ideation gate — slug-collision-on-shared-path-segment

**Entity:** `slug-collision-on-shared-path-segment` (`jc`) · **Stage:** `ideation` → `implementation`
**Source:** kata `pxf4` (P2) · **Score:** 0.6

## Question

Is the design sound, and what happens to AC6, which is explicitly a Captain call?

## The decisive finding: a slug collision is not a duplicate

The kata issue guessed that `wiki-ingest-dupcheck` should gain target-slug awareness. **That guess is a worse bug than the one being fixed**, and the ensign established why: dupcheck exits 0 meaning *"already ingested, skip"*. Teaching it to report target-slug collisions would make it exit 0 on a genuinely new source and **reject a page that deserves to exist**. The design therefore leaves dupcheck unchanged and instead *reuses* it as a URL→owning-file lookup — which is the exact primitive needed to tell a legitimate `--force` re-ingest from a real collision.

That reuse is also what keeps the fix small: one new function, two changed lines, no new canonicalization plumbing. Re-implementing URL folding inside `wiki-ingest-run` would give two copies that drift, and the drift failure mode *is* the re-ingest-duplication bug.

## The defect is wider than the incident showed

Exercising the real `url_slug()` text (sole derivation, `bin/wiki-ingest-run:65-78`, reached from exactly two call sites):

- `github.com/a/x` and `github.com/b/x` both slug to `x` — **same-host collisions exist**, so a host-based suffix alone does not close the bug. Hence the ladder's numeric tail.
- The query string is stripped, so **every** `news.ycombinator.com/item?id=N` collapses to `item`.

Call sites were enumerated rather than assumed: `--repo`, `--content`, `--verbatim-only` and the default all pass through one line; `--dry-run` has no collision surface; `wiki-ingest-backfill` derives no slug from a URL at all and needs no change.

## Re-ingest vs collision — the property I was most worried about

I briefed this stage specifically on the risk that a collision-detector turns every re-ingest into a duplicate. The design handles it structurally rather than by special-casing: step 1 asks dupcheck whether any archive already holds this URL (returns that slug, update in place), step 2 only suffixes when nothing does. Verified to survive cosmetic URL differences — trailing `/`, `www.`, `http`/`https`, `#fragment`, `.git`.

A consequence worth noting: against a wiki seeded with your 2026-08-06 hand resolution, step 1 finds `raw/cloudflare-os-repo.md` — a slug **no derivation rule would ever generate**. So a future `--force` re-ingest updates the file you made by hand instead of minting a rival beside it.

## `--summary-only` is in scope, and correctly so

`bin/wiki-ingest-run:124` has the same defect in mirror image: once slugs can be suffixed, `url_slug` no longer identifies which archive a URL lives in, so `--summary-only <url>` could backfill the **wrong source's** precis. The ensign is right that this is not scope creep — leaving it out means *this change introduces* a wrong-file-write path that does not exist today.

## Option (b) properly declined

Host+path slugging is costed as a five-step migration entity (re-slug both tiers, rewrite every `[[raw/…]]` and `[[summary/…]]` footer across `topic/`, rewrite every `log.md` pointer, decide what to do with files lacking `url:` frontmatter, dry-run against a clone). It also reads badly on a phone (`blog-cloudflare-com-cloudflare-os`) and still needs a terminal disambiguator. Declined as out of remit, and explicitly left available later — (a) renames nothing, so (b) stays open.

## AC6 — the Captain's call, and how I am handling it

AC6 is declared **interactive**: the suffix shape. The kata proposed host-based (`cloudflare-os-github`); the Captain's own 2026-08-06 hand resolution chose `cloudflare-os-repo`. Those are different schemes, not the same choice, and the ensign flagged it rather than assuming.

**I am not deciding this, and I am not letting it block the build.** The mechanism is entirely independent of which token gets appended. Implementation proceeds with the host-token ladder as the working default, with the token derivation isolated at a single point so changing it is a one-line edit. AC6 is carried forward **unsatisfied** and will be presented at the validation gate as an open decision.

The cost of guessing wrong is bounded to zero in practice: this fix only affects **new** ingests, renames nothing, and no ingest will run before the Captain wakes. No file will have been minted under the wrong scheme.

## Correction I owe the record

My dispatch brief told this stage that `bin/wiki-ingest-run` "has just changed on main (a new guard around the auto-commit, kata `cntt`)". **That was wrong** — `bd74a28` is not an ancestor of `main`; the `cntt` branch is unmerged. The ensign checked rather than believing me, wrote the design against `main` at `f8616a2` as instructed, and identified the real interaction: the two changes do not overlap in `bin/wiki-ingest-run` (`cntt` at line 657, this at 124 and 261) but **do** overlap in `tests/test-guard.sh`. Coordination noted for implementation.

## Follow-ups this stage identified, to be filed rather than absorbed

- Retroactive sweep for collisions already in the live wiki (group `raw/`+`summary/` by canonicalized `url:`).
- `topic/` page clobbering when an LLM uses `Write` rather than `Edit` on an existing page — different cause, and correctly refused here because its only available proof would be a grep over prompt text.
- `url_slug` discarding the query string, which is what collapses every HN item to `item`.

## Recommend

**Approve** — enter implementation with the host-token ladder as the working default and AC6 carried forward for the Captain.

Checklist: 3 done, 0 skipped, 0 failed (`docs/bug-fixes/slug-collision-on-shared-path-segment.md` lines 223–238).
