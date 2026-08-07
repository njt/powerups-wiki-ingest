---
id: ypjex7e2gedwvx040yf97pw1
title: Bare $2 in the surf awk snippet is replaced by the user's second URL argument
status: backlog
source: kata:dw2f
started:
completed:
verdict:
score: 0.5
worktree:
issue:
pr:
mod-block:
---

## Problem

`commands/wiki-ingest.md` line 70 documents the surf tab-id extraction as:

    TAB_ID=$(surf tab new ... | grep "tabId:" | awk '{printf "%.0f\n", $2}')

Claude Code substitutes positional parameters when expanding the command body, so that bare `$2` is replaced with the *second argument the user passed*. Observed 2026-08-07 running `/wiki-ingest` with 26 URLs, the snippet arrived as:

    ... | awk '{printf "%.0f\n", https://keel-iot.eu/blog/state-oriented-consistency.html}'

which is not a valid awk program. An agent that pastes the documented snippet verbatim gets an empty `TAB_ID`, and the guidance immediately above it says to bail out of the surf fallback entirely when `TAB_ID` is empty — so the whole browser-fallback path silently dies for every batch of two or more URLs. Single-URL invocations are unaffected, which is presumably why it went unnoticed.

The irony is that this line is itself the fix for an earlier bug — the comment above it warns not to sed-strip at the dot. The correct value never survives to the reader.

## Proposed approach

Escape it as `\$2`, or use `$(NF)`, or restructure so the field index is not a bare positional. Ideation should pick one and say why; `$(NF)` avoids the trap entirely rather than escaping around it, which may be worth more than the diff size.

Grep the whole file — line 70 is currently the only `$N`, but the same trap applies to any shell example added later. Whether that warrants an inline warning comment for future editors is an ideation call.

## Acceptance criteria

To be written at ideation. Note the constraint in the workflow rules: grepping `commands/wiki-ingest.md` for the escaped form proves only that the file contains what we typed. The behavioral claim — that Claude Code's expansion now leaves the snippet intact when a second argument is present — needs an exercised expansion, not a text match. Ideation should declare whether that AC is offline or interactive, and if interactive, say so rather than building a harness to fake it.

## Test plan

To be written at ideation.

## Out of scope

The surf fallback's own behaviour once `TAB_ID` is correct. This fix restores the documented snippet to working order; it does not audit the rest of the fallback path.
