<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

<!-- factory:begin (generated from factory/core/templates/agents-section.md; edit that, then run bash factory/core/agents.sh generate) -->
## Factory

This project is built by the factory: the vendored `factory/` (its version is in `tools/verify/factory-version`). Its terms are in [`factory/CONTEXT.md`](factory/CONTEXT.md); the structure and the numbered rules agents build to are in [`ARCHITECTURE.md`](ARCHITECTURE.md).

- **Code work** goes through `/build <spec>`, from an approved Spec: it works the `ready-for-agent` issues Feature by Feature, up to two at once, each inside its Build Brief. The Editor writes every line of code and tests; Opus, the Driver, never writes code. Start a Run's session at effort low (`claude --effort low`): its main session mostly dispatches drivers and relays their reports (`factory/core/relay.sh`), and each driver and subagent keeps its own effort. `/spec` turns an overview into a Spec with Features and Slices, and asks only the Human's calls.
- **Verify:** `bash tools/verify.sh` runs every Gate step in order: prepare → format → typecheck → lint → arch → deviation → test → mutate → smoke (mutate only in an issue's Green phase: it lists the change's surviving mutants for the Verifier, in `<git-dir>/factory/survivors.txt`). `bash tools/verify.sh <step...>` runs a subset. While the Baseline (`tools/verify/ratchet/baseline.txt`) holds findings, the full verify is red by design, and `bash factory/core/baseline.sh gate` is the check that passes: no finding outside the Baseline. Until the Baseline is empty, only `Kind: cleanup` issues can land: every other Kind gates on the full verify.
- **Each checkout** needs `git config core.hooksPath factory/core/hooks/githooks` (prepare fails without it) and its own gitignored `tools/verify/local.env` with the machine's tool locations (copy `tools/verify/local.env.example`). The tools' versions are pinned in `tools/verify/pins`.
- **The gate:** `factory/`, `tools/verify/` (step scripts, pins, scope, generated, ratchet files and the Baseline) and the hook config (the `hooks`, `model`, `effortLevel` and `maxEffortLevel` keys of `.claude/settings.json`, and the Lock lift's rule in its `permissions` `allow` list). A ratchet file grows only by a declared Deviation that Opus accepts (the brief's `grows` line), and the Baseline shrinks at Land in the Driver's own commit; any other change to the gate is an amend the human approves.
- **Deviations:** every ruling on a Deviation is appended to [`docs/deviations.md`](docs/deviations.md).
- **State:** the project is Adopted (the write deny refuses, pre-commit only reports) until `factory/core/arm.sh` Arms it (pre-commit blocks too), once verify is green twice and the Baseline is empty. The Editor's stop hook loops it on its gate in both states.
- **Updates:** the factory has its own repo, named by factory-version's `upstream` line. `bash factory/core/sync.sh <tag>` (or `latest`) re-copies `factory/` from a release there, refusing while it has local edits; `sync.sh check` says whether a newer release exists, and a Claude session checks once a day at its start: a newer patch release syncs itself, committed on dev, when no issue is in flight (its log is `.git/factory/update-sync.log`); a minor one, or a patch held back, makes it ask the human whether to sync. It never touches `tools/verify/`; it prints the adapter-template diff to port there by hand.
- **Amends:** `/factory-amend` builds and lands the factory improvements the human approved. After any edit to `factory/`, `bash factory/core/amend.sh record` re-records it and refreshes its installed copies; `amend.sh check` finds what it would change. `amend.sh land` publishes each amend to the factory's repo first, as a release (`amend.sh release`, by the amends' `Release:` trailers), then pushes the project.
<!-- factory:end -->

## Agent skills

- **Issue tracker:** Gitea via `gt`; every command is in [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).
- **Triage labels:** [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).
- **Domain docs:** single-context (`CONTEXT.md`, `docs/adr/`); see [`docs/agents/domain.md`](docs/agents/domain.md).
