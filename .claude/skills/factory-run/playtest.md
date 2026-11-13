# The Playtest

After the Drift sweep and the retro the Run prepares a build, checks everything a script can, and hands it to the human. The human judges only feel and look. The checklist is in the milestone's description, written by factory-spec: **Run checks** for you, **Human checks** for the human.

## Run checks

From the main checkout, on dev:

1. **Scenarios** first, with [`scenarios.md`](scenarios.md): scripted at the Feature's first end, then run, every Feature's. A Scenario that fails, against the Spec, is a bug filed there before any build.
2. **Build:** `bash tools/verify/playtest`. It prepares a playable build and prints where it is (a file path, a URL, the devices it installed on); the project may have tailored it to install too. Exit 1: its stderr says why. A missing device or toolchain is a setup problem: report it as the build's result, and the human builds and installs it themselves.
3. **Install and launch** the build the way the project's device doc says (AGENTS.md points to it), unless the step already did. Send no scripted input: the human may be holding the device.
4. **Log:** capture the game's log from launch, the way the device doc says, and report every error line. Without a device: "not run".
5. **Frame pacing:** only when the milestone lists it for a performance criterion, measured on the device and in the way the device doc says. Otherwise, or without that device: "not measured".
6. Any other run check the milestone lists.

A run check that fails on the build (it won't launch, the log has errors) contradicts the Spec: file a `Kind: bug` slice in this milestone (below) and go back to picking issues. Never hand the human a broken build.

## The Playtest issue

Create it in the milestone, labelled `playtest` and `ready-for-human`, titled `Playtest: <Feature title>` (`Re-playtest: ...` after a fail). Then send the human a push notification and go on into the next Feature's ready slices (SKILL.md's Pick): the Playtest waits on the human, the Run doesn't. Never two Playtests open at once: when the next Feature ends while this one is open, its whole End of run waits, Drift sweep and retro too, and the Run, with nothing else to take, tells the human so and stops; once this one is answered, a Run runs that End of run from its first step. The body:

```markdown
## Synopsis
The playtest build of <Feature title> (Spec #<spec>) <is ready | didn't build here: <why>, so you build it yourself>. <The run checks in a line: all passed, or which were not run or not measured.> **Needs <n> checks from you.**

## What you need to do
1. **Get the build:** <where the playtest step put it: the file, the URL or the devices it is installed on; or why it didn't build, and how to build it yourself>.
2. **Play it** and judge each check:
   - [ ] <copied from the milestone: a thing to do, and a thing to judge>
3. **Report back:** tick each check that passes and comment on the rest, here or in a `/factory-run <spec>` session. That session sorts what you found: a pass closes the Feature, and anything else becomes new issues.

## Build
Commit <dev SHA>. <what the playtest step printed, or why it didn't build>

## Run checks
- Scenarios: <pass | not run: <why>> — `bash factory/core/scenarios.sh`, exit <code>
  - <Scenario name>: pass
- <check>: <pass | fail | not run | not measured> — <the evidence: command and exit code, or the log lines>

## Untested
- #<n> <title>: parked, so not in this build.

## Drift
- #<n> <title> (cleanup, next milestone), or "Nothing found."

## Retro
- #<n> <title> (factory-improvement, part of the Factory backlog), "Nothing repeated." or "Nothing to decide: the proposals are noted in the retro comment." ([`retro.md`](retro.md))
```

## Intake

The human reports in a `/factory-run <spec>` session, or in comments on the Playtest issue that the next session reads. Either way, sort each finding into one class. When you can't tell a Tweak from a behaviour change, it is the human's call: ask in the session, or reply on the issue and wait.

| The finding | What you do |
|---|---|
| Contradicts the Spec | A `Kind: bug` slice in this milestone; the run uses repro-first. |
| **Tweak**: feel or tuning, the behaviours stay as they are | A `Kind: build` slice in this milestone. Log the human's words under the Spec's Human's calls. No re-approval: asking is the approval. |
| Changes, adds or drops a behaviour, or reorders Features | Remove `approved` and change the Spec with factory-spec ("Changing an approved Spec"). The Run waits for re-approval. |
| An idea beyond this Spec | A `needs-triage` issue, in no milestone and outside the Slices, for a later Spec. |
| An architecture change, or a check for one | A `Kind: amend` issue labelled `ready-for-human`, as for any amend: once approved, a slice whose check of the project's gate files an amend builder writes ([`amend-slices.md`](amend-slices.md)). A check inside `factory/` is a `factory-improvement` proposal instead, as [`retro.md`](retro.md)'s "File it" files one. |

The bug and Tweak slices take the shape [`slicing.md`](../factory-spec/slicing.md) gives, labelled `ready-for-agent`, each listed under its Feature in the Spec's Slices. The `needs-triage` and amend issues take the shape `docs/agents/issue-tracker.md`'s "How an issue reads" gives, their question for the human under `## What you need to do`. Then post one intake comment on the Playtest issue: each finding, its class and its issue link. Tick the human checks that passed, and mark the issue answered as that section says.

## Pass and fail

- **Pass:** every human check passes and the intake opened no bug, Tweak or behaviour change. Close the Playtest issue. Close the milestone once all its issues are closed (the tracker doc's milestone command); the Run, on the next Feature already, carries on, and the Spec closes with its last milestone.
- **Fail:** close the Playtest issue with the links to the new issues. The Run works them in this milestone ahead of every open slice of a later Feature (the Spec's order lists them first; an issue already in flight finishes), sweeps, and opens a Re-playtest issue holding only the failed checks plus a check for each thing the fixes touched (each Tweak among them).
- **Parked issues** keep the milestone open until they are resolved or the human moves them out, even after a pass.
