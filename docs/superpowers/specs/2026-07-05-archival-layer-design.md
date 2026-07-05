# Wiki Archival Layer — Design

**Date:** 2026-07-05
**Status:** Approved in brainstorming, pre-implementation
**Repo:** primarily `powerups-wiki-ingest` (Phase 1 code); Phases 2–3 operate on the wiki content repo.

## Goal

Give the wiki three distinct layers per source, captured at ingest time so re-reading the original never triggers a runtime fetch:

1. **Verbatim** — the cleaned original article text (or a repo's README), preserved as Markdown.
2. **Summary** — the précis.
3. **Analysis/synthesis** — the topic page, which may span multiple sources.

Today only two artifacts exist and neither is verbatim: `raw/<slug>.md` holds a *summary*, and the flat `<Title>.md` topic page holds quotes/themes/analysis. The original text is never archived. This design adds the verbatim layer, reorganizes into three directories, and backfills the ~700 existing sources.

## Decisions (from brainstorming, 2026-07-05)

1. **Three directories:** `raw/<article-slug>.md` (verbatim), `summary/<article-slug>.md` (summary), `topic/<topic-slug>.md` (analysis). `index.md`/`log.md` stay at the wiki root.
2. **Full migration + verbatim backfill** of existing content (not new-only).
3. **Verbatim fidelity = cleaned article Markdown** (readability-extracted; nav/ads/boilerplate stripped). Repo sources archive the README (already Markdown).
4. **Backfill = two-pass:** HTTP-fetch+extract, then surf-retry the failures, then log the remainder to `ingest-queue.md`.
5. **Content-validity gate = LLM verdict only.** No deterministic pre-filter, no forced-surf domain list. Every fetch's text is judged CONTENT/BLOCKED by the ingest LLM.
6. **Extractor tool:** `trafilatura` (Python, `pip install`) — fetches and readability-extracts to Markdown. *Load-bearing: verify output quality and that pip install is acceptable before Phase 1 build.*

## Why fetching moves out of the LLM

Today the LLM `WebFetch`es and writes a summary, so no verbatim copy ever exists. To archive verbatim deterministically, the **script** fetches (trafilatura → cleaned Markdown), stages it in `raw/<slug>.md`, and hands it to the LLM as pre-fetched content (generalizing today's `--content` path). The LLM never fetches. Benefits: a real archive, deterministic/testable fetching, and "read it all later" never re-fetches.

## The content-validity gate (the load-bearing risk)

Moving fetch into the script introduces the **false-success** risk: many sites (x.com, Substack, JS SPAs, paywalls, Cloudflare/consent interstitials) return HTTP 200 with a login wall or app shell instead of the article. Naively archiving that would poison `raw/` — and silently, at 700-item backfill scale.

The gate, per decision 5, is **the LLM's judgment, reusing the existing empty-output → exit-3 signal**:

```
script fetches URL via trafilatura → stages text in raw/<slug>.md
  → LLM step 0: "Is raw/<slug>.md the real article, or a login/paywall/JS/consent/bot page?"
       CONTENT  → keep raw/<slug>.md; write summary/<slug>.md + topic/<Title>.md
       BLOCKED  → delete raw/<slug>.md; write nothing
  → script: LLM produced output?
       yes → commit raw/ + summary/ + topic/
       no  → exit 3 (no changes) → orchestrator retries via surf
              → surf grab staged, LLM judged again → still BLOCKED → ingest-queue.md
```

The LLM *producing* summary+topic is itself the CONTENT verdict — the same mechanism the current pipeline already uses (from the 2026-07-05 recursion fix, where a failed fetch means "write nothing, exit 3"). No new signalling plumbing. Verbatim only lands in `raw/` on a CONTENT verdict; nothing that can't be gotten cleanly is ever archived as a false success.

**Accepted tradeoff:** without a forced-surf domain list, known-JS sites burn one cheap HTTP+verdict roundtrip before falling to surf. Recorded as a future optimization (a domain shortcut list), not built now.

## Phase 1 — Forward pipeline (plugin v1.1.0)

New ingests produce all three tiers with a real archive.

- **New fetch+extract module** (`bin/wiki-ingest-fetch` or inline in `wiki-ingest-run`): given a URL, fetch via trafilatura → cleaned Markdown → stdout/file. Repo mode: use the cloned README. Deterministic, unit-testable.
- **`wiki-ingest-run` changes:** fetch verbatim → stage `raw/<slug>.md` → invoke the LLM with the "judge then write summary/ + topic/" prompt (no WebFetch). Commit logic keys off LLM output as today (empty → exit 3). The `--content` path becomes the common case rather than a fallback.
- **Prompt changes:** add the CONTENT/BLOCKED step-0 instruction; retarget outputs to `summary/<slug>.md` and `topic/<Title>.md`; drop WebFetch instructions.
- **Schema update:** `assets/wiki-CLAUDE.md` (and the live wiki `CLAUDE.md`) document the three-directory layout, the verbatim/summary/topic split, and the frontmatter home (`raw/` carries the `url:` line that dup-check depends on).
- **surf fallback** keeps working: a surf grab is staged into `raw/<slug>.md` and judged the same way.
- Ships as plugin **v1.1.0** (new behavior + new layout); marketplace bump.

## Phase 2 — Migrate existing structure (mechanical, no network)

- `git mv raw/*.md → summary/*.md` (existing raw files are already summaries).
- `git mv` the ~600 flat `<Title>.md` topic pages → `topic/`.
- Rewrite source footers `*Sources: [[raw/x]]*` → `[[summary/x]]`; audit any other path-style references. Name-based `[[wikilinks]]` need no change.
- Leaves `raw/` empty and ready for Phase 3. Fully reversible; no data loss.
- Do this as its own reviewable change before backfill.

## Phase 3 — Verbatim backfill (slow, lossy)

- Two-pass over the ~700 sources using Phase 1's fetch+extract module:
  - Pass 1: HTTP fetch+extract → LLM CONTENT/BLOCKED → on CONTENT write `raw/<slug>.md`.
  - Pass 2: surf-retry the BLOCKED/failed set → judge again.
  - Remainder: log to `ingest-queue.md` with reason (dead / paywalled / bot-blocked).
- Runs in the background; idempotent (skip sources that already have a `raw/` verbatim file).
- Report hit-rate; expect a meaningful miss tail for older/dead links.

## Sequencing & rationale

Phase 1 builds the fetch+extract module and locks the three-dir layout and schema. Phase 2 reshapes existing files into it. Phase 3 reuses Phase 1's module to populate `raw/`. Each phase is a separate spec→plan→implement cycle with a review checkpoint. If backfill hit-rates disappoint, Phases 1–2 still stand alone.

## Out of scope

- A forced-surf domain shortcut list (future optimization).
- Re-generating existing summaries/analyses (Phase 2 preserves them as-is; only structure moves).
- Any change to the wiki *content* repo's remote/hosting.

## Load-bearing items to validate before/within Phase 1

- `trafilatura` install path and output quality on a sample of real wiki URLs (does it yield clean Markdown; how does it behave on the JS-shell false-success cases the gate must catch).
- That the empty-output → exit-3 → surf mechanism still holds when raw/ is pre-staged by the script (the script must treat "LLM deleted raw/ and wrote nothing" as exit 3, not "raw/ present = changes").
