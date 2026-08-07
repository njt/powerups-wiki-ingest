# Validation gate (cycle 2) — guard-auto-commit-against-conflicted-merge

**Entity:** `guard-auto-commit-against-conflicted-merge` (`2e`) · **Stage:** `validation` → `done`
**Source:** kata `cntt` (P1) · **Score:** 0.9 · **Feedback cycle:** 1 (resolved)

## Question

Does AC-4 now hold for quoted paths, and does the fix merge?

## The rejected finding is closed

The reviewer re-measured its own census three ways on the live wiki, read-only, and published the contradiction rather than quietly restating a number:

```
git ls-files                        | grep -c '[^ -~]'   →  0     ← the check that could not fail
git -c core.quotePath=true ls-files | grep -c '^"'       → 80
git -c core.quotePath=false ls-files| grep -c '[^ -~]'   → 80
```

80 of 2889 tracked paths, all under `topic/`, all the em-dash title convention. Its own words: *"classifying it Deferred risk on that evidence was wrong."*

**AC-4 re-reproduced and now holds.** The guard refuses a staged marker-bearing `topic/ARIES — Write-Ahead Logging Recovery.md`, and names the real filename rather than its escaped form. Falsified by deleting **only** the `-c core.quotePath=false` token (sole difference confirmed by `diff`): case 13b goes fully red — `expected rc=1, got rc=0`, `main advanced`, and `conflict markers reached a commit on main: … Auto-commit local changes before ingest merge` — while case 13 (ASCII) stays green.

That is the strongest falsification in the suite. The red run does not merely flip an exit code; it lands `<<<<<<< ` in a commit on `main` **under the incident's own commit subject**.

## What the reviewer re-checked, and why each was the right thing to re-check

It carried forward AC1, AC2, AC3, AC5, AC6, AC7 from cycle 1 rather than re-running everything — correct, since the diff is one functional token plus test cases — but it re-checked exactly what that diff could disturb:

- **AC5, because the diff changed the scan's *input*.** A widened path list risks over-firing on legitimate content. Probed directly: a wiki holding an em-dash-titled page whose body is a setext heading ingests at rc=0 with the page tracked and its `^=======$` intact. `quotePath=false` changes rendering, not the regex.
- **AC6, because case 15's fixture path was renamed.** Green, and its self-check verified live by breaking the fixture. It needed its own `-c core.quotePath=false` to keep matching `^raw/`, and has it.

## The backfill asymmetry claim — checked, not accepted

The implementation argued `wiki-ingest-backfill` needs no equivalent fix. The reviewer verified it three ways instead of accepting the reasoning:

- **Static:** `git show ":$p"` is the *only* place either script feeds a git-produced path back to git as an argument. Every git call in backfill takes a literal path or none, and `$UNMERGED` is only ever reached by `[ -n … ]`.
- **Mechanism:** with the only conflicted path non-ASCII, `--diff-filter=U` is non-empty under *both* quotePath settings — only rendering differs, and emptiness is all the guard tests.
- **Behavioural:** both branches exercised separately — in-progress and unmerged — each rc=1 with index stages `1 2 3` and `MERGE_HEAD` surviving.

## Scope

`bin/wiki-ingest-run` has exactly **one** removed line, replaced by itself plus the token, plus five comment lines; the cycle-1 guard is otherwise byte-identical. The seed block is byte-identical. The six lines removed from `tests/test-guard.sh` are all the case-15 fixture rename, none touching the seed or any pre-existing case. Both suites green under bash 3.2.57, 17 assertions.

## Findings and FO disposition

1. **Correct-but-disproportionate — the unmerged-paths messages print the C-quoted path** (`"raw/Backfill \342\200\224 Conflicted Source.md"`). **Declined.** The guard fires, exits non-zero and preserves state; no AC is affected and the ASCII portion still identifies the file. A third cycle for message cosmetics is not proportionate. Recorded here: the same one-token fix applies at `bin/wiki-ingest-run:676` and `bin/wiki-ingest-backfill:83` if anyone is in there later.
2. **Out of scope — `wiki-ingest-backfill` has no marker-scan equivalent.** Markers already sitting in a `raw/` file with no operation in progress would still be committed by its `git add raw/`. Pre-existing, matches the ideation-approved scope ("the same in-progress/unmerged block"), and not a regression from this rework. **Declined here and filed as its own kata issue** — a proven-shaped hole should not vanish into a closed entity's gate record.

## Recommend

**Approve** — merge to `main`, terminal. The rejection was right, the rework closes it, and the reviewer's self-correction is recorded in the entity rather than smoothed over.

Checklist: 3 done, 0 skipped, 0 failed (`docs/bug-fixes/guard-auto-commit-against-conflicted-merge.md` lines 477–505).
