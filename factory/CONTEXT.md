# Factory

The stack-agnostic system that turns an approved spec into built, verified features: agents build to a project's architecture under automated gates, and the human gives intent, approves the spec and playtests.

## Language

### Structure

**Core**:
The part of the factory that is the same for every stack: the gate runner and step order, the Deviation check, the test lock, the hooks and the repo skills. A project receives it as a vendored copy at a pinned version and changes it only by an **Amend**.
_Avoid_: Framework, kit, base

**Adapter**:
The part of the factory that knows one stack (Godot, Next.js): the commands behind each gate step, their pinned tools and config, the default architecture rules and a new-project skeleton. A project's step scripts are seeded from it once and then belong to the project.
_Avoid_: Plugin, driver, stack config

**Seam**:
An agreed shape of what passes between the **Core** and an **Adapter**, such as the per-test results file, so any **Adapter** that meets it plugs in without changing the **Core**.
_Avoid_: Interface, contract, hook

**Gate**:
A point where the full set of verify steps decides whether work may go on. Every **Gate** runs every step, but the optional mutate step, which runs only in an issue's **Green phase**: the red gate and Land's leave it out, since no **Verifier** reads their survivors.
_Avoid_: Check (a check is one rule inside a step), CI

**Gate stamp**:
A verify run's verdict, kept with a key naming everything it depends on: the commit, the working tree, the **Build Brief**, the diff base and the run state. A later run on the same inputs may print it again (`verify.sh --reuse`) instead of running every step: the **Driver** and the **Verifier** reuse the one the **Editor**'s gate kept, but in the **Green phase**: there the **Editor**'s lighter gate keeps a stamp of its own, so the **Driver**'s runs fresh and the **Verifier** reuses that. A run in which a step failed for a transient cause (a lock held too long, a refused connection: exit 75) keeps none. Nothing that can't be undone rests on one: the red gate before the **Lock** and Land always run fresh.
_Avoid_: Cache

**Surviving mutant**:
A small change to a line the branch changed that no test caught. In the **Green phase** the optional mutate step makes such changes one at a time and lists each survivor in the survivors file; the **Editor**'s stop hook shows it the list once, and the **Verifier** needs each one killed by a test or justified. In the **Editor**'s own gate, mutate reuses its last run's results (Stryker incremental); the **Driver**'s gate runs it in full. No score gates anything.
_Avoid_: Mutation score

### Adoption

**Adopted**:
A project that has the **Core** and its step scripts installed. Its pre-commit hook reports findings without blocking, while the **Editor**'s write deny refuses from the start.
_Avoid_: Installed, onboarded

**Armed**:
An **Adopted** project whose pre-commit hook blocks too: verify was green twice with identical output and the human approved arming.
_Avoid_: Enabled, live

**Baseline**:
The tracked list of findings an **Adopted** project started with. It only shrinks, and each cleanup issue must remove its own findings without adding any. The one exception is an amend that adds a check the code already fails: that check's findings join the **Baseline** in the amend's own commit, and a cleanup issue removes them next.
_Avoid_: Allowlist (an allowlist is a permanent exception, a **Baseline** is debt), snapshot

**Bootstrap**:
Installing a project's dependencies when a worktree is created, before any **Gate** runs, so every **Gate** runs offline.
_Avoid_: Prepare (the first gate step, which runs offline), install

### Planning

**Human's call**:
A decision only the human makes: how the product should feel and look, what is in scope and what comes first, an amend to the architecture, or anything that costs money or can't be undone. An agent decides everything else and lists it for the human to review.
_Avoid_: Open question, blocker

**Driver's call**:
A call the **Driver** makes in a **Run** instead of escalating, on findings inside the sealed **Build Brief** (fixing them changes no acceptance criterion, no Spec behaviour, nothing a player would see or feel beyond the brief): up to two extra **Fix rounds** per phase, then one **Takeover** by the Sonnet **Editor**, a finding accepted as out of practical reach, or one move of the **Lock** for a locked test that contradicts the brief. Each is posted under Decided for you, logged in `docs/deviations.md` and counted (`self-ruled`), so the human audits it after the fact.
_Avoid_: Self-approval, auto-escalation

