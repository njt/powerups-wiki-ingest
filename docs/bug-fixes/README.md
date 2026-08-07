---
commissioned-by: spacedock@0.27.0-pre2
entity-type: bug_fix
entity-label: fix
entity-label-plural: fixes
id-style: sd-b32
state: $inline
stages:
  defaults:
    worktree: false
    concurrency: 2
  states:
    - name: backlog
      initial: true
      gate: true
    - name: ideation
      gate: true
    - name: implementation
      worktree: true
      context-sections:
        - Review-finding disposition
    - name: validation
      worktree: true
      fresh: true
      feedback-to: implementation
      gate: true
      context-sections:
        - Review-finding disposition
    - name: done
      terminal: true
---

# Fix the open bugs in powerups-wiki-ingest

This workflow works the open defect backlog for `powerups-wiki-ingest`, the Claude Code plugin that ingests URLs into an Obsidian wiki. Each entity is one bug fix, sourced from a kata issue. Every bug in the seed set shares a family resemblance worth naming up front: they are all **silent** failures. The auto-commit bug wrote conflict markers into a wiki page and reported success. The slug collision would have clobbered one source's archive with another's and left a log pointing two entries at one file. The `$2` substitution killed the entire browser-fallback path for multi-URL batches and nothing said so. The topic-page merge conflicts were the only member of the family that failed loudly, and only because git refused to guess.

That shapes the quality bar for this workflow. A fix here is not finished when the bad thing stops happening — it is finished when the bad thing *cannot happen quietly*. The guard must exist, and something outside the fix's own prose must demonstrate it firing.

Fixes are built in isolated worktrees and merged directly to `main` on validation pass. This repo has no merge commits in its history and ships straight to trunk; there is no PR review step and no `pr-merge` mod.

## File Naming

Each fix lives as either:

- a flat markdown file `{slug}.md` (default — use this unless the fix produces sibling artifacts), or
- a folder `{slug}/` containing `index.md` as the canonical entity file, when the fix produces artifacts that belong alongside the tracker (a repro script, a captured failing-run transcript, a before/after diff worth keeping).

Slugs are lowercase, hyphens, no spaces. Example: `guard-auto-commit-against-conflicted-merge.md`.

## Schema

Every fix file has YAML frontmatter. Fields are documented below; see **Fix Template** for a copy-paste starter.

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier; SD-B32, for concurrent creation across worktree branches |
| `title` | string | Human-readable fix name |
| `status` | enum | One of: backlog, ideation, implementation, validation, done |
| `source` | string | Where this fix came from — normally the kata ref (e.g. `kata:cntt`) |
| `started` | ISO 8601 | When active work began |
| `completed` | ISO 8601 | When the fix reached terminal status |
| `verdict` | enum | PASSED or REJECTED — set at validation |
| `score` | number | Priority score, 0.0–1.0 (optional) |
| `worktree` | string | Worktree path while a dispatched agent is active, empty otherwise. Once set on first dispatch into a `worktree: true` stage it stays set across non-terminal advancements, and clears at terminal merge. |
| `issue` | string | GitHub issue reference (e.g. `#42`) — optional cross-reference |
| `pr` | string | GitHub PR reference — unused in this workflow; fixes merge straight to main |
| `mod-block` | string | Pending mod-declared blocking action, format `{lifecycle_point}:{mod_name}` |

### ID Style

`id-style: sd-b32`. The `id` field stores the full stable 24-character lowercase SD-B32 value from `spacedock status --next-id --id-seed <slug>`. SD-B32 is Spacedock Base32: SHA-256 digest material formatted with the human-safe alphabet `0123456789abcdefghjkmnpqrstvwxyz`. Status tables display the shortest unique prefix (`MIN_PREFIX: 2`). Stored IDs are stable even when a display prefix lengthens after a colliding entity appears on another branch.

Use `spacedock status --validate` before trusting workflow state, and `spacedock status --resolve <ref>` to resolve a slug, stored ID, or address prefix.

## Stages

### `backlog`

A fix enters backlog when its kata issue is triaged in but no design work has happened. Captain-curated: the gate decides which fixes advance, and in what order. Nothing here is committed to.

