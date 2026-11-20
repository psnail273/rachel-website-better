#!/usr/bin/env bash
# Read the Build Brief's fenced block (format: lib/brief.sh). Run from the project root:
#   bash factory/core/brief.sh check [brief]   print findings; exit 1 if the brief is malformed
#   bash factory/core/brief.sh seal [brief]    check it, then seal it: its hash goes in the
#                                              branch's run state (brief-sha), and its
#                                              lane (lane small, or none)
#   bash factory/core/brief.sh scope [brief]   the scope globs, one per line
#   bash factory/core/brief.sh tests [brief]   the test names, one per line
#   bash factory/core/brief.sh seams [brief]   the seams, `<path> <symbol>` per line
#   bash factory/core/brief.sh removes [brief] the Baseline entries it removes, one per line
#   bash factory/core/brief.sh grows [brief]   the accepted ratchet growth, `<file> <entry>` per line
#   bash factory/core/brief.sh invariants [brief]
#                                              the invariants, `<path> <symbol> <property>` per line
#   bash factory/core/brief.sh readers         the source readers: each test that reads
#                                              source files as text, and its reach,
#                                              `<test file> <path>` per line (a folder
#                                              ends in /); it reads no brief
#
# [brief] defaults to $FACTORY_BRIEF, else <git-dir>/factory/brief.md. The
# listings print nothing but the findings when the block is malformed, and exit 1.
# check and seal read the prose too (factory_brief_lint), once the block parses:
# the template's Kind line and sections, and that they agree with the block,
# each Constraint naming the test that pins it or `untested: <reason>` among
# them; a `lane small` brief's limits (factory_brief_lane_lint); a test-only
# brief's, Kind build in Phase green (factory_brief_test_only_lint); that each
# source reader whose reach a scope line covers is under Existing tests
# (factory_brief_readers_lint); and that `invariants` lines have their test file
# in scope, `<module>.invariants<test file ending>`, or where tests keep a
# folder of their own a test file named for invariants
# (factory_brief_invariants_lint).
#
# The source readers come from a text scan of the test files (lib/readers.sh
# names what it reads), for JavaScript and TypeScript tests: a test file that
# calls readFileSync, readFile, readdirSync, readdir, opendirSync, opendir,
# existsSync, statSync, lstatSync, createReadStream or globSync, or imports a
# file with `?raw`. Its reach is the files and folders it names: a join or
# resolve from import.meta.dirname, __dirname, process.cwd() or a literal path,
# a new URL(<path>, import.meta.url), a literal path, a `?raw` specifier; a join
# whose next part isn't a literal, as a directory walk like
# sourceFiles(srcDir) has, reaches the whole folder.
#
# seal runs in the issue's worktree, on its branch. The Driver seals the brief
# before the Editor's first round and again after every edit to it: state.sh
# refuses a phase until it is sealed, and the Editor's gate and the deviation
# step fail with brief-changed once it no longer matches its seal.
#
# Issues run in parallel only on scopes apart, so seal also refuses, with a
# brief-overlap finding, a scope line that may overlap one of another issue's
# that is in flight: an issue/<n> branch with a sealed brief in a worktree of
# this repo (factory_scope_overlap). The Driver's docs (FACTORY_DRIVER_DOCS in
# lib/brief.sh), which any issue may scope, don't count. Seal it again once that
# issue has landed. An issue in
# flight whose brief can't be read at its worktree's <git-dir>/factory/brief.md
# counts as an overlap too. Seals take turns, through a lock folder in the repo's
# shared git folder (factory-seal.lock), so two seals can't both miss each other;
# one waits up to $FACTORY_SEAL_WAIT seconds (default 10) for the other.
#
# Exit codes: 0 ok, 1 missing or malformed (or, for seal, no branch), 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/diff.sh"
. "$core/lib/run.sh"
. "$core/lib/lock.sh"
. "$core/lib/json.sh"
. "$core/lib/protect.sh"
. "$core/lib/readers.sh"

usage() {
	echo "usage: bash factory/core/brief.sh check|seal|scope|tests|seams|removes|grows|invariants [brief], or readers" >&2
	exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
what="$1"
if [ "$what" = readers ]; then
	[ "$#" -eq 1 ] || usage
	git rev-parse --is-inside-work-tree > /dev/null 2>&1 || {
		echo "brief: not in a git repository" >&2
		exit 1
	}
	factory_test_paths_load || exit 1
	factory_source_readers
	exit
fi
case "$what" in check | seal | scope | tests | seams | removes | grows | invariants) ;; *) usage ;; esac
if [ "$#" -eq 2 ]; then
	brief="$2"
else
	brief="$(factory_brief_path)" || {
		echo "brief: not in a git repository" >&2
		exit 1
	}
fi

# Parse in this shell (not a $(...) subshell) so the BRIEF_* arrays stay filled.
findings="$(mktemp)"
trap 'rm -f "$findings"' EXIT
if ! factory_brief_parse "$brief" > "$findings"; then
	factory_sort_findings < "$findings"
	exit 1
