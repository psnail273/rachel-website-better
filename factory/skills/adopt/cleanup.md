# Cleanup issues

How the adopt skill turns the Baseline into `Kind: cleanup` issues that `/build` works in Partial mode. Run it on the adoption commit, and again any time (say, after a cleanup issue was closed unfinished): it files only what no open cleanup issue covers.

## 1. Findings by step

`bash factory/core/verify.sh --keep-going > <tmp>/verify.txt`, from the project root. Each `== <step> FAIL` line heads that step's findings, `file:line rule message`. The Baseline entries (`tools/verify/ratchet/baseline.txt`) are the same findings without the line number. A finding with no Baseline entry means the tree moved since the Baseline: stop and tell the human.

## 2. Already covered

List the open issues whose body has `Kind: cleanup` (the tracker doc's list command, then read each body). An entry is covered when one of them quotes it, or when its rule and acceptance criteria clearly remove that finding (same rule, and the entry's file is in what it changes): drop it. When you can't tell, keep the entry and say in the new issue which open issue may overlap. Done when each remaining entry is one no open issue covers.

## 3. Group

One issue per step and rule (`format`, `lint` + `max-line-length`, `arch` + `R<n>`). Split a group into one issue per top-level folder when it holds more than about 30 entries or the fixes need different decisions; a group of one is fine. Order the issues so that a fix that may clear others comes first (format before lint; a layer rule before the per-file rules it causes).

## 4. The cleanup Spec

Use the open Spec titled `Adoption cleanup` if there is one. Otherwise create it: labelled `spec`, with a body that opens with a `## Synopsis` saying it holds the Baseline's cleanup issues, has no Playtest, and closes when the Baseline is empty. Give it one Feature, the milestone `#<spec> 1. Cleanup`, whose description says it has no Playtest: a Feature of cleanup issues only may skip it. The human adds `approved` before `/build <spec>` works it; ask them.

## 5. File

Each issue, in the order from step 3, labelled `ready-for-agent`, in the cleanup milestone:

````markdown
Part of #<spec>

Kind: cleanup
Touches: <the shared areas the findings sit in, as the spec skill's slicing.md names them; `none` when they sit in none>

## Synopsis

<Two or three plain sentences: which findings this removes and where, what the rule asks, and that done means the Baseline loses these entries.>

## What to build

Remove the <step> step's `<rule>` findings<in folder>: <what the rule asks, one sentence, with the ARCHITECTURE.md rule or the tool's rule name>.

## Acceptance criteria

- [ ] None of these Baseline entries is found any more, and no new finding appears:

```
<file> <rule> <message>
...
```

## Rules it touches

<R<n> for an arch finding, else "None">
````

Quote each entry exactly as `baseline.txt` holds it: the run's Build Brief copies them into `removes` lines. Then add `- [ ] #<n> <title>` lines to the cleanup Spec's task list. Done when every Baseline entry is quoted in exactly one open cleanup issue (count them against `baseline.txt`).