- **Inputs:** The kata issue (`kata show <ref>`), including its comments — several of these issues carry a proposed fix or a post-mortem in the comment thread that is more current than the description.
- **Outputs:** A fix file whose Problem section states the defect in terms of observed damage, not suspicion, with the kata ref in `source`.
- **Good:** The Problem section is specific enough that a reader who has never seen the kata issue understands what broke and who got hurt.
- **Bad:** Advancing a fix whose kata issue is a proposal or an epic rather than a defect. `87sc` is the live example — the full SQLite rearchitecture is not a bug fix; the interim mitigation named in its comment is.

### `ideation`

The captain greenlights a fix for design: reproduce the defect, confirm the root cause rather than the symptom, propose the narrowest change that closes it, and write acceptance criteria as end-state properties with a `Verified by:` clause each.

- **Inputs:** The fix's Problem section, the offending code path in `bin/` or `commands/`, and the two existing test scripts (`tests/test-fetch.sh`, `tests/test-guard.sh`) — a new test usually belongs in one of these rather than in a new file.
- **Outputs:** A reproduction that actually fails, named in the fix body — the exact command or scenario, not a description of one. Acceptance criteria whose evidence lives outside this file. A test plan naming which of the two test scripts gains the case, or why a new one is warranted.
- **Outputs:** Each AC split by how it is verified: **offline** (a test or command a fresh agent re-runs) or **interactive** (needs the Captain or a live drive). Declare the split here, at the gate, before any harness is built for it.
- **Good:** The root cause is distinguished from the trigger. `cntt` was triggered by a hand-merge racing an ingest, but the cause is an unguarded `git add`/`commit` over an arbitrary working tree — the fix belongs on the guard, not on the timing.
- **Good:** The proposed change names what it deliberately leaves alone. These scripts are load-bearing for a live wiki.
- **Bad:** An AC whose only proof is re-reading this fix's own prose, or a grep over an instruction file. See **Workflow-specific rules**.
- **Bad:** Proposing a rewrite where a guard would do. Scope creep from `pxf4` into a general slug-scheme redesign, or from `87sc`'s interim mitigation into the SQLite orchestrator, fails this stage.

### `implementation`

The design is approved. The fix is built in a dedicated worktree on a feature branch: the failing test first, watched failing for the right reason, then the minimum change that turns it green.

