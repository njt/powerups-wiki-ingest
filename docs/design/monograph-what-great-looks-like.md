# What Great Looks Like

*A monograph on wiki ingestion and automatic curation.*
*Written 2026-08-08 against a wiki of 919 archived sources, 1,020 digests and 1,017 topic pages.*

---

## 1. Thesis

**A wiki is not a pile of pages. It is a compiled artifact over an immutable source corpus.**

Everything good follows from taking that sentence literally. If topic pages are *compiled*, they can be regenerated — so a better prompt improves a thousand pages instead of the next twenty-six. They can be split, merged, and rewritten — so the structure can change as understanding changes. They can be audited against their inputs — so "confidently wrong" becomes detectable rather than permanent. And they cannot conflict, because only one process writes them, one at a time, from inputs that never move.

Everything bad in the current system follows from the opposite premise: that a topic page is a *mutable store* which each new source visits and appends to.

Karpathy's pattern names three operations — **ingest, query, lint**. This wiki implements ingest, smuggles a degenerate form of lint inside it, and has no query. The single most consequential change available is to pull curation out of ingestion and make it a first-class operation over the whole corpus.

---

## 2. Where we actually are

Measured, not asserted.

| population | count | what it really is |
|---|---:|---|
| topic pages citing exactly one source | **922** | a digest with opinions bolted on |
| topic pages citing two or more sources | **21** | genuine synthesis |
| topic pages whose sources had to be reconstructed | 69 | accretion hubs |
| topic pages with no recoverable provenance | 5 | un-auditable, un-rebuildable |
| **total** | **1,017** | |

**91% of the wiki's topic pages are built from exactly one source.** They are
not topics; they are digests with opinions bolted on. Only 21 pages in a
thousand-page wiki do the thing the tier exists to do.

The reconstructed hubs are the ones with names like `Software Engineering Craft`
(2,952 words), `Agent Coding Workflow` (3,169), `Databases and Data`,
`Agent Memory and Context`, `Guardrails and Feedback Loops`,
`Agent Orchestration`. They are the only real *topics* in the wiki, and they are
the exact pages that collide on every concurrent batch: seven merge failures
across eleven conflicted files in the 2026-08-08 run, eleven genuine content
conflicts since 2026-08-05.

That correlation is not a coincidence; it is the diagnosis. The hubs are the only pages that many sources legitimately want to touch, and the architecture gives them a mutation interface instead of a compilation step.

The instruction that produces this is in `assets/wiki-CLAUDE.md`:

> After writing the new page, integrate the source into the existing wiki: find the 2–4 most-related existing `topic/` pages and make **minimal, additive** edits…

Three failures are encoded in that one paragraph:

1. **One source in view.** A pass that has read one document cannot revise a claim that rests on forty. It can only append.
2. **Additive-only.** It is structurally incapable of correcting `Software Engineering Craft`'s assertion that "the wiki has 197 pages" — the wiki has 1,017. Nothing in the system can ever fix that sentence.
3. **Concurrent.** N ingests append to the same file from divergent bases. The merge conflicts are the *symptom*; the missing revision capability is the disease.

The archive layer, by contrast, is sound and should not be touched: `curl` piped into `trafilatura --markdown`, deterministic, no model, 2.33M words of verbatim source under git. That is the foundation everything else can be rebuilt from, and it is already right.

---

## 3. The invariants

Great is not a feature list. It is a small set of properties that, once held, make the features fall out.

**I1 — Nothing downstream of `raw/` is precious.** Every derived artifact can be destroyed and regenerated from the archive. This is what makes experimentation safe and prompt improvements retroactive.

**I2 — Every derived artifact names its inputs.** Provenance is not documentation; it is the mechanism. It gives auditability (is this claim supported?), rebuildability (what must I recompile?), and citation (what makes the corpus trustworthy to an agent). The 299 hubs are broken precisely because they lack it.

**I3 — One writer per artifact.** Ingest writes only files it uniquely owns. Compilation writes topic pages, one theme at a time. Concurrency conflicts become structurally impossible rather than arbitrated by a merge driver. This deletes the entire class of bug that a bounded-union resolver and a `mkdir` mutex were invented to referee.

