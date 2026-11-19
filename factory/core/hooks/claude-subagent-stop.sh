#!/usr/bin/env bash
# The Sonnet Editor's hand-back hook (Claude Code), for two events: its
# SubagentStop, and the PreToolUse of its SubagentHandback call. claude-hooks.json
# wires both to it, the first for the editor-sonnet subagent
# (factory/agents/editor-sonnet.md), the second for every SubagentHandback call;
# it takes only the editor-sonnet's. Claude Code passes the hook's JSON input on
# stdin.
#
# Why both: a subagent that reports through the SubagentHandback tool (Claude
# Code in auto mode) has delivered its report, and ended, when the call runs; its
# SubagentStop hook fires after that, so a block from it reaches no one (#21: the
# small lane's green instruction was lost so on five issues). The hook therefore
# decides before the hand-back: exit 2 on the PreToolUse refuses the call, and
# Claude Code hands the stderr to the subagent, which carries on in the same chat.
# When it lets a hand-back through it leaves a mark (<counter>.handback), and the
# SubagentStop that follows it ends at once, with no second gate. A subagent that
# ends with plain text (no SubagentHandback) is judged at its SubagentStop, as it
# always was.
#
# It runs the Editor's gate (editor-gate.sh) in the subagent's worktree, the one
# named by the `factory-worktree: <path>` line of the subagent's prompt, read from
# its transcript (agent_transcript_path at SubagentStop; at the PreToolUse, the
# session's transcript_path with .jsonl dropped, then subagents/agent-<agent_id>.jsonl).
# While the gate is red it blocks: it exits 2 with the gate's output on stderr,
# which Claude Code hands the subagent as its next instruction. When the small
# lane moved the issue on to the green phase (editor-gate.sh's exit 3), it blocks
# with the green phase's instruction, and that block starts the count afresh.
# When the gate is green, it lets the subagent finish only when its final message
# (the hand-back's message, or last_assistant_message at SubagentStop) quotes the
# gate's result line, `<verdict> at <short HEAD>` (the gate output's last
# `verify: ...` or `baseline: ...` line, e.g. `verify: PASS at 1a2b3c4`); else it
# blocks with that line to quote. Before that, once per subagent, a green gate
# in the green phase (the Editor's loop, editor-gate.sh) whose mutate step left
# surviving mutants (lib/mutate.sh's survivors file, its lines not starting
# with #) blocks with them listed: kill each with a test, or say in the final
# message why it can't be killed. It marks the subagent (<counter>.survivors),
# so the next green stop goes on to the quote check, whatever survivors are
# left. That block is the gate's green end, not a red try: like a green stop it
# clears the count, so the work it asks for gets the full FACTORY_EDITOR_LOOP_LIMIT
# again, and it is never counted itself. It lets the subagent finish anyway after
# FACTORY_EDITOR_LOOP_LIMIT (5) blocks of one subagent, counted in
# <git-dir>/factory/subagent-stop/<agent_id>; the Driver's own verify then sees
# what is still red. The gate is this checkout's Core, not the worktree's copy,
# so an Editor's edit to factory/ can't loosen its own gate.
#
# One gate at a time per worktree: the run holds <git-dir>/factory/editor-gate/running
# (a folder holding its pid) and leaves its key, exit code and
# output in <git-dir>/factory/editor-gate/result, writing them itself, so a hook
# Claude Code stopped while its gate ran leaves both to the next. A hook that
# finds a run in flight waits for it, before it compares the round (that run may
# be writing the small lane's Lock and phase), up to FACTORY_EDITOR_GATE_WAIT
# seconds (900), and takes its result for the same HEAD, whatever it is; past the wait it
# lets the subagent stop, saying so. Without a wait it takes a small lane's exit 3
# for the same HEAD that no hook passed on yet (once: taking it removes it), so
# the green instruction still reaches the subagent, and a green result for the
# same key (HEAD, phase, the Build Brief's hash and the subagent) on a clean
# tree, so the stop, then the hand-back it asks for, run one gate; anything
# else, another round's subagent included, runs the gate again.
#
# Before the gate it compares the round with the snapshot its SubagentStart hook
# (claude-subagent-start.sh) took (lib/round.sh: the protected files on disk in
# the worktree and the main checkout, those the round's commits changed, the git
# config and the branch's run state, dev and main here and on the remote). A
# difference blocks with a `round-changed` finding for each, and the gate does
# not run; each such block counts toward the limit too. At the limit with a
# difference still there it lets the subagent stop, and writes the findings to
# <git-dir>/factory/round-changed for the Driver (the build skill's editor.md). With
# no snapshot (the start hook did not run) it says so and takes one now. When the
# small lane moves the issue on to green it takes a fresh one, since the Lock and
# the phase it sets are the gate's, not the round's.
#
# It does nothing (exit 0) for another agent or tool, and when the prompt names
# no worktree.
#
# Exit codes: 0 let the subagent stop (or hand back), 2 block it.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$core/lib/json.sh"
. "$core/lib/bounded.sh"
limit="${FACTORY_EDITOR_LOOP_LIMIT:-5}"
wait_limit="${FACTORY_EDITOR_GATE_WAIT:-900}"

