---
name: new-project
description: Start a new project from the factory's repo: its folder, its git repo on dev, its Gitea repo and the factory from a release, then the adopt skill's steps, committed and pushed.
disable-model-invocation: true
---

# new-project

You take a project from nothing to **Adopted**, committed on dev and pushed, from this checkout of the factory's own repo (`.factory-repo` at its top). Terms are in `factory/CONTEXT.md`. `factory/core/new-project.sh` does the mechanics (its header is the reference); you settle what it can't, then take the project through the adopt skill's steps with the human. This skill lives only in this workspace: no project installs it.

## 1. Ask

One question at a time, each led by your recommendation; skip what the human said already.

- **Name and folder**: the project's name (its Gitea repo's: letters, digits, `.`, `_`, `-`) and its folder, by default beside this checkout (`../<name>`). The folder must be missing or empty.
- **Adapter**: a folder of `factory/adapters/`; recommend `nextjs`.
- **Owner**: the user gt is logged in as (`gt api user --jq .login`), or an organisation.
- **Visibility**: private, unless the human says public.
- **Release**: the latest, unless the human names a tag.

gt exits 4 (not logged in): ask the human to run `gt auth login`, and wait.

## 2. Make

From the checkout's top: `bash factory/core/new-project.sh <dir> <adapter> [--repo <owner>/<name>] [--public] [--tag <vX.Y.Z>]`. Read its stderr.

- Exit 2, or 1 before `made <dir>`: nothing was made. Fix what it says (another name, a login) and run it again.
- Exit 1 after `created the Gitea repo`: it says what it made and how to remove each. An install that stopped at prepare (tool locations) goes on in step 3 (the adopt skill's step 2.4). Anything else: show the human its lines; removing the Gitea repo is their call, never yours.
- Exit 0: `<dir>` is on dev with its first commit pushed, the factory vendored at the tag, the skeleton laid, the adoption staged, and the `spec`, `approved` and `playtest` labels in the new repo, but those a `could not create the labels` line names.

## 3. Adopt

Work in `<dir>` from here on, with its own `factory/` (the tag's). Read `<dir>/factory/skills/adopt/SKILL.md`, its `tracker.md` and `cleanup.md`, and do its steps from where the script left off:

- Step 1 finds the adoption staged, not committed (install.sh ran adopt.sh with `--new`): skip step 2.3, as it says, running the label script below only for each label the script could not create.
- The tracker is Gitea through `gt`, on the repo the script made: don't ask it again. Ask only tracker.md's other questions (triage labels, domain docs).
- The label script tracker.md's step 3 needs, in a temp folder outside the repo: `gt label create "$1" --repo <owner>/<name> --color "$2" --description "$3" --force`.
- ARCHITECTURE.md as the adopt skill says: the human approves it.
- Step 4 commits the adoption on `dev`, on the human's go-ahead; then `git push origin dev`.
- An empty Baseline needs no cleanup issues: offer to arm, as the adopt skill says, and push that commit too.

## Report

Tell the human: the folder, the Gitea repo's URL and visibility, the adapter and the factory's tag, what the adopt skill's report lists, and the commits pushed to dev. Then: open a Claude session in `<dir>` to write the first Spec with `/spec`.
