# Validation gate — guard-auto-commit-against-conflicted-merge

**Entity:** `guard-auto-commit-against-conflicted-merge` (`2e`) · **Stage:** `validation` → `implementation` (rejected)
**Source:** kata `cntt` (P1) · **Score:** 0.9

## Question

Do the seven acceptance criteria hold, and does the fix merge?

## The validation work itself was excellent

All seven ACs reproduced independently, with every falsifying edit applied to a *scratch copy* (`git archive HEAD | tar -x`) rather than the worktree. The load-bearing design claim is now measured rather than argued: the skip-instead-of-exit variant destroys the captain's merge and its hand-resolved working tree, which is exactly the damage AC2 exists to prevent. Case 15's fixture self-check was verified by breaking the fixture. Assertion shape was checked per case against "what single edit would pass while the bug is present".

None of what follows is a criticism of that work. It is one census that could not have come out any other way.

## Why I am rejecting: finding 1 is Material, not Deferred risk

The validator found that the belt-and-braces marker scan **fails open on non-ASCII paths**. Under git's default `core.quotePath`, `git diff --cached --name-only` C-quotes such paths, so the loop's `git show ":$p"` fails and is swallowed by `2>/dev/null`. Reproduced: three staged files all carrying `<<<<<<< `, and only `topic/Plain Name.md` was caught.

It classified this **Deferred risk** on the evidence that *"the live wiki has 0 of 2889 tracked paths with a non-ASCII byte"*, with promote-to-material on "the first such page title".

**That census is self-defeating, and the number is wrong.** The check was `git ls-files | grep -cP '[^\x00-\x7F]'`. With `core.quotePath` at its default, git has *already* C-quoted those paths in its output — `topic/Café.md` is emitted as the literal ASCII string `"topic/Caf\303\251.md"`. The output is ASCII **by construction**, so that grep can only ever return 0. The very quoting that causes the bug is what makes the census read clean. It is a check that cannot fail — the exact class this workflow's README bans.

Measured the other way, against the same live wiki, read-only:

```
$ git -c core.quotePath=true ls-files | grep -c '^"'
80
```

**80 of 2889 tracked paths are quoted today** — 80 of 991 topic pages. And they are not exotic: the wiki's dominant title convention is an em-dash separator (`20-20-20 Rule — Digital Eye Strain Study.md`, `ARIES — Write-Ahead Logging Recovery.md`). U+2014 is non-ASCII.

So the promote-to-material condition is not a future event awaiting a first trigger. It was met before the guard was written, on roughly 8% of the live wiki, including the busiest naming pattern in it.

### The four evidence fields

1. **Released user and normal workflow** — Nat, ingesting URLs into the live wiki. The supported path.
2. **Observable harm** — conflict markers committed silently into a topic page whose title carries an em-dash. Identical to the 2026-08-06 incident this entity exists to prevent.
3. **Affected value AC** — `value-ac[AC-4]`: *"conflict markers are refused even with no operation in progress."* The property does not hold for 80 existing pages.
4. **Trigger evidence** — the validator's own reproduction of the skip, plus the census above.

All four establish supported-workflow harm to a value AC. That is **Material**.

The irony is worth stating plainly: this fix exists because a tool proceeded when it should have stopped, and said it was fine. Its belt-and-braces scan currently does the same thing for one page title in twelve.

## Disposition — FO authorization

**Authorized: `fix`.** Owned Material, in scope, and the remedy is one token the validator already verified working:

```
git -C "$WIKI" -c core.quotePath=false diff --cached --name-only
```

Findings 2 and 3 (cases 12/12b asserting message rather than damage; AC1/AC3 `Fails if:` text overstating observability) are **Polish — declined**. They are correct and non-material, and I am not spending a rework cycle on wording. Finding 2's suggested `--diff-filter=U` assertion is recorded here should anyone revisit those cases later.

## Concrete revise assignment

1. Add `-c core.quotePath=false` to the marker scan's `diff --cached --name-only` in `bin/wiki-ingest-run`. Check whether `wiki-ingest-backfill`'s guard needs the same treatment and say what you found.
2. Extend `tests/test-guard.sh` case 13 (or add 13b) with a **staged marker-bearing file whose name carries an em-dash** — the wiki's real convention, not a contrived accent. Watch it fail before the one-token fix, and record the red output verbatim.
3. Re-run both suites and `/bin/bash -n` over `bin/`.

Do not re-triage. The classification, disposition and assignment above are authorized; carry them out.

## Recommend

**Reject** — route to implementation to close the non-ASCII hole in AC-4's mechanism. Everything else about this fix is sound and stays as built.
