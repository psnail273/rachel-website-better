#!/usr/bin/env bash
# A Run's relay (the build skill's parallel.md): read a driver's report and print
# exactly what the main session does with it, so it relays a `needs` report
# without reasoning about it. Run from the main checkout:
#   bash factory/core/relay.sh [<report-file>]   the report, or stdin without one
#
# It reads the report's one `outcome:` line. For
# `needs <subagent> <prompt file> <effort>`, <subagent> one of editor-sonnet,
# verifier and amend-builder, it prints
#   relay: agent
#   subagent_type: <subagent>
#   effort: <effort>
#   reply: factory-result: <subagent>
#   reply: factory-relay: <what it changed>     only when it changed the effort
#   prompt: <the prompt file's absolute path>
# and then the prompt file's text, unchanged: the Agent call's prompt. The reply
# lines head the SendMessage to the driver, the subagent's final message below
# them. A driver never asks for max: an effort of max runs at xhigh, and a report
# with no effort at medium, each said in a factory-relay reply line.
#
# A Verifier check changes nothing (the build skill's editor.md, Subagents), so for
# verifier it also takes the workspace's fingerprint, in the worktree the prompt's
# last line names (`factory-worktree: <path>`): HEAD, git status with untracked
# files and the diff against HEAD, kept in <its git dir>/factory/relay-before. It
# prints, above the prompt line,
#   after: bash <this script> after <the worktree>   (each path shell-quoted)
# for the main session to run once the check ends:
#   bash factory/core/relay.sh after <worktree>
# prints `relay: unchanged` when the fingerprint is the same, else
#   relay: void
#   reply: factory-relay: <why>: the check's verdict is void; restore the worktree ...
# a reply line to add below the first ones (a missing fingerprint is void too).
#
# Any other outcome (landed, escalated, waits-on <branch>, or needs <what> for a
# subagent the main session runs by itself, such as the asset subagent) prints
#   relay: main-session <the outcome>
# and is the main session's to handle, as parallel.md says.
#
# A report it can't read (no outcome line or two, a needs line with no prompt
# file, an effort it doesn't know, words past the effort, a prompt file that is
# missing or empty, a verifier's prompt with no worktree it can read) prints
#   relay: malformed
#   reply: factory-relay: <what is wrong>; report again
# for the main session to send back to the driver, and exits 1.
#
# Exit codes: 0 a relay, the main session's outcome or an after's verdict, 1
# malformed, 2 usage (a report file or worktree that can't be read).
set -u

usage() {
	sed -n '2,47s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
	exit 2
}

malformed() {
	printf 'relay: malformed\nreply: factory-relay: %s; report again\n' "$1"
	exit 1
}

# fingerprint <worktree>: what a Verifier check must leave as it was.
fingerprint() (
	set -o pipefail
	{
		git -C "$1" rev-parse HEAD &&
			git -C "$1" status --porcelain --untracked-files=all &&
			git -C "$1" diff HEAD --binary
	} | sha256sum | cut -d' ' -f1
)

# before_file <worktree>: where the fingerprint from before the check is kept.
before_file() {
	local gitdir
	gitdir="$(git -C "$1" rev-parse --absolute-git-dir 2> /dev/null)" || return 1
	printf '%s/factory/relay-before\n' "$gitdir"
}

void() {
	printf 'relay: void\nreply: factory-relay: %s: the check'"'"'s verdict is void (editor.md, Subagents); restore the worktree and run a fresh check, with no round counted\n' "$1"
	exit 0
}

if [ "${1:-}" = after ]; then
	[ "$#" -eq 2 ] || usage
	[ -d "$2" ] || void "no worktree $2"
	file="$(before_file "$2")" || void "$2 is no git worktree"
	[ -s "$file" ] || void "no fingerprint of $2 from before the check"
	before="$(cat "$file")"
	rm -f "$file"
	now="$(fingerprint "$2")" || void "could not read the workspace of $2"
	[ "$now" = "$before" ] || void "the check changed the workspace of $2 (HEAD, git status or the diff)"
	echo "relay: unchanged"
	exit 0
fi

case "$#" in
	0) report="$(cat)" ;;
	1)
		case "$1" in -h | --help) usage ;; esac
		[ -f "$1" ] && [ -r "$1" ] || {
			echo "relay: no report file $1" >&2
			usage
		}
		report="$(cat -- "$1")"
		;;
	*) usage ;;
esac

# The outcome line, without carriage returns, leading blanks or the key.
report="$(printf '%s\n' "$report" | tr -d '\r')"
count="$(printf '%s\n' "$report" | grep -c '^[[:space:]]*outcome:' || true)"
[ "$count" -ne 0 ] || malformed "the report has no outcome: line"
[ "$count" -eq 1 ] || malformed "the report has $count outcome: lines, not one"
outcomes="$(printf '%s\n' "$report" |
	sed -n 's/^[[:space:]]*outcome:[[:space:]]*//p' | sed 's/[[:space:]]*$//')"
[ -n "$outcomes" ] || malformed "the report's outcome: line is empty"

read -r -a words <<< "$outcomes"
case "${words[0]}" in
	needs) ;;
	*)
		printf 'relay: main-session %s\n' "$outcomes"
		exit 0
		;;
esac
subagent="${words[1]:-}"
case "$subagent" in
	editor-sonnet | verifier | amend-builder) ;;
	*)
		printf 'relay: main-session %s\n' "$outcomes"
		exit 0
		;;
esac

prompt="${words[2]:-}"
effort="${words[3]:-}"
[ "${#words[@]}" -le 4 ] || malformed "the needs line has words past its effort: $outcomes"
[ -n "$prompt" ] || malformed "the needs line names no prompt file: $outcomes"
note=""
case "$effort" in
	low | medium | high | xhigh) ;;
	max)
		effort=xhigh
		note="the report named effort max, which a driver never asks for: ran at xhigh"
		;;
	"")
		effort=medium
		note="the report named no effort: ran at medium"
		;;
	*) malformed "the needs line's effort $effort is none of low, medium, high, xhigh" ;;
esac
[ -f "$prompt" ] && [ -r "$prompt" ] || malformed "no prompt file $prompt"
[ -s "$prompt" ] || malformed "the prompt file $prompt is empty"
dir="$(cd "$(dirname -- "$prompt")" && pwd)" || malformed "no prompt file $prompt"
path="$dir/$(basename -- "$prompt")"

after=""
if [ "$subagent" = verifier ]; then
	worktree="$(tr -d '\r' < "$path" | sed -n 's/^factory-worktree:[[:space:]]*//p' | tail -n 1 | sed 's/[[:space:]]*$//')"
	[ -n "$worktree" ] || malformed "the prompt file $prompt has no factory-worktree: line"
	[ -d "$worktree" ] || malformed "the prompt file's worktree $worktree is no folder"
	file="$(before_file "$worktree")" || malformed "the prompt file's worktree $worktree is no git worktree"
	mkdir -p "$(dirname "$file")" && fingerprint "$worktree" > "$file.tmp" && mv "$file.tmp" "$file" ||
		malformed "could not take the fingerprint of $worktree"
	after="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/relay.sh"
	after="$(printf 'bash %q after %q' "$after" "$worktree")"
fi

printf 'relay: agent\nsubagent_type: %s\neffort: %s\nreply: factory-result: %s\n' \
	"$subagent" "$effort" "$subagent"
[ -z "$note" ] || printf 'reply: factory-relay: %s\n' "$note"
[ -z "$after" ] || printf 'after: %s\n' "$after"
printf 'prompt: %s\n' "$path"
cat -- "$path"
