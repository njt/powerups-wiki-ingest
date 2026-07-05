# powerups-wiki-ingest

A [Claude Code](https://claude.ai/code) plugin: feed it a URL or GitHub repo, and it fetches the source, analyzes it with an LLM, and files a cross-linked page into your Obsidian wiki — updating an index and an append-only log as it goes.

## What it does

- **Regular web pages** — fetches content, saves a raw source file, writes a topic page (precis, quotes, themes, opinionated analysis), updates the index and log.
- **GitHub repos** — shallow-clones the repo and does a deep architectural read (5–10 source files) before writing.
- **JS-heavy / bot-protected pages** — optional browser fallback via the [`surf`](https://github.com/nat/surf) CLI when plain fetch can't get the content.

Each ingest runs in an isolated git worktree, so many URLs process in parallel safely (`merge=union` on the index and log prevents conflicts).

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

## License

MIT
