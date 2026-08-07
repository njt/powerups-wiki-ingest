# Ideation gate — escape-positional-in-surf-awk-snippet

**Entity:** `escape-positional-in-surf-awk-snippet` (`yp`) · **Stage:** `ideation` → `implementation`
**Source:** kata `dw2f` (P2) · **Score:** 0.5

## Question

Is `$NF` the right fix, is the bail-out change in scope, and is AC-1 an honest proof?

## The correction that matters most

The kata issue — and the FO's own backlog-gate summary — said `$2` becomes the *second* URL and that the bug fires for "every batch of two or more URLs". **Both are wrong**, and the second one would have sunk the investigation.

The ensign measured Claude Code's expander directly with a four-argument probe and read the expansion back out of the session transcript. Substitution is **0-based**: `$0` is the first argument, so `$2` is the **third**. Out-of-range indices survive untouched. Therefore **the bug requires three or more URLs** — a two-URL reproduction passes cleanly against the unfixed file and would have been read as "not reproducible".

The full substitution table is in the fix body, including that `\$2` does get its backslash consumed, `$NF` and `$(NF)` survive untouched, and `$$2` is *not* an escape (it yields `$https://c.example/3`). The `Skill`-tool invocation path was confirmed to behave identically to the slash-command path.

The claim that line 70 is the only affected site was re-verified rather than repeated: every `$` in the file was enumerated (11 sites), and line 70's is the only digit-indexed form.

## Is `$NF` right, over the smaller `\$2` escape

Yes, and the reasoning is the strongest thing in this design. `\$2` is correct **only in front of Claude Code's expander**. Every other reading of the file — the `Read` tool during development, GitHub's markdown view, a person copying the block — yields a literal `\$2`, and `awk '{printf "%.0f\n", \$2}'` is a syntax error that exits 2 with no stdout. That is *the identical empty-`TAB_ID` failure this fix exists to remove*, reintroduced through a different door. Verified, not reasoned about.

`$NF` is correct on every reading path, and the equivalence is structural rather than incidental: `surf tab new` prints YAML, `grep "tabId:"` isolates one line, and a YAML scalar float cannot contain whitespace, so that line is two fields by construction. Confirmed end-to-end against live surf output, including a `surf tab close` against the extracted id.

A runner-up (`awk -v k=2 … $k`) is recorded so this gate could overrule; it was rejected as indirection buying insurance against a drift YAML structure already precludes. I agree with the call.

## The second change — in scope

The ensign found a second defect and flagged it as separable: lines 71–74 say "bail out of the surf fallback entirely" in a comment, but the code has no `exit`. Measured: the block exits **0** with a warning on stderr, so a verbatim paste falls through to `surf navigate --tab-id ""`. The diagnostic also names only Chrome and the extension, which is why the one agent who hit this went hunting for a browser problem that did not exist.

I am approving it in scope. This workflow's README makes "fail closed, and loudly" a stated rule, and this is precisely the silence mechanism that turned a broken snippet into an invisible one. Fixing the token without fixing the fall-through would close the defect while leaving the thing that hid it.

## Is AC-1 an honest proof

Yes — and this is the gate's central concern, because the tempting proof here was a grep over the very file we edit.

AC-1 drives the **real `claude` binary** against a byte-identical copy of `commands/wiki-ingest.md` (verified with `cmp`) in a throwaway sandbox, then reads the expansion out of Claude Code's own session transcript. The expected value comes from the expander, not from the file under test. Three hard-won details are recorded: three URLs are required; the copy must be renamed or it collides with the installed plugin and the transcript carries two expansions; and it must run against the sandbox copy, not the marketplace cache, which will lag once the fix lands.

The refusal recorded in `## Out of scope` is the right one: a harness reimplementing Claude Code's substitution would be a second implementation of the thing under test and would go green whether or not the real expander works.

**The honesty worth rewarding:** AC-2 *passes on the unfixed file* and can never go red on the expansion defect, because the on-disk text was always fine. The ensign states this plainly instead of presenting it as coverage. Only AC-1 bears on the actual bug.

**The cost this gate accepts:** AC-1 needs one live API call, so it cannot join `tests/test-fetch.sh` or `tests/test-guard.sh`, both of which must run with no network and no LLM. It stays a recorded, re-runnable manual command rather than a committed test. That is the correct trade — a committed offline proxy would be the tautology, and the alternative is no proof at all.

## Recommend

**Approve** — enter implementation with the `$NF` fix, the bail-out `exit 1`, and the `CLAUDE.md` convention line. No AC is written for the convention line, correctly: asserting `CLAUDE.md` contains a sentence we just wrote is the prose-grep the README bans.

Checklist: 3 done, 0 skipped, 0 failed (`docs/bug-fixes/escape-positional-in-surf-awk-snippet.md` lines 236–249).
