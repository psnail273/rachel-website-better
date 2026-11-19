---
name: build
description: Work an approved Spec's ready-for-agent issues, up to two at once and Feature by Feature, from Build Brief through the red and green phases to Land, the Editor writing all code.
disable-model-invocation: true
effort: low
---
# build

You are the **Driver** of a **Run**: you brief, gate, rule and land; the Editor writes and commits all code and tests. Terms are in `factory/CONTEXT.md`; tracker commands, and how an issue reads, in the tracker doc AGENTS.md points to. Run the Core's scripts from the issue's worktree unless a step says otherwise; [`editor.md`](editor.md) holds how each Editor round and Verifier check runs, at what effort (Agents and effort), and how `prompt.sh` writes each prompt.

## Durable state

A session can end at any point, so all state lives outside it: the branch's run state (`bash factory/core/state.sh [--issue <n>] list`: phase, `rounds-<phase>`, red-commit) and the issue's comments (brief, rulings, verdicts). Write each one the moment it changes. **Todos:** track each issue's steps as todos; every todo ends done, or skipped with a one-line reason that goes into the close comment.

## Pick the next issue

`/build <spec>` refuses a Spec without the `approved` label. Work its first open Feature (its tracker milestone), and the next one while the first's Playtest waits ([`playtest.md`](playtest.md)). At the Run's start, in the main checkout, take up the factory's patch releases. When the session's update check said it is syncing one, wait for the last line of its log, `<git common dir>/factory/update-sync.log`: `update-check: synced` or `failed`. Otherwise run `bash factory/core/sync.sh check`; on `newer` with a patch release (the same major.minor) and no `.claude/worktrees/issue-*`, run `bash factory/core/sync.sh <tag>` and commit it on dev as `Sync factory <new> (from <old>)`. After either sync, push dev, since issues are cut from `origin/dev`, and say so in one line. A failed sync, an adapter-template diff it printed to port into `tools/verify/`, or any other `newer`: ask the human before the first issue.

1. **Playtest intake** first: an open `playtest` issue waits on the human. Sort the human's findings, from this session or its comments, with [`playtest.md`](playtest.md); with none yet, it waits: go on with the next Feature.
2. **Resume:** an issue with a worktree `.claude/worktrees/issue-<n>` and no `ready-for-human` label is in progress: dispatch it again. Its run state and comments say where it stopped; its driver reruns an Editor round or a Verifier check whose result was lost. A worktree `.claude/worktrees/brief-<n>` is the snapshot that issue's brief review reads; `.claude/worktrees/drift-<spec>` is a Drift sweep under way.
3. Otherwise take the first open, unblocked `ready-for-agent` issue in the Spec's order, skipping parked ones, and claim it: assign it and comment that the Run has it.

