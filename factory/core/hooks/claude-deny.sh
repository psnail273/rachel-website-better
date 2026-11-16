#!/usr/bin/env bash
# The factory subagents' deny, a Claude Code PreToolUse hook (claude-hooks.json):
# it refuses the editor-sonnet subagent (the Sonnet Editor) and the asset-fetcher
# subagent, which reads downloaded files, a write to a protected path
# (lib/protect.sh), the Core's writing subcommands (baseline.sh shrink, record and
# add, brief.sh seal, hooks.sh generate, lock.sh record and lift, state.sh set,
# unset and incr, and land.sh) among them, and any read of the Scenario folder
# (factory_protect_reads: Read, Grep, Glob and the shell). It also refuses the
# Editor alone a Skill call that invokes frontend-design (a plugin-qualified or
# slash-prefixed name counts too): that skill is the design and Verifier roles'
# only (the #42 ruling); every other Skill call passes.
# Claude Code runs it before each tool call its matcher names, the read tools
# and Skill among them, with the call as JSON on stdin:
#   {"agent_type": "editor-sonnet", "cwd": "...", "tool_name": "Write",
#    "tool_input": {"file_path": "..."}, ...}
# By hand: bash factory/core/hooks/claude-deny.sh < call.json
#
# It acts only inside those two subagents. Claude Code puts the
# subagent's name in agent_type when a hook fires inside a subagent, and leaves
# agent_type out in the main session, so the Driver is never refused; a call that
# names neither subagent anywhere exits before the libs load, since the matcher
# sends every subagent's reads and Skill calls too.
#
# The call is checked by factory_protect_call, with relative paths
# taken from its cwd. The subagent works in an issue's worktree while Claude Code
# runs from the main checkout, so every worktree's protected paths count.
#
# A refusal exits 2 with the reason on stderr, which Claude Code hands the
# subagent. Otherwise it exits 0 with no output, and the call goes on to the
# normal permission flow. It refuses from adoption on, whatever the hook mode.
set -u

input="$(cat)"
# The main session's calls carry no agent_type: let them by before loading anything.
case "$input" in *'"agent_type"'*) ;; *) exit 0 ;; esac
# Nor do the other subagents', whose reads the matcher sends too.
case "$input" in *editor-sonnet* | *asset-fetcher*) ;; *) exit 0 ;; esac

core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# A lib that fails to load (a syntax error, or an unset variable under set -u,
# which ends the hook with an error the tool reads as no answer) would let every
# call by: on any failure or exit while loading, refuse every subagent call instead.
refuse_unloaded() {
	trap - EXIT
	echo "Refused: the factory deny hook could not load $core/lib/$lib.sh, so it refuses every call. Say so in your final message and stop." >&2
	exit 2
}
trap refuse_unloaded EXIT
for lib in steps findings brief diff run lock json scenarios protect; do
	# shellcheck disable=SC1090 # the Core's libs, by name
	. "$core/lib/$lib.sh" || refuse_unloaded
done
trap - EXIT

agent="$(printf '%s' "$input" | factory_json_get agent_type)"
case "$agent" in
	editor-sonnet | asset-fetcher) ;;
	*) exit 0 ;;
esac
# A Skill call reads and writes no path: it is checked for frontend-design alone,
# its name taken bare of a leading slash, a plugin or folder prefix ("x:") and
# any arguments after it.
if [ "$(printf '%s' "$input" | factory_json_get tool_name)" = Skill ]; then
	[ "$agent" = editor-sonnet ] || exit 0
	skill="$(printf '%s' "$input" | factory_json_get tool_input.skill)" || exit 0
	skill="${skill#"${skill%%[![:space:]]*}"}"
	skill="${skill%%[[:space:]]*}"
	skill="${skill#/}"
	skill="${skill##*:}"
	[ "${skill,,}" = frontend-design ] || exit 0
	echo "Refused: the frontend-design skill belongs to the design and Verifier roles, never the Editor's. Build to the brief and docs/design.md." >&2
	exit 2
fi
# shellcheck disable=SC2164 # best effort: a cwd that is gone leaves the hook where it started
cwd="$(printf '%s' "$input" | factory_json_get cwd)" && [ -n "$cwd" ] && cd "${cwd//\\//}" 2> /dev/null
factory_protect_call "$input"
[ -n "$PROTECT_DENIED" ] || exit 0

echo "Refused: the factory protects $PROTECT_DENIED. If the issue really needs this, say so in your final message and stop." >&2
exit 2
