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
6. **Extractor tool:** `trafilatura` (Python) — fetches and readability-extracts to Markdown. **Validated 2026-07-05:** installed via `pipx install trafilatura` (CLI at `~/.local/bin/trafilatura`; Homebrew Python is PEP-668 externally-managed, so pipx, not `pip --user`). On a clean blog it produced clean structured Markdown (headings/bold/lists/blockquotes); on a Substack that *failed the LLM's WebFetch earlier* it retrieved the full article (direct HTTP+extraction beats WebFetch on server-rendered sites → likely higher backfill hit-rate); on true JS-only SPAs (x.com, reddit) it returned **0 bytes** (cheaply gate-able).

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
- **Verbatim-only mode** (e.g. a `--verbatim-only` flag on the fetch/verdict path): fetch → LLM CONTENT/BLOCKED verdict → on CONTENT write `raw/<slug>.md` only, touching no `summary/` or `topic/` file. Phase 3 backfill reuses this exact mode; building it here (not as a Phase-3 one-off) keeps a single tested code path.
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

**Safety invariant (non-negotiable): backfill is strictly additive to `raw/`. It never creates, modifies, or deletes any `summary/` or `topic/` file.** A failed or BLOCKED re-fetch must leave the existing summary (and topic page) completely intact and simply queue the URL. We must not trade an existing summary for a failed fetch.

This means backfill does **not** run the full ingest pipeline (which regenerates and would overwrite `summary/` + `topic/`). It runs a narrower **verbatim-only mode**:

```
for each source lacking a raw/<slug>.md:
  fetch+extract (trafilatura; surf on pass 2)
    → stage candidate text
    → LLM verdict: CONTENT or BLOCKED?   (verdict ONLY — no summary/topic regeneration)
        CONTENT → write raw/<slug>.md (verbatim) and nothing else
        BLOCKED → write nothing; log to ingest-queue.md
```

- Two-pass over the ~700 sources: Pass 1 HTTP fetch+extract; Pass 2 surf-retry the BLOCKED/failed set; remainder logged to `ingest-queue.md` with reason (dead / paywalled / bot-blocked).
- Runs in the background; idempotent (skip sources that already have a `raw/` verbatim file).
- Report hit-rate; expect a meaningful miss tail for older/dead links.
- Because `summary/` and `topic/` are never written by backfill, even a bug cannot lose them (and they remain in git history regardless).

## Sequencing & rationale

Phase 1 builds the fetch+extract module and locks the three-dir layout and schema. Phase 2 reshapes existing files into it. Phase 3 reuses Phase 1's module to populate `raw/`. Each phase is a separate spec→plan→implement cycle with a review checkpoint. If backfill hit-rates disappoint, Phases 1–2 still stand alone.

## Out of scope

- A forced-surf domain shortcut list (future optimization).
- Re-generating existing summaries/analyses (Phase 2 preserves them as-is; only structure moves).
- Any change to the wiki *content* repo's remote/hosting.

## Load-bearing items

- ✅ **trafilatura install + output quality — VALIDATED 2026-07-05** (see decision 6). pipx install; clean Markdown on real pages; 0 bytes on JS-only SPAs; beats WebFetch on Substack. Implication: an **empty/near-empty fetch is short-circuited straight to surf** (nothing to hand the LLM), which is not a content-verdict — it's "we got nothing." This does not violate the LLM-verdict-only decision.
- ⏳ **exit-3 inversion (to prove in Phase 1's tests):** when the script pre-stages `raw/<slug>.md` and the LLM judges BLOCKED (deletes raw/, writes nothing), the script must treat the net-empty result as exit 3 (→ surf), NOT as "raw/ present = changes." Design is settled; a Phase 1 test must assert a BLOCKED verdict yields exit 3 and leaves no `raw/` file committed.