Every issue but an asset slice (`Kind: asset`: the `asset-fetcher` subagent fetches the Spec's Assets, with no Editor, as [`assets.md`](assets.md) says) goes to a `driver` subagent of its own, resumed after each `needs` report, even when it is the only one in flight, and never to a fork. The main session dispatches up to two at once and keeps Playtest intake, asset slices, the Drift sweep, the retro, the `needs` subagents and every question for the human: [`parallel.md`](parallel.md). A driver follows Per issue and the sections after it.

## End of run

When nothing is left to take in the Feature, parked issues aside, and no other Feature's Playtest is open (with one open, this End of run waits whole: [`playtest.md`](playtest.md)):

1. Run the **Drift sweep** with [`drift.md`](drift.md): a read-only Verifier reviews the whole codebase against the `review` rules and the accepted Deviations; you file what it finds as cleanup issues, and any proposed check as an amend.
2. Run the **retro** with [`retro.md`](retro.md): total the Feature's `factory-stats:` lines, sort every failure and escalation by cause, and file what needs the human's yes as one `factory-improvement` child of the **Factory backlog**.
3. Run the checks and open the **Playtest** with [`playtest.md`](playtest.md): the **Scenarios** first ([`scenarios.md`](scenarios.md)), whose failures are bugs filed before any build, then the playtest build, the other run checks and the Playtest issue for the human. Then go on into the next Feature.

## Per issue

1. **Start:** from the main checkout, pipe the issue's raw body, from the tracker doc's read command, into `bash factory/core/start.sh <n> --title "<title>"`. It prints the worktree and saves the issue for `prompt.sh` at the worktree's `<git-dir>/factory/issue.md`; a rerun without `--title` keeps the one saved. Exit 1: rerun once, then escalate.
2. **Build Brief:** write it with [`build-brief.md`](build-brief.md), `bash factory/core/brief.sh seal` in the worktree, post a copy as an issue comment, then `state.sh set phase red` (`partial` for `Kind: cleanup`, see Partial mode; `green` for a test-only issue or an amend, see Test-only issues). After any later edit to the brief, seal it again before the next round. A brief with `test` lines gets a **Brief review** ([`editor.md`](editor.md)) before the first round, which waits for its PASS. On a FAIL, rule on each FAIL line: overrule one you judge wrong, posting why under the review; a FAIL whose every line you overrule counts as a PASS. If any line stands, `state.sh incr fails-brief`, correct the brief, seal it again, post the change and review again, all before the first round. A second FAIL is the last review: correct or overrule each of its lines yourself.
3. **Red phase:** the first Editor round. Then `bash tools/verify.sh --red --reuse`, and on exit 0 a Verifier with phase red. Both pass, and the brief review passed on the brief as sealed, or you ruled on every line of its last FAIL: `bash factory/core/lock.sh record` (the **Lock**). It runs the red gate again itself, fresh, and locks only when that passes, so the Lock never rests on a kept verdict. Comment the red SHA, `state.sh set phase green`.
4. **Green phase:** an Editor round with the green prompt. Then `bash tools/verify.sh --reuse`: after a green round it runs fresh (every browser, a full mutate), as the Editor's lighter gate keeps its own **Gate stamp**. Then a Verifier with phase green, and your rulings on every Deviation. Read the Editor's final message, the verify summary, the Verifier's verdict, `git diff --stat` and the Deviation hunks; the Verifier reads the full diff. Spot-check any claim without evidence.
5. **Land:** from the main checkout, `bash factory/core/land.sh <n>`. It prints the gate's verdict and keeps the steps' output in `<common git dir>/factory/land-<n>.log` (the main checkout's `.git/factory/`); on a red gate it also prints that output's last lines, the failing step's, and the log's path.
   - Exit 3: land.sh aborted a conflicting rebase. Start it again yourself in the worktree (`git fetch origin && git rebase origin/dev`); it stops on the conflicts. Send the rebase-conflict round (uncounted), in which the Editor resolves them and continues the rebase, then Land again. Exit 1 on a red gate: a counted trigger; on a gate change (`gate:` lines), a counted round that reverts it, unless the issue is an amend; on a refused push: rerun Land.
   - Exit 0: post the close comment (what was built, rounds per phase from the printed state, rulings, the Verifier's verdict, skipped todos), then any `factory-note:` lines (driver.md), ending with the printed `factory-stats:` line as is; close the issue. The main session ticks `- [x] #<n>` in the Spec on your `landed` report ([`parallel.md`](parallel.md)).

## Small lane

A brief with a `lane small` line, from a slice marked `Lane: small`: `brief.sh seal` holds it to the lane's limits and records the lane. One Editor round, and no red Verifier.

- Once the brief review passes, send the first prompt with phase `red, small lane`. Its stop hook runs the red gate; once that passes on a clean tree, the hook records the Lock, sets the phase to green and sends the green instruction in the same subagent. A round that ends with the phase still red is a counted red fix round on the gate's findings (Fix rounds); the hook moves on once the gate passes.
- Then step 4, with one Verifier on phase `green, small lane`: it judges the tests as well as the code.
- **A test FAIL** (the Verifier says the test itself is wrong): `state.sh incr fails-green`, as for any FAIL. A test that contradicts the sealed brief is the Lock lift of Driver's calls, as in any lane. Any other (the brief is wrong) is a Human's call: escalate, with the evidence and the alternative: accept the Editor's workaround as a Deviation.

## Test-only issues

A `Kind: build` slice marked `Tests only: yes` adds tests over behaviour already built, such as a leak check that now covers new screens. A test of working code can't fail first, so the issue has no red phase and no Lock. Tests that turn out to need a product change are a new slice with a red phase: escalate that as a Human's call the Spec missed. Its brief says `Kind: build. Phase: green.` `brief.sh seal` holds it to test files and the Driver's docs in scope, at least one test and no seam. The deviation step fails any other file the branch changes, with a trailer or without. Then `state.sh set phase green`, run the brief review, then send the first prompt with phase `green, test-only`, then step 4, with the Verifier on phase `green, test-only`. **An amend** (`Kind: amend`, Phase green) has no red phase and no Lock either: the same steps, with the first prompt on phase `green, amend` (and a brief review only when the brief has `test` lines) and the Verifier on phase `green`; an amend builder writes the project's checks it names first ([`amend-slices.md`](amend-slices.md)).

## Fix rounds

Counted triggers: the gate red after a round, a deviation-step failure, a Verifier FAIL, a rejected Deviation. Before a counted round, read `rounds-<phase>`: below the cap of 2, `state.sh incr rounds-<phase>`, then send the fix round; from 2 on, only as an extra round (Driver's calls), else escalate. `incr` refuses a 5th, the ceiling of 4. Rebase conflicts, accepted Deviations and clarifications don't count. The retro's counts, the moment each happens: `state.sh incr fails-<phase>` on every Verifier FAIL, `incr fails-brief` on every brief review FAIL with a line that stands (step 2), `incr rejected` on every rejected Deviation, `incr uncounted` on every uncounted round you send (a brief fix too).

## Rulings

Every Deviation gets a ruling: each `deviation-declared` and `deviation-undeclared` finding, each `ratchet-growth` and every off-scope file the Verifier names.

- **accept:** the change stands. For an off-scope file with no trailer, add a `scope` line for it to the brief; for ratchet growth (a rule may call a new allowlist entry one), add a `grows <file> <entry>` line, which is what lets it pass the deviation step. Seal the brief again after the edit.
- **reject:** a counted fix round to undo it.
- **amend:** it changes `ARCHITECTURE.md`, an ADR or a gate: escalate.

Append each ruling to `docs/deviations.md` and commit it on the branch: issue, commit, what deviated, the reason or "undeclared", the ruling, your reasoning, and the amend link if any. The file is append-only.

## Driver's calls

A finding is **inside the brief** when fixing it changes no acceptance criterion, no Spec behaviour, and nothing a player would see or feel beyond what the sealed brief already says. On such findings these calls are yours, each within its limit: decide, log, carry on. Everything else is a Human's call (Escalation).

1. **Extra round:** from the cap on, when every open finding is inside the brief, up to 2 more counted rounds per phase (4 in all, the ceiling), each naming the exact fixes: `incr rounds-<phase>`, then send it.
2. **Takeover:** past the ceiling, every open finding still inside the brief, one per issue: a fresh Sonnet Editor (`editor-sonnet`) writes one round from the current commit, under the same brief and gates, its prompt a fix round's. It keeps the round counts (`state.sh` refuses a 5th): `incr uncounted`. A counted trigger after it escalates.
3. **Out of reach:** a surviving mutant or a Verifier finding you judge out of practical reach (an unreachable input, an equivalent mutant): accept it as a Deviation with its reason, overruling that FAIL line; a FAIL whose every line you overrule counts as a PASS. The gate's own findings stay: Land runs it.
4. **Lock lift:** a locked test that contradicts the sealed brief (the test is wrong, the brief is right), in any lane: in the green phase, `bash factory/core/lock.sh lift`, then the counted fix round that may change the tests (an extra round at the cap), `lock.sh record` (it runs the full verify fresh) and a fresh Verifier. `lift` works once per issue, whoever runs it: a second wrong locked test escalates. The factory's allow rule for it (`hooks.sh generate`) lets it run without a prompt; should a permission prompt or the classifier still refuse it, escalate, and never work around a refusal (no other way to move the Lock); on the human's yes the main session lifts it ([`parallel.md`](parallel.md)), and you log the lift and the FAIL lines as a ruling (no `self-ruled`) and go on from the fix round.

Log each call as you make it, the lift once `lift` succeeds: post it on the issue under **Decided for you**, as `Driver's call: <extra round|takeover|out of reach|lock lift>: <what>. <one-line reason>`; append it to `docs/deviations.md` (Rulings), its ruling `driver's call: <kind>`; then `state.sh incr self-ruled`. The retro lists every one.

**Editor questions:** when the Editor stops on one that is a Human's call (feel and taste, scope and priority, an amend, cost or irreversibility), escalate. Otherwise decide it, post it under **Decided for you** with a one-line reason, and send one uncounted clarification round (no `self-ruled`). A second question on the same issue escalates.

## Agents and effort

The Editor is the `editor-sonnet` subagent (`claude-sonnet-5-5`); the Verifier, for every check, the brief review, the Drift sweep and the Scenarios, is the `verifier` subagent (`claude-opus-5-5`). Every round and check is a fresh subagent, run as [`editor.md`](editor.md)'s Subagents says, at effort medium unless its dispatcher raises it (`factory/CONTEXT.md`, Models and effort; editor.md's Effort): high for a big change, xhigh after the same tests fail in two rounds in a row, never max. Fable runs only with the human's yes for that one subagent. A subagent's second infrastructure failure escalates.

## Partial mode

For `Kind: cleanup`: on an Adopted project, and on an Armed one, where the Baseline is empty and the same gate allows no finding at all (a Drift sweep's cleanup). No red phase and no Lock: the first Editor round uses phase `partial`, and the brief lists `removes` lines (none for a Drift sweep finding on a `review` rule, which has no Baseline entry).

- Gate: `bash factory/core/brief.sh removes > <tmp>/removes`, then `bash factory/core/baseline.sh --reuse gate <tmp>/removes`. It passes when the findings sit within the Baseline minus those entries; the Editor's stop hook loops on the same gate. The Verifier judges the acceptance criteria and the Rules (phase green), with this gate as its gate command (verify-rubric.md).
- Before Land: `bash factory/core/baseline.sh shrink`, commit `tools/verify/ratchet/baseline.txt` yourself. `land.sh` then gates on the Baseline instead of the full verify. While the Baseline holds findings, only `Kind: cleanup` can land: every other Kind gates on the full verify, which stays red until the Baseline is empty. Put the cleanup ahead of it.
- An amend made outside an issue branch that adds a check the code already fails (a new rule, or a factory update's; [`amend-slices.md`](amend-slices.md) covers a Run's amend slice): in the amend's commit, `bash factory/core/baseline.sh add <rule>...` puts that check's findings in the Baseline. File a `Kind: cleanup` issue whose `removes` lines are those entries, ahead of everything else in the Feature.

## Escalation

A **Human's call**, anything that isn't a Driver's call: a finding or question not inside the brief (the brief wrong in a way that changes behaviour, a new behaviour or a visible or audible choice the Spec didn't make, scope or priority), an amend (`ARCHITECTURE.md`, an ADR or the gate), cost or irreversibility, a subagent's second infrastructure failure, a Core script failing twice, a refused or second Lock lift, and a counted trigger once the ceiling and the Takeover are both spent. Then:

1. Post a comment that opens with `## What you need to do`: the question, and each option with your recommendation, a **Takeover** among them (you or Sonnet write the code, under the same gates, logged in `docs/deviations.md`). The evidence follows (commands, exit codes, findings).
2. Label the issue `ready-for-human`, `state.sh incr escalations`, and send the human a push notification. A driver reports `escalated` instead, with the question and its options: the main session notifies the human and asks them ([`parallel.md`](parallel.md)).
3. Leave the worktree and its run state as they are. The issue is **parked** until the human answers: carry on with issues that don't depend on it.