**Spec**:
The human-approved index of what to build: the problem, the **Features**, the **Human's calls** and their answers, what an agent decided, and the slices that build it. A **Run** works only from an approved **Spec**.
_Avoid_: PRD, plan, epic

**Feature**:
A group of a **Spec**'s slices that ends in one **Playtest**; a **Feature** of cleanup issues only, such as an Adoption cleanup, may have none. A **Run** works the first open **Feature**, and the next one while the first's **Playtest** waits on the human; the human sets their order.
_Avoid_: Milestone, epic, slice

**Design direction**:
One of two or three clearly different looks (tokens, type, and the layout of Home, one inner page, the header and the footer) that the designer subagent builds as a live prototype in the real app, behind a dev-only switcher, before a **Spec** whose look or feel is a **Human's call** is sliced. Each is checked against `frontend-design`'s list of generic AI-design tells, and at least one breaks from the current `docs/design.md`. The human picks one or mixes them, the designer iterates on the winner until the human approves, and the prototypes are thrown away.
_Avoid_: Mood board, mock-up, theme

**Board**:
The approved **Design direction**'s screenshots, committed in `docs/design/board/` beside the `docs/design.md` written from it: Home and the inner page at 390 and 1280 px, light and dark, named `<route-slug>-<width>-<scheme>.png`. Slices are written to match it: the picture of the goal, where adjectives fall short.
_Avoid_: Mock-up, design comp, reference images

**Contact sheet**:
Screenshots of every page route at 390, 768 and 1280 px, light and dark, with reduced motion, named as the **Board**'s are, that `tools/verify/contact-sheet` takes into the checkout's git dir and never commits. A page that carries the layout contract's `[data-shell]` is taken at 1920 px too, light. Its index lists what axe couldn't decide at 390 and 1280 px, such as text over an image, and what smoke's layout check reports and leaves to the eye (lines of one word, ragged and short paragraphs), for the **Verifier** to judge by eye. The **Editor** of a visual issue takes it at hand-back for the **Design check**.
_Avoid_: Screenshot set, gallery

**Design check**:
The **Verifier**'s yes/no check of a visual issue's **Contact sheet** beside the **Board** and `docs/design.md`: tokens and spacing, a 65ch measure, no overflow at 390 px, visible focus rings, no generic AI-design tells, the **Board**'s layout, what axe couldn't decide, and what the layout check left to the eye. A visual issue is one whose diff changes what a page renders, as the build skill's `verify-rubric.md` defines it. A no fails the check. It is a filter: the human's **Playtest** and the screenshot baselines it records are the proof.
_Avoid_: Design review, visual QA

### Roles

**Driver**:
The agent that plans, writes each **Build Brief**, runs the **Gates** and rules on **Deviations**. It never writes code.
_Avoid_: Orchestrator, lead

**Editor**:
The agent that writes and commits every change to code and tests, inside one **Build Brief**. Its stop hook loops it on its phase's **Gate**; in the **Green phase** a lighter one, smoke in one browser and mutate incremental, while the **Driver**'s green gate and Land run every browser and a full mutate.
_Avoid_: Coder, worker, implementer

**Verifier**:
A fresh agent that changes nothing, on a different model from the **Editor** (Opus, where the **Editor** is Sonnet), that checks an issue's tests or diff against the **Build Brief** and cites evidence for each verdict.
_Avoid_: Reviewer, judge

**Takeover**:
The **Driver** or a fallback agent writing an issue's code because the human said so at an **Escalation**, or the Sonnet **Editor**'s one round past the **Fix rounds**' ceiling, a **Driver's call**. The same **Gates** still apply and it is logged like a **Deviation**.
_Avoid_: Break, override, solo mode

