# The Scenarios

A **Scenario** plays one of a Feature's behaviours through the real game and checks what must hold. factory-spec writes each in words, in the milestone's checklist under Run checks: "do this, then this must hold". At the Feature's end a `verifier` subagent scripts them; from then on they run before every Playtest, each earlier Feature's too. The Editor never sees them, so its own tests can't be shaped to them: a Scenario that fails is a bug the Editor fixes from the Spec's words alone (breakout #176 reached the human instead).

## Where they live

In the Scenario folder that the adapter's `tools/verify/scenario-folder` names (Godot: `scenarios/`, holding a `.gdignore`; Next.js: `scenarios/`, Playwright scripts), committed on dev. The adapter's driver, `tools/verify/scenarios`, runs them; its header says how a script drives the game or app. They are kept from the Editor two ways: its hook refuses to read or write the folder, and an issue's worktree leaves it out of its checkout (`start.sh`), so a Verifier check there doesn't meet it either, and the `verifier` agent's rules have it leave the folder unread unless its prompt is a Scenario's. In Next.js, what the app reads from outside and keeps on disk during the run comes from `tools/verify/scenario-env`, the app's env for the run (a feed pointed at the driver's fixture server, a cache at a folder emptied before each Scenario file), so a Scenario sets the state it needs, as the driver's header says, and never meets the live service or an earlier Scenario's feed or cache file. One server serves the whole run, so what the app rendered and kept for an earlier Scenario stays until a Scenario has the app read again (Next.js: a revalidation route the app enables in that env, as the header says); a Scenario that needs a state the driver can't give is escalated as an amend. No gate step runs them.

**Looks** (Next.js): before the Scenarios the driver holds each page route of ARCHITECTURE.md's Routes table, at 390 and 1280 px, light and dark, to a screenshot baseline in `<folder>/looks/` (Playwright's `toHaveScreenshot`, at most 0.2% of its pixels differing; the driver's header says the rest), one results line each, named `looks/<route-slug>-<width>-<scheme>`. The page's fixture feed is empty then, so no date changes it. A run never records a baseline: only the Driver does, with `bash tools/verify/scenarios record`, once the human passes a Playtest ([`playtest.md`](playtest.md)), so a look can't drift from what the human approved. Being in the Scenario folder, the baselines are kept from the Editor as the scripts are.

A project with no driver or no folder file reports them "not run": one adopted before the Scenarios gets them once it ports the adapter's driver and folder file, which `sync.sh` prints with the rest of the template's changes to `tools/verify/`.

## Script them

Once per Feature, when its milestone lists Scenarios and the folder has no script for them. A rerun of the End of run goes straight to Run them.

1. **Worktree:** from the main checkout, `git worktree add --detach .claude/worktrees/scenarios-<spec> dev`, and copy `tools/verify/local.env` into it. While it exists a Scenario run is under way: on resume, rerun it.
2. **Prompt**, in `<scratch>/scenarios-<spec>-<k>.md`: `Script the Scenarios of Spec #<spec>, Feature <Feature title>, in <folder>/ of this worktree.`, then the milestone's Scenarios as written and the Spec's behaviours for the Feature, then these rules: one script per Scenario, under `<folder>/<feature>/`, named after it; it plays the Scenario through as a player would and checks only what the Scenario says must hold, by the names the code already has (read the code and the driver's header), and sets what the app reads from outside as the header says. Change nothing outside the folder. Run `bash factory/core/scenarios.sh` and report each line. A Scenario the game fails stays as its words say: report it, and change no game file. Stay off the web.
3. **Agent:** a fresh `verifier` subagent (`subagent_type: verifier`), which writes the scripts with its shell, its prompt the file's text with a first line `factory-effort: <level>` (medium; high for a Feature with many Scenarios) and a last line `factory-worktree: <absolute path>`, at that effort. Compare the workspace before and after as [`editor.md`](editor.md)'s Subagents says, with `-- . ':!<folder>'` after its status and diff commands, and `git status --porcelain -- <folder>/looks` empty after: a change outside the folder, or to a baseline, voids the run: remove the worktree and start again.
4. **Review:** read each script beside its Scenario's words. It must do what they do and check what they say must hold, nothing more. Send back what misses, once, to a fresh agent with the scripts so far; a second miss escalates.
5. **Commit:** in the worktree, `git add <folder> && git commit -m "Scenarios: #<spec> <n>. <Feature title>"`, then `git push origin HEAD:dev` (a fast-forward; on a refusal, `git pull --rebase origin dev` and push again). Pull in the main checkout (`git pull --ff-only`) and `git worktree remove .claude/worktrees/scenarios-<spec>`.

## Run them

From the main checkout on dev, pulled: `bash factory/core/scenarios.sh`. It prints one line per Scenario, `<name>\t<PASS|FAILURE|ERROR|SKIP>\t<file:line>`, then a last line: PASS (exit 0), FAIL (exit 1), or not run and why (exit 3). Not run is the check's result: report it with the reason.

A `looks/` line that isn't PASS is no bug: SKIP has no baseline yet, the page as it is now in `<git-dir>/factory/looks/<name>-actual.png`; FAILURE is a page that changed from the look the human last approved, its expected, actual and diff images there (the driver's stderr names them). List it under Run checks, and add a human check to the Playtest issue to judge that look from those images; the Playtest's pass records it. ERROR (the page didn't load) is a bug, as below.

For each other line that isn't PASS, check it against the Spec first, reading the script and the Spec's words for that behaviour:

- **The script is wrong** (it checks what the Spec doesn't say, or plays it another way): script that Scenario again (Script them) and run them again.
- **The game contradicts the Spec:** file a `Kind: bug` slice in this milestone, in the shape [`slicing.md`](../factory-spec/slicing.md) gives, labelled `ready-for-agent` and listed under its Feature in the Spec's Slices. Quote the Spec's behaviour, say what the game did instead in a player's words, and add "Found by the Scenarios". Never quote the script, name its path or describe its code: the Editor reads the issue. Then go back to picking issues; the next End of run runs them again. Never hand the human a build that contradicts the Spec.

A finding line from `scenarios.sh` (a malformed or doubled result, a wrong exit) is the driver's fault: report the check as failed with the line, and escalate it as an amend.

List the result under Run checks on the Playtest issue ([`playtest.md`](playtest.md)): one line for the check, then one per Scenario with its result.
