# Design direction

How factory-spec settles a look before slicing: the `designer` subagent builds two or three clearly different **Design directions** as live prototypes inside the real app, the human picks one or mixes them by looking at them, and the winner becomes `docs/design.md` and the **Board**, the screenshots slices are written to match. The human approves what they see far more reliably than adjectives.

## When

Run it when step 2 leaves a look-and-feel decision as a Human's call: a redesign, a new visual identity, a page or component whose look nothing settles yet. Skip it otherwise, as when the Spec adds behaviour inside a look `docs/design.md` and the Board already cover, or the human says the current design stands; say which under Decided for you.

It is written for a web app (the Next.js adapter). For another stack, follow the same steps with that stack's dev build in place of `next dev`, and its own screenshots.

## 1. The throwaway branch

From the main checkout, make the branch `design/directions` in a worktree of its own, off dev, and ready it the way `start.sh` readies an issue's (the machine's tool locations, then the bootstrap, which installs the dependencies and Playwright's Chromium):

```bash
git fetch origin dev
git worktree add -b design/directions .claude/worktrees/design-directions origin/dev
cp tools/verify/local.env .claude/worktrees/design-directions/tools/verify/local.env
(cd .claude/worktrees/design-directions && set -a && . tools/verify/local.env && set +a && bash tools/verify/bootstrap)
```

A `design/directions` already there is an earlier step's that never finished: resume from it, or remove it (step 7) and start over; ask the human which. The branch is never pushed and never merged: nothing from it lands but what step 6 copies.

## 2. Serve it on localhost:3000

