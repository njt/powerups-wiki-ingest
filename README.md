# powerups-wiki-ingest

A [Claude Code](https://claude.ai/code) plugin: feed it a URL or GitHub repo, and it fetches the source, analyzes it with an LLM, and files a cross-linked page into your Obsidian wiki — updating an index and an append-only log as it goes.

## What it does

- **Regular web pages** — fetches content, archives it verbatim, writes a precis and an analysis page (quotes, themes, opinionated take), updates the index and log.
- **GitHub repos** — shallow-clones the repo and does a deep architectural read (5–10 source files) before writing.
- **JS-heavy / bot-protected pages** — the fetch step is `curl` piped into `trafilatura` (readability extraction, no browser), so pages that only render client-side come back empty; there's an optional browser fallback via the [`surf`](https://github.com/nat/surf) CLI for those.

Each ingest runs in an isolated git worktree and writes only files it uniquely owns, so many URLs process in parallel without contending. `index.md` and `log.md` carry `merge=union`; nothing else is shared, because cross-page curation is a separate step (below) rather than something each ingest does on its way past.

### Layout

Every source lands in three places, so the verbatim record stays separable from the interpretation. Topics are a fixed list, and their pages are compiled, never hand-filed:

| Path | Contents |
|------|----------|
| `raw/<slug>.md` | the **verbatim** fetched source (extracted with trafilatura). Written by the pipeline, never rewritten by the model. |
| `summary/<slug>.md` | a concise precis with curated frontmatter (title, author, dates, and `topics:` — the one or two topics the source is filed under). |
| `note/<Title>.md` | the analysis of that one source (quotes, themes, opinionated take), cross-linked with `[[wikilinks]]`. |
| `topics.md` | the fixed list of topics: `slug | title | scope`. Includes `misc`. Edited by people, read by the tools. |
| `topic/<Title>.md` | one **compiled** page per entry in `topics.md`, rebuilt by `wiki-compile` from every summary tagged with it. Nothing else writes here. |

`index.md` (one section per topic) and `log.md` stay at the wiki root.

The topic behaviour switches on when `topics.md` exists in the wiki. A wiki without it gets the 2.x behaviour (a per-source page under `topic/`), so upgrading is a migration you run, not something an ingest does to you.

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
wiki-curate topics                   # members per topic, oversized ones, what is in misc

wiki-compile --theme "X"             # rebuild one topic from ALL its tagged summaries
wiki-recompile --since HEAD~20 --top 8   # recompile only what the batch touched
wiki-review --branch curate/...      # render a compile branch as a report
wiki-retag --topic misc              # re-file summaries after you edit topics.md
```

Topics do not discover themselves. `topics.md` is the list; every ingest picks
one or two entries from it; `wiki-curate topics` tells you when a topic has
outgrown one page or when `misc` has accumulated something that wants a name. To
split a topic: edit the table, `wiki-retag --topic <old-slug>`, then
`wiki-recompile`.

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
| `WIKI_INGEST_MODE` | no | `agentic` | `single`: a fresh topics-mode article ingest is ONE chat-completions call via `wiki-llm` (the script writes summary, note, index and log); `--repo`, `--summary-only`, `--force` stay agentic |
| `WIKI_COMPILE_MODE` | no | `agentic` | `single`: `wiki-compile` inlines the context, the current page and its links in ONE call via `wiki-llm`; same gates |
| `WIKI_LLM_BASE_URL` | for `single` | — | OpenAI-compatible endpoint, e.g. `https://gw.lunaroute.com/v1` |
| `WIKI_LLM_API_KEY` or `WIKI_LLM_KEY_FILE` + `WIKI_LLM_KEY_PATH` | for `single` | — | the key, or a JSON file and a dotted path into it |
| `WIKI_INGEST_MODEL` / `WIKI_INGEST_EFFORT` / `WIKI_INGEST_MAX_TOKENS` | no | `deepseek-4.1-flash-background` / `low` / `16000` | single-call ingest settings |
| `WIKI_COMPILE_MODEL` / `WIKI_COMPILE_EFFORT` / `WIKI_COMPILE_MAX_TOKENS` | no | `glm-5.3-flash-background` / `high` / `32000` | single-call compile settings (`max_tokens` includes reasoning) |

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

## Upgrading from 2.x

2.x wrote one `topic/<Title>.md` per source, which is how a wiki ends up with a thousand one-article "topics". 3.0 keeps that page but files it as `note/<Title>.md`, tags each summary with `topics:`, and reserves `topic/` for the compiled pages of a fixed list. Links keep working: Obsidian resolves `[[Title]]` by filename anywhere in the vault. Migrate with:

```bash
wiki-migrate-topics --all --topics-file "$PLUGIN/assets/topics.md"   # on a branch: moves pages, seeds topics.md, backfills topics:, restructures index.md
wiki-retag --topic misc --branch curate/topics-YYYYMMDD               # let the model file what the backfill could not
wiki-recompile --branch curate/topics-YYYYMMDD                        # build every topic page
wiki-review --branch curate/topics-YYYYMMDD                           # then merge it yourself
```

Stop ingesting while the branch is open: `index.md` is `merge=union`, and a union merge of a restructured file against new appends duplicates sections. Edit the topic list in `assets/topics.md` (or your own copy) first; the titles of pages you already have compiled should be kept exactly so their links survive.

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
