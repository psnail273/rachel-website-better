---
name: adopt
description: Adopt the vendored factory into a project: seed its gates, tracker docs and labels, get ARCHITECTURE.md approved, and file cleanup issues for the Baseline.
disable-model-invocation: true
---

# adopt

You take a project from no factory to **Adopted**: the gates run, the write deny refuses the Editor the gate's files, pre-commit reports without blocking, `ARCHITECTURE.md` is the human's approved rule set, and every Baseline finding has a cleanup issue. Terms are in `factory/CONTEXT.md`. The human answers the **Human's calls** (feel and taste, scope and priority, amends, cost or irreversibility) and approves `ARCHITECTURE.md`; decide the rest and list it under **Decided for you** with a one-line reason.

## 1. Explore

Read before writing anything:

- `factory/` is vendored at the root, and `factory/adapters/` holds the project's stack. No adapter fits: stop and tell the human. No `factory/` yet: in step 2.3 run `bash <factory clone>/factory/core/install.sh <project> <adapter> [--new]` instead (`<factory clone>/core/install.sh` at a tag that has no `factory/`), with the same `FACTORY_LABEL_CMD`, from a clone of the factory's repo at a release tag: it copies `factory/` in, then runs adopt.sh, and records the factory repo and tag.
- A new project (no code yet): it starts from the adapter's skeleton, `factory/adapters/<adapter>/new/`. No skeleton: stop and tell the human.
- `tools/verify/factory-version` committed: the project adopted already; stop (`bash factory/core/sync.sh <tag>` updates it). Staged, not committed: install.sh ran adopt.sh; in step 2, skip 2.3 (run the label script for each label it listed) and go on.
- `git status` is clean, an install's staged adoption aside; adopt.sh refuses a dirty tree.
- The tracker, label and domain-doc setup: run step 1 of [`tracker.md`](tracker.md).
- `AGENTS.md` / `CLAUDE.md`, `ARCHITECTURE.md`, `CONTEXT.md` or `CONTEXT-MAP.md`, `docs/adr/`, and the code's folders.

Done when you can name the adapter, the tracker and its CLI, and whether `ARCHITECTURE.md` exists.

## 2. Seed

1. Settle the tracker questions with the human ([`tracker.md`](tracker.md), step 2); write nothing yet.
2. Write a label script **outside the repo** (a temp dir): `<script> <name> <color> <description>` creates that label with the tracker's own command (the tracker doc's label command, `#` before the color where it wants one), and succeeds when the label already exists.
3. `FACTORY_LABEL_CMD="bash <script>" bash factory/core/adopt.sh <adapter>`, with `--new` after `<adapter>` for a new project: that lays the skeleton first. It seeds `tools/verify/`, the hooks (pre-commit in report mode), the skills, the agents (`.claude/agents/`), the `verify-<project>` skill, `docs/deviations.md`, an `ARCHITECTURE.md` if absent, the AGENTS.md section, the `spec`, `approved` and `playtest` labels, and records the Baseline. Read its stderr: every `kept` file is the project's own, left as it was.
4. Prepare failed (tool locations): copy `tools/verify/local.env.example` to `tools/verify/local.env`, fill this machine's paths, then run step 3's command again: it resumes at the Baseline. Any other failure undid the run (the tree is back at HEAD): fix what it reports and run it again.
5. `.claude/skills/verify-<project>/` missing (the adapter has no generator, or a skill by that name was kept): run `bash factory/core/verify-skill.sh`, or tell the human which skill stands in.
6. Write the tracker docs and the other labels: [`tracker.md`](tracker.md), step 3.

Done when adopt.sh exited 0, `tools/verify/ratchet/baseline.txt` is staged, and every label exists.

## 3. ARCHITECTURE.md

Draft it from the code, then grill the human on it until they approve it.

- **Draft.** Fill the modules table (folder, what it owns, its public seam) and the layer line from what the code does today, not what it should do. Keep the adapter's default rules that hold for this project; a rule the code breaks stays, and its findings go into the Baseline.
- **Every rule** has a stable number, one sentence, an `Enforced by:` the arch step's sync check accepts, and a `Source:`. Run `bash tools/verify.sh arch` and fix every sync finding it prints.
- **Every `lint:<rule>` tag is on**: arch reports each whose rule the lint config leaves off. Port the skeleton's lint config (`factory/adapters/<adapter>/new/`; Next.js: `eslint.config.mjs.txt`'s typescript-eslint blocks) into the project's, beside its own; a package it adds is the human's call. Not done while arch reports one; never baseline it.
- **Grill.** Walk the human through it one decision at a time: each layer edge, each rule kept or dropped, each module's seam. Lead with your recommendation, quote the code that backs it, and revise the file after each answer. Every rule is a Human's call (it is an amend once Adopted).
- **Approval** is the human's explicit words in this session. Done when they approved the whole file.
- The rules or the lint config changed since adopt.sh recorded the Baseline: `git rm --cached -q tools/verify/ratchet/baseline.txt && rm tools/verify/ratchet/baseline.txt`, then `FACTORY_BASE=HEAD bash factory/core/baseline.sh record`.

## 4. Commit

Stage everything and show the human `git status --short` and the Baseline's entry count. Commit the adoption as one commit on their go-ahead (a project adopting through an issue lands it the way that issue says). Done when `FACTORY_BASE=HEAD bash factory/core/baseline.sh gate` prints `baseline: PASS` on the commit.

## 5. Cleanup issues

File the Baseline as cleanup issues with [`cleanup.md`](cleanup.md). Done when every Baseline entry is listed in exactly one open cleanup issue.

An empty Baseline (a `--new` project, say) needs no issues: offer to arm. Arming is the human's call; on their go-ahead, `bash factory/core/arm.sh` runs verify twice, stages `enforce` in `tools/verify/hook-mode` and commits nothing, so commit it.

## Report

Tell the human: the adapter and factory version, every file kept, the Baseline count by step, the cleanup Spec and its issues, the labels created, and what is left for them (filling `local.env` on other machines; arming with `factory/core/arm.sh` once the Baseline is empty and verify is green twice).