**I4 — Deterministic where possible, model-assisted only where necessary.** Dead links, orphans, duplicate titles, stale counts, and dirty-set computation are `grep` and set arithmetic. Reserve the model for judgement: synthesis, contradiction, and prose.

**I5 — Revision is a first-class operation.** A system that can only add will degrade. Compilation must be able to rewrite, split, merge and *delete*.

**I6 — The corpus must be able to surprise its owner.** Without external feedback an agent-maintained wiki converges to a fixed point. Questions asked, corrections made, and predictions falsified are the inputs that keep it moving.

---

## 4. Functional decomposition

Six elements. Three are new; three already exist and mostly work.

### 4.1 Archive — `raw/` *(exists, keep)*
Verbatim extracted source. Immutable, append-only, one file per source. Written by the script, never by a model. The trust anchor: every downstream claim can be checked against it.

### 4.2 Digest — `summary/` *(exists, elevate)*
A source-faithful precis. One per source, no cross-references, no opinions, no outside knowledge. Currently a convenience; under this design it becomes **load-bearing**, because it is the compression layer that makes whole-corpus operations affordable: 620k words of digest against 2.33M words of archive, a 3.8× reduction that decides whether compilation is tractable.

Its lossiness sets a ceiling on every topic page compiled from it, so it deserves to be designed for that job — dense, factual, and quotable, with the *specific* details (numbers, names, claims) preserved rather than smoothed away.

### 4.3 Facts — `facts/<slug>.json` *(new)*
Structured extraction per source: entities mentioned, themes, claims with confidence, and proposed relations. Machine-readable, append-only, one file per source — therefore **zero contention by construction**.

This is the element that converts routing and dirty-set computation from model guesswork into set arithmetic. It is also the substrate for contradiction detection: two claims about the same entity that cannot both be true are findable when claims are structured, and effectively unfindable when they are prose buried in 1,017 documents.

### 4.4 Themes and Entities — `topic/` *(exists, re-found)*
Topic pages split into two kinds with different rules, which resolves the "why are there two files for Hunk" confusion at its root:

- **Entity page** — a tool, person, company, or paper. Legitimately 1:1 or 1:N with sources. Thin, factual, and mostly a router: what it is, and which themes it bears on. `Hunk` is one of these.
- **Theme page** — a concept, tension, or practice. **Always** multi-source. This is where the argument lives, where sources are compared, and where synthesis earns its name. The terminal-native agentic review stack that `topic/Hunk.md` keeps reaching toward is a theme; Hunk is an instance within it.

The rule that does most of the work: **a theme page earns existence at two or more sources.** Single-source material stops at the digest. This is what stops 709 source-pages from masquerading as topics.

### 4.5 Curator *(new — the missing operation)*
Not one thing; a small family, ordered from cheap and certain to expensive and judgemental:

- **index** — build the provenance and link graph from the corpus. Deterministic. *(built: `wiki-curate index`)*
- **audit** — dead links, orphans, duplicate titles, stale counts, digest-less sources, and **wanted pages**: absent pages several others link to, which is the corpus naming a theme it lacks. Deterministic, sub-second; should run nightly. *(built: `wiki-curate audit`)*
- **route** — assign sources to themes: declared provenance first, retrieval to discover new edges. *(half built: `wiki-curate dirty --since REF` does the declared-provenance half as set arithmetic. The retrieval half — the new-edge problem — is not built, and the backstop is a periodic full recompile.)*
- **compile** — regenerate a theme page from its member digests, pulling full `raw/` only for the sources it quotes in depth. Single writer, one theme at a time. *(built: `wiki-compile`, `wiki-recompile`. It reads digests only; the selective `raw/` deep-read is not built.)*
- **reconcile** — the model-assisted audit: contradictions, stale temporal claims, themes that have outgrown one page and should split. *(not built)*

Two more emerged from use and were not in the original decomposition:

