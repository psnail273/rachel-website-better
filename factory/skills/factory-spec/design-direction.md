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

A `design/directions` already there is an earlier step's that never finished: resume from it, or remove it (step 6) and start over; ask the human which. The branch is never pushed and never merged: nothing from it lands but what step 5 copies.

## 2. Serve it on the LAN

Start the dev server in the worktree, in the background (the Bash tool's `run_in_background`), on the machine's LAN address so the human's phone can open it too; Next.js accepts requests from the hostname it was started with. Load the tool locations first, and put a Node or pnpm that `local.env` names by path first on PATH, as the adapter's steps do:

```bash
cd .claude/worktrees/design-directions && set -a && . tools/verify/local.env && set +a &&
  for b in "${PNPM_BIN:-}" "${NODE_BIN:-}"; do case "$b" in */*) PATH="$(dirname "$b"):$PATH" ;; esac; done &&
  pnpm exec next dev -H "$(hostname -I | cut -d' ' -f1)" -p 3100
```

It reloads as the designer edits, so start it first and keep it running until step 6.

## 3. The directions

Dispatch the `designer` subagent (the Agent tool, `subagent_type: designer`, effort `medium`; never another model or `max`). It runs on Fable, `claude-fable-5-2`, which the human approved for this step alone (`factory/CONTEXT.md`, Models and effort), and it preloads `frontend-design`. Its prompt, as `factory/agents/designer.md` reads it:

```
factory-effort: medium
factory-design: build
factory-dev-server: http://<address>:3100/
<the overview or the Spec's draft, the look-and-feel Human's calls and their answers so far, and the inner page: the one most slices change, or the human's pick>
factory-worktree: <the worktree's absolute path>
```

It plans each direction as `frontend-design`'s two passes say (a palette of 4–6 named colours, type, layout, principles), reviews each plan against that skill's list of generic AI-design tells, and builds two or three of them (each with its own tokens, type, and layout for Home, the inner page, the header and the footer), at least one breaking from the current `docs/design.md`, behind a floating switcher that exists only in development and keeps its choice in a cookie. A subagent that ends in an error is an infrastructure failure: dispatch it once more; a second goes to the human.

## 4. The human picks

Give the human the two URLs (Home and the inner page) and the designer's report: each direction's name, idea, palette, type and layout. Ask them to open both on their laptop and their phone, flip between the directions with the switcher, and pick one, or mix parts ("A's hero with B's type"), with any mark-up. Log their answer, in their words, under Human's calls.

Then send the designer the pick and the mark-up as an `iterate` round (SendMessage to the same designer; a fresh one gets the earlier reports too), show the human the result, and repeat until the human approves the winner in so many words.

## 5. The winner becomes the reference

Send the designer a `board` round. It writes the new `docs/design.md` in the worktree, and the Board in `docs/design/board/`: Home and the inner page at 390 and 1280 px, light and dark, `<route-slug>-<width>-<scheme>.png` (`home-390-light.png`, ...). It takes them with Playwright, from the project's `@playwright/test`, in the Chromium the bootstrap installed, with a small script its definition gives.

Read each image, and check there are eight, named so. Then, in the main checkout, on dev with a clean tree, copy them over the old ones and commit:

```bash
cp .claude/worktrees/design-directions/docs/design.md docs/design.md
rm -rf docs/design/board && mkdir -p docs/design/board
cp .claude/worktrees/design-directions/docs/design/board/*.png docs/design/board/
git add docs/design.md docs/design/board && git commit -m "Design direction: <the winner's name>"
```

Push dev before SKILL.md's Approve and publish step publishes the slices, so every issue's worktree, cut from `origin/dev`, has the Board.

## 6. Throw the branch away

Stop the dev server, then remove the worktree and the branch:

```bash
git worktree remove --force .claude/worktrees/design-directions
git branch -D design/directions
```

## Slicing against the Board

The Spec's Solution links `docs/design.md` and the Board. A slice that changes the look names, in What to build, the `docs/design.md` sections and the Board images it builds toward; its criteria stay ones a test can check (a token's value, a layout at a width), never "looks like the picture". The Feature's Playtest human checks compare the built pages with the Board.
