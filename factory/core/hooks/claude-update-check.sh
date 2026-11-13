#!/usr/bin/env bash
# The session-start update check (Claude Code). claude-hooks.json wires it to
# SessionStart; it runs in the project at $CLAUDE_PROJECT_DIR (else the current
# folder's checkout).
#
# At most once per FACTORY_UPDATE_CHECK_EVERY seconds (a day by default) per
# checkout, it runs this Core's `sync.sh check`. The time of the last check is the
# stamp <git common dir>/factory/update-check, written before the check runs,
# whatever its result, so an offline machine doesn't retry every session.
#
# When the factory's repo has a newer release:
#   - a patch release (the project's major.minor, a greater patch) syncs itself,
#     when no issue is in flight (no .claude/worktrees/issue-* in the main
#     checkout, and no worktree on an issue/<n> branch) and the
#     session is in the main checkout, on the base branch
#     ($FACTORY_BASE_BRANCH, dev by default), with a clean tree. The sync runs in
#     the background, detached, so the session never waits: `sync.sh <release>`,
#     then a commit on the base branch, "Sync factory <new> (from <old>)". Its log
#     is <git common dir>/factory/update-sync.log, whose last line starts
#     `update-check: synced` or `update-check: failed`. The hook prints
#     SessionStart JSON whose additionalContext tells the session to say so in
#     one line ("factory synced <old> → <new> (patch); push dev so new issues
#     get it": the commit is local, and issues are cut from origin's base
#     branch) and to read that log line before its first commit.
#   - any other release (a minor or a major), or a patch one of the conditions
#     above holds back, prints SessionStart JSON whose additionalContext tells the
#     session to ask the human whether to sync it in (and, for a held-back patch,
#     why it did not sync itself).
#
# It prints nothing and exits 0 on a current factory, on any failure, without an
# upstream and outside an adopted project. It never blocks a session: the check's
# network call is bounded (sync.sh), and the whole check is too, to
# FACTORY_UPDATE_CHECK_TIMEOUT seconds (12 by default; a value that is not a
# positive whole number means 12). A check that runs out says nothing.
#
# The whole hook is one function, read whole before it runs, since a sync
# rewrites factory/, this file among it.
#
# Exit code: always 0.
set -u

# say_context <text>: the SessionStart JSON that hands the session <text>.
say_context() {
	printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(factory_json_string "$1")"
}

