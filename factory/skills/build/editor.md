# Running the Editor and the Verifier

The Editor is the `editor-sonnet` subagent (`claude-sonnet-5-5`), the Verifier the `verifier` subagent (`claude-opus-5-5`): both Claude Code subagents (Agent tool), a fresh one for every round and every check, the brief review's too. They run as [Subagents](#subagents) says; a driver, which can't start one, hands each to the main session ([`parallel.md`](parallel.md)).

## Effort

Each round and check runs at an effort its dispatcher picks (`factory/CONTEXT.md`, Models and effort): the issue's driver for its rounds and checks, the main session for the Drift sweep and the Scenarios. Every agent's definition says `medium`, the default; raise it with the Agent tool's `effort` only:

- **high** for a big change: a brief whose scope spans many files or touches a Core script, or a rebuild after a red Land; its Verifier checks too.
- **xhigh** after the same tests failed in two rounds in a row: the next round, and the Takeover.
- Never `max`, and never another model: Fable (`claude-fable-5-2`) runs only when the human approved it for that one subagent.

Write the effort as the prompt file's first line, `factory-effort: <level>`, so the retro can see it.

## Mechanics

- **Every command** runs in the foreground, with the Bash tool's timeout at 600000 ms: start, seal and the Core's other scripts each end well inside it. Verify, `lock.sh record` and land run past the 180 s after which the Bash tool backgrounds a command anyway, and may wait for a machine-wide gate slot or the build lock while other issues' gates run: run them with `run_in_background` and wait for the notification, or on their PID with `tail --pid=<pid> -f /dev/null`, as `driver.md` says. Never wait with `sleep`, `until`, or a background command you poll.
- **Worktree:** the absolute path of the issue's worktree under `.claude/worktrees/`, named on the prompt's last line.
- **Prompt:** written to a file outside the worktree (your scratch or temp folder), as Prompts below says; the subagent gets its text unchanged.

**Infrastructure failure** (the subagent ends in an error: model unavailable, a usage limit, a crash): run the round or check once more, as a fresh subagent from the current commit; it adds no round. A second failure escalates (SKILL.md, Escalation).

**Visual issue** (`verify-rubric.md`'s Design check defines it): the Editor's final message names the contact sheet's folder (`tools/verify/contact-sheet`), and the green check's Verifier judges the sheet beside the Board; a Verifier takes the sheet itself when it is missing or stale.

**A Verifier changes nothing:** `tools/verify.sh` has to write, so a check can't run read-only, and nothing sandboxes it. Its agent file tells it to change nothing and to leave secrets (`.env*`, `tools/verify/secret-paths`) unread, and to leave the Scenario folder unread, which the issue's worktree doesn't hold ([`scenarios.md`](scenarios.md)). Whoever runs it compares the workspace before and after (Subagents): any change voids the verdict. Restore the worktree and run a fresh check; a void verdict is not a Verifier FAIL and adds no round.

## Prompts

`bash factory/core/prompt.sh` prints each fixed prompt, filled in: redirect it to the round's prompt file, so you never retype the brief, the issue or the fixed text, and no line is left out. Run it in the issue's worktree. It fills the templates in `prompts/` from the issue as `start.sh` saved it at Start (`<git-dir>/factory/issue.md`), the sealed brief (`<git-dir>/factory/brief.md`), `rubric.sh` and the branch's base, as the deviation step takes it. A missing input exits 1, naming the file.

- **First Editor round:** `prompt.sh editor <phase>`, with phase `red`, `red, small lane`, `partial`, `green, test-only` or `green, amend` ([`prompts/editor.md`](prompts/editor.md)).
- **Verifier:** `prompt.sh verifier <phase>`, with phase `red`, `green`, `green, small lane` or `green, test-only` ([`prompts/verifier.md`](prompts/verifier.md)).
- **Brief review:** `prompt.sh brief-review` ([`prompts/brief-review.md`](prompts/brief-review.md)).

Later rounds send only what changed, then the footer ([`prompts/footer.md`](prompts/footer.md)): `prompt.sh footer >> <file>` appends it after a blank line.

- **Green** (after the Lock): `prompt.sh green` prints the whole round: the green line ([`prompts/green.md`](prompts/green.md)), then the footer.
- **Fix round:** the trigger's evidence (the failing findings, the Verifier's FAIL lines, the rejected Deviation and why) and what must change; an extra round (SKILL.md's Driver's calls) names each exact fix. The green gate's mutate step writes the mutants no test caught to the worktree's `$(git rev-parse --git-dir)/factory/survivors.txt`; the Editor's stop hook shows the Editor its own gate's list once, and your `verify.sh --reuse` writes the file afresh from a full run: after a Verifier FAIL on a mutant, quote that mutant's line from the file beside the FAIL line.
- **Takeover** (SKILL.md's Driver's calls): a fix round's evidence and fixes for the Sonnet Editor, after a line that it takes over the issue past the ceiling of counted rounds, from the current commit; it is a fresh subagent, so quote the findings in full.
- **Clarification:** your decision on the Editor's question, as it appears under Decided for you; quote the question above it, since a fresh subagent never saw it.
- **Rebase conflict:** you have started the rebase in the worktree (SKILL.md, Land), and it stopped. "The rebase onto origin/dev I started stopped on conflicts in <files>. Resolve them keeping both sides' intent, `git add` them and `git rebase --continue`, until the rebase is done; start, abort or redo no rebase yourself. Then rerun the gate."

