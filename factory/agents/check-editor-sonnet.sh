#!/usr/bin/env bash
# A live check of the Sonnet Editor in Claude Code: run it after a Claude
# Code update, and keep its output in check-editor-sonnet.log next to this script.
#   bash factory/agents/check-editor-sonnet.sh
#
# It builds a throwaway project in a temp folder: the Core's fixture steps, the
# generated hooks, editor-sonnet.md installed (its skills left out), and
# CLAUDE_CODE_SUBAGENT_MODEL=claude-opus-5-5 set both in the environment and in
# .claude/settings.json. The lint step is red until .fixture/fail-lint is deleted,
# and its finding says so. Then `claude -p` (on Haiku) starts editor-sonnet with a
# prompt that only asks it to reply, and the check reads the result:
#   model    the subagent ran on claude-sonnet-5-5, and no Opus model ran
#   blocked  the SubagentStop hook blocked the first stop: lint ran twice
#   fixed    the subagent then deleted the file, and the gate passed (smoke ran)
# It needs the claude CLI and spends a few cents. It is not part of test.sh.
#
# Exit codes: 0 every check passed, 1 one failed, 2 no claude CLI.
set -u

factory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude > /dev/null || {
	echo "check: no claude CLI on PATH" >&2
	exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"

cp -R "$factory/core/tests/fixture/project" "$project"
cp -R "$factory" "$project/factory"
cd "$project" || exit 1
cp tools/verify/local.env.example tools/verify/local.env
mkdir -p .claude/agents .fixture
printf '{\n  "env": {\n    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-opus-5-5"\n  }\n}\n' > .claude/settings.json
bash factory/core/hooks.sh generate || exit 1
awk '/^skills:/ { skip = 1; next } skip && /^  - / { next } { skip = 0; print }' \
	"$factory/agents/editor-sonnet.md" > .claude/agents/editor-sonnet.md
printf '/.fixture/\n/tools/verify/local.env\n' > .gitignore
git init -q -b dev . && git add -A && git -c user.name=check -c user.email=check@example.com commit -q -m fixture
git checkout -q -b work
echo "src/a.txt:1 lint-check delete the file .fixture/fail-lint (in the worktree) to fix this finding" > .fixture/fail-lint

worktree="$(pwd -W 2> /dev/null || pwd)"
prompt="Use the Agent tool once, with subagent_type editor-sonnet and exactly this prompt (two lines):
factory-worktree: $worktree
Reply with the word done and nothing else.
Then report what the agent returned."

echo "claude: $(claude --version)"
CLAUDE_CODE_SUBAGENT_MODEL=claude-opus-5-5 claude -p "$prompt" --model haiku --output-format json \
	--allowedTools=Agent,Bash,Read < /dev/null > "$tmp/result.json" 2> "$tmp/stderr"
echo "claude exit: $?"

models="$(grep -o '"canonicalModel":"[^"]*"' "$tmp/result.json" | sed 's/.*:"//; s/"$//' | LC_ALL=C sort -u | tr '\n' ' ')"
echo "models used: $models"
ran="$(tr '\n' ' ' < .fixture/ran 2> /dev/null)"
echo "steps run: $ran"

bad=0
verdict() {
	if [ "$2" = 0 ]; then echo "PASS $1"; else
		echo "FAIL $1"
		bad=1
	fi
}
case " $models" in *" claude-sonnet-5-5 "*) s=0 ;; *) s=1 ;; esac
case "$models" in *opus*) s=1 ;; esac
verdict "model: the subagent ran on claude-sonnet-5-5 with CLAUDE_CODE_SUBAGENT_MODEL=claude-opus-5-5" "$s"
[ "$(grep -cx lint .fixture/ran 2> /dev/null)" -ge 2 ]
verdict "blocked: the SubagentStop hook blocked the stop while lint was red" "$?"
[ ! -f .fixture/fail-lint ] && grep -qx smoke .fixture/ran 2> /dev/null
verdict "fixed: the subagent fixed the finding and the gate went green" "$?"
exit "$bad"
