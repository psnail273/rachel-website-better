#!/usr/bin/env bash
# Start an issue's Run: its worktree and branch, the issue saved for prompt.sh,
# then the adapter's bootstrap. Run from the main checkout or any worktree of the
# repo:
#   <the issue's raw body> | bash factory/core/start.sh <n> --title <title>
#   bash factory/core/start.sh <n>      a resume that keeps the issue saved
#
# With --title it saves the issue, the line `#<n>: <title>`, then a blank line
# and the body read from stdin as it is (when it has one), ending in a newline,
# at the worktree's <git-dir>/factory/issue.md (making the folder), where
# prompt.sh reads it; a rerun with --title saves it again. The tracker is not one
# of the Core's seams, so start.sh never reads it: the Driver pipes in the body
# from the tracker doc's read command, and passes the title, for instance as
# --title "$(<the read command for the title>)". The title is one line, not
# blank. It reads stdin only with --title, and refuses a terminal there. Without
# --title it saves nothing and keeps any issue.md already there, and says on
# stderr when there is none.
#
# It creates .claude/worktrees/issue-<n> on branch issue/<n>, cut from the
# freshly fetched origin/dev (lib/run.sh names them). When the main checkout's
# tools/verify/scenario-folder names a Scenario folder (lib/scenarios.sh), the new
# worktree's checkout leaves that folder out (a non-cone sparse checkout of the
# worktree alone, `/*` and `!/<folder>/`), so a search of the worktree, the
# Editor's own indexing among them, never finds a Scenario; git still tracks the
# folder, and a rebase carries it. A worktree it reuses gets the same, once. It
# copies the main
# checkout's gitignored tools/verify/local.env into the worktree, then runs the
# project's tools/verify/bootstrap there: the only step of a Run with network
# access. A bootstrap holding the no-op marker is skipped. Then, on every start
# and resume, it runs the worktree's prepare (`bash tools/verify.sh prepare`,
# with FACTORY_NO_STAMP=1, so it keeps no gate stamp and counts no gate run), so
# the worktree's installed tools match its lock file before the Editor's first
# commit: the pre-commit hook and the first gate find them there (#21). A failing
# prepare fails start.sh, its output on stderr.
#
# Rerunning it resumes: an existing worktree or branch is reused, and a bootstrap
# that passed once (run state `bootstrap`) is not run again.
#
# When it makes the branch it records the time, the run state's `started`, which
# the stats line's minutes count from (lib/run.sh); a resume keeps it, and a
# branch made before start.sh recorded it stays without one. The time is
# FACTORY_NOW when that is a whole number of seconds since the epoch (a test's
# clock), else the system clock.
#
# stdout is the worktree's path and nothing else; progress goes to stderr.
# Exit codes: 0 ready, 1 a step failed (rerun to retry), 2 usage (a title that is
# blank or more than one line, or a terminal for the body, among them).
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/run.sh"
. "$core/lib/steps.sh"
. "$core/lib/scenarios.sh"

say() { echo "start: $*" >&2; }
die() {
	say "$*"
	exit 1
}

usage() {
	echo "usage: <the issue's raw body> | bash factory/core/start.sh <issue number> --title <title>" >&2
	echo "       bash factory/core/start.sh <issue number>" >&2
	exit 2
}
{ [ "$#" -eq 1 ] || { [ "$#" -eq 3 ] && [ "$2" = --title ]; }; } && factory_is_issue "$1" || usage
n="$1"
title=""
[ "$#" -eq 3 ] && title="${3%$'\r'}"

# The issue to save, read before anything changes: a bad title or body is a usage error.
tmp="$(mktemp -d)" || die "could not make a temp folder"
trap 'rm -rf "$tmp"' EXIT
if [ "$#" -eq 3 ]; then
	case "$title" in *$'\n'* | *$'\r'*)
		say "the title must be one line"
		usage
		;;
	esac
	[ -n "${title//[[:space:]]/}" ] || {
		say "the title is blank"
		usage
	}
	[ ! -t 0 ] || {
		say "pipe the issue's raw body into stdin"
		usage
	}
	cat > "$tmp/body" || die "could not read the issue's body from stdin"
	{
		printf '#%s: %s\n' "$n" "$title"
		if [ -s "$tmp/body" ]; then
			echo
			cat "$tmp/body"
			[ -z "$(tail -c 1 "$tmp/body")" ] || echo
		fi
	} > "$tmp/issue.md" || die "could not write the issue to a temp file"