- **Inputs:** The approved ideation design and ACs; the target script in `bin/`; the seeded throwaway-wiki harness in `tests/test-guard.sh`.
- **Outputs:** A test that fails before the fix and passes after, with both observations recorded in the fix body — the failure message from the red run, not just an assertion that it was red.
- **Outputs:** The fix itself, scoped to the approved change. Bash 3.2 compatible: no `mapfile`, no associative arrays, no negative array indexing (macOS `/bin/bash`).
- **Outputs:** When a review finding arrives, follow `## Review-finding disposition` — investigate read-only, preserve the evidence, propose materiality and disposition, and get distinct FO authorization before any candidate edit, commit, or reviewer rerun.
- **Good:** The guard fails closed. Every one of these bugs did damage by proceeding when it should have stopped, so a fix that warns and continues has not fixed it.
- **Good:** `WIKI_PATH` points at a throwaway wiki for the entire stage. Never a real one.
- **Bad:** Weakening the `tests/test-guard.sh` seed to make a test pass. That seed — a pre-existing `summary/` and `topic/` page — is what makes the completeness guard's original bug visible at all; remove it and the test silently stops testing anything.
- **Bad:** Introducing `${CLAUDE_PLUGIN_ROOT}` into a script (broken in command markdown, issue #9354), or adding `--dangerously-skip-permissions` to the default LLM path.

### `validation`

A `fresh` agent — no memory of building it — independently verifies the fix against the ideation ACs, reproducing each `Verified by:` clause rather than trusting the implementation's self-report. The validator checks what was produced; it does not produce it.

- **Inputs:** The fix's ACs and test plan, the worktree branch, and the diff against `main`.
- **Outputs:** A per-AC verdict, each citing the command it ran and what came back — exit code, output, or resulting on-disk state.
- **Outputs:** The negative case exercised: revert or defeat the guard and confirm the new test goes red. A test that passes both with and without the fix proves nothing, and this is the cheapest way to catch that.
- **Outputs:** Both test scripts run, not only the one the fix touched — `tests/test-fetch.sh` and `tests/test-guard.sh` both run with no network and no real LLM, so there is no excuse to skip either.
- **Outputs:** Findings triaged before acting: classify each as material (fix), correct-but-disproportionate (record a decline, do not fix), or needs-decision (escalate). A non-material finding must not force a dutiful fix.
- **Good:** Rigor scaled to blast radius. A one-line escape in `commands/wiki-ingest.md` does not need the treatment a `git commit` guard in `wiki-ingest-run` needs.
- **Bad:** Accepting "the test passes" as evidence without having watched it fail. The failing observation is the load-bearing half.
- **Bad:** Approving a fix that leaves the failure silent — closing the specific case while an adjacent input still corrupts quietly.

### `done`

Terminal. The branch is merged to `main`, `completed` is set, `verdict: PASSED`, the entity is archived, and the kata issue is closed with a comment naming the merge commit.

- **Inputs:** The passed validation report and the merged branch.
- **Outputs:** Merge landed on `main`; worktree removed; `worktree` field cleared.
- **Outputs:** The kata issue closed (`kata close <ref>`) with a comment citing the commit and the test that now covers it.
- **Good:** A future reader hitting this bug's symptom finds the closing comment and the test in the same breath.
- **Bad:** Flipping the status manually without a real merge.

## Review-finding disposition

Every finding enters this checkpoint when it arrives during implementation, validation, a detached audit, consequential FO quick work, or a correction routed from a rejected gate.

1. The reviewer owns observation, not task ownership or authorization.
2. The worker preserves the finding, investigates without candidate mutation, records the four evidence fields, and proposes materiality, task ownership, and disposition separately. Its `actor:ensign` round Resolution is advisory.
3. The FO sends a distinct `fix`, `decline`, `hold`, or `route for decision` authorization through the runtime's addressable-worker boundary.
4. The validator recommends `PASSED` or `REJECTED`; a new finding re-enters step 1.
5. Only the captain changes approved scope, accepted value, thresholds, tolerance, or acceptance criteria.
6. After revise is selected, rejection routing transports the evidence, workflow classifications, authorized dispositions, and concrete assignment unchanged; it never re-triages.

Before FO authorization, candidate bytes and Git HEAD stay unchanged, no candidate commit is made, and no reviewer rerun starts. Read-only file/history inspection, non-mutating reproductions, existing tests, and adversarial work in a throwaway checkout are allowed. After authorization, perform only that disposition; `hold` and `route for decision` forbid mutation and rerun. Changed evidence re-enters the checkpoint, and an unobservable runtime authorization means hold and re-consult.

The four evidence fields are released user and normal workflow; observable harm; affected value AC or non-negotiable boundary; and trigger evidence. Field 3 uses `value-ac[AC-N]`, `captain-ruling[YYYY-MM-DD]`, or `contract[repo/relative/path#anchor]` plus a nonblank claim; `none:` plus a rationale cannot establish Material.

- **Material:** all four fields establish supported-workflow harm to a value AC or protected boundary.
- **Deferred risk:** the trigger is hypothetical, unsupported, unobserved, or outside current promises; record its promote-to-material condition.
- **Polish:** no current user-visible loss or protected boundary is at risk.
- **Needs decision:** the task cannot own the required scope, product, or compatibility decision.

Materiality and task ownership are independent. Owned Material is eligible for an FO-authorized fix; out-of-scope Material holds unchanged as Needs decision. Deferred risk or Polish may be declined only after FO authorization.

After reviewer and worker entries and FO consultation, retain the advisory round with `${SPACEDOCK_BIN:-spacedock} gate record`; it applies no gate or status change. A workflow correction round uses `- Cycle {N}: {verdict} — {reviewer/loop}; surface {files}/{LOC} vs estimate {declared} ({P}%); AC {unchanged | narrowed: <note>}`. Compare `git diff --numstat "$(git merge-base main HEAD)"..HEAD` with the ideation estimate; beyond declared tolerance or on narrowed AC, require a captain-visible design reset. Cycle 3 escalates.

## Workflow-specific rules

The FO/ensign operating contract already governs generic stage semantics and proof discipline: prefer the cheapest check that can fail — a shipped guard's run, an existing mechanical check, a one-off falsifiable exercise recorded in the report, then the captain's judgment — with new standing enforcement as the last resort rather than the default; prove by exercising rather than re-reading; and reject any AC whose only proof is a review of its own prose. Fixes in this workflow inherit those rules from the contract the FO loads at boot; the rules below add the specifics for this repo.

- **Repo-mutation worktree layer.** `implementation` and `validation` run in a worktree against the codebase, and `validation` is `fresh` so an independent agent checks the ACs. This workflow ships straight to `main` — there is no `pr-merge` mod, no `pr_open` stage, and the `pr` field goes unused.
- **Never point `WIKI_PATH` at a real wiki.** Both test scripts run against a throwaway wiki with no network and no real LLM. The live wiki at `~/Library/Mobile Documents/.../Wiki/` is out of bounds for every stage of this workflow. A fix that can only be demonstrated against the live wiki is a fix whose test plan is not finished.
- **Bash 3.2 is the target.** macOS `/bin/bash`. No `mapfile`, no associative arrays, no negative array indexing. A fix that works under your shell and dies under `/bin/bash` has not been tested.
- **No prose-grep over instruction files.** A string, substring, or regex match over an instruction file the model reads (the FO/ensign contract, this README, a skill, `commands/wiki-ingest.md`) never proves a behavioral claim. The matched text was written by the same implementer the check polices, so it asserts only that the file contains what we put in it. A valid paraphrase fails it; an inverted clause passes it. To settle a case, ask whether the expected value comes from outside the file under test; if it does not, the check is a tautology and is banned. A check binding two independent values that can diverge — the plugin manifest's version sharing a major.minor with the marketplace entry's — is legitimate and is not prose-grep. A grep whose output is pasted into a validation report is fine as one-off evidence for that run; the same grep committed as a test is banned. This rule has direct bite on `dw2f`, whose fix lives in a markdown file: grepping `commands/wiki-ingest.md` for `\$2` proves the file contains what we typed, not that Claude Code's expansion now leaves it intact. The behavioral claim needs an exercised expansion.
- **Evidence must be able to fail.** Each AC's cited evidence names the concrete change that would flip it — the falsifying edit. An author who cannot name what would make the evidence fail has not shown it can fail, and the criterion does not count. In practice: revert the guard, watch the test go red, record it.
- **Test-first authoring.** Write the failing test first, watch it fail for the right reason, then write the minimum code to pass. The test is what the gate judges.
- **Fail closed, and loudly.** Every bug in this backlog did its damage by continuing when it should have stopped, while reporting success. A fix that detects the bad state and proceeds with a warning does not close its bug.

## Workflow State

View the workflow overview:

```bash
spacedock status --workflow-dir docs/bug-fixes
```

Output columns: ID, SLUG, STATUS, TITLE, SCORE, SOURCE.

Find dispatchable fixes ready for their next stage:

```bash
spacedock status --workflow-dir docs/bug-fixes --next
```

## Fix Template

```yaml
---
id:
title: Fix title here
status: backlog
source:
started:
completed:
verdict:
score:
worktree:
issue:
pr:
mod-block:
---

## Problem

What is broken, what damage it did or would do, and why it matters now.

## Proposed approach

The narrowest change that closes the defect. Concrete enough that a worker can start.

## Acceptance criteria

Each AC names a property of the finished fix (not a stage action) and how it is verified.

**AC-1 — End-state property.**
Verified by: test name / command output or exit code / resulting on-disk state — something outside this file that a future reader can reproduce and that can fail. Name the concrete change that would make it fail.

## Test plan

Which test script gains the case, what the red run looks like, and whether the negative case is exercised.

## Out of scope

What this fix deliberately does not address.
```

## Commit Discipline

- Commit status changes at dispatch and merge boundaries
- Commit fix body updates when substantive
- Implementation commits land on the worktree branch; the merge to `main` happens at `done`
