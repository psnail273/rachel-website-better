#!/usr/bin/env bash
# The Sonnet Editor's SubagentStart hook (Claude Code). claude-hooks.json wires it
# to the editor-sonnet subagent; Claude Code passes the hook's JSON input on stdin
# ({"agent_id": "...", "agent_type": "editor-sonnet", "cwd": "...", ...}).
#
# It takes the round's snapshot (lib/round.sh): what the factory protects in every
# checkout of the repo, the git config and run state, and dev and main here and on
# the remote, into <git-common-dir>/factory/round/<agent_id>. The Editor's
# SubagentStop hook (claude-subagent-stop.sh) compares the round with it. Its input
# names no worktree (the prompt is not in it), so it takes them all; the stop hook
# compares only the one the prompt names, and the main checkout.
#
# It never stops the subagent: it exits 0 whatever happens, and a snapshot it
# could not take is one the stop hook says it lacks.
set -u

input="$(cat)"
case "$input" in *editor-sonnet*) ;; *) exit 0 ;; esac

core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for lib in steps findings brief diff run lock json scenarios protect bounded round; do
	# shellcheck disable=SC1090 # the Core's libs, by name
	. "$core/lib/$lib.sh" || exit 0
done

field() {
	printf '%s' "$input" | factory_json_get "$1"
}

[ "$(field agent_type)" = editor-sonnet ] || exit 0
cwd="$(field cwd)"
cwd="${cwd//\\//}"
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-.}"
cd "$cwd" 2> /dev/null || exit 0
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

snap="$(factory_round_file "$(field agent_id)")" || exit 0
factory_round_snapshot "$snap" 2> /dev/null || rm -f "$snap"
exit 0