Start the dev server in the worktree, in the background (the Bash tool's `run_in_background`), on port 3000 and bound to this machine alone: `next dev`'s default host is `0.0.0.0`, every network interface, so pass `-H localhost` explicitly. Load the tool locations first, and put a Node or pnpm that `local.env` names by path first on PATH, as the adapter's steps do:

```bash
cd .claude/worktrees/design-directions && set -a && . tools/verify/local.env && set +a &&
  for b in "${PNPM_BIN:-}" "${NODE_BIN:-}"; do case "$b" in */*) PATH="$(dirname "$b"):$PATH" ;; esac; done &&
  pnpm exec next dev -H localhost -p 3000
```

Check the port first: `ss -Hltn 'sport = :3000'` prints nothing (or `lsof -i :3000` prints nothing). If port 3000 is taken (there, or `EADDRINUSE` in the server's output), ask the human what to do: stop what holds it, or serve on a port they name. Never pick another port yourself; on one they name, use it wherever this page says 3000. The server is ready when `curl -fsS -o /dev/null http://localhost:3000/` succeeds: retry that until it does, never a fixed sleep. It reloads as the designer edits, so start it first and keep it running until step 7.

The human reaches it from their laptop or phone through an SSH tunnel to this machine, `ssh -L 3000:localhost:3000 <host>` (on a phone, an SSH app that forwards ports), and opens `http://localhost:3000/` there. Only if the human opts into their LAN for this session, in so many words, restart it with `-H <the LAN address>` (Next.js accepts requests from the hostname it was started with) and give them that address instead.

## 3. The directions

Dispatch the `designer` subagent (the Agent tool, `subagent_type: designer`, effort `medium`; never another model or `max`). It runs on Fable, `claude-fable-5-2`, which the human approved for this step alone (`factory/CONTEXT.md`, Models and effort), and it preloads `frontend-design`. Its prompt, as `factory/agents/designer.md` reads it:

```
factory-effort: medium
factory-design: build
factory-dev-server: http://localhost:3000/
<the overview or the Spec's draft, the look-and-feel Human's calls and their answers so far, and the inner page: the one most slices change, or the human's pick>
factory-worktree: <the worktree's absolute path>
```

It plans each direction as `frontend-design`'s two passes say (a palette of 4–6 named colours, type, layout, principles), reviews each plan against that skill's list of generic AI-design tells, and builds two or three of them (each with its own tokens, type, and layout for Home, the inner page, the header and the footer, on the layout contract's attributes), at least one breaking from the current `docs/design.md`, behind a floating switcher that exists only in development and keeps its choice in a cookie. Before it reports, it runs the standalone axe and layout checks on every route of every direction and fixes what they find (designer.md's Checks). Its report lists every screenshot (each direction, route, width and scheme), the checks' reported lines and axe's undecided results, and any finding it left because fixing it would break its direction's idea. A subagent that ends in an error is an infrastructure failure: dispatch it once more; a second goes to the human.

## 4. The critique

The designer reviews its own directions against frontend-design's tells, and misses what a fresh eye catches. So before a `build` or `iterate` round reaches the human, a fresh `verifier` subagent (the Agent tool, `subagent_type: verifier`, effort `medium`) critiques its screenshots, without the designer's reasoning. Record the worktree before and after it, `{ git rev-parse HEAD; git status --porcelain --untracked-files=all; git diff HEAD --binary | sha256sum; }`: any difference voids its verdict; dispatch it again. Its prompt:

```
factory-effort: medium
Critique a round of design directions before the human sees it. You see only what the round produced, not the designer's reasoning: judge it as a fresh eye.

The screenshots (every direction, route, width and scheme): <the absolute paths the designer's report lists, each with its direction's key and name>
What the checks reported, which gates nothing: <the designer's report's reported: lines and axe's undecided results, as it gave them>
The brief's own words on the look: <the look-and-feel Human's calls and their answers, or "none">

The tells are factory/third-party/frontend-design/SKILL.md's: the numbered traits AI-generated design clusters around (its Process section), the typographic tells (one word or phrase accented in a headline, all-caps labels, needless labels above content), structure as decoration (numbered markers on content that isn't a sequence), and, as far as a screenshot shows it, the motion it warns against.

Read every screenshot. Report, numbered, one line each, every tell you see: the direction's key, the screenshot's file name, the tell (its number or words in that list), and what in the picture shows it. Report too a reported line or an undecided axe result that its screenshot shows to be a real fault (a one-word line that reads badly, text you can't read over an image), naming the screenshot.

Not findings: a trait the brief's own words ask for; taste beyond the list; what a screenshot can't show (hover, focus, motion between states); a direction's choice that is clearly made for this site's subject rather than a default.

End with PASS, or FAIL and the findings.
factory-worktree: <the design-directions worktree's absolute path>
```

On FAIL, send its findings, word for word, to the same designer as a `critique` round (SendMessage); it fixes them, runs the checks again, retakes the screenshots and reports as the round it answers did, and the critique runs again on that report. At most two `critique` rounds for each round the human will see: when the critique after the second still fails, its findings go to the human with the round (step 5), beside the screenshots they name. A finding the designer keeps because fixing it would break its direction's idea, which its report names with why, goes to the human the same way. A verifier that ends in an error is an infrastructure failure: dispatch it once more; a second goes to the human, who then sees the round with no critique, and is told so.

The `board` round gets no critique: it runs the checks on the winner, but only writes `docs/design.md` and the Board of a look the human already approved.

## 5. The human picks

Give the human the two URLs (Home and the inner page, on `http://localhost:3000/`, through the tunnel of step 2) and the designer's report: each direction's name, idea, palette, type and layout; and what step 4 left: the critique's last findings and the findings the designer kept, each beside the screenshot it names. Ask them to open both on their laptop and their phone, flip between the directions with the switcher, and pick one, or mix parts ("A's hero with B's type"), with any mark-up. Log their answer, in their words, under Human's calls.

Then send the designer the pick and the mark-up as an `iterate` round (SendMessage to the same designer; a fresh one gets the earlier reports too), run step 4's critique on its report, show the human the result, and repeat until the human approves the winner in so many words.

## 6. The winner becomes the reference

Send the designer a `board` round. It runs the checks on the winner and fixes what they find, as in every round, then writes the new `docs/design.md` in the worktree, and the Board in `docs/design/board/`: Home and the inner page at 390 and 1280 px, light and dark, `<route-slug>-<width>-<scheme>.png` (`home-390-light.png`, ...). It takes them with Playwright, from the project's `@playwright/test`, in the Chromium the bootstrap installed, with a small script its definition gives.

Read each image, and check there are eight, named so. Then, in the main checkout, on dev with a clean tree, copy them over the old ones and commit:

```bash
cp .claude/worktrees/design-directions/docs/design.md docs/design.md
rm -rf docs/design/board && mkdir -p docs/design/board
cp .claude/worktrees/design-directions/docs/design/board/*.png docs/design/board/
git add docs/design.md docs/design/board && git commit -m "Design direction: <the winner's name>"
```

Push dev before SKILL.md's Approve and publish step publishes the slices, so every issue's worktree, cut from `origin/dev`, has the Board.

## 7. Throw the branch away

Stop the dev server, then remove the worktree and the branch:

```bash
git worktree remove --force .claude/worktrees/design-directions
git branch -D design/directions
```

## Slicing against the Board

The Spec's Solution links `docs/design.md` and the Board. A slice that changes the look names, in What to build, the `docs/design.md` sections and the Board images it builds toward; its criteria stay ones a test can check (a token's value, a layout at a width), never "looks like the picture". The Feature's Playtest human checks compare the built pages with the Board.