**Models and effort**:
Every agent runs on an Anthropic model, named by its pinned id: the main session, the **Driver**, the **Verifier** and the amend builder on `claude-opus-5-5`, the **Editor**, the asset fetcher and the **Spec**'s research subagents on `claude-sonnet-5-5`, mechanical lookups on `claude-haiku-5-5`, and the designer, for the spec skill's **Design direction** step alone, on Fable, `claude-fable-5-2`, which the human approved on #42. The main session runs at effort medium (the project's `.claude/settings.json`, which `hooks.sh generate` writes with `maxEffortLevel` xhigh as a backstop to this rule), but a **Run**'s at low: `/build`'s `effort: low` lowers the turn it starts, and the human starts a Run's session with `claude --effort low` for the turns a driver's report wakes, since its relays are mechanical (`relay.sh`). Every agent's definition says medium, and an Agent call's `effort` sets each subagent's, whatever the session's. Whoever dispatches an agent may raise its effort: high for a big change (a slice or an amend touching many files or a **Core** script, or a rebuild after a red land), xhigh after the same tests failed in two rounds in a row, or an amend builder's rework came back twice; never max. The main session decides it for what it dispatches, and an issue's **Driver** for its **Editor** rounds and **Verifier** checks, in its `needs` report; each prompt names it on its first line, `factory-effort: <level>`. Every other use of Fable (`claude-fable-5-2`) still needs the human's yes for that one subagent.
_Avoid_: Roles list, editor/verifier choice

### Running

**Run**:
One unattended Opus session working a spec's ready issues, at once where their `Touches:` areas are apart, each in a driver subagent of its own, **Feature** by **Feature** from the first claim, each **Feature** ending in its **Playtest**.
_Avoid_: Batch, pipeline, job

**Build Brief**:
What Opus hands the Editor for one issue: what to build, the acceptance tests by name, the existing tests the change reaches, the seams to stub, the files in scope and the architecture rules that apply.
_Avoid_: Prompt, ticket, task

