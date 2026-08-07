# Backlog gate — escape-positional-in-surf-awk-snippet

**Entity:** `escape-positional-in-surf-awk-snippet` (`yp`) · **Stage:** `backlog` → `ideation`
**Source:** kata `dw2f` (P2) · **Score:** 0.5

## Question

Does this advance to ideation, and does it run concurrently with the `cntt` guard?

## Is it a real defect

Yes. `commands/wiki-ingest.md` line 70 documents the surf tab-id extraction with a bare `$2` inside an awk program. Claude Code substitutes positional parameters when expanding the command body, so on a multi-URL invocation the `$2` is replaced by the user's second URL. Observed 2026-08-07 with 26 URLs, the snippet arrived as:

    ... | awk '{printf "%.0f\n", https://keel-iot.eu/blog/state-oriented-consistency.html}'

which is not a valid awk program. `TAB_ID` comes back empty, and the guidance immediately above the snippet says to bail out of the surf fallback when `TAB_ID` is empty — so the whole browser-fallback path dies silently for every batch of two or more URLs. Single-URL invocations are unaffected, which explains why it went unnoticed.

Same family as the rest of the backlog: it fails quietly and reports nothing.

## Is it correctly scoped as a bug

Yes, and it is the smallest item here — a one-line change in one markdown file.

## Why concurrent with `cntt`

Zero file overlap. This fix touches `commands/wiki-ingest.md` only; the `cntt` guard touches `bin/wiki-ingest-run`. Two concurrent worktrees on disjoint files is exactly what the declared `concurrency: 2` is for, and running the cheapest fix alongside the most urgent one costs nothing.

## The trap this gate must flag forward

The fix lives in a markdown file, which makes the obvious verification a tautology. Grepping `commands/wiki-ingest.md` for the escaped `\$2` proves only that we typed what we typed — the file asserting its own contents. The behavioral claim is about what Claude Code's expansion *does* when a second argument is present, and that needs an exercised expansion.

Ideation must declare whether that AC is **offline** (a reproducible command) or **interactive** (needs the Captain or a live drive), and must not build a harness to fake an interactive one. An honest "interactive, waits for the Captain" is an acceptable outcome for this AC; a green tautology is not.

## Recommend

**Approve** — advance to ideation, concurrent with `guard-auto-commit-against-conflicted-merge`.
