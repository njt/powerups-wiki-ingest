# Validation gate — escape-positional-in-surf-awk-snippet

**Entity:** `escape-positional-in-surf-awk-snippet` (`yp`) · **Stage:** `validation` → `done`
**Source:** kata `dw2f` (P2) · **Score:** 0.5

## Question

Do the three acceptance criteria hold under independent reproduction, and does the fix merge to `main`?

## AC cross-check

| AC | Verdict | Evidence the validator produced itself |
|---|---|---|
| AC-1 — expansion with 3+ args yields an intact awk program | **PASS** | Real `claude` binary, renamed sandbox copy (`cmp` clean), session `3dccb032` — exactly one matching line ending `awk '{printf "%.0f\n", $NF}')`, no `http` in it |
| AC-2 — documented pipeline extracts `359286798` from real surf output | **PASS** | `test-fetch: ALL PASS`, rc=0; the case `sed`-extracts the block and executes it against a stub `surf` rather than grepping the markdown |
| AC-3 — guard exits non-zero instead of falling through | **PASS** | Same suite; red with `exit 1` removed |

**Mechanism→value re-anchor.** AC-1 is the value AC — it measures the end the fix exists for. AC-2 and AC-3 are mechanism ACs serving it, and AC-1 is satisfied, so neither passes on a regressed end value.

**Every negative case was watched going red**, which is what separates this from a vacuous green:

- AC-1: the reverted copy (a one-token `diff`) puts `https://c.example/3` back inside the awk program — session `60a71449`.
- AC-2: red on the literal `\$2` variant and on the `sed`-strip variant.
- AC-3: red with the `exit 1` removed.
- Anchor-break: renaming the `TAB_ID=` anchor yields `FAIL: tab-id block extracted empty` — so the pair cannot pass on nothing if a future edit breaks the `sed` span.

## The disclosed limitation, confirmed rather than quietly dropped

AC-2 passes on the unfixed-but-`$2` file. The validator confirmed this and recorded it as the test plan's disclosed limitation, not a defect: the on-disk text was always well-formed, and only the expansion corrupts it. Only AC-1 bears on the expansion bug. This framing survived all three stages intact, which is the outcome the ideation gate turned on.

## Scope

`git diff --name-only main..HEAD` = `CLAUDE.md`, `commands/wiki-ingest.md`, `tests/test-fetch.sh`, and the entity file. `git diff main..HEAD -- bin/ assets/ tests/test-guard.sh` is **empty**. The `test-guard.sh` seed is byte-identical to `main`. Nothing moved that was not declared.

## Blast radius of the new `exit 1`

The validator checked this rather than assuming it. It fires only when `TAB_ID` is empty — `surf tab new` failed, or its output carried no `tabId:` line — both genuinely fatal for the surf fallback, since there is no tab to navigate. It cannot fire on a healthy path. Inside a `Bash` tool call it ends that call, not the parent agent, and the sibling background ingests are separate calls already finished before the fallback runs. Skipping `surf tab close` on that path is correct: no tab was created.

## Findings and FO disposition

Both are **Polish** — no current user-visible loss, no protected boundary at risk. The validator recommended decline; that recommendation is advisory, and I authorize both declines here.

1. **Prose drift in the implementation report** — it cites AC-2's literal-`\$2` red as `yielded 'TAB_ID='`; re-run against the committed file it is `yielded ''`, because the `exit 1` from the same commit now aborts before the `printf`. Same test, same reason. **Declined** — the validation report carries the corrected value, so the record as a whole is accurate.
2. **`exit 1` would close a persistent interactive shell** if a human pasted the guard fragment alone. **Declined** — not a supported workflow; the block is written for agents, and the alternative is the original silent fall-through this fix exists to remove.

## Declined check, stated rather than hidden

The validator did not drive real Chrome to re-confirm `NF=2` on live `surf tab new` output. It gave the reason: the fixture was captured live at ideation, the structural argument holds (a YAML scalar float cannot contain whitespace, so the grepped line is two fields by construction), and it verified `NF=2` on the fixture. Its stated ground for declining — *"creating a tab in the Captain's browser while he is asleep is a side effect no AC asked for"* — is correct judgment, and I am accepting the decline rather than overriding it.

## Recommend

**Approve** — merge to `main`, terminal. Checklist: 3 done, 0 skipped, 0 failed (`docs/bug-fixes/escape-positional-in-surf-awk-snippet.md` lines 286–317).