input="$(cat)"

# field <name>: the input's field (a dotted path), decoded (lib/json.sh); empty when absent.
field() {
	printf '%s' "$input" | factory_json_get "$1"
}

[ "$(field agent_type)" = editor-sonnet ] || exit 0

agent="$(field agent_id)"
event="$(field hook_event_name)"
if [ "$event" = PreToolUse ]; then
	[ "$(field tool_name)" = SubagentHandback ] || exit 0
	message="$(field tool_input.message)"
	transcript="$(field transcript_path)"
	transcript="${transcript//\\//}"
	transcript="${transcript%.jsonl}/subagents/agent-$agent.jsonl"
else
	message="$(field last_assistant_message)"
	transcript="$(field agent_transcript_path)"
	transcript="${transcript//\\//}"
fi

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

# The stop that follows a hand-back this hook let through: judged already.
if [ "$event" != PreToolUse ] && [ -f "$counter.handback" ]; then
	rm -f "$counter.handback"
	exit 0
fi

count="$(cat "$counter" 2> /dev/null)" || count=0
case "$count" in '' | *[!0-9]*) count=0 ;; esac

# counted <why>: keep this block's count, and why it blocked (quote, else red).
counted() {
	mkdir -p "$(dirname "$counter")" && printf '%s\n' "$count" > "$counter" && printf '%s\n' "$1" > "$counter.why"
}

# release: let the subagent stop; a hand-back marks the stop that follows it.
release() {
	if [ "$event" = PreToolUse ]; then
		mkdir -p "$(dirname "$counter")" && : > "$counter.handback"
	fi
	exit 0
}

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

