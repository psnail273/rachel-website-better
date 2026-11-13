#!/usr/bin/env bash
# Read and set a Run's state: the issue branch's git config (keys in lib/run.sh).
# Run from the main checkout or any worktree of the repo:
#   bash factory/core/state.sh get <key>            print it; exit 1 when unset
#   bash factory/core/state.sh set <key> <value>   (phase: once the brief is sealed)
#   bash factory/core/state.sh incr <count>         add one (unset is 0); print the new count
#                                                  (rounds-<phase>: refused at the ceiling of 4)
#   bash factory/core/state.sh unset <key>
#   bash factory/core/state.sh list                 every key=value, sorted
#   bash factory/core/state.sh stats                its factory-stats line (retro.sh)
#   bash factory/core/state.sh --branch <b> <command> ...   another branch's state
#   bash factory/core/state.sh --issue <n> <command> ...    issue <n>'s branch
# Without --branch or --issue it uses the checked-out branch. The counts are
# rounds-<phase>, fails-<phase>, fails-brief, rejected, uncounted, escalations,
# self-ruled and lifts, and the gate's (gate-runs, caught-<step>, seconds-<step>),
# which verify.sh keeps (lib/run.sh). A phase's counted rounds stop at the ceiling
# of 4 (FACTORY_ROUNDS_CEILING): incr refuses a 5th and leaves the count as it was,
# since past it comes the Sonnet Takeover or an escalation (factory-run's SKILL.md).
# The lane is the sealed brief's: brief.sh seal sets it, not set.
# set phase also records when the branch first entered that phase (began-<phase>),
# which the stats line's minutes read; stats counts them up to now. Now is
# FACTORY_NOW when that is a whole number of seconds since the epoch (a test's
# clock), else the system clock.
#
# Exit codes: 0 ok, 1 unset (get), a phase set before the brief is sealed, a
# round past the ceiling (incr), or a git failure, 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/run.sh"

usage() {
	sed -n '2,21s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
	exit 2
}

branch=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--branch)
			[ "$#" -ge 2 ] || usage
			branch="$2"
			shift 2
			;;
		--issue)
			[ "$#" -ge 2 ] && factory_is_issue "$2" || usage
			branch="$(factory_issue_branch "$2")"
			shift 2
			;;
		-h | --help) usage ;;
		*) break ;;
	esac
done
[ "$#" -ge 1 ] || usage
cmd="$1"
shift

if [ -z "$branch" ]; then
	branch="$(factory_current_branch)" || {
		echo "state: HEAD is detached; pass --branch or --issue" >&2
		exit 2
	}
fi

need_key() {
	[ "$#" -ge 1 ] || usage
	factory_state_key_ok "$1" || {
		echo "state: unknown key '$1'" >&2
		exit 2
	}
}

case "$cmd" in
	get)
		[ "$#" -eq 1 ] || usage
		need_key "$1"
		factory_state_get "$branch" "$1"
		;;
	set)
		[ "$#" -eq 2 ] || usage
		need_key "$1"
		factory_state_value_ok "$1" "$2" || {
			echo "state: bad value for $1: '$2'" >&2
			exit 2
		}
		if [ "$1" = lane ]; then
			echo "state: the lane is the Build Brief's; add 'lane small' to its block and run bash factory/core/brief.sh seal" >&2
			exit 2
		fi
		if [ "$1" = phase ] && ! factory_state_get "$branch" brief-sha > /dev/null; then
			echo "state: $branch's Build Brief isn't sealed; run bash factory/core/brief.sh seal in its worktree first" >&2
			exit 1
		fi
		if [ "$1" = phase ]; then
			factory_state_set_phase "$branch" "$2"
		else
			factory_state_set "$branch" "$1" "$2"
		fi
		;;
	incr)
		[ "$#" -eq 1 ] || usage
		need_key "$1"
		factory_state_is_count "$1" || {
			echo "state: only a count counts up (rounds-<phase>, fails-<phase>, fails-brief, rejected, uncounted, escalations, self-ruled, lifts)" >&2
			exit 2
		}
		case "$1" in
			rounds-*)
				n="$(factory_state_get "$branch" "$1")" || n=0
				if [ "$n" -ge "$FACTORY_ROUNDS_CEILING" ]; then
					echo "state: $1 is at $n, the ceiling of $FACTORY_ROUNDS_CEILING counted rounds in a phase; send no more counted rounds: the next step is the Sonnet Takeover or an escalation (factory-run's SKILL.md, Driver's calls)" >&2
					exit 1
				fi
				;;
		esac
		factory_state_incr "$branch" "$1"
		;;
	unset)
		[ "$#" -eq 1 ] || usage
		need_key "$1"
		factory_state_unset "$branch" "$1"
		;;
	list)
		[ "$#" -eq 0 ] || usage
		factory_state_list "$branch"
		;;
	stats)
		[ "$#" -eq 0 ] || usage
		factory_is_issue "${branch#issue/}" && [ "$branch" = "$(factory_issue_branch "${branch#issue/}")" ] || {
			echo "state: stats needs an issue's branch (--issue <n>)" >&2
			exit 2
		}
		factory_stats_line "$branch" "${branch#issue/}"
		;;
	*)
		echo "state: unknown command '$cmd'" >&2
		usage
		;;
esac
