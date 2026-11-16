# The factory

A set of automated gates, scripts, skills and agent roles that build a project from an approved Spec: the Driver writes Build Briefs, the Editor writes the code and tests, the Verifier checks them, and the gates decide what lands. It lives in each project as a vendored `factory/` folder, pinned to a release; a stack plugs in through an adapter (`adapters/<name>/`). Its terms are in [`CONTEXT.md`](CONTEXT.md).

## Install

From a clone of this repo, checked out at a release tag, into a project that is a clean git checkout:

```bash
git clone -b <tag> git@git.stuffworks.net:psnail273/factory.git ~/factory
bash ~/factory/factory/core/install.sh <project dir> <adapter>         # an existing project
bash ~/factory/factory/core/install.sh <project dir> <adapter> --new   # a new one, from the adapter's skeleton
```

(A tag from before the repo became a workspace, below, has the factory at its root: there it is `bash ~/factory/core/install.sh`.) `install.sh` copies the clone's tracked `factory/` into `<project>/factory/`, runs `factory/core/adopt.sh` there, and records this repo's URL and the tag in `tools/verify/factory-version` (its `upstream` and `tag` lines). It commits nothing. Then, before you commit, the `/factory-adopt` skill (now in `.claude/skills/`) takes the project the rest of the way from the staged adoption (labels, tracker docs, ARCHITECTURE.md, cleanup issues).

## Machine tools

`bash factory/tools/install.sh` installs the machine's tool (`claude-usage`); it is not `core/install.sh`, which installs the factory into a project.

## Update

`bash factory/core/sync.sh <tag>` re-copies `factory/` from a release of the repo that factory-version's `upstream` line names (`FACTORY_UPSTREAM` overrides it). It refuses while `factory/` has local edits, and prints the adapter templates' diff to port into `tools/verify/` by hand. `sync.sh latest` syncs to the highest `v<major>.<minor>.<patch>` tag there, and `sync.sh check` only says whether one is newer than the project's (`newer v<x> (on <version>)` or `current <version>`). A Claude Code session runs that check at its start, at most once a day per checkout. A newer patch release (the same major and minor) syncs itself there, in the background, and is committed on dev as `Sync factory <new> (from <old>)`, when no issue is in flight (no `.claude/worktrees/issue-*`) and the session is in the main checkout, on dev, with a clean tree; the session says so in one line, `factory synced <old> → <new> (patch); push dev so new issues get it`, since that commit is local and issues are cut from `origin/dev`, and the log is `.git/factory/update-sync.log`. A newer minor or major release, or a patch held back, makes the session ask the human whether to sync.

## Amends

A change to the factory is an amend the human approves (or the Driver, for an amend that changes only tests and the READMEs: `Amend-class: tests-or-docs`, which land checks); the `/factory-amend` skill builds it, inside a real project against that project's vendored `factory/`, or in this repo (below). `factory/core/amend.sh` does the mechanics; in a project:

1. After each edit to `factory/`, `bash factory/core/amend.sh record`; `amend.sh check` prints what is stale.
2. Each amend commit carries a `Release: minor` or `Release: patch` trailer. A minor adds or tightens a check, changes a step the human does, changes how issues are filed or needs a template ported by hand, and projects sync it only with their human's yes; a patch syncs into them by itself. On the landing branch, `bash factory/core/amend.sh release` bumps `VERSION` by those trailers (a minor, too, when the diff touches a path the floor in `amend.sh`'s header lists; `release <version>` sets another by hand), committed as `Release factory <new>`; land refuses an amend commit with no trailer and a bump they disagree with.
3. `bash factory/core/amend.sh land` refuses when the project's `factory/` differs from this repo's `main` (sync to the latest tag first), runs the full suite (with the whole `local.env`; it refuses when a real-tool test it ran skipped for a missing tool) and the gate, then publishes here first, each commit that changed `factory/` replayed onto `main` with its author and message and tagged `v<VERSION>`, and only then pushes the project.

## Working in this repo

The factory is `factory/`, exactly what a project vendors; the top of the repo is the workspace for changing it (`CLAUDE.md`, `docs/agents/`, `local.env.example`, a `.factory-repo` marker and `.claude/skills/`), and never reaches a project. Its first releases had the factory at the root instead (the root layout), and `sync.sh`, `install.sh` and a project's `amend.sh land` still read both layouts. Here `amend.sh record` refreshes the workspace's skill copies, `release` bumps `factory/VERSION` by the amends' `Release:` trailers, and `land` runs check and the full suite, then pushes `main` (a fast-forward only) and, when `factory/VERSION` changed, the tag `v<VERSION>`, in one atomic push. Issues are this repo's Gitea issues.

`factory/third-party/` holds what the factory vendors from elsewhere (Anthropic's `frontend-design` skill, for the designer and the Verifier), each exactly as its source has it, with its licence, and its source, version and blob ids in [`third-party/README.md`](third-party/README.md). Take a newer one by replacing the folder whole and updating that line, never by editing it.

## Tests

From the repo's top: `bash factory/core/test.sh` runs every suite (`bash factory/core/test.sh <suite...>` some of them). The Godot adapter's suites need `GODOT_BIN`, and `FACTORY_GDUNIT4` (a gdUnit4 addon folder at its pinned version) for the tests that run gdUnit4, which skip without it. The Next.js adapter's suites need Node and pnpm (on PATH, or `NODE_BIN` and `PNPM_BIN`), the Node at the version `factory/adapters/nextjs/tools/verify/pins` names (another fails each test that would run it, naming both versions), `FACTORY_PNPM_STORE` (a pnpm store primed with its skeleton's packages) for the tests that install packages, offline from that store, and `FACTORY_PLAYWRIGHT_BROWSERS` (a folder holding the Chromium, Firefox and WebKit its pinned Playwright runs) for the tests that load a page; they skip without them. `bash factory/adapters/nextjs/tests/prime-store.sh <dir> <browsers dir>`, the one command that uses the network, primes both.
