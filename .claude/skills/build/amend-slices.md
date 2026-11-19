# Amend slices

A `Kind: amend` slice changes `ARCHITECTURE.md` or an ADR, plus the project's checks that enforce them: its step scripts, pins and ratchet files in `tools/verify/`, the gate's files. The human approved it with the Spec, or as the Drift sweep's or a Playtest's proposed check. Its brief says `Kind: amend. Phase: green.`, with each file it changes in scope, the gate's among them: no red phase and no Lock (SKILL.md, Test-only issues).

- **Who writes what.** The Editor can't write the gate's files: its first prompt (phase `green, amend`) has it stop and name one the brief needs. Those are an **amend builder**'s, the `amend-builder` subagent; the Editor writes the rest: `ARCHITECTURE.md`, the ADR and any product change.
- **A check inside `factory/`** (the Core's or an adapter's) is no slice's: file it as a `factory-improvement` proposal on the **Factory backlog**, as [`retro.md`](retro.md)'s "File it" files one, for `/factory-amend`. A brief that would need one is a Human's call: escalate.
- **Order:** the brief review when the brief has `test` lines, then the builder, then the Editor's first round (none when the brief names only gate files), so the Editor's gate already runs the new check. Then step 4 and Land: `land.sh` lets a branch whose sealed brief is `Kind: amend` change the gate's files.
- **Dispatch:** `state.sh incr uncounted`, then a driver reports `needs amend-builder <prompt file> <effort>` ([`parallel.md`](parallel.md)), at the effort [`editor.md`](editor.md)'s Effort gives a round; its report comes back as `factory-result: amend-builder`. A builder that can't build the check as briefed, or whose check the code already fails, is an escalation: a Human's call, recommending a slice ahead of this one that fixes that code. The Baseline never takes such findings: an issue branch can't grow it (`baseline.sh`), and an Armed project's pre-commit refuses a static check's.

## The builder's brief

[factory-amend's `brief.md`](../factory-amend/brief.md), every field filled, `factory-amend: issue-<n>` its second line, with these changes:

- **Goal, Evidence, Decisions:** the issue, its approval and the human's words from the Spec or the issue; the brief's Constraints for the check.
- **Worktree:** the issue's worktree, on its branch `issue/<n>`, from the branch's current commit: no new branch or worktree. Pushing, rebasing, landing and dev are yours.
- **Build:** only the gate files the brief names, each with what done looks like; never `factory/`. No `amend.sh record`. Then `bash tools/verify.sh` passes on the code as it stands. A check the code already fails is a stop: commit nothing, and report its findings, leaving the Baseline alone (no `baseline.sh add`).
- **Tests:** the check's own fixtures, where the project keeps its checks' tests; `bash tools/verify.sh` stands in for the factory's suite.
- **Review:** none: the issue's Verifier reads the whole branch at step 4.
- **Commit:** commits on the issue branch, each `Amend the project's checks: <what>`, with no squash and no `Targets:` trailer.
- **Report:** as `brief.md` says, without the review passes.