fi
case "$what" in check | seal)
	factory_brief_lint "$brief" > "$findings"
	lint=$?
	# The lane's and the test-only limits need the Kind and Phase the lint read.
	factory_brief_lane_lint "$brief" >> "$findings" || lint=1
	factory_brief_test_only_lint "$brief" >> "$findings" || lint=1
	factory_brief_readers_lint "$brief" >> "$findings" || lint=1
	factory_brief_invariants_lint "$brief" >> "$findings" || lint=1
	if [ "$lint" -ne 0 ]; then
		factory_sort_findings < "$findings"
		exit 1
	fi
	;;
esac

case "$what" in
	seal)
		branch="$(factory_current_branch)" || {
			echo "brief: HEAD is detached; seal on the issue's branch" >&2
			exit 1
		}
		seal_lock="$(git rev-parse --path-format=absolute --git-common-dir)/factory-seal.lock" || exit 1
		# The traps go first, so a signal any time after the lock is taken releases it.
		# While the seal takes it, a signal is only noted, and acted on once the lock
		# is marked held: one that landed between mkdir and locked=1 would otherwise
		# exit with the lock taken but not marked, and leave it behind. mkdir runs
		# deaf to them, so its exit code says only whether it made the lock (a Ctrl-C
		# reaches the whole process group, mkdir too).
		waited=0 locked=0 stopped=0
		trap 'rm -f "$findings"; [ "$locked" -eq 0 ] || rmdir "$seal_lock" 2> /dev/null' EXIT
		trap 'stopped=1' INT TERM HUP
		until (trap '' INT TERM HUP && exec mkdir "$seal_lock" 2> /dev/null) && locked=1; do
			[ "$stopped" -eq 0 ] || exit 1
			if [ "$waited" -ge "$((${FACTORY_SEAL_WAIT:-10} * 10))" ]; then
				echo "brief: another seal holds $seal_lock; seal again once it ends, or remove that folder if no seal is running" >&2
				exit 1
			fi
			sleep 0.1
			waited=$((waited + 1))
		done
		trap 'exit 1' INT TERM HUP
		[ "$stopped" -eq 0 ] || exit 1
		# Another issue in flight on an overlapping scope: wait for it to land.
		while IFS=$'\t' read -r other dir; do
			[ "$other" != "$branch" ] && factory_state_get "$other" brief-sha > /dev/null || continue
			other_brief="$(cd "$dir" 2> /dev/null && git rev-parse --path-format=absolute --git-dir)/factory/brief.md" || other_brief="$dir"
			# A malformed brief prints findings, not scope lines.
			if ! { [ -f "$other_brief" ] && other_scope="$(bash "$core/brief.sh" scope "$other_brief" 2> /dev/null)"; }; then
				factory_finding "$brief" 1 brief-overlap "$other is in flight but its brief can't be read at $other_brief, so its scope may overlap; seal this brief once it has landed"
				continue
			fi
			while IFS= read -r o; do
				o="${o%$'\r'}"
				! factory_is_driver_doc "$o" || continue
				for i in "${!BRIEF_SCOPE[@]}"; do
					! factory_is_driver_doc "${BRIEF_SCOPE[i]}" || continue
					factory_scope_overlap "${BRIEF_SCOPE[i]}" "$o" || continue
					factory_finding "$brief" "${BRIEF_SCOPE_LINES[i]}" brief-overlap "scope ${BRIEF_SCOPE[i]} may overlap $o, in the scope of ${other}, which is in flight; seal this brief once it has landed"
				done
			done <<< "$other_scope"
		done < <(git worktree list --porcelain 2> /dev/null | tr -d '\r' | awk '
			/^worktree / { dir = substr($0, 10) }
			/^branch refs\/heads\/issue\// { print substr($0, 19) "\t" dir }
		') > "$findings"
		if [ -s "$findings" ]; then
			factory_sort_findings < "$findings"
			exit 1
		fi
		sha="$(factory_brief_hash "$brief")" || exit 1
		factory_state_set "$branch" brief-sha "$sha" || exit 1
		if [ "$BRIEF_LANE" = small ]; then
			factory_state_set "$branch" lane small || exit 1
			echo "brief: sealed $brief for $branch at $sha, in the small lane"
		else
			factory_state_unset "$branch" lane || exit 1
			echo "brief: sealed $brief for $branch at $sha"
		fi
		;;
	scope) [ "${#BRIEF_SCOPE[@]}" -eq 0 ] || printf '%s\n' "${BRIEF_SCOPE[@]}" ;;
	tests) [ "${#BRIEF_TESTS[@]}" -eq 0 ] || printf '%s\n' "${BRIEF_TESTS[@]}" ;;
	seams) [ "${#BRIEF_SEAMS[@]}" -eq 0 ] || printf '%s\n' "${BRIEF_SEAMS[@]}" ;;
	removes) [ "${#BRIEF_REMOVES[@]}" -eq 0 ] || printf '%s\n' "${BRIEF_REMOVES[@]}" ;;
	grows) [ "${#BRIEF_GROWS[@]}" -eq 0 ] || printf '%s\n' "${BRIEF_GROWS[@]}" ;;
	invariants) [ "${#BRIEF_INVARIANTS[@]}" -eq 0 ] || printf '%s\n' "${BRIEF_INVARIANTS[@]}" ;;
esac
exit 0
