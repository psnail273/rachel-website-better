---
name: audit
description: Audit the whole project against its gates: run every step, report the findings beyond the Baseline by step and rule, and on the human's yes file them as cleanup issues.
disable-model-invocation: true
---

# audit

You run every gate step over the whole project and tell the human what it finds that the Baseline doesn't hold: code that slipped past a gate, or a check a factory update brought in that the code fails. Terms are in `factory/CONTEXT.md`. You change no code. Growing the Baseline and filing issues are the human's calls.

## 1. Ready

- `tools/verify/factory-version` is committed: the project is adopted. Not adopted: stop and point the human at `/adopt`.
- `git status` is clean, and you are on the base branch (`dev`) at its tip, pulled: the audit is of what the project holds, not of work in flight. Not so: stop and say what is in the way.
- `tools/verify/local.env` names this machine's tools (prepare reports one it can't find): fill it from `local.env.example` first.

Done when the tree is clean at the base branch's tip.

## 2. Run every step

From the project root, into a temp folder outside the repo:

```
FACTORY_BASE=HEAD bash factory/core/verify.sh --keep-going --reuse > <tmp>/verify.txt 2> <tmp>/verify.err
FACTORY_BASE=HEAD bash factory/core/baseline.sh --reuse gate > <tmp>/gate.txt 2> <tmp>/gate.err
```

`--keep-going` runs every step past a failing one; the gate reuses that run's verdict (its stamp) and prints, under `new:`, each failing step's finding the Baseline (`tools/verify/ratchet/baseline.txt`) doesn't hold, then `baseline: PASS` or `baseline: FAILED`. A prepare that fails stops every step: fix what it says (a tool, `local.env`) and run again.

Done when `gate.txt` ends with a `baseline:` line.

## 3. Report

Tell the human, from `verify.txt` (each `== <step> PASS|FAIL|SKIP` line heads that step's findings, `file:line rule message`) and `gate.txt`:

- **Beyond the Baseline**: the `new:` findings grouped by step, then by rule (the finding's second word), with a count and up to three examples each. Say which rules are new to this factory version (`factory/VERSION`, the release notes or the adapter's docs) and which are code that slipped past.
- **The Baseline's size**: its entry count, and the count by rule.
- **Skipped**: each `SKIP` step with the reason `verify.err` gives (the mutate step runs only in an issue's Green phase, so it is skipped here), and each `step-failed` finding (a step that failed without naming one).
- `baseline: PASS` with nothing skipped but mutate: say the project is clean against its Baseline, and stop.

Then ask the human which rules to file. Lead with your recommendation: a rule whose fixes are few and mechanical may be fixed in one cleanup issue; a rule they want gone, rather than cleaned up, is an amend to `ARCHITECTURE.md` or the gate's config, not an issue.

## 4. File, on the human's yes

1. `bash factory/core/baseline.sh add <rule>...` with every rule they said yes to. It adds those rules' findings to the Baseline and stages it, and refuses, adding nothing, while any finding beyond the Baseline is from a rule it wasn't given: name the rest to the human (fixed first, or added too).
2. Commit the Baseline alone on the base branch, `Baseline: add <rules> found by /audit`, on the human's go-ahead, and push it the way the project lands a change.
3. File the new entries with [`../adopt/cleanup.md`](../adopt/cleanup.md): it files only what no open cleanup issue covers.

Done when every Baseline entry is quoted in exactly one open cleanup issue.

## Report

Tell the human: the factory version, the steps run and skipped, the findings beyond the Baseline by step and rule, the Baseline's size before and after, the issues filed, and what is left (a rule they chose to amend instead, findings left unfiled).
