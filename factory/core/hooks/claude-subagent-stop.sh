#!/usr/bin/env bash
# The Sonnet Editor's SubagentStop hook (Claude Code). claude-hooks.json
# wires it to the editor-sonnet subagent (factory/agents/editor-sonnet.md); Claude
# Code passes the hook's JSON input on stdin.
#
# It runs the Editor's gate (editor-gate.sh) in the subagent's worktree, the one
# named by the `factory-worktree: <path>` line of the subagent's prompt, read from
# its transcript. While the gate is red it blocks the stop: it exits 2 with the
# gate's output on stderr, which Claude Code hands the subagent as its next
# instruction. When the small lane moved the issue on to the green phase
# (editor-gate.sh's exit 3), it blocks with the green phase's instruction, and
# that block starts the count afresh. It lets the subagent finish when the gate
# is green, and after FACTORY_EDITOR_LOOP_LIMIT (5) blocks of one subagent, counted in
# <git-dir>/factory/subagent-stop/<agent_id>; the Driver's own verify then sees
# what is still red. The gate is this checkout's Core, not the
# worktree's copy, so an Editor's edit to factory/ can't loosen its own gate.
#
# Before the gate it compares the round with the snapshot its SubagentStart hook
# (claude-subagent-start.sh) took (lib/round.sh: the protected files on disk in
# the worktree and the main checkout, those the round's commits changed, the git
# config and the branch's run state, dev and main here and on the remote). A
# difference blocks the stop with a `round-changed` finding for each, and the gate
# does not run; each such block counts toward the limit too. At the limit with a
# difference still there it lets the subagent stop, and writes the findings to
# <git-dir>/factory/round-changed for the Driver (factory-run's editor.md). With
# no snapshot (the start hook did not run) it says so and takes one now. When the
# small lane moves the issue on to green it takes a fresh one, since the Lock and
# the phase it sets are the gate's, not the round's.
#
# It does nothing (exit 0) for another agent, and when the prompt names no worktree.
#
# Exit codes: 0 let the subagent stop, 2 block it.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$core/lib/json.sh"
limit="${FACTORY_EDITOR_LOOP_LIMIT:-5}"

input="$(cat)"

# field <name>: the input's top-level field, decoded (lib/json.sh); empty when absent.
field() {
	printf '%s' "$input" | factory_json_get "$1"
}

[ "$(field agent_type)" = editor-sonnet ] || exit 0

agent="$(field agent_id)"
transcript="$(field agent_transcript_path)"
transcript="${transcript//\\//}"

# The worktree line of the prompt: its first occurrence in the transcript, where
# the prompt is a JSON string (so a backslash in the path appears doubled).
worktree=""
if [ -f "$transcript" ]; then
	worktree="$(grep -o 'factory-worktree: \([^"\\]\|\\\\\)*' "$transcript" | head -n 1 |
		sed 's/^factory-worktree: //; s/\\\\/\//g; s/[[:space:]]*$//')"
fi
if [ -z "$worktree" ] || ! git -C "$worktree" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
	echo "editor-sonnet stop hook: the prompt names no worktree (a 'factory-worktree: <path>' line), so no gate ran" >&2
	exit 0
fi

gitdir="$(cd "$worktree" && cd "$(git rev-parse --git-dir)" && pwd)" || exit 0
counter="$gitdir/factory/subagent-stop/${agent:-unknown}"
count="$(cat "$counter" 2> /dev/null)" || count=0
case "$count" in '' | *[!0-9]*) count=0 ;; esac

# The round's snapshot and its compare (lib/round.sh), loaded in a subshell so
# a lib that fails to load costs the compare, not the gate.
round() {
	(
		for lib in steps findings brief diff run lock json scenarios protect bounded round; do
			# shellcheck disable=SC1090 # the Core's libs, by name
			. "$core/lib/$lib.sh" || exit 9
		done
		cd "$worktree" || exit 9
		case "$1" in
			file) factory_round_file "$agent" ;;
			snapshot) factory_round_snapshot "$snap" ;;
			compare) factory_round_compare "$snap" "$worktree" ;;
		esac
	)
}
snap="$(round file)" || snap=""
changed="" notes=""
if [ -z "$snap" ]; then
	notes="editor-sonnet stop hook: the round lib did not load, so the round was not compared with its start"
elif [ -f "$snap" ]; then
	# Its findings on stdout, its notes (an unreachable remote) on stderr.
	notes="$(round compare 2>&1 > "$snap.changed")"
	changed="$(cat "$snap.changed" 2> /dev/null)"
	rm -f "$snap.changed"
else
	notes="editor-sonnet stop hook: no snapshot of this round's start (its SubagentStart hook did not run), so the round was not compared; it is taken now, for the next stop"
	round snapshot 2> /dev/null || rm -f "$snap"
fi

if [ "$count" -ge "$limit" ]; then
	if [ -n "$changed" ]; then
		mkdir -p "$gitdir/factory" && printf '%s\n' "$changed" > "$gitdir/factory/round-changed"
		echo "editor-sonnet stop hook: the round still changes what the factory protects after $limit tries ($gitdir/factory/round-changed); letting the subagent stop" >&2
	else
		echo "editor-sonnet stop hook: the gate is still red after $limit tries; letting the subagent stop" >&2
	fi
	rm -f "$snap"
	exit 0
fi

count=$((count + 1))
if [ -n "$changed" ]; then
	mkdir -p "$(dirname "$counter")" && printf '%s\n' "$count" > "$counter"
	{
		echo "This round changed what the factory protects (block $count of $limit), so the gate did not run. Put each back in $worktree as it says, commit, then stop again; if you can't, say so in your final message:"
		printf '%s\n' "$changed"
		[ -z "$notes" ] || printf '%s\n' "$notes"
	} >&2
	exit 2
fi

out="$(cd "$worktree" && bash "$core/hooks/editor-gate.sh" 2> /dev/null)"
case "$?" in
	0)
		rm -f "$counter" "$snap"
		# A green stop says only what left the round uncompared, not a remote
		# that could not be reached, which a project with no remote always has.
		[ -z "$notes" ] || printf '%s\n' "$notes" | grep -v '^round compare: .* could not be reached, ' >&2
		exit 0
		;;
	3)
		rm -f "$counter"
		[ -z "$snap" ] || round snapshot 2> /dev/null || rm -f "$snap"
		printf '%s\n' "$out" | tail -n +2 >&2
		exit 2
		;;
esac

mkdir -p "$(dirname "$counter")" && printf '%s\n' "$count" > "$counter"
{
	echo "The gate is red (block $count of $limit). Fix these findings in $worktree, commit, then stop again:"
	printf '%s\n' "$out"
	[ -z "$notes" ] || printf '%s\n' "$notes"
} >&2
exit 2