# survivors [path]: the surviving mutants the worktree's survivors file lists
# (lib/mutate.sh: its lines not starting with #), or with `path`, the file's path.
survivors() {
	(
		. "$core/lib/mutate.sh" || exit 0
		cd "$worktree" || exit 0
		file="$(factory_survivors_file)" || exit 0
		case "$file" in /*) ;; *) file="$worktree/$file" ;; esac
		if [ "${1:-}" = path ]; then
			printf '%s\n' "$file"
		else
			grep -v -e '^#' -e '^[[:space:]]*$' "$file" 2> /dev/null
		fi
		exit 0
	)
}

# --- one gate at a time per worktree -------------------------------------------------

gatedir="$gitdir/factory/editor-gate"
mkdir -p "$gatedir"

# gate_key: what a gate result is for: the worktree's HEAD, then its phase, the
# Build Brief's hash and the subagent, so a green result serves only the
# subagent whose stop ran it, on the same brief.
gate_key() {
	local branch phase="" brief=""
	if branch="$(git -C "$worktree" symbolic-ref --short -q HEAD)"; then
		phase="$(git -C "$worktree" config --get "branch.$branch.factory-phase")" || phase=""
	fi
	if [ -f "$gitdir/factory/brief.md" ]; then
		brief="$(git hash-object --no-filters "$gitdir/factory/brief.md" 2> /dev/null)" || brief=""
	fi
	printf '%s %s %s %s\n' "$(git -C "$worktree" rev-parse HEAD 2> /dev/null)" "${phase:--}" "${brief:--}" "${agent:-unknown}"
}

# read_result [any]: set status and out from the result file when it is this
# hook's to take: with `any` (the run this hook ran or waited for), any result
# for this HEAD; without, a green one for this whole key (HEAD, phase, brief and
# subagent: the stop, then the hand-back it asks for) on a clean tree,
# or a small lane's exit 3 for this HEAD that no hook passed on yet (its hook was
# stopped). An exit 3 is passed on once: taking it removes the file.
read_result() {
	local k s
	[ -f "$gatedir/result" ] || return 1
	k="$(head -n 1 "$gatedir/result")"
	s="$(sed -n 2p "$gatedir/result")"
	case "$s" in '' | *[!0-9]*) return 1 ;; esac
	[ "${k%% *}" = "${key%% *}" ] || return 1
	if [ "${1:-}" != any ] && [ "$s" != 3 ]; then
		[ "$s" = 0 ] && [ "$k" = "$key" ] && [ -z "$(git -C "$worktree" status --porcelain 2> /dev/null)" ] || return 1
	fi
	status="$s"
	out="$(tail -n +3 "$gatedir/result")"
	[ "$s" != 3 ] || rm -f "$gatedir/result"
}

# wait_in_flight: wait, up to the wait limit, for the run holding the gate to
# end: its folder gone, or its pid no longer running (it was killed; its folder
# is then removed). False when the wait ran out.
wait_in_flight() {
	# shellcheck disable=SC2016 # the loop's own variables
	factory_run_bounded "$wait_limit" bash -c '
		while [ -d "$1" ]; do
			pid="$(cat "$1/pid" 2> /dev/null)"
			[ -z "$pid" ] || kill -0 "$pid" 2> /dev/null || exit 0
			sleep 1
		done' _ "$gatedir/running"
	if [ "$?" -eq 124 ]; then
		# A run that never wrote its pid (its hook stopped at the start) frees the gate.
		[ -s "$gatedir/running/pid" ] || rm -rf "$gatedir/running"
		return 1
	fi
	rm -rf "$gatedir/running"
}

# await_gate: true when a gate was in flight, after waiting for it to end; past
# the wait limit, let the subagent stop, saying so.
await_gate() {
	[ -d "$gatedir/running" ] || return 1
	echo "editor-sonnet stop hook: a gate is already running in $worktree; waiting for it (up to ${wait_limit}s)" >&2
	if ! wait_in_flight; then
		echo "editor-sonnet stop hook: a gate already running in $worktree ran past FACTORY_EDITOR_GATE_WAIT (${wait_limit}s), so this stop has no result; letting the subagent stop" >&2
		rm -f "$snap"
		release
	fi
}

# A gate in flight (its hook stopped) may be writing the small lane's Lock and
# phase, the gate's and not the round's: the round is compared once it is done,
# when that run has taken the round's fresh snapshot.
waited=""
! await_gate || waited=1

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
	elif [ "$(cat "$counter.why" 2> /dev/null)" = quote ]; then
		echo "editor-sonnet stop hook: the final message still doesn't quote the gate's result after $limit tries; letting the subagent stop" >&2
	else
		echo "editor-sonnet stop hook: the gate is still red after $limit tries; letting the subagent stop" >&2
	fi
	rm -f "$snap"
	release
fi

count=$((count + 1))
if [ -n "$changed" ]; then
	counted round
	{
		echo "This round changed what the factory protects (block $count of $limit), so the gate did not run. Put each back in $worktree as it says, commit, then stop again; if you can't, say so in your final message:"
		printf '%s\n' "$changed"
		[ -z "$notes" ] || printf '%s\n' "$notes"
	} >&2
	exit 2
fi

key="$(gate_key)"
status="" out=""
for _ in 1 2 3; do
	if [ -n "$waited" ]; then
		waited=""
		read_result any && break
	fi
	if await_gate; then
		read_result any && break
	fi
	read_result && break
	mkdir "$gatedir/running" 2> /dev/null || continue
	echo "$$" > "$gatedir/running/pid"
	# The run writes its own result and frees the gate, so a hook stopped while
	# it runs leaves both to the next one; after the small lane's move to green
	# it takes the round's fresh snapshot too, or the next stop would count the
	# gate's Lock and phase as the round's.
	(
		cd "$worktree" || exit 1
		gate_out="$(bash "$core/hooks/editor-gate.sh" 2> /dev/null)"
		gate_status=$?
		if [ "$gate_status" = 3 ] && [ -n "$snap" ]; then
			round snapshot 2> /dev/null || rm -f "$snap"
		fi
		{ printf '%s\n%s\n' "$key" "$gate_status" && printf '%s\n' "$gate_out"; } > "$gatedir/result.$BASHPID" &&
			mv -f "$gatedir/result.$BASHPID" "$gatedir/result"
		rm -rf "$gatedir/running"
	) < /dev/null > /dev/null 2>&1 &
	run=$!
	{ echo "$run" > "$gatedir/running/pid"; } 2> /dev/null
	wait "$run"
	read_result any || {
		status=1
		out="editor-sonnet stop hook: the gate left no result in $gatedir; run it again by stopping again"
	}
	break
done
if [ -z "$status" ]; then
	status=1
	out="editor-sonnet stop hook: the gate stayed busy in $worktree; stop again to run it"
fi

case "$status" in
	0)
		# The result line the final message must quote.
		verdict="$(printf '%s\n' "$out" | grep -E '^(verify|baseline): ' | tail -n 1)"
		line="${verdict:-gate: PASS} at $(git -C "$worktree" rev-parse --short HEAD)"
		if [ ! -e "$counter.survivors" ] && [ "$(printf '%s\n' "$key" | cut -d ' ' -f 2)" = green ]; then
			list="$(survivors)"
			if [ -n "$list" ]; then
				mkdir -p "$(dirname "$counter")" && : > "$counter.survivors"
				rm -f "$counter" "$counter.why"
				{
					echo "The gate is green, but its mutate step left these mutants no test caught ($(survivors path)); this list is shown once. Kill each with a test that fails on it, commit, then stop again; or say in your final message why it can't be killed. Your final message still quotes the gate's result line, $line, as the gate gives it then:"
					printf '%s\n' "$list"
				} >&2
				exit 2
			fi
		fi
		case "$message" in
			*"$line"*)
				rm -f "$counter" "$counter.why" "$snap"
				# A green stop says only what left the round uncompared, not a remote
				# that could not be reached, which a project with no remote always has.
				[ -z "$notes" ] || printf '%s\n' "$notes" | grep -v '^round compare: .* could not be reached, ' >&2
				release
				;;
		esac
		counted quote
		{
			echo "The gate is green, but your final message doesn't quote its result (block $count of $limit). End again with your final message quoting this line as it stands:"
			printf '%s\n' "$line"
		} >&2
		exit 2
		;;
	3)
		rm -f "$counter" "$counter.why"
		printf '%s\n' "$out" | tail -n +2 >&2
		exit 2
		;;
esac

counted red
{
	echo "The gate is red (block $count of $limit). Fix these findings in $worktree, commit, then stop again:"
	printf '%s\n' "$out"
	[ -z "$notes" ] || printf '%s\n' "$notes"
} >&2
exit 2
