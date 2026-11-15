---
name: factory-spec
description: Turn the human's overview or a finished wayfinder map into an approved Spec issue, with its Features as playtest milestones and its slices published as ready-for-agent issues.
disable-model-invocation: true
---

# factory-spec

You draft a **Spec** and, on the human's approval, publish it as issues `/factory-run` works unattended. You decide by default; the human answers only the **Human's calls** and approves. Terms are defined in `factory/CONTEXT.md`. Issue-tracker commands, and how an issue reads, are in the tracker doc AGENTS.md points to.

## 1. Gather

Input is the human's overview, or a wayfinder map that has reached its destination (read the map and every decision ticket it links). Read the code the work touches, `ARCHITECTURE.md`, the ADRs and the CONTEXT files, and send research questions to subagents: each a fresh `general-purpose` one with `model: sonnet` (the Agent tool's name for `claude-sonnet-5-5`) at effort `medium` (`factory/CONTEXT.md`, Models and effort). Done when you can name every decision the Spec needs and which code and rules each slice will touch.

## 2. Decide

Sort every open decision:

- **Human's call**: feel and taste; scope and priority, including the order of Features; an **amend** (anything that changes `ARCHITECTURE.md` or an ADR); cost or irreversibility (accounts, money, publishing, deleting data). Ask these, a few at a time, in plain words with your recommendation.
- **Everything else**: decide it and list it under **Decided for you** with a one-line reason. When you can't tell whether a decision is the human's call, decide it and put it first in that list.

Run as many rounds as the answers raise, all in this session. Done when no Human's call is open, including any slicing turns up.

## 3. Design direction

When a look-and-feel decision is a Human's call, settle it by sight before you slice, as [`design-direction.md`](design-direction.md) says: the `designer` subagent builds two or three **Design directions** live in the app on a throwaway branch, the human picks or mixes one, and the winner becomes `docs/design.md` and the **Board**, which the slices are written to match. Skip it otherwise, and say why under Decided for you.

## 4. Draft the Spec

Create one issue labelled `spec` (the draft stays unapproved until step 5). Its body is an index: it links decisions, tickets and ADRs instead of restating them, and has no user-stories list. Sections, in order:

- **Synopsis**: two to four plain sentences: what the Spec changes for the player or the developer, why it matters, and what done looks like.
- **Problem**, **Solution**: from the human's side.
- **Features**: for each, its behaviours and what its Playtest checks (below).
- **Human's calls**: each question asked, with the human's answer.
- **Decided for you**: one-line reasons, the uncertain ones first.
- **Amends**: the approved changes to `ARCHITECTURE.md` or an ADR.
- **Assets**: every external file the slices need (sound, music, image, font, data), as a table: the path it gets in the project, its source URL, its licence, the slices that use it. Or None. A licence that asks more than a credit (share-alike, non-commercial, no derivatives) is a Human's call.
- **Out of scope**.
- **Slices**: a task list grouped by Feature; each line gives the title, Kind and dependencies. Slice with [`slicing.md`](slicing.md).
- From a map: a link to the map and its decision tickets.

A **Feature** is a group of slices that ends in one Playtest; a Feature of cleanup issues only, such as an Adoption cleanup, may have none. Split Features where the human can first judge something new; a small spec has one.

**Playtest checklist**, one per Feature, from its behaviours and Human's calls:

- **Run checks**, done by the agent before the run stops: the playtest build installs and launches; the log has no errors through the Feature; frame pacing only when the Feature has a performance criterion, measured where the project's device doc says (otherwise reported "not measured"). Anything a script can check goes here.
- **Scenarios**, under Run checks: one per behaviour a player can drive, in words, "do this, then this must hold": "Lose the last ball, then tap: a new ball leaves the paddle." The Spec's behaviour only, never how the code does it. The Run scripts them at the Feature's end, out of the Editor's sight, and runs them before every Playtest from then on (factory-run's `scenarios.md`).
- **Human checks**: feel and look only. Each is a thing to do plus a thing to judge: "Finish the sign-up flow. Does the welcome screen feel friendly, and is it too long?"

Show the human the draft and revise the issue for each round of feedback. Done when every section is filled, every slice passes `slicing.md`, and the human has read the whole draft.

## 5. Approve and publish

Publish only on the human's explicit approval in this session. Then, in order:

1. Post the comment `Approved by the human` on the Spec, quoting their words.
2. Add the `approved` label. `/factory-run` refuses a Spec without it.
3. Create one milestone per Feature, named `#<spec> <n>. <feature>`, with the Feature's playtest checklist as its description (the tracker doc's milestone command). Number Features in the human's order.
4. Publish the slices in dependency order (dependencies first), each in the shape `slicing.md` gives, labelled `ready-for-agent`, in its Feature's milestone (`--milestone`). Add each dependency as a native issue dependency.
5. Rewrite the Spec's Slices section as `- [ ] #<n> <title>` lines, still grouped by Feature, so the run ticks them as it closes issues.

Done when every slice exists with its label, milestone and dependencies, and the Spec's task list names each one by number. Report the Spec and milestone links to the human.

## Changing an approved Spec

Given an existing Spec number, read it, its milestones and its open slices first. A change to a Feature's behaviours, the Feature order or the scope, or an amend (an architecture change found later, at a Playtest say), removes `approved` before you edit, then runs steps 2 to 5 again for what changed; publish only new or changed slices and leave closed ones alone. These don't count as a change and keep `approved`:

- Drift sweep cleanup issues;
- a **Tweak** from a Playtest, logged under Human's calls in the human's words.
