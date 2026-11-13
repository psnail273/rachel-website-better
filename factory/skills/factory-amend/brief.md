# The builder's brief

A builder knows only what its brief says, so fill in every field, and copy the human's rulings word for word. Its first line names the effort you dispatch it at (SKILL.md, Build), so the retro can see it; its second, `factory-amend: <slug>`, lets `claude-usage amends` total the amend's tokens, its reviewers' with them. Leave out a section in angle brackets that starts with "When" if its case doesn't apply. The review prompts are at the end of this file: paste both into the brief, with what the amend does and its accepted costs filled in; the builder fills in the commits.

````markdown
factory-effort: <medium, high or xhigh>
factory-amend: <slug>

You build one approved amend to the factory, in the project at <project root>.

## Goal

<The amend in a sentence or two, and the factory-improvement issues and proposals it answers.>

## Evidence

<What happened, issue by issue: the events, what they cost (rounds, questions, minutes, tokens), the comments that show them.>

## Decisions

- The human's ruling, word for word: <ruling>
- Mine: <names, formats, where things live; what the ruling left open and how I settled it>

## Worktree

Work only in <worktree> (branch amend/<slug>, base <base SHA>). It is a plain git worktree: use git and absolute paths, never EnterWorktree, ExitWorktree or a fork. Commit there. Keep your prompt files, commit messages and logs in <scratch>/amend-<slug>/: that folder is yours alone, while the scratch area around it is shared with the builders running beside you. Pushing, landing, dev and the full factory suite (`bash factory/core/test.sh` with no suite names) are mine: `amend.sh land` runs the suite once, at landing. <Other builders own these files right now; leave them alone: ...>

## Build

1. <Each change: the file, what it does, and what done looks like.>
2. A change to an adapter's templates (`factory/adapters/<adapter>/tools/verify/`) is ported to `tools/verify/` by hand, in the same commit: the gate runs the project's copy, and `amend.sh record` names each port due.
3. After your last edit to `factory/`: `bash factory/core/amend.sh record`. It refreshes the installed copies, the hook config and AGENTS.md's factory section, and re-records `tools/verify/factory-version`. Then `bash factory/core/amend.sh check` must print nothing, and `bash tools/verify.sh prepare` must pass.

## Tests

A test for each new behaviour, in the suite of the script it changes (`factory/core/tests/<name>_test.sh`, or the adapter's `tests/`), and a fixture for each input the evidence or a review reports. Run the suites you touched by name, <as AGENTS.md's notes on the factory's tests say>: `bash factory/core/test.sh <suite...>`, and `bash factory/core/shell-lint.sh <the scripts you changed>` when you changed a shell script; the `shell_lint` suite instead only when you changed `shell-lint.sh`, `factory/.shellcheckrc` or its shellcheck or shfmt pin (the land runs the whole suite). Write each run's output (a suite, shell-lint) to a log in <scratch>/amend-<slug>/, `> <log> 2>&1`, and read the log: grep it for `FAIL` and `test.sh:`, or Read it. Never pipe a run through `| tail` or `| head`: what they cut off costs a whole rerun to see. Report each suite's pass and fail counts, and shell-lint's output.

No test's outcome may hang on a fixed sleep or on elapsed time: write no raw `sleep`, `timeout` or `$SECONDS` in a `*_test.sh` file (test.sh's raw-waits step refuses them). Wait for a condition with `wait_until`, and make a stand-in that must keep running with `blocking_stand_in` (both in `factory/core/tests/lib.sh`); a limit or an age in the code under test is set through a setting or a stand-in clock.

<When the amend adds or changes a test that starts a real tool or a background process:> don't run `stress.sh`: I run it once for the batch, on the landing branch. Name each such test in your report.

<When the amend adds a check or makes one stricter:> run its step over the real tree before your change and after it, and report both outputs. If the code on dev fails it, add those findings in your commit with `bash factory/core/baseline.sh add <rule>`, and say so. Then, for each paused or in-flight issue branch (<branches>), make a detached scratch worktree of it, merge your branch in, run the step there, report what it flags, and remove the scratch worktree.

## Review

Once the suites pass, a fresh Opus reviewer reviews your commits, in at most three passes:

