#!/usr/bin/env bash
# The Lock (lib/lock.sh). Run from the issue's worktree, on its branch:
#   bash factory/core/lock.sh record   run the phase's gate fresh, then lock HEAD as the
#                                      red commit; print the locked files
#   bash factory/core/lock.sh files    the locked files, one per line
#   bash factory/core/lock.sh check    print a finding per locked file changed since; exit 1 on any
#   bash factory/core/lock.sh check --staged   the same for what is staged (the pre-commit hook)
#   bash factory/core/lock.sh lift     the green phase only: move the Lock, once per issue
#
# record needs a clean tree (the Lock is a commit) and a red commit that changes at
# least one test file. The Lock rests on a fresh verdict, never on one a gate
# stamp kept (lib/stamp.sh), so record first runs the gate of the run state's
# phase (factory_gate, lib/run.sh) itself, with no --reuse: the red gate
# (verify.sh --red) in the red phase, where the first Lock is recorded; the full
# verify in the green phase, where a lifted Lock is recorded again (after lift)
# over code that now passes. It locks only when that gate passes and
# leaves HEAD and the tracked files as they were. It overwrites an earlier Lock.
# The deviation step runs the same check as `check`.
#
# lift moves the Lock when a locked test is wrong, in any lane: the Driver's own
# call when the test contradicts the sealed brief, else on the human's yes
# (factory-run's SKILL.md, Driver's calls). A permission check may refuse it; the
# Driver then escalates and never moves the Lock another way. It needs the run
# state's phase green, a Lock, and lifts below FACTORY_LOCK_LIFTS (1): once per
# issue. It clears the Lock and counts a lift; after the fix round the Driver
# records the Lock again.
#
# Exit codes: 0 ok, 1 refused, no Lock (files) or a locked file changed (check), 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/diff.sh"
. "$core/lib/run.sh"
. "$core/lib/lock.sh"

usage() {
	echo "usage: bash factory/core/lock.sh record|files|lift|check [--staged]" >&2
	exit 2
}

to=HEAD
case "$#:${1:-}:${2:-}" in
	1:record: | 1:files: | 1:check: | 1:lift:) ;;
	2:check:--staged) to=:index ;;
	*) usage ;;
esac

branch="$(factory_current_branch)" || {
	echo "lock: HEAD is detached; check out the issue's branch" >&2
	exit 1
}
base="$(factory_diff_base)" || {
	echo "lock: no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}'; set FACTORY_BASE or FACTORY_BASE_BRANCH" >&2
	exit 1
}

findings="$(mktemp)"
trap 'rm -f "$findings"' EXIT

case "$1" in
	record)
		# The cheap refusals first, then the gate, then the same checks again on
		# what the gate left. An earlier Lock stays while the gate runs, so its
		# deviation step still fails a locked test changed since.
		factory_lock_record_check "$base" || exit 1
		head="$(git rev-parse HEAD)" || exit 1
		phase="$(factory_state_get "$branch" phase)" || phase=""
		echo "lock: running $(factory_gate_name "$phase") fresh at $(git rev-parse --short HEAD)" >&2
		factory_gate "$phase" "$core/verify.sh" > "$findings" 2> /dev/null
		gate=$?
		if [ "$gate" -ne 0 ]; then
			echo "lock: that gate fails at $(git rev-parse --short HEAD), so nothing is locked:" >&2
			tr -d '\r' < "$findings" >&2
			exit 1
		fi
		if [ "$(git rev-parse HEAD)" != "$head" ]; then
			echo "lock: HEAD moved while the gate ran; record the Lock again" >&2
			exit 1
		fi
		factory_lock_record "$branch" "$base" || exit 1
		;;
	lift)
		if [ "$(factory_state_get "$branch" phase)" != green ]; then
			echo "lock: lift comes in the green phase, once a locked test proves wrong" >&2
			exit 1
		fi
		red="$(factory_lock_red_commit)" || {
			echo "lock: no Lock on $branch to lift" >&2
			exit 1
		}
		lifts="$(factory_state_get "$branch" lifts)" || lifts=0
		if [ "$lifts" -ge "$FACTORY_LOCK_LIFTS" ]; then
			echo "lock: this issue's Lock moved $lifts time(s) already, the most it may (once per issue); a second wrong locked test escalates" >&2
			exit 1
		fi
		factory_state_unset "$branch" red-commit || exit 1
		factory_state_incr "$branch" lifts > /dev/null || exit 1
		echo "lock: lifted the Lock at $(git rev-parse --short "$red" 2> /dev/null || echo "$red"); after the fix round, record it again with lock.sh record"
		;;
	files)
		red="$(factory_lock_red_commit)" || {
			echo "lock: no Lock on $branch" >&2
			exit 1
		}
		factory_test_paths_load > "$findings" || {
			cat "$findings"
			exit 1
		}
		factory_lock_files "$red" "$base"
		;;
	check)
		factory_lock_check "$base" "$to" > "$findings"
		status=$?
		factory_sort_findings < "$findings"
		exit "$status"
		;;
esac
