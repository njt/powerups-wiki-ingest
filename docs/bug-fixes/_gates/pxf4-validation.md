# Validation gate — slug-collision-on-shared-path-segment

**Entity:** `slug-collision-on-shared-path-segment` (`jc`) · **Stage:** `validation` → `implementation` (rejected)
**Source:** kata `pxf4` (P2) · **Score:** 0.6

## Question

Do the ACs hold, and does the fix merge?

## The shipped behaviour is sound

AC1–AC5 each reproduced green **and** each watched failing under its own `Falsified by:` edit, with every falsification run in a `cp -R` scratch tree so the candidate was never mutated. 27/27 green in the merged tree — cntt's cases 1–15/13b and the collision cases A–F in one run. Seed block sha1-identical to `main`'s.

The duplicate-generator failure mode — the one I was most worried about — fires exactly where step 1 is removed: `collision B — re-ingest added an archive (9 -> 10)`. The control is not vacuous.

Two things the validator checked that no test covers:

- **`.git` variant.** The suite's single cosmetic variant folds http + `www.` + no-trailing-slash + `#fragment`, but **`.git` is exercised nowhere**. Probed separately: each `--force` re-ingest kept `raw/` at one file. Non-vacuous — against a defeated step 1 the same probe minted six duplicates including `cloudflare-os-git.md`.
- **`--verbatim-only`**, exercised by no collision case: two colliding sources produce two archives under the fix and a single clobbered file under `main`.

The orthogonality measurement with cntt reproduces exactly — 19/0 and 0/16.

## Why I am rejecting: F1 is Material

The implementation reported that changing the suffix token "touches that line and one deliberately-isolated test assertion … every other assertion is name-agnostic."

**That is false.** Changing only `bin/wiki-ingest-run:97` produces **four** FAIL lines, because case E's ladder seed at `tests/test-guard.sh:625-627` and the grep at `:638` hard-code `zed-code-example`, which encodes the current token. Change the token and those seeds no longer occupy the ladder, so the ingest legitimately finds a free slug — and the suite reports:

```
collision: exhausted slug ladder is rejected — expected rc=1, got rc=0
collision E — candidates not named in the message
collision E — main advanced to 'Ingest: https://code.example.invalid/q/zed'
```

### Why this is material rather than a stale fixture

The four evidence fields:

1. **Released user and normal workflow** — answering AC6 *is this entity's declared next action*. The Captain was handed that line deliberately, with a stated cost. Not hypothetical.
2. **Observable harm** — a pure taste change reports the **fail-closed guard as broken** and `main` as having **advanced on a source that should have been refused**. That reads as a correctness regression in the fix, not a stale test fixture.
3. **Affected value AC** — `value-ac[AC6]`, the one criterion carried forward unsatisfied for the Captain. Its cost estimate is the information he acts on.
4. **Trigger evidence** — the run above.

The validator offered accept-with-note as a defensible alternative, on the grounds that this report now documents the true cost directly above the claim it corrects. I considered it and I am not taking it, for one reason: **the note lives somewhere he may not read, and the failure lands somewhere he certainly will.** He will go to `bin/wiki-ingest-run:97` because that is where the summary points him, change one token, run the suite, and see the fail-closed guard reported broken. A correction that depends on him having read a validation report first is not a correction.

The mechanism claim underneath is sound — the validator confirmed it independently by changing the token *and* the four literals and getting 27/27 green again. Only the cost claim is wrong.

## Disposition — FO authorization

**F1 — Material. Authorized: `fix`.** Derive the four literals from the token instead of hard-coding it, so the suite is genuinely token-agnostic, and correct the AC6 cost sentence in the implementation stage report.

**F2 — Polish. Authorized: `fix`, folded into the same round.** The stale `5 -> 6` figure is `9 -> 10` in the merged tree. Normally a decline, but the ensign is editing that report anyway and a wrong number in the evidence section is cheap to correct while it is open.

**F3 — Confirmed pre-existing, no action.** The byte-identical-LLM-output `rc=1` reproduces against `main`'s `bin/`. The "not introduced here" claim is correct.

**F4 — Residual, pre-existing, out of scope. Declined and filed separately.** The documented batch pattern runs one ingest per URL in parallel, so `resolve_slug` resolves against a worktree cut before a peer merges and two colliding URLs can both take the base slug. Verified identical on the fix and on `main`, three runs each: the loser exits 1, `branch kept for retry`, never a silent clobber, and the retry suffixes correctly. Loud and retryable — a real residual, but not a regression and not this entity's.

## Recommend

**Reject** — narrowly, and test-file only. Nothing about the shipped behaviour changes.
