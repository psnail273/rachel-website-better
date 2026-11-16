# Third-party files

What the factory vendors from elsewhere, each folder exactly as its source has it, so it can be diffed against a newer one; nothing here is edited by hand. Each is installed like the factory's own files (`factory_installed_copies` in `core/lib/vendor.sh`), and stays outside `skills/` so the factory's own skill budget (`core/skill-budget.sh`) never asks it to change.

One line per vendored thing: its folder, its source, its version, its licence, and the git blob id of each file as vendored (`git hash-object <file>`), which `core/tests/agents_test.sh` checks.

- `frontend-design/`: Anthropic's `frontend-design` skill, from the `claude-plugins-official` Claude Code plugin marketplace, `plugins/frontend-design/skills/frontend-design/`; plugin version 1.1.1; Apache License 2.0 (`frontend-design/LICENSE.txt`); `SKILL.md` a5333457c414d20d625f307df945842c0952ecc3, `LICENSE.txt` f433b1a53f5b830a205fd2df78e2b34974656c7b. Installed to `.claude/skills/frontend-design/` for the `designer` and `verifier` subagents, which preload it (their `skills:` lists); never listed for the Editor, and the deny hook (`core/hooks/claude-deny.sh`) refuses the Editor's `Skill` call of it.