## Brief review

The **Brief review** is the Verifier's check of a sealed brief with `test` lines, before the Lock (SKILL.md, step 2). It reads a snapshot of the issue's branch from before the first round, so the Editor's commits can't void it:

1. **Snapshot:** from the main checkout, before the first round, `git worktree add --detach .claude/worktrees/brief-<n> issue/<n>`, the brief worktree. Link the issue worktree's installed dependencies into it, so the Verifier can read library sources (Next.js: `ln -s "$PWD/.claude/worktrees/issue-<n>/node_modules" .claude/worktrees/brief-<n>/`; Godot vendors them in `addons/`). A review after a FAIL reads the same snapshot.
2. **Check:** a Verifier check (Subagents) in the brief worktree, with the prompt `prompt.sh brief-review` prints and the brief worktree's absolute path on its last line.
3. **Clean up** after the Lock, or a test-only issue's PASS: remove the link first (Next.js: `rm .claude/worktrees/brief-<n>/node_modules`, no trailing `/`; a `/node_modules/` ignore line doesn't cover a link, so git counts it untracked), then `git worktree remove .claude/worktrees/brief-<n>`.

Each FAIL line names what the brief must fix.

## Subagents

A driver can't start a subagent, so it hands each round and check to the main session ([`parallel.md`](parallel.md)):

1. Write the round's or the check's prompt file (Prompts above): its first line `factory-effort: <level>` (Effort), then the prompt, then a last line of its own, `factory-worktree: <absolute path>`: the issue's worktree, or the brief worktree for a brief review.
2. Do the round's run-state step first (`incr rounds-<phase>` or `incr uncounted`; when `incr rounds-<phase>` refuses at the ceiling, send no round: SKILL.md's Driver's calls), then report `needs editor-sonnet <prompt file> <effort>` or `needs verifier <prompt file> <effort>`. The main session runs it and resumes you with SendMessage, its final message under a line `factory-result: editor-sonnet` or `factory-result: verifier`; carry on from there.
3. **Editor rounds** go to `subagent_type: editor-sonnet`, the file's text as the prompt and the Agent tool's `effort` the one it names. Its SubagentStop hook (`claude-subagent-stop.sh`), which also runs at the PreToolUse of its SubagentHandback call (in auto mode the hand-back delivers the report, so that is where a block still reaches it), finds the worktree from the last line (the first `factory-worktree:` line naming a git worktree, past Claude Code's records of the agent file's sample line) and loops it on the phase's gate, the small lane's red-to-green handoff included (editor-gate.sh's exit 3), in the same subagent; a hook that finds the gate already running waits for it (`FACTORY_EDITOR_GATE_WAIT`, 900 s) and takes its result. Claude Code kills the hook at 3600 s, so the hook gives every wait (a gate in flight, a gate slot, the build lock) its first 1500 s and the gate 1800 s of work with those waits left out (lib/run.sh); a gate past that budget is stopped and the subagent stops with no stamp, as at the timeout, and a gate that failed only because a step's wait ran out is busy, not red: the hook blocks without asking for a fix, and `prompt.sh verifier` and `lock.sh record` say so instead of asking for a fix round. As that gate passes on a clean tree it records its stamp for HEAD in the run state (`editor-gate`), which `prompt.sh verifier` and `lock.sh record` check before they go on (driver.md). Once the gate is green it refuses a final message that doesn't quote the gate's result line (`verify: PASS at <short HEAD>`), so the Editor's final message carries it. In the green phase that gate is lighter (editor-gate.sh exports `FACTORY_GATE_LOOP=editor`: smoke in Chromium alone, mutate incremental, a gate stamp of its own), and once per subagent, after a green gate whose survivors file lists mutants, the hook blocks the stop with that list, uncounted: the Editor kills each with a test or says in its final message why it can't be killed. Its SubagentStart hook (`claude-subagent-start.sh`) snapshots what the factory protects, the git config and run state, and dev and main here and on the remote (lib/round.sh), and the stop hook blocks a round that changed any of them (`round-changed`). When `<git-dir>/factory/round-changed` exists after a round, the Editor stopped at the block limit with those changes still in place: read it first, undo each change (a moved dev or main on the remote is the human's), delete the file, and treat it as a counted trigger. Every round, the first and each later one (green, fix, clarification, rebase conflict, Takeover), is a fresh subagent with the same `prompt.sh` text, carrying on from the branch's commits; its agent file has it read the brief and the issue first.
4. **Verifier checks** go to a fresh `subagent_type: verifier`, the file's text as the prompt and the Agent tool's `effort` the one it names. Whoever runs it compares the workspace: in the worktree, `{ git rev-parse HEAD; git status --porcelain --untracked-files=all; git diff HEAD --binary | sha256sum; }` before the check and again after; any difference voids the verdict (Mechanics).
5. Run a brief review before the first round, not beside it.
