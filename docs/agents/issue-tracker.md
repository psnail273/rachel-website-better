# Issue tracker

Issues live on the Gitea repo `psnail273/rachel-website-better` at `https://git.stuffworks.net`, driven by the `gt` CLI (logged in with `gt auth status`). Run every command from the repo root: `gt` finds the repo from the `origin` remote (add `-R psnail273/rachel-website-better` from elsewhere). Write bodies to a temp file and pass `-F <file>`, or `-F -` for stdin.

## Issues

| Operation | Command |
|---|---|
| Create, labels at creation | `gt issue create -t "<title>" -F <body.md> -l ready-for-agent -l <label>` (prints the new issue's URL; its number ends it) |
| Read one, with comments | `gt issue view <n> --comments` |
| List by label and state | `gt issue list -l <label>[,<label>] -s open\|closed\|all -L 200` (all labels must match; `--json number,title,labels,state` for machine use) |
| Comment | `gt issue comment <n> -F <comment.md>` |
| Add / remove labels | `gt issue edit <n> --add-label <label> --remove-label <label>` |
| Assign | `gt issue edit <n> --add-assignee @me` (or a login) |
| Close, with a comment | `gt issue close <n> -c "<comment>"` (posts the comment, then closes) |
| Reopen | `gt issue reopen <n>` |
| Read the raw body | `gt issue view <n> --json body --jq .body > <body.md>` |
| Rewrite the body | `gt issue edit <n> -F <body.md>` (how a Spec's `- [ ] #<n>` line gets ticked: read, edit to `- [x] #<n>`, rewrite) |
| Create a label | `gt label create <name> --color <rrggbb> --description "<text>"` (no `#`; refused when it exists) |
| List labels | `gt label list --json name --jq '.[].name'` |

A list filtered by a label the repo doesn't have fails with `label "<name>" does not exist`, exit 1: treat that as an empty list.

## Milestones

| Operation | Command |
|---|---|
| Create, with a description | `gt milestone create -t "<title>" -d "<description>"` |
| Put an issue in one | `gt issue edit <n> -m "<title>"` (or `-m "<title>"` on `gt issue create`) |
| List its issues | `gt issue list -m "<title>" -s all` |
| Close one | `gt milestone close "<title>" --by-name` |

## Dependencies and parents

- **Blocked by:** `gt issue edit <n> --add-blocked-by <m>`; read with `gt issue view <n> --json blocked_by,blocks`; lift with `--remove-blocked-by <m>`. Gitea has native dependencies, so the fallback (a `Blocked by: #<m>` line at the top of the body) is needed only when the call is refused (dependencies switched off for the repo).
- **Parents of `#<n>`:** an issue's first line `Part of #<p>` names its parent. Also search for task lists naming it: `gt issue list -s all -S "#<n>" --json number,title,body --jq '.[] | select(.body | test("- \\[[ x]\\] #<n>\\b")) | .number'`.

## How an issue reads

Every issue an agent files opens with its template's header lines (`Part of #<spec>`, `Kind: …`, and `Lane:` / `Tests only:` where they apply), then `## Synopsis`: two to four plain sentences saying what changes or is wrong, why it matters, and what done looks like.

An issue that waits on the human (`ready-for-human`, or `needs-triage` for their triage) ends its synopsis with a bold line (**Needs two decisions from you.**), then has `## What you need to do`: one numbered item per decision (a bold question, its options, a recommendation with its reason) or action (its steps), then how to reply and what happens next. The details come last.

An escalation comment opens with its own `## What you need to do`. On the human's answer: comment it in their words, remove the label, and rewrite the bold line and that heading as the answer (e.g. **Decided: …** / `## What was decided`).

## Factory backlog

The parent is one issue titled `Factory backlog`, labelled `factory-backlog`. Its body is only:

```markdown
## Synopsis

Factory improvements found during Runs, each waiting on the human. This issue closes when the list is empty.

## Open

- [ ] #<n> <title>
```

- **Find it** (open or closed): `gt issue list -l factory-backlog -s all --json number,state`. Before the label exists this fails with `label "factory-backlog" does not exist`: there is no backlog yet.
- **Create it:** `bash <label script> factory-backlog 5319e7 "The Factory backlog parent"` (or `gt label create factory-backlog --color 5319e7 --description "The Factory backlog parent"`), the same for `factory-improvement` (`bfdadc`, "A factory improvement for the human"), then `gt issue create -t "Factory backlog" -F <body.md> -l factory-backlog`.
- **File a child:** `gt issue create -t "<title>" -F <body.md> -l factory-improvement -l ready-for-human`, its body's first line `Part of #<backlog>`; then read the backlog body, append `- [ ] #<child> <title>` under `## Open`, rewrite it; and `gt issue reopen <backlog>` if it was closed.
- **A child closed:** read the backlog body, delete that child's line (never tick it), rewrite it.
- **Empty list:** `gt issue close <backlog> -c "Backlog empty: every factory improvement is closed."`.

## Wayfinding

- A map is one issue labelled `wayfinder:map`.
- Its tickets carry `Part of #<map>` as their first line and one label of `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task`.
- **Claim:** `gt issue edit <n> --add-assignee @me`.
- **Resolve:** `gt issue comment <n> -F <result.md>`, `gt issue close <n>`, then `gt issue comment <map> -b "#<n> resolved: <one line>"`.
