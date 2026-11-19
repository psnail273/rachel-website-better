# The retro

After a Feature's Drift sweep, before its Playtest, the Run looks back at what slowed the Feature down: each counted round, uncounted round, escalation and driver's note cost minutes and tokens, and most have a cause the factory can remove. You sort them by cause, price them and propose fixes; the human decides which ones land.

## The numbers

1. **Gather** every comment of the Feature's closed issues (its milestone), with the tracker doc's commands (AGENTS.md points to it), into one scratch file: each comment's whole body, each issue's comments oldest first. Add a line for each parked issue in the Feature: `bash factory/core/state.sh --issue <n> stats`, from its run state, after that issue's comments.
2. **Total:** `bash factory/core/retro.sh < <file>`. It totals the `factory-stats:` line that ends each close comment (land.sh prints it from the run state) and lists each issue's counts that aren't 0, then its minutes from start.sh to the landing, split by phase (`minutes-brief` runs to the first one). An issue's last line counts. An issue with no line, one closed without landing or landed before the line existed, isn't in the totals: read its close comment. One started before start.sh kept the time has no minutes. Its `gate counts: <n> of <m> issues` line says how many recorded the gate's own counts, which verify.sh keeps on the issue branch: `caught-<step>`, a red run that step stopped, and `seconds-<step>`, its run time.
3. **Tokens:** `claude-usage issues --since <t>` and `claude-usage sessions --since <t>`, `<t>` being the UTC time of the Feature's first claim (`2026-11-03T18:30`); `--help` explains the fields. An issue's line totals its drivers' transcripts; an issue the main session drove has none, its tokens being in the session's. The sessions' lines are the Run's own cost.
4. **Notes:** the `factory-note:` lines in the close comments. Each is an event, like a count.

## The Driver's calls