fi

main="$(factory_main_checkout)" || die "not inside a git repo"
cd "$main" || die "cannot enter the main checkout $main"
branch="$(factory_issue_branch "$n")"
wt="$(factory_issue_worktree "$main" "$n")"

# add_worktree <git worktree add arguments...>: add the worktree, leaving the
# Scenario folder out of its checkout when the project names one.
scenarios="$(factory_scenario_folder)" || scenarios=""
add_worktree() {
	if [ -z "$scenarios" ]; then
		git worktree add "$@" >&2
		return
	fi
	git worktree add --no-checkout "$@" >&2 &&
		git -C "$wt" sparse-checkout set --no-cone '/*' "!/$scenarios/" >&2 &&
		git -C "$wt" checkout -q >&2
}

if [ -e "$wt/.git" ]; then
	say "reusing the worktree $wt"
	[ "$(git -C "$wt" symbolic-ref --short -q HEAD)" = "$branch" ] ||
		die "$wt is not on branch $branch"
	if [ -n "$scenarios" ] && [ "$(git -C "$wt" config --bool core.sparseCheckout)" != true ]; then
		git -C "$wt" sparse-checkout set --no-cone '/*' "!/$scenarios/" >&2 ||
			die "could not leave $scenarios/ out of $wt"
	fi
elif git show-ref --verify --quiet "refs/heads/$branch"; then
	say "reusing the branch $branch"
	add_worktree "$wt" "$branch" || die "could not add the worktree $wt"
else
	git fetch "$FACTORY_REMOTE" "$FACTORY_BASE_BRANCH" >&2 ||
		die "could not fetch $FACTORY_BASE_BRANCH from $FACTORY_REMOTE"
	add_worktree --no-track -b "$branch" "$wt" "refs/remotes/$FACTORY_REMOTE/$FACTORY_BASE_BRANCH" ||
		die "could not create the worktree $wt"
	factory_state_set "$branch" started "$(factory_now)" || die "could not record the run state"
fi
factory_state_set "$branch" issue "$n" || die "could not record the run state"

# The issue, for prompt.sh: saved with --title, else kept as it is.
issue="$(git -C "$wt" rev-parse --path-format=absolute --git-dir)/factory/issue.md" || die "no git dir for $wt"
if [ -s "$tmp/issue.md" ]; then
	mkdir -p "${issue%/*}" && cp "$tmp/issue.md" "$issue.tmp" && mv -f "$issue.tmp" "$issue" ||
		die "could not save the issue at $issue"
elif [ ! -s "$issue" ]; then
	say "no issue saved at $issue for prompt.sh: rerun with --title <title> and the issue's raw body on stdin"
fi

local_env="$FACTORY_STEPS_DIR/local.env"
if [ -f "$local_env" ] && [ ! -e "$wt/$local_env" ]; then
	mkdir -p "$wt/$FACTORY_STEPS_DIR" && cp "$local_env" "$wt/$local_env" ||
		die "could not copy $local_env into the worktree"
fi

if [ "$(factory_state_get "$branch" bootstrap)" != "done" ]; then
	cd "$wt" || die "cannot enter $wt"
	script="$FACTORY_STEPS_DIR/bootstrap"
	if [ ! -f "$script" ]; then
		die "no $script in the project; adopt the factory first"
	elif factory_step_is_noop "$script"; then
		say "bootstrap is a no-op"
	else
		say "running $script"
		(
			if [ -f "$local_env" ]; then
				set -a
				# shellcheck disable=SC1090
				. "./$local_env"
				set +a
			fi
			export FACTORY_CORE="$core"
			bash "$script" >&2
		) || die "$script failed; rerun start.sh to retry"
	fi
	factory_state_set "$branch" bootstrap "done" || die "could not record the run state"
fi

cd "$wt" || die "cannot enter $wt"
[ -f tools/verify.sh ] || die "no tools/verify.sh in the project; adopt the factory first"
say "running bash tools/verify.sh prepare"
FACTORY_NO_STAMP=1 bash tools/verify.sh prepare >&2 ||
	die "bash tools/verify.sh prepare failed in $wt (above); fix it, then rerun start.sh"

printf '%s\n' "$wt"