- **classify** — split single-source pages by whether they are named after their
  source. On the live corpus this turned "922 single-source pages" into 861
  entity pages (legitimately 1:1) and 61 coined concepts that want to be themes,
  which is a far more tractable problem than the undifferentiated number.
  *(built: `wiki-curate classify`)*
- **review** — render a compile branch as per-page word and link deltas plus the
  corpus audit delta. Not a nicety: a multi-page compile diff is unreadable, and
  this is what caught the compiler silently destroying cross-links.
  *(built: `wiki-review`)*

### 4.6 Query *(designed for, not built)*
Retrieval over digests and themes returning provenance-backed answers. Explicitly future work — but two cheap decisions now avoid foreclosing it: keep provenance machine-readable, and compile pages into self-contained sections that survive chunking. Both improve human reading anyway, so they cost nothing.

Query also closes the feedback loop of **I6**: a question the wiki answers badly is the highest-quality curation signal available, and it is free because the question was going to be asked regardless.

---

## 5. Data flow

```
                    ┌─────────────────────────────────────────┐
   URL ──▶ fetch ──▶│  raw/<slug>.md          IMMUTABLE       │
   (curl +          └─────────────────────────────────────────┘
    trafilatura)                   │
                                   ▼  digest  (LLM, per source, fully parallel)
                    ┌─────────────────────────────────────────┐
                    │  summary/<slug>.md      one writer each  │
                    │  facts/<slug>.json      append-only      │
                    └─────────────────────────────────────────┘
                                   │
                                   ▼  route  (deterministic + retrieval)
                    ┌─────────────────────────────────────────┐
                    │  themes.json   theme ──▶ [slugs]         │
                    └─────────────────────────────────────────┘
                                   │
                                   ▼  compile  (LLM, ONE theme at a time)
                    ┌─────────────────────────────────────────┐
                    │  topic/<Theme>.md       DERIVED          │
                    │    frontmatter: sources[], built, hash   │
                    └─────────────────────────────────────────┘
                                   │
                                   ▼  audit / reconcile
                    ┌─────────────────────────────────────────┐
                    │  reports/*.md     corrections queue      │
                    └─────────────────────────────────────────┘
```

**The ingest path becomes conflict-free.** It writes `raw/`, `summary/`, `facts/` — all uniquely owned — plus `index.md` and `log.md`, which already carry `merge=union`. It touches no shared prose. The bounded-union resolver, the merge classifier and the `mkdir` mutex all become unnecessary, because there is nothing left to contend over.

**Compilation is a separate, single-writer pass.** It runs after a batch, or on a schedule, or on demand. It never races because there is only ever one of it.

**The dirty set is arithmetic, not judgement.** A theme is dirty when its declared source set intersects the new batch. The *new-edge* problem — a source belonging to a theme nobody declared — is the one genuinely hard part, and it is handled by over-approximating with retrieval, then backstopped by an occasional full recompile. Incremental need not be correct, only cheap, when a periodic full pass is the correctness guarantee. This is generational garbage collection, and the analogy is exact.

---

## 6. Migration: how the 299 get their provenance back

The hubs cannot simply be recompiled, because nobody recorded what they were built from. But the link graph already encodes it, and this was verified before it was written down:

`topic/Software Engineering Craft.md` carries 55 outbound wikilinks. **All 55** resolve to real topic pages, and **51** of those carry `[[summary/...]]` provenance. So:

> **A hub's source set ≈ the union of the digests of the pages it links to.**

Deterministic. No model required.

**Correction, 2026-08-10 — this works for auditing and fails for compiling.**
In a densely-linked wiki the union explodes: a page about one company came out
with 188 "sources", another with 269. It is a fair answer to "roughly what does
this page rest on" and a wrong answer to "compile from exactly these", and the
pages a post-batch dirty-set surfaces are precisely the densely-linked ones. A
compile against 188 reconstructed sources produced a footer with 117 fabricated
digest names. Mitigated with a plausibility cap and by having the tool write the
provenance footer itself; the heuristic still needs replacing. See kata `3h0h`. That gives every hub a reconstructed bibliography, which is enough to (a) audit it — do its claims survive contact with its sources? — and (b) recompile it for the first time.