Every call the drivers made instead of escalating (SKILL.md's Driver's calls), so the human can overrule a pattern. Take them from the gathered comments: each line `Driver's call: <kind>: <what>. <reason>` under a **Decided for you** heading (an Editor question's decision there is not one). Their number must match retro.sh's `self-ruled` total; name any difference and the issue it is on. A table, a row per call in issue order:

| Issue | Call | What | Reason |
|---|---|---|---|

Then one line per kind that repeats (the same kind and the same kind of finding on two issues or more), such as "3 extra rounds for tests that missed a brief line", which the human may want made a Human's call again, or a fix that makes the call unneeded.

## The checks

Each check costs time on every issue; the table shows what each caught and cost, so the human can prune one. A row per gate step, in the gate's order (`prepare format typecheck lint arch deviation test mutate smoke`), from retro.sh's `caught-<step>` and `seconds-<step>`, and a row per Verifier check, from `fails-red`, `fails-green`, `fails-partial` and `fails-brief` (the brief review):

| Check | Caught here | Caught, all retros | Seconds here | Recorded |
|---|---|---|---|---|

- **Caught, all retros** adds this Feature's to the same line in every earlier Feature retro's retro.sh block (the `Retro:` comments; a `Retro: Spec #` one repeats them, so skip it).
- **Recorded:** for a gate step, `gate counts`' `<n> of <m>`; a step missing from the totals caught nothing in those `n` issues, and with `n` at 0 every cell is "not recorded", never 0. A Verifier row's is every issue with a stats line, and its seconds are "—" (its cost is in the cost table).

**Caught nothing:** each check with no catch in this Feature and the two Feature retros before it that recorded it (until three have, say so and list none), with its seconds over them. For each, one line on what would be lost without it, since a check can prevent what it never catches (the Editor formats because the format step would refuse it), and a recommendation: keep, loosen (run it at Land only, or only on the files it guards) or remove. A loosen or a remove is a proposal like any fix below: nothing is pruned without the human's yes.

## The causes

For every count in the per-issue rows but the gate's own (the checks table holds them) and every note, read that issue's comments (the Verifier's verdicts, your rulings, the close comment) and `docs/deviations.md`, and give the event one cause from the table, named `<cause>: <what>`, short and stable (`brief: no seam line`) so later retros and amends can match it; reuse an earlier retro's name when it fits.

| Cause | What happened |
|---|---|
| brief | The brief was short or wrong: a missing `seam` or `scope` line, a wrong locked test, a wrong fact. |
| weak test | The Verifier failed a test that passes on wrong code. |
| workaround | The Editor got past a gate instead of meeting it. |
| engine | An engine or tool fact nobody knew. |
| gate | A check misfired, or one was missing and you caught the problem by hand. |
| infra | A tool, tab or service failed. |
| human | A Human's call the Spec missed. |

A cause name seen twice or more, in this Feature or in an earlier retro, is **repeated**.

**Amends since the last retro** (the last `Retro:` comment's date; with none, all): an amend's commit names the cause it fixes on a `Targets: <cause name>` line, so `git log dev --since=<date> --grep='^Targets: ' --format='commit %h %s%n%b' | grep -E '^(commit |Targets: )'` lists them. Mark each "held" when no event of this Feature has its cause name, else "recurred: #n, #m".

## The fixes

Propose one fix for each repeated cause, the most deterministic that would have stopped it, in this order: a check (a lint, an arch rule, a `brief.sh check`), a hook, a template line in `build-brief.md`, an Editor skill's fact, a prompt line. A check catches the problem every time; a prompt line only asks the model. A recurred cause moves up the ladder from its amend's fix: a prompt line becomes a template line, a template line a check.

Each proposal says what it saves (the counted rounds, the human's questions, the minutes and the tokens its events cost) and what it adds (seconds or tokens per issue, the risk of a false positive).

## File it

- **Always:** a comment on the Spec headed `Retro: <Feature title>`, holding:
  - retro.sh's output, in a code block;
  - a cost table: a row per issue with its minutes and its cost (in millions), a row for the sessions, a row for the Scenario run when the Feature had one (its agent's minutes and tokens), and the Feature's totals; the three costliest issues name the causes they paid for;
  - the checks table, and the checks that caught nothing under a heading `Caught nothing`;
  - the amends' marks;
  - the Driver's calls, under a heading `Driver's calls`: the table and its repeats, or "None.";
  - one line per event: issue, count or note, cause name, one line of what happened.
- **When a cause repeats, an amend recurred or a check caught nothing, and you recommend yes on at least one proposal:** one child issue of the **Factory backlog**, titled `Retro: <Feature title> (Spec #<spec>)`, labelled `factory-improvement` and `ready-for-human`, in no milestone and outside the Slices (create the label if the tracker lacks it). Its body takes the shape `docs/agents/issue-tracker.md`'s "How an issue reads" gives, with `Part of #<backlog>` as its first header line. It opens with its `## Synopsis` (what slowed the Feature, what the fixes would save, and in bold how many decisions it needs) and `## What you need to do`, a line per proposal: `- [ ] <n>. <cause name>: <fix, in plain words>. Recommend yes|no: <why>`, then how to reply and that `/factory-amend` builds what is approved. The numbers, the cost table, the amends' marks and the Driver's calls follow, then for each repeated cause: its name, the issues it hit, what happened, and the proposal with the file or check it changes. Each check to loosen or remove gets its line too (`<n>. check <step>: loosen to Land only. Recommend yes: <why>`), and its catches, seconds and what would be lost under `Caught nothing`. Causes seen once go under a heading `Seen once`. Then add the child's line to the backlog's `## Open` list, creating the backlog or reopening it as needed, with the commands under that doc's `## Factory backlog`.
- **When you recommend no on every proposal:** file no child, since nothing waits on the human. The proposals go in the Spec's retro comment instead, under a heading `Noted, not proposed`, each with its reason.
- Name it under **Retro** on the Playtest issue, or "Nothing repeated.", or "Nothing to decide: the proposals are noted in the retro comment."

Each fix changes `factory/`, a gate or a skill, so it is an amend: nothing changes until the human approves it, and the Run goes on meanwhile. Its commit carries `Targets: <cause name>`.

## At the Spec's end

After the last Feature's retro, run one more over every Feature's issues, `--since` the Spec's first claim: a cause each Feature saw once may repeat across the Spec. File it the same way, titled `Retro: Spec #<spec>`, naming the Feature retros it adds to.
