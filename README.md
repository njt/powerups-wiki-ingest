# powerups-wiki-ingest

A [Claude Code](https://claude.ai/code) plugin: feed it a URL or GitHub repo, and it fetches the source, analyzes it with an LLM, and files a cross-linked page into your Obsidian wiki — updating an index and an append-only log as it goes.

## What it does

- **Regular web pages** — fetches content, archives it verbatim, writes a precis and an analysis page (quotes, themes, opinionated take), updates the index and log.
- **GitHub repos** — shallow-clones the repo and does a deep architectural read (5–10 source files) before writing.
- **JS-heavy / bot-protected pages** — the fetch step is `curl` piped into `trafilatura` (readability extraction, no browser), so pages that only render client-side come back empty; there's an optional browser fallback via the [`surf`](https://github.com/nat/surf) CLI for those.

Each ingest runs in an isolated git worktree and writes only files it uniquely owns, so many URLs process in parallel without contending. `index.md` and `log.md` carry `merge=union`; nothing else is shared, because cross-page curation is a separate step (below) rather than something each ingest does on its way past.

### Three-tier layout

Every source lands in three places, so the verbatim record stays separable from the interpretation:

| Directory | Contents |
|-----------|----------|
| `raw/<slug>.md` | the **verbatim** fetched source (extracted with trafilatura). Written by the pipeline, never rewritten by the model. |
| `summary/<slug>.md` | a concise precis with curated frontmatter (title, author, dates). |
| `topic/<Title>.md` | analysis and synthesis, cross-linked with `[[wikilinks]]`. May draw on several sources. |

`index.md` and `log.md` stay at the wiki root.

## Curation

Ingest files sources. **Curation is a separate operation over the whole corpus**,
because a pass that has read one document can only ever append to a shared page —
it cannot revise a claim that rests on forty sources.

```bash
wiki-curate index                    # provenance and link graph
wiki-curate audit                    # 13 deterministic health checks
wiki-curate themes --min 4           # pages ranked by how many sources back them
wiki-curate sources --theme "X"      # the source set for one theme
wiki-curate dirty --since HEAD~20    # themes a batch of new sources touched
wiki-curate classify                 # entity pages vs coined concepts
wiki-curate gaps                     # every page's "What's Missing", collected
wiki-curate fixme                    # pending %%fix: ...%% notes you left while reading

wiki-compile --theme "X"             # rebuild one theme from ALL its sources
wiki-recompile --since HEAD~20 --top 8   # recompile only what the batch touched
wiki-review --branch curate/...      # render a compile branch as a report
```

The everyday loop is two commands: ingest a batch, then
`wiki-recompile --since <ref-before-the-batch>`. A theme is dirty when its own
declared source set intersects the digests that changed — set arithmetic over
provenance, no model and no retrieval. Its blind spot is a source belonging to a
theme nobody has declared yet; the backstop for that is an occasional full
recompile, not a cleverer diff.

`wiki-curate` is read-only, deterministic, and needs no LLM or network — under a
second across a thousand-page wiki, so it is cheap enough to run nightly. It
reports dead links, orphans, pages with no provenance, duplicate titles,
oversized pages, stale self-referential counts, and **wanted pages**: absent
pages that several others link to, which is the corpus naming a theme it wants.

`wiki-compile` treats a topic page as a **derived artifact** and rebuilds it from
every digest that backs it, so it can correct stale claims, merge duplicated
passages and drop weak material rather than only adding. It works in a throwaway
detached worktree and commits to a branch — your live checkout never moves and
nothing is merged without you. Output is validated (provenance footer present,
no conflict markers, no collateral writes) before it is committed.

`wiki-recompile` drives the whole set serially — one writer, one theme at a time
— and audits the wiki before and after, so "this improved the wiki" is a
measurement rather than an opinion.

Design and rationale: [`docs/design/monograph-what-great-looks-like.md`](docs/design/monograph-what-great-looks-like.md).

## Install

### Via Powerups Marketplace (recommended)

```
/plugin marketplace add njt/powerups-marketplace
/plugin install powerups-wiki-ingest@powerups-marketplace
```

### Manual

```bash
git clone https://github.com/njt/powerups-wiki-ingest.git
/plugin marketplace add ./powerups-wiki-ingest
/plugin install powerups-wiki-ingest@powerups-wiki-ingest-dev
```

## Configuration

Set these in your Claude Code environment (e.g. `~/.claude/settings.json` under `env`):

| Variable | Required | Default | Meaning |
|----------|----------|---------|---------|
| `WIKI_PATH` | yes | — | absolute path to your Obsidian wiki directory |
| `WIKI_INGEST_CLI` | no | `claude` | the LLM CLI used for analysis and writing |

First time? Create the wiki with one command:

```bash
WIKI_PATH=/path/to/wiki wiki-ingest-setup
```

(Add `--gitdir /path/outside/cloud` to keep the `.git` directory out of a cloud-synced folder.)

## Usage

```
/wiki-ingest https://example.com/some-article
/wiki-ingest https://github.com/owner/repo   # deep repo analysis
```

Pass several URLs at once; each ingests in parallel.

## Upgrading from 1.x

1.x wrote analysis pages flat at the wiki root (`<Title>.md`) and had no `summary/` tier. 2.0 writes `raw/` + `summary/` + `topic/`. Existing wikis keep working — Obsidian `[[wikilinks]]` resolve by name regardless of folder, and duplicate detection reads `raw/` and `summary/` — but the layout will be inconsistent until you migrate:

```bash
cd "$WIKI_PATH"
# move flat topic pages into topic/, keeping index.md and log.md at the root
for f in *.md; do
  case "$f" in index.md|log.md|ingest-queue.md|CLAUDE.md) continue ;; esac
  git mv "$f" topic/
done
git commit -m "Migrate flat topic pages into topic/"
```

Sources archived under 1.x have no precis. Backfill them from the existing `raw/` files, without refetching:

```bash
for f in raw/*.md; do
  slug=$(basename "$f" .md)
  [ -f "summary/$slug.md" ] || wiki-ingest-run --summary-only "$slug"
done
```

## License

MIT