The 709 single-source pages need classification, not deletion: entity pages keep their identity and get slimmed toward routing; concept pages fold their argument into the theme they belong to. Deleting them wholesale would be destructive and would throw away real writing; the compiler should absorb them.

**Nothing is destroyed to achieve this.** `raw/` and `summary/` are untouched, so the worst outcome of a bad compile is a bad compile — discarded with `git checkout`, and recompiled with a better prompt.

---

## 7. What good feels like from the outside

Worth stating in the user's terms, because it is the actual test.

- You read a theme page and it argues something, with the sources that support it named.
- A page that was wrong last month is right this month, because something recompiled it — not because you found and fixed it.
- Adding twenty-six sources takes twenty-six parallel fetches and one compile, and never asks you to resolve a merge.
- The morning after a batch, there is a short report: what changed, what contradicts what, and what the wiki now believes that it did not believe yesterday.
- When you notice something wrong, saying so takes five seconds and the next pass consumes it.
- Nothing in `topic/` is precious, so improving the compiler improves the whole wiki at once.

---

## 8. Non-goals

Named so they are not smuggled in later.

- **A retrieval/RAG layer.** Explicitly future work. Design for it; do not build it.
- **A vector database.** BM25-class retrieval first, measured, before anything heavier.
- **Multi-user or multi-agent write access.** One owner, one curator.
- **Rewriting `raw/` or re-fetching the corpus.** The archive is sound and re-fetching would be both wasteful and rude to 919 origin servers.
- **The bounded-union merge resolver and merge mutex.** Superseded. They referee a race this design deletes.

---

## 9. Open questions

1. **Entity/theme boundary.** Mechanically decidable, or a judgement the compiler must make per page? Current instinct: proposed by the model, recorded in `themes.json`, and stable thereafter.
2. **How aggressively to fold the 709.** Absorbing them into themes is right in principle but risks losing good writing. Start by absorbing none — compile themes alongside, compare, then decide.
3. **Compile cost at full corpus scale.** ~300 themes is affordable overnight; 1,017 pages is a different budget. The dirty-set plus periodic-full-pass design exists to make this a choice rather than a constraint.
4. **Where corrections live.** An inline `%%fix: …%%` convention in the vault, or a separate queue file. Inline is lower friction and higher risk of being clobbered — which the derived/`built:` hash check would catch.

---

## 10. First build

Ordered so there is something working and valuable at every stop, and nothing destructive at any of them.

1. **`wiki-curate index`** — provenance and link graph, including hub reconstruction. Deterministic, no model, fast.
2. **`wiki-curate audit`** — health report from that graph. Deterministic. Immediately useful on today's wiki with no changes to anything.
3. **`wiki-compile --theme`** — recompile one theme from its sources, into a worktree, on a branch. Reviewable as a diff.
4. **Scale to the worst hubs**, measure quality against what is there now, and report.

Steps 1 and 2 change nothing and can run against the live wiki safely. Step 3 writes only inside a scratch worktree on a branch, so `main` — and the Obsidian window that is open on it — never moves until it is chosen.

**All four were built and run on 2026-08-08/09.** Eleven themes were recompiled
and merged, with every cross-link preserved and corpus health unchanged or
better. What that exercise taught, beyond the code:

- Compiling improves prose and can silently destroy structure. The first run
  wrote better pages and dropped 48 of 104 links from one hub. A theme page is
  also a **directory** — often the only inbound link a page has — and link
  preservation had to become a mechanical gate, not an instruction.
- Measure on the filesystem you will actually run against. Audits taken inside a
  git worktree and against the live iCloud tree disagreed, because macOS stores
  filenames decomposed and markdown links compose them. That read as a
  regression from a merge that had changed nothing.
- The compiled pages roughly doubled in length while referencing exactly the
  same 455 pages — elaboration, not coverage. No budget pushes back on length,
  and nothing in the design says how long a theme should be.
