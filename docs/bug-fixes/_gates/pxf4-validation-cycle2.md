# Validation gate (cycle 2) — slug-collision-on-shared-path-segment

**Entity:** `slug-collision-on-shared-path-segment` (`jc`) · **Stage:** `validation` → `done`
**Source:** kata `pxf4` (P2) · **Score:** 0.6 · **Feedback cycle:** 1 (resolved)

## Question

Does the F1 correction hold without trading one problem for a worse one, and does the fix merge?

## The rejected claim is now true, confirmed first-hand

Changing `bin/wiki-ingest-run:97` alone, `tests/test-guard.sh` untouched, with the reviewer's own driver asserting the edit touched exactly one line: `tok="repo"` (the AC6 candidate) → **27/27**. `tok="x"` → **27/27**. All five rows of the implementation's table reproduce. In cycle 1 the first of these gave four FAIL lines across two cases.

## The risk I flagged did not materialise

The obvious way to "fix" F1 is to stop asserting the suffix at all — a suite that checks nothing also passes every token scheme. I dispatched that specifically, and the reviewer went past the implementation's own evidence (which offered only cases C and E) to break the suffix behaviour **three ways and check case A itself**:

- `resolve_slug` returns the base — the original clobber → 4 case-A failures, including `second source's slug is 'widget-os', expected 'widget-os-' plus a non-empty disambiguator`
- disambiguator collapses to empty → case A red on `'widget-os-'`
- suffix replaces the base instead of extending it → case A red on `'code-example'`

And in all three, case E additionally reports `no disambiguator learned in case A, so the ladder cannot be built` — **the learned-token plumbing fails loudly rather than skipping silently**, which is exactly the failure mode a learn-from-behaviour design most invites. That is the check I most wanted and did not get from the implementation.

## The scope caveat is accurate in both directions

The implementation claimed the suite is agnostic to host-derived and constant tokens, but a path-varying scheme would need case E revisited. Verified both ways: five host/constant schemes green; a token varying with the URL path breaks case E **and only case E** (26 ok, 3 FAIL). A token varying with the base slug does the same, and sits inside the caveat's wording since the base slug *is* the last path segment. In every such case the failure is **red, not silently green** — the safe direction.

## The load-bearing scope claim

`bin/` byte-identical to cycle 1, verified **three independent ways**: `git diff` empty over `bin/`, per-file shasums equal across all five scripts, and a `diff` against the reviewer's own cycle-1 copy taken *before* any falsification. So AC1–AC5 carry forward intact and this cycle is test-file and report only.

The duplicate-generator guard was **not** carried forward — it was re-run against the reworked suite, and still fires at `9 -> 10`. The rework did not weaken it.

27/27 in the merged tree, cntt's cases and the collision cases in one run. Seed block sha1 `47c4675e…`, still byte-identical to `main`'s.

## Findings

**None material, none new.** Two observations recorded without disposition:

- **By design:** case A's structural assertion accepts any non-empty base-preserving suffix, so it no longer distinguishes an informative token from an arbitrary one — `tok="x"` passes. That is the intended consequence of the F1 fix and precisely what AC6 reserves to the Captain. The properties AC1 actually promises are all still asserted and all still fail when broken.
- **Polish, not raised:** when case E's ladder assumption is broken by a path-varying scheme, its output is still the misleading `main advanced to 'Ingest: …'` shape. But that now appears only for a genuinely different design rather than a taste change, and the caveat is documented — the cycle-1 harm is gone.

## AC6 — carried to the Captain, unsatisfied by design

The suffix scheme remains his call: `bin/wiki-ingest-run:97`, one line, and now genuinely one line. It currently yields `cloudflare-os-github`; his 2026-08-06 hand resolution chose `cloudflare-os-repo`, and `tok="repo"` is verified to leave the suite fully green. Nothing is renamed either way, and the fix affects only new ingests.

## Recommend

**Approve** — merge to `main`, terminal, with AC6 carried to the Captain.

Checklist: 3 done, 0 skipped, 0 failed (`docs/bug-fixes/slug-collision-on-shared-path-segment.md` lines 503–537).