- Commit first: the reviewer reads commits. Write the prompt to a file in your scratch folder, `factory-amend: <slug>` on its first line and the worktree's absolute path on its last, `factory-worktree: <worktree>`. Give its text to a fresh `verifier` subagent (Agent tool, `subagent_type: verifier`), at effort <medium, or high for a big amend>; with no Agent tool, run `claude -p --model claude-opus-5-5 --effort <the same> --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)" < <file>` from the worktree, in the foreground. A reviewer that ends in an error (model unavailable, a usage limit, a crash) is an infrastructure failure: rerun it once. It changes nothing: when `git status --porcelain` or HEAD differs after it, its verdict is void: restore the worktree and rerun.
- Pass 1 reviews the whole diff with the first prompt below; passes 2 and 3 review only the rework since the previous pass's commit, with the second.
- A real finding: fix it, with its input as a fixture. A finding that is an accepted cost, or no bug: say why in your report. After each rework, a check's output over the real tree stays as it was, unless the fix meant to change it.
- Whatever is left after pass 3 goes in your report as "not blocking", each with your recommendation (yes or no) and its reason. I file what you recommend yes for the human; what you recommend no I note on the issue.

<The two prompts, filled in.>

## Commit

Squash your commits into one on <base SHA>:

    Amend the factory: <what it does, in a few words>

    Approved by the human <when, and on which issue>: <the evidence, in a few sentences>.

    - <one bullet per change: what it does, and the check or test that holds it>

    <When a not-blocking item is left that you recommend no: Noted, not proposed: <each, with its reason, in a line>.>

    Targets: <cause>: <what happened, in the retro's words>
    <When I decided the amend as tests-or-docs:> Amend-class: tests-or-docs
    Release: <minor|patch>

One `Targets:` trailer per cause the amend targets, `<cause>` from the retro's table (brief, weak test, workaround, engine, gate, infra, human). The trailers stay in the last paragraph, together with any trailer your session adds. `Amend-class: tests-or-docs` marks an amend I approved myself: `amend.sh land` refuses it if it touches a path outside the class (`tests_or_docs_paths` in `amend.sh`) or leaves a test file with fewer tests. `Release:` is `minor` when the amend adds or tightens a check, changes a step the human does, changes how issues are filed or needs a template ported by hand, else `patch`; `amend.sh release` bumps by it, and land refuses an amend commit without one.

## Rules

- You run unattended: settle every question yourself, from this brief and the code. If something is impossible as written, take the closest faithful option and report it.
- Stay off the web. Leave secret files unread (`.env*`, export credentials).
- Run commands in the foreground with long timeouts, or with run_in_background and its notification; never wait in a poll loop. Should a loop be unavoidable, wait on a PID (`while kill -0 "$pid"`) or a file, never on `pgrep -f` with a pattern your own command contains: it matches your own shell and never ends (the wait guard refuses it; bracket a character, `[f]oo`). Stop every background shell you started before you report.
- Set work aside in a commit on your branch, not in `git stash`: the stash is shared by every worktree.

## Report

Under 400 words: the branch, its commit and its base; `git diff --stat <base>`; each suite with its pass and fail counts; shell-lint's output; `amend.sh check`'s output; each review pass and its verdict; each departure from this brief, and why; anything not blocking, each with your recommendation and its reason; your wall-clock minutes.
````

## The review prompts

Pass 1:

```text
Review the amend on this worktree's branch: git diff <base SHA>...HEAD. <What it does and why, in a paragraph.>

Report only these, numbered:
- a bug: its file:line, an input that shows it (a command, a file's text, the tree's state), what happens and what should;
- a regression: a behaviour the diff changes without meaning to, with the input or test that shows it;
- a contradiction between a skill's or a doc's text and a script's behaviour, quoting both;
- the commit's `Release:` trailer contradicting the rule: a minor adds or tightens a check, changes a step the human does, changes how issues are filed or needs a template ported by hand; anything else is a patch.

Not findings: <each cost the human accepted or the build chose, with why>; style and wording; features the amend doesn't claim.

End with PASS, or FAIL and the findings.
```

Passes 2 and 3:

```text
Review only the rework since <the previous pass's commit>: git diff <that commit>..HEAD. It answers these findings: <them>.

Report only a regression this diff brings: a bug that wasn't there at <that commit>, with its file:line and an input that shows it. <For a lint or another heuristic check: for <check>, report only false positives, valid input it flags; input it misses is not a finding.>

Not findings: <the accepted costs, the earlier passes' included>.

End with PASS, or FAIL and the findings.
```

A heuristic check always has one more input it misses, so a review that hunts them never ends. The scope above is what lets three passes converge: what a pass misses goes to the next retro as evidence.