**Brief review**:
The **Verifier**'s check of a sealed **Build Brief** with tests: that its tests would pin every part of each acceptance criterion, and that it names the existing tests the change reaches. It reads the branch as it was before the first **Editor** round and runs before that round; the **Lock** waits for its pass.
_Avoid_: Brief check (`brief.sh check`, the brief's lint), pre-review

**Red phase**:
The Editor's first run on an issue, which writes the acceptance tests and stubs of the seams so that every named test fails for an assertion reason.
_Avoid_: Test phase, TDD step

**Lock**:
The red phase's commit, after which any change to its tests is a **Deviation**. It moves at most once per issue, for a locked test that proves wrong.
_Avoid_: Freeze, snapshot

**Green phase**:
The Editor's runs after the **Lock** that make the locked tests pass under every **Gate** step.
_Avoid_: Build phase, implementation

**Deviation**:
Any change outside the **Build Brief**: an off-scope file, a new pattern, a bent rule or an edit to locked tests. Opus rules on each one: accept, reject or amend.
_Avoid_: Exception, scope creep

**Fix round**:
One more Editor turn on the same chat after a **Gate** failure, a verifier fail or a rejected **Deviation**. Each phase allows two; the **Driver** may grant two more when every open finding is inside the brief (a **Driver's call**), and never a fifth.
_Avoid_: Retry, iteration

**Escalation**:
Handing an issue to the human because it needs a **Human's call**, or has used up its **Fix rounds** and its **Takeover**. The issue is parked and the **Run** carries on with work that doesn't depend on it.
_Avoid_: Blocker, failure

**Partial mode**:
How a **Run** works a cleanup issue: no **Red phase**, and the issue passes when it removes its own **Baseline** findings and adds none. On an **Armed** project the **Baseline** is empty, unless an amend just added a check, so it passes only with no finding at all.
_Avoid_: Cleanup mode, soft mode

**Small lane**:
How a **Run** works a small, low-risk issue: at most four tests and three product files, no seam, no **Gate** file. One **Editor** round: its stop hook records the **Lock** once the **Red phase** passes and moves the same chat to the **Green phase**, and one Verifier judges the tests and the code at the end. If that Verifier fails a test that contradicts the brief, the **Driver** may move the **Lock** once, as in any lane (a **Driver's call**).
_Avoid_: Fast track, express lane

**Test-only issue**:
A build issue that adds tests over behaviour already built and changes no product file. It has no **Red phase** and no **Lock**, since a test of working code can't fail first; its gate fails any file but tests and the **Driver**'s docs.
_Avoid_: Test task, green-only issue

**Asset slice**:
A slice that brings the external files a **Spec** lists (sounds, images, fonts) into the repo, each with its licence and credit, fetched by the **Driver**'s asset subagent, so no **Editor** round needs the web.
_Avoid_: Download task

**Drift sweep**:
A whole-codebase review against the architecture and the accepted **Deviations**, run when a **Run** ends, that turns what it finds into cleanup issues.
_Avoid_: Audit, refactor pass

**Retro**:
The **Driver**'s look back after a **Drift sweep**: it totals the **Feature**'s counted and uncounted **Fix rounds**, **Escalations** and the drivers' notes, with the minutes and Claude tokens each issue took, sorts each event by a named cause, marks whether each **Amend** since the last retro held, and proposes a priced factory fix for every cause that repeats, which waits on the human's decision list.
_Avoid_: Post-mortem

**Amend**:
A change to the factory: the **Core** or an **Adapter**, the step scripts in `tools/verify/`, or the hook config. The human approves one, most often a **Retro**'s proposal; the one exception is the tests-or-docs class, which the **Driver** may approve itself and lists in its report, where the human can overrule it. That class touches only the factory's `tests/` folders and the docs no agent reads as instructions (the list is `tests_or_docs_paths` in `amend.sh`: the READMEs, `local.env.example` and a project's `tools/verify/factory-version`; never a skill, an agent file, CONTEXT.md, a template or a prompt), removes no test, and says so with the commit trailer `Amend-class: tests-or-docs`, which `amend.sh land` checks. `/factory-amend` builds each in a commit of its own, outside any **Run**. Amends are made in the factory's own repo; a project's, built in its vendored copy, is published there by `amend.sh land` before it lands on dev. A landed batch is a release: a minor when it adds or tightens a check, changes a step the human does, changes how issues are filed or needs a template ported by hand, which a project syncs only with its human's yes; else a patch, which a project's session syncs by itself at its start when no issue is in flight. Each amend commit says which in the trailer `Release: minor` or `Release: patch`; `amend.sh release` bumps by them, raised to a minor by the floor its header lists, and land refuses an amend commit without one. A batch that changes only the factory repo's workspace is no release.
_Avoid_: Patch, hotfix, local edit

**Factory backlog**:
The one tracker issue that lists the open factory-improvement issues: each a child holding the **Retro** or amend-batch proposals that wait on the human's yes. It lists only the open children, so it stays short, and it closes when none is left. What waits on nobody is never filed: an amend batch's notes recommended no, and a retro whose every proposal is recommended no, are noted where they were found.
_Avoid_: Improvement queue, inbox

### Playtesting

**Playtest**:
The human playing a finished **Feature** on a real build and judging only its feel and look, after the **Run** has checked everything a script can. It passes when every check passes and nothing new is found in the **Feature**. The **Run** goes on into the next **Feature** while one waits; at most one is open at a time, and a failed one's fixes go ahead of later **Features**' slices.
_Avoid_: QA, acceptance test, phone check

**Scenario**:
A scripted play-through of one of a **Feature**'s behaviours: written in words in the **Spec**, scripted at the **Feature**'s end by a **Verifier**-role agent, and kept where the **Editor** can neither read nor write it. The **Run** runs every **Scenario** before each **Playtest**; one that fails, against the **Spec**, is a bug. In Next.js the run first holds each page's look to a screenshot baseline in the **Scenario** folder, which only a passed **Playtest** records.
_Avoid_: Acceptance test, E2E test (the **Editor**'s own tests), Playtest check

**Tweak**:
A feel or tuning change the human asks for at a **Playtest** that leaves the **Feature**'s behaviours as they are. Asking for it is its approval.
_Avoid_: Bug (a bug contradicts the **Spec**), scope change
