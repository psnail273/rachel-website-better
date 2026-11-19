# Tracker, labels and domain docs

How the adopt skill sets up what the factory's skills read about the project's issue tracker, its labels and its domain docs. The tracker is not a seam: the factory names no tracker CLI, and every skill reads the commands from `docs/agents/issue-tracker.md`. Each file here is the project's own once written: keep what exists and fill only the gaps.

## 1. Explore

- `git remote -v`: the host (GitHub, GitLab, Gitea, other) and the repo.
- `docs/agents/issue-tracker.md`, `triage-labels.md`, `domain.md`: which exist, and whether each covers what step 3 lists.
- `AGENTS.md` / `CLAUDE.md`: is there an `## Agent skills` section?
- The tracker's CLI is installed and logged in (`gh auth status`, `glab auth status`, `gt auth status`). Not logged in: ask the human to log in, and wait.
- The labels the tracker has now (its list command).
- `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/`.

## 2. Ask

One question at a time, each led by your recommendation; skip a question the files already answer.

- **Tracker**: the remote's host with its CLI (`gh`, `glab`, `gt`), or local Markdown files under `.scratch/`, or another the human describes in a paragraph.
- **Triage labels**: keep the five defaults? Only on a no, collect the project's names for each role.
- **Domain docs**: single-context (`CONTEXT.md` and `docs/adr/` at the root) unless the repo holds several separately built packages; then offer multi-context (`CONTEXT-MAP.md` pointing at one `CONTEXT.md` per context).

## 3. Write

**`docs/agents/issue-tracker.md`**: the tracker, the repo, the exact command for each operation the factory's skills use, and how an issue reads:

- create an issue (body from a file or stdin, labels at creation), read one with its comments, list by label and state;
- comment, add and remove labels, assign, close (with the comment posted first when close takes none);
- read a raw body and rewrite it, which is how a Spec's `- [ ] #<n>` line gets ticked;
- create a label, and a milestone with a description; put an issue in a milestone; close a milestone;
- add an issue dependency (blocked by), and the fallback when the tracker has none: a `Blocked by: #<n>` line at the top of the body;
- find an issue's parents (`Part of #<n>`, and task lists naming it);
- **how an issue reads**, in a section `## How an issue reads`: every issue an agent files opens with the template's header lines, then `## Synopsis`, two to four plain sentences (what changes or is wrong, why it matters, what done looks like). An issue that waits on the human (`ready-for-human`, or `needs-triage` for their triage) ends its synopsis with a bold line ("**Needs two decisions from you.**"), then has `## What you need to do`: one numbered item per decision (a bold question, its options, a recommendation with its reason) or action (its steps), then how to reply and what happens next. The details come last. An escalation comment opens with its own `## What you need to do`; on the human's answer, comment it in their words, remove the label, and rewrite the bold line and that heading as the answer;
- the **Factory backlog** operations, in a section `## Factory backlog`: the parent is one issue titled `Factory backlog` and labelled `factory-backlog` (the label created the first time it is needed), whose body is a `## Synopsis` (what it is, and that it closes when empty) and an `## Open` task list, one `- [ ] #<n> <title>` line per open child, and nothing else. Find it by its label, open or closed, and say what the list command does when the label doesn't exist yet; create it; file a child (`Part of #<backlog>` as its first line, labelled `factory-improvement` and `ready-for-human`) and add its line, reopening a closed parent; remove a closed child's line (remove it, never tick it); close the parent, with a comment, once the list is empty;
- the **wayfinding** operations: a map is one issue labelled `wayfinder:map`; its tickets carry `Part of #<map>` and a `wayfinder:<type>` label (`research`, `prototype`, `grilling`, `task`); claim by assigning; resolve by commenting, closing, and adding a pointer to the map.

Try each command once against the tracker (a read, a label list) before writing it down.

**`docs/agents/triage-labels.md`**: a table from each role to the project's label: `needs-triage` (to evaluate), `needs-info` (waiting on the reporter), `ready-for-agent` (fully specified, an agent can take it), `ready-for-human` (waits on the human: a decision, a check or a hands-on step), `wontfix`.

**`docs/agents/domain.md`**: the layout, and how agents use it: read `CONTEXT.md` (or `CONTEXT-MAP.md` and the relevant contexts) and the ADRs touching the area before exploring; name things with the glossary's terms; say so when output contradicts an ADR. A missing file is fine: it is created when a term or decision is first settled.

**`AGENTS.md`** (or `CLAUDE.md` when only it exists): an `## Agent skills` section with one line each for the tracker, the triage labels and the domain docs, each pointing at its file. Update the section in place when it exists.

**Labels**: with the same label script adopt.sh used, create every label the tracker lacks: the five triage labels (by their project names), `wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling` and `wayfinder:task`. Done when the tracker's label list shows all of them plus `spec`, `approved` and `playtest`. A local-Markdown tracker has no label store: its labels are words in the issue files, so record the full list in `issue-tracker.md` and run adopt.sh without `FACTORY_LABEL_CMD`.
