---
name: factory-amend
description: Take the human's rulings on factory-improvement issues to landed amends, each built and reviewed in its own worktree, and report on every issue what landed.
disable-model-invocation: true
---

# factory-amend

You are the **Driver** of the factory's own changes. An **Amend** changes `factory/`, the step scripts in `tools/verify/` or the hook config, and the human approves one. The exception is the tests-or-docs class (CONTEXT.md, **Amend**): a proposal that touches only the factory's `tests/` folders and the docs `tests_or_docs_paths` in `amend.sh` lists, and removes no test, you may approve yourself; its commit carries the trailer `Amend-class: tests-or-docs` (land checks it), and step 5 lists it, where the human can overrule it. You turn the approved ones into commits on dev, each built by a subagent in its own worktree, and you account for every proposal on its issue. Terms are in `factory/CONTEXT.md`; tracker commands, and how an issue reads, in the tracker doc AGENTS.md points to. `factory/core/amend.sh` does the mechanics (record, check, release, land); its header comment is the reference. The factory has its own repo (factory-version's `upstream` line): land publishes each batch there first, as a release, then pushes the project. [`brief.md`](brief.md) holds the builder's brief, the commit's shape and the review prompts.

**In the factory repo** (`.factory-repo` at the top: the factory is `factory/`, the rest its workspace), the same steps hold, with these changes: the proposals are that repo's issues (its tracker doc is `docs/agents/issue-tracker.md`); worktrees branch from `origin/main`, and the landing branch too; copy the root `local.env`, if any, in place of `tools/verify/local.env`; `amend.sh record` refreshes only the workspace's copies (`.claude/skills/factory-amend/`, `.claude/skills/frontend-design/`, which the Verifier preloads, `.claude/agents/amend-builder.md` and `verifier.md`) and its `.claude/settings.json` (only the wait guard's hook), and writes no `factory-version` or AGENTS.md; there is no project verify and no publishing, so `amend.sh land` runs check and the full suite, pushes `main` and tags the release (none for a change to the workspace alone). Builders run suites with `local.env` loaded (`set -a; . ./local.env; set +a`).

## 1. Read the rulings

Read every open issue labelled `factory-improvement`, with its comments: the open children of the **Factory backlog**, and any open one without a `Part of` line, filed before the backlog. A retro's issue opens with its decision list, under `## What you need to do`, one line per proposal. Find the human's ruling on each proposal, on the issue or in this conversation:

- **approved**, as written or changed: the changed words are the ones to build;
- **declined**: comment on the issue now, quoting the ruling and its reason, so a later retro proposes it again only on new evidence;
- **moved** to another issue: comment naming that issue.

A proposal with no ruling is a Human's call: ask about all of them in one message before you build. Done when every proposal has a ruling, and each issue is marked answered as the tracker doc's "How an issue reads" says.

## 2. Group them

Split the approved proposals into amends: one per proposal, or one for proposals that only work together. For each, list the files it will touch, from the proposal and a read of those files. Two amends **overlap** when they touch a common file. The files `amend.sh record` writes don't count: `tools/verify/factory-version`, the installed copies (`.claude/skills/`, `.claude/agents/`, `tools/verify.sh`), the hook config and AGENTS.md's factory section.

Amends that don't overlap build at once. One that overlaps an earlier amend is **stacked**: it builds after that one, on its branch. Done when each amend has a slug, its files, its base (origin/dev, or the branch it stacks on) and the issues it answers.

## 3. Build

For each amend, from the main checkout:

```bash
git fetch origin
git worktree add --no-track -b amend/<slug> .claude/worktrees/amend-<slug> <base>
cp tools/verify/local.env .claude/worktrees/amend-<slug>/tools/verify/
```

Give each builder a scratch folder of its own, `<scratch>/amend-<slug>/`, for its prompt files, commit messages and logs: builders running at once share the scratch area, and one would overwrite another's files. Then dispatch a fresh `amend-builder` subagent in the background with the brief from [`brief.md`](brief.md), every field filled: the brief is all it knows. Pick its effort (`factory/CONTEXT.md`, Models and effort), pass it as the Agent tool's `effort` and write it on the brief's first line (its second is `factory-amend: <slug>`, which `claude-usage amends` totals): `medium`, `high` for a big amend (many files, or a Core script), `xhigh` once its rework has come back twice; never `max`, and Fable only with the human's yes for that builder. A fresh subagent starts small; a fork would carry this session's context into each of its calls. Dispatch the amends that don't overlap together, and a stacked one once the amend under it has reported.

The builder tests each new behaviour, records (`amend.sh record`, then `amend.sh check` printing nothing), has a fresh `verifier` subagent review its commits in at most three scoped passes, and squashes them into one amend commit with a `Targets:` trailer per cause it targets. Read its report against the brief: each review finding fixed with its input as a fixture, or named "not blocking"; each departure reasoned. A report that falls short goes back to the same subagent (SendMessage), which still holds its context. Of what is not blocking, only what you recommend yes waits on the human: file those items as one `factory-improvement` child issue of the backlog, labelled `ready-for-human`, with `Part of #<backlog>` as its first header line, in the shape `docs/agents/issue-tracker.md`'s "How an issue reads" gives: one decision per item under `## What you need to do`, each with your recommendation and its reason. Add its line to the backlog's `## Open` list, creating the backlog or reopening it as needed, with the commands under that doc's `## Factory backlog`. File no child for the items you recommend no: step 5 notes them. Done when every builder's report meets its brief.

**A new check meets old code.** When an amend adds a check or makes one stricter:

- If the code on dev fails it, the builder adds those findings to the Baseline in the amend's commit (`bash factory/core/baseline.sh add <rule>`) and you file a `Kind: cleanup` issue to remove them. Until that lands, only cleanup issues can land, so a check that judges only the lines a branch adds is the better build.
- The builder runs it over each paused or in-flight issue branch (`.claude/worktrees/issue-*`). Comment on each issue what it will flag at its next gate.

## 4. Land

Land the amends in one batch, so the full suite and the full gate run once for all of them:

1. From the main checkout, `git fetch origin`, then `git worktree add --no-track -b amend/land .claude/worktrees/amend-land origin/dev`, and copy `local.env` into it as in Build. There, `git cherry-pick` each amend's commit, a stacked one after the amend under it. On a conflict in a file `amend.sh record` writes, take either side, run `amend.sh record`, `git add` the file and continue; `amend.sh check` then prints nothing. After any other conflict, keep both amends' intent and rerun the suites both touched. Then `bash factory/core/amend.sh release`, which reads the amends' `Release:` trailers, and commit it as `Release factory <new>`. In the factory repo, a batch that changes only the workspace lands with no release.
2. When the batch adds or changes a test that starts a real tool or a background process, run `bash factory/core/stress.sh` there first, with `run_in_background` (three full runs under load, with `local.env` loaded; builders never run it): every run must pass, or the amend whose test failed goes back to its builder.
3. `bash factory/core/amend.sh land`, with the Bash tool's `run_in_background`: it runs the full suite and the full gate, longer than the tool's 10-minute limit on a foreground command. Wait for the completion notification, then read the output. Only one full suite runs at a time, so a second land started meanwhile is refused.
4. It refuses before any stage when the project's `factory/` differs from the factory repo's main: run `sync.sh` to the factory repo's latest tag first, then rebuild the landing branch. It publishes to the factory repo, then pushes the project, only when every stage is green. A refused project push means dev moved: fetch, `git rebase origin/dev` and land again; the rerun skips publishing. A red stage names its suite or step: rebuild the landing branch without the amend that caused it, send that one back to its builder, and land the rest.
5. Landed: note the SHA it prints. From the main checkout, `git worktree remove` each amend's worktree and the landing one, then delete their branches with `git branch -D` once `git cherry origin/dev <branch>` marks every commit `-`: a cherry-picked commit has a new SHA, so `-d` refuses.

Done when every approved amend is on origin/dev, or back with its builder for a reason you can name.

## 5. Report

On each `factory-improvement` issue, one comment that accounts for every proposal: **landed** (its commit SHA), **declined** (the ruling), **moved** (to which issue) or **open** (why, and what comes next). Each landed amend gets its cost: the builder's wall-clock minutes and review passes, from its report, and its tokens, the line `bash factory/tools/claude-usage amends --since <the batch's start>` prints for its slug; an amend you approved as tests-or-docs says so. Under a heading `Noted, not proposed`, the same comment lists each builder's not-blocking item you recommend no, with its reason, on the issue that builder's amend answered. Close the issue once every proposal is landed, declined or moved; the closing comment says which of each. When a child of the backlog closes, remove its line from the backlog's `## Open` list (remove it, never tick it, so the backlog stays short); once the list is empty, close the backlog with a comment naming the last child and the landing SHA, or the ruling when nothing landed. The tracker doc's `## Factory backlog` has the commands. Then tell the human, in a few lines, what landed, what is open and what you filed.
