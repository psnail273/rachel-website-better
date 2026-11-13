# The Drift sweep

When a Run has no issue left to take in its Feature, parked issues aside, it sweeps the whole codebase for drift before it stops for the Playtest. The gates judge one diff at a time; the sweep catches what they can't: the `review`-tagged rules across all the code, and accepted Deviations that have spread or no longer hold. A read-only Verifier does the reading; you file what it finds.

## Run it

1. **Snapshot:** from the main checkout, `git worktree add --detach .claude/worktrees/drift-<spec> dev` (dev holds every issue the run landed). While this worktree exists a sweep is under way: on resume, rerun it.
2. **Prompt:** in that worktree, `FACTORY_RUBRIC_TEMPLATE=factory/skills/factory-run/drift-rubric.md bash factory/core/rubric.sh > <scratch>/drift-<spec>-<k>.md`. It is [`drift-rubric.md`](drift-rubric.md) with the review rules filled in. Put one line above it: `Drift sweep for Spec #<spec>, Feature <Feature title>.`
3. **Verifier:** a fresh `verifier` subagent (`subagent_type: verifier`) with the file's text as its prompt, the effort its first line names (`factory-effort: medium`, or `high` for a Feature that landed many issues or changed a Core script) and the drift worktree's absolute path on its last (`factory-worktree: <path>`), run and compared before and after as [`editor.md`](editor.md)'s Subagents says.
4. **Check:** read each `FINDING` and `CHECK` line, and open its `file:line`. Drop a line whose evidence doesn't show it, and one an open issue already covers. You confirm; you don't sweep again yourself.
5. **Clean up:** `git worktree remove .claude/worktrees/drift-<spec>`.

## File the findings

**Cleanup issues.** Group the confirmed `FINDING` lines one Build Brief can fix (same rule, same module) into one issue, in the shape [`slicing.md`](../factory-spec/slicing.md) gives, with:

- `Kind: cleanup`, so the run works it in Partial mode, on an Adopted or an Armed project alike (SKILL.md). A `review` rule has no Baseline entry, so its brief may have no `removes` line: the Partial gate then only forbids new findings, and the Verifier judges the criteria.
- an `## Evidence` section with the finding lines as the Verifier wrote them. A cleanup's behaviour is the code, so here file:line belongs in the issue.
- one acceptance criterion per finding: "`<file>` no longer <drifts>, and R<n> holds there".
- the label `ready-for-agent` and the milestone below.

**Which milestone.** The next open Feature milestone of the Spec, where the issues run first as prefactors: list them at the top of that Feature's group in the Spec's Slices, as `- [ ] #<n> <title>`, so they never hold up this Feature's Playtest. After the last Feature, create a `#<spec> cleanup` milestone (description: "Drift sweep cleanup. No Playtest.") and add a **Cleanup** group to the Slices. Neither change is a change to the Spec: it keeps `approved`.

**Proposed checks are amends.** A `CHECK` line proposes a new gate check, which changes `ARCHITECTURE.md` or a gate, so it is the human's call: open a `Kind: amend` issue labelled `ready-for-human`, in no milestone and outside the Slices, in the shape `docs/agents/issue-tracker.md`'s "How an issue reads" gives. Under `## What you need to do` it asks one question, "Approve this check?", yes or no, with your recommendation and its reason; the evidence goes in the details. It joins a Spec only once the human approves it. Then it is a slice the Run builds, an amend builder writing the project's check ([`amend-slices.md`](amend-slices.md)). A check inside `factory/` (the Core's or an adapter's) is no slice's: file it as a `factory-improvement` proposal on the **Factory backlog** instead, as [`retro.md`](retro.md)'s "File it" files one, for `/factory-amend`.

Done when every confirmed line is in an issue. List them all, with any amends, under Drift on the Playtest issue ([`playtest.md`](playtest.md)); a sweep that found nothing says so there.

## The cleanup milestone

It has no Playtest: a Feature of cleanup issues only may skip it. A Run that empties it sweeps the whole codebase as any sweep does, and files new findings back into it. When a sweep there finds nothing, close the milestone; the Spec closes with it.