# is_patch <release> <version>: true when v<release> has <version>'s major and
# minor (the check already said it is greater, so its patch is).
is_patch() {
	local r="${1#v}"
	[ "${r%.*}" = "${2%.*}" ] && [[ $2 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# held_back: why a patch release can't sync itself here, on stdout; nothing when
# it can. Run from the checkout's top.
held_back() {
	local main="" line wt branch base="${FACTORY_BASE_BRANCH:-dev}"
	while IFS= read -r line; do
		case "$line" in
			"worktree "*) [ -n "$main" ] || main="${line#worktree }" ;;
			"branch refs/heads/issue/"*)
				echo "an issue is in flight (the branch ${line#branch refs/heads/})"
				return
				;;
		esac
	done < <(git worktree list --porcelain 2> /dev/null)
	for wt in "$main"/.claude/worktrees/issue-*; do
		if [ -n "$main" ] && [ -e "$wt" ]; then
			echo "an issue is in flight (.claude/worktrees/${wt##*/})"
			return
		fi
	done
	if [ -z "$main" ] || [ "$(cd "$main" 2> /dev/null && pwd -P)" != "$(pwd -P)" ]; then
		echo "this session is not in the main checkout"
		return
	fi
	branch="$(git symbolic-ref -q --short HEAD 2> /dev/null)" || branch=""
	if [ "$branch" != "$base" ]; then
		echo "the main checkout is on ${branch:-a detached HEAD}, not $base"
		return
	fi
	[ -z "$(git status --porcelain 2> /dev/null)" ] || echo "the tree is dirty"
}

# auto_sync <release> <version>: sync to <release> and commit it on the base
# branch, logging to stdout; the last line says how it ended.
auto_sync() {
	local release="$1" version="$2" port
	echo "update-check: syncing $release (from $version), $(date)"
	if ! port="$(bash "$core/sync.sh" "$release")"; then
		[ -z "$port" ] || printf '%s\n' "$port"
		echo "update-check: failed: sync.sh $release refused or failed (above), so nothing was committed; see git status, and sync by hand with the human's yes"
		return 1
	fi
	if ! git commit -q -m "Sync factory ${release#v} (from $version)"; then
		[ -z "$port" ] || printf '%s\n' "$port"
		echo "update-check: failed: the sync to $release is staged but its commit failed (above); review it with the human, then commit it or drop it (git reset --hard HEAD)"
		return 1
	fi
	if [ -n "$port" ]; then
		printf '%s\n' "$port"
		echo "update-check: synced $release (from $version) and committed it as $(git rev-parse --short HEAD); its adapter templates changed too: port the diff above into tools/verify/ by hand"
	else
		echo "update-check: synced $release (from $version) and committed it as $(git rev-parse --short HEAD)"
	fi
}

main() {
	core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	. "$core/lib/json.sh"
	. "$core/lib/bounded.sh"
	local every limit top common stamp now last result release version why log message
	every="${FACTORY_UPDATE_CHECK_EVERY:-86400}"
	limit="${FACTORY_UPDATE_CHECK_TIMEOUT:-12}"
	case "$limit" in '' | *[!0-9]*) limit=12 ;; esac
	case "$limit" in *[1-9]*) ;; *) limit=12 ;; esac

	cd "${CLAUDE_PROJECT_DIR:-.}" 2> /dev/null || return 0
	top="$(git rev-parse --show-toplevel 2> /dev/null)" || return 0
	cd "$top" || return 0
	[ -f tools/verify/factory-version ] || return 0

	common="$(git rev-parse --git-common-dir 2> /dev/null)" || return 0
	common="$(cd "$common" 2> /dev/null && pwd)" || return 0
	stamp="$common/factory/update-check"
	now="$(date +%s)"
	last="$(tr -dc '0-9' 2> /dev/null < "$stamp")" || last=""
	[ "${#last}" -le 12 ] || last=""
	case "$every" in '' | *[!0-9]*) every=86400 ;; esac
	if [ -n "$last" ] && [ "$((10#$last))" -le "$now" ] && [ "$((now - 10#$last))" -lt "$((10#$every))" ]; then
		return 0
	fi
	mkdir -p "$(dirname "$stamp")" 2> /dev/null && printf '%s\n' "$now" > "$stamp" 2> /dev/null

	result="$(factory_run_bounded "$limit" bash "$core/sync.sh" check < /dev/null 2> /dev/null)" || return 0
	case "$result" in
		"newer v"*" (on "*")") ;;
		*) return 0 ;;
	esac
	release="${result#newer }"
	release="${release%% *}"
	version="${result##*(on }"
	version="${version%)}"

	message="The factory repo has a newer release, $release; this project is on $version. Ask the human whether to pull it in now with \`bash factory/core/sync.sh $release\` (or \`sync.sh latest\`). Sync only with their yes, and not while an issue is mid-Run: between issues. After a sync, review the staged diff, port any adapter-template diff it printed into tools/verify/ by hand, run \`bash tools/verify.sh\`, and commit."
	if is_patch "$release" "$version"; then
		why="$(held_back)"
		if [ -n "$why" ]; then
			say_context "$message It is a patch release, which syncs itself at a session's start, but not this time: $why."
			return 0
		fi
		log="$common/factory/update-sync.log"
		(
			trap '' HUP
			auto_sync "$release" "$version"
		) > "$log" 2>&1 < /dev/null &
		disown
		say_context "The factory repo has a newer patch release, $release; this project is on $version. Patch releases sync without asking, so this session's start is syncing it in the background and committing it on ${FACTORY_BASE_BRANCH:-dev} as \"Sync factory ${release#v} (from $version)\". That commit stays local, so new issues, cut from origin/${FACTORY_BASE_BRANCH:-dev}, get it only once ${FACTORY_BASE_BRANCH:-dev} is pushed. Tell the human so now in this one line: \"factory synced $version → ${release#v} (patch); push ${FACTORY_BASE_BRANCH:-dev} so new issues get it\". Before your first commit, read the last line of $log: \`update-check: synced\` means done (and says whether an adapter-template diff needs porting into tools/verify/); \`update-check: failed\` says why: tell the human that the sync failed after all, and the sync is then their call."
		return 0
	fi
	say_context "$message"
	return 0
}

# One compound command, parsed whole before it runs, so nothing after it is read
# from a file a sync may have rewritten.
{
	main "$@"
	exit 0
}
