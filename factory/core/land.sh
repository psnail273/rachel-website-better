#!/usr/bin/env bash
# Land an issue's branch on dev (FACTORY_BASE_BRANCH, lib/run.sh). Run from the
# main checkout or any worktree of the repo (not from inside the issue's
# worktree: it is removed at the end):
#   bash factory/core/land.sh <n>
#
# In the issue's worktree (start.sh made it), with a clean tree:
#   1. fetch origin and rebase issue/<n> onto origin/dev. On a conflict it aborts
#      the rebase, lists the conflicting files and exits 3: an uncounted round for
#      the Editor. The branch, its worktree and dev are as they were.
#   2. refuse a branch that changes the gate's own code or config (factory/,
#      tools/verify/ but its ratchet files, the hook config: factory_gate_changes
#      in lib/protect.sh), since the verify below runs the branch's own copy of
#      the gate and would grade itself. Only an amend may: when the brief the
#      Driver sealed says Kind amend, it names those files and goes on. Otherwise
#      it exits 1 naming them; dev is not moved. This check runs from the copy of
#      land.sh invoked, so run it from the main checkout.
#      Then run the full verify (tools/verify.sh) on the rebased branch. Red exits 1
#      with the verdict; dev is not moved. In Partial mode (run state phase
#      partial) it runs `baseline.sh gate` instead: the project still has
#      Baseline findings, so the full verify stays red until the Baseline is
#      empty. The Driver has already committed `baseline.sh shrink`.
#      The gate runs with FACTORY_LAND=<n>, so verify skips its mutate step
#      (lib/mutate.sh): no Verifier reads the survivors after Land. Every other
#      step runs.
#      The gate's stdout, its verdict, is printed indented: verify's line per step
#      and its last line, or baseline.sh's verdict in Partial mode. The steps' own
#      output (an engine's and a test runner's, often hundreds of KB) goes to the
#      log <common git dir>/factory/land-<n>.log, the main checkout's
#      .git/factory/, which outlives the worktree. Each Land rewrites it: a header
#      line, the steps' output, then the gate's exit code and its verdict. On a
#      red gate it also prints the path and the failing step's last
#      LAND_TAIL_LINES lines of output, with no CR or terminal colour codes: the
#      output between the runner's marks for that step and the next. The gate
#      runs with FACTORY_STEP_MARK set to a mark no step sees, so verify writes
#      `<mark> <step>` on stderr before each step and `<mark>` after the last
#      (verify.sh); Land takes those lines out on the way to the log and keeps
#      their offsets, so the bounds are exact and no text a step prints moves
#      them. With no `== <step> FAIL` line (Partial mode), or no mark for that
#      step (a runner that writes none), it prints the last lines of all the
#      steps' output instead.
#   3. push the rebased head to origin/dev. A push is a fast-forward or nothing,
#      so if origin/dev moved meanwhile it exits 1 and a rerun starts over.
#      #80 lists "fast-forward dev, push"; pushing first is deliberate: a
#      refused push leaves local dev untouched, so nothing is half-landed.
#   4. fast-forward the local dev to it (when dev is checked out, only in the
#      main checkout, and only by a fast-forward; otherwise it says why it left
#      dev alone).
#   5. print the Run's state and its `factory-stats:` line (both for the close
#      comment, which ends with that line as printed: retro.sh totals it), then
#      remove the worktree and delete the branch, which drops its run state. The
#      line's minutes run from start.sh to now, the landing (factory_stats_line,
#      lib/run.sh); now is FACTORY_NOW when that is a whole number of seconds
#      since the epoch (a test's clock), else the system clock.
#
# stdout is the outcome (`land: ...` lines, the gate's verdict, the state and the
# stats line); git's own output goes to stderr, and the gate's to the log.
# Exit codes: 0 landed, 1 not landed (or landed but cleanup failed: it says
# which), 2 usage, 3 rebase conflict.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/run.sh"
. "$core/lib/protect.sh"

say() { echo "land: $*"; }
die() {
	say "$*"
	exit 1
}

# How many of the steps' last lines a red gate prints.
LAND_TAIL_LINES=20

[ "$#" -eq 1 ] && factory_is_issue "$1" || {
	echo "usage: bash factory/core/land.sh <issue number>" >&2
	exit 2
}
n="$1"

main="$(factory_main_checkout)" || die "not inside a git repo"
branch="$(factory_issue_branch "$n")"
wt="$(factory_issue_worktree "$main" "$n")"
remote_ref="refs/remotes/$FACTORY_REMOTE/$FACTORY_BASE_BRANCH"

[ -e "$wt/.git" ] || die "no worktree $wt; start.sh makes it"
cd "$wt" || die "cannot enter $wt"
[ "$(factory_current_branch)" = "$branch" ] || die "$wt is not on branch $branch"
[ -z "$(git status --porcelain)" ] || die "$wt has uncommitted changes; commit or drop them first"

# 1. Rebase.
git fetch "$FACTORY_REMOTE" "$FACTORY_BASE_BRANCH" >&2 || die "could not fetch $FACTORY_BASE_BRANCH from $FACTORY_REMOTE"
if ! git rebase "$remote_ref" >&2; then
	conflicts="$(git diff --name-only --diff-filter=U)"
	git rebase --abort >&2 2> /dev/null
	say "rebase conflict onto $FACTORY_REMOTE/$FACTORY_BASE_BRANCH (an uncounted round); rebase aborted, $FACTORY_BASE_BRANCH not moved"
	[ -n "$conflicts" ] && printf '%s\n' "$conflicts" | sed 's/^/  conflict: /'
	exit 3
fi
head="$(git rev-parse HEAD)" || die "no HEAD after the rebase"

# 2. The gate's own files: only an amend changes them.
gate_files="$(factory_gate_changes "$remote_ref")" || die "could not list the files the branch changed"
if [ -n "$gate_files" ]; then
	if [ "$(factory_brief_sealed_kind "$(factory_brief_path)")" = amend ]; then
		say "this amend changes the gate's own files:"
		printf '%s\n' "$gate_files" | sed 's/^/  gate: /'
	else
		say "the branch changes the gate's own files, which only an amend (a sealed Kind amend brief) may; $FACTORY_BASE_BRANCH not moved"
		printf '%s\n' "$gate_files" | sed 's/^/  gate: /'
		exit 1
	fi
fi

# Full verify on the rebased branch; in Partial mode, the Baseline gate
# (lib/run.sh picks it from the phase). Nothing lands on the red gate: it passes
# while the brief's new tests fail, so every phase but partial gets the full verify.
phase="$(factory_state_get "$branch" phase 2> /dev/null)" || phase=""
[ "$phase" = partial ] || phase=green
gate="$(factory_gate_name "$phase")"
tmp="$(mktemp -d)" || die "could not make a temp folder; $FACTORY_BASE_BRANCH not moved"
trap 'rm -rf "$tmp"' EXIT
log="$(git rev-parse --path-format=absolute --git-common-dir)/factory/land-$n.log" || die "no git dir for the log"
mkdir -p "${log%/*}" && printf 'land.sh %s: %s, on %s at %s\n' "$n" "$gate" "$branch" "$head" 2> /dev/null > "$log" ||
	die "cannot write the log $log; $FACTORY_BASE_BRANCH not moved"
# The gate's stdout is the verdict; its stderr, the steps' output, goes to the
# log line by line through awk, which takes out the runner's mark lines (a mark
# glued to a line a step left unended splits off it) and writes each one's
# offset in the log to $tmp/marks: `<offset> <step>` where that step's output
# starts, `<offset>` where the steps' output ends. Its offsets count the bytes
# it wrote, so they are line boundaries of the log.
start=$(($(wc -c < "$log")))
mark="land.sh-mark-$(od -An -N8 -tx1 /dev/urandom 2> /dev/null | tr -d ' \n')$RANDOM$RANDOM$$"
verdict="$(
	{
		FACTORY_LAND="$n" FACTORY_STEP_MARK="$mark" factory_gate "$phase" tools/verify.sh 2>&1 1>&3 3>&- |
			LC_ALL=C awk -v mark="$mark" -v pos="$start" -v marks="$tmp/marks" '
				{
					i = index($0, mark)
					rest = i ? substr($0, i + length(mark)) : ""
					if (i == 0 || (rest != "" && rest !~ /^ [A-Za-z0-9_-]+$/)) {
						printf "%s\n", $0
						pos += length($0) + 1
					} else {
						if (i > 1) {
							printf "%s", substr($0, 1, i - 1)
							pos += i - 1
						}
						print pos rest > marks
					}
					fflush()
				}
				END { close(marks) }
			' >> "$log" 3>&-
		exit "${PIPESTATUS[0]}"
	} 3>&1
)"
verify_status=$?
end=$(($(wc -c < "$log")))
# The failing step's output: from its mark to the next one (or the steps'
# end). With no `== <step> FAIL` line, or no mark for that step, the steps'
# whole output.
failed="$(printf '%s\n' "$verdict" | sed -n 's/^verify: FAILED at step \([^ ]*\)$/\1/p' | tail -n 1)"
printf '%s\n' "$verdict" | grep -qxF -- "== $failed FAIL" || failed=""
from=$start to=$end bounds=""
if [ -n "$failed" ] && [ -f "$tmp/marks" ]; then
	bounds="$(awk -v want="$failed" -v end="$end" '
		NF == 2 && $2 == want { from = $1; to = ""; found = 1; next }
		found && to == "" { to = $1 }
		END { if (found) print from, (to == "" ? end : to) }
	' "$tmp/marks")"
	[ -z "$bounds" ] || read -r from to <<< "$bounds"
fi
[ "$to" -ge "$from" ] 2> /dev/null || { from=$start to=$end bounds=""; }
steps_tail="$(tail -c +"$((from + 1))" "$log" | head -c "$((to - from))" | tail -n "$LAND_TAIL_LINES" |
	tr -d '\r' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | cut -c 1-300)"
# shellcheck disable=SC2094 # the group appends to the log; tail only reads its last byte first
{
	[ -z "$(tail -c 1 "$log")" ] || printf '\n'
	printf 'land.sh: the gate exited %s; its verdict:\n' "$verify_status"
	[ -z "$verdict" ] || printf '%s\n' "$verdict"
} >> "$log"
if [ "$verify_status" -ne 0 ]; then
	say "${gate%% (*} is red on the rebased branch; $FACTORY_BASE_BRANCH not moved"
	[ -n "$verdict" ] && printf '%s\n' "$verdict" | sed 's/^/  /'
	what="the steps"
	[ -z "$bounds" ] || what="the failing step, $failed,"
	if [ -n "$steps_tail" ]; then
		say "the last lines $what printed, of the whole output in $log:"
		printf '%s\n' "$steps_tail" | sed 's/^/  | /'
	else
		say "$what printed nothing else; the log is $log"
	fi
	exit 1
fi
say "${gate%% (*} passed on the rebased branch; the steps' output is in $log"
[ -n "$verdict" ] && printf '%s\n' "$verdict" | sed 's/^/  /'

# 3. Push: a fast-forward of origin/dev, or nothing.
if ! git push "$FACTORY_REMOTE" "$head:refs/heads/$FACTORY_BASE_BRANCH" >&2; then
	die "push to $FACTORY_REMOTE/$FACTORY_BASE_BRANCH refused (did it move?); $FACTORY_BASE_BRANCH not moved, rerun land.sh"
fi
say "landed $branch on $FACTORY_REMOTE/$FACTORY_BASE_BRANCH at $head"

# 4. Fast-forward the local dev.
cd "$main" || die "cannot enter the main checkout $main"
base_ref="refs/heads/$FACTORY_BASE_BRANCH"
if ! git show-ref --verify --quiet "$base_ref"; then
	say "no local $FACTORY_BASE_BRANCH to fast-forward"
elif ! git merge-base --is-ancestor "$base_ref" "$head"; then
	say "local $FACTORY_BASE_BRANCH has commits $FACTORY_REMOTE does not; left it alone"
elif [ "$(factory_current_branch)" = "$FACTORY_BASE_BRANCH" ]; then
	git merge --ff-only -q "$head" >&2 || say "could not fast-forward the main checkout's $FACTORY_BASE_BRANCH; left it alone"
elif git worktree list --porcelain | grep -qxF "branch $base_ref"; then
	say "$FACTORY_BASE_BRANCH is checked out in another worktree; left it alone"
else
	git update-ref "$base_ref" "$head" || say "could not fast-forward local $FACTORY_BASE_BRANCH; left it alone"
fi

# 5. Report the run state, then clean up.
factory_state_list "$branch" | sed 's/^/  state: /'
factory_stats_line "$branch" "$n"
cleanup=0
git worktree remove "$wt" >&2 || {
	say "could not remove the worktree $wt"
	cleanup=1
}
git branch -D "$branch" >&2 || {
	say "could not delete the branch $branch"
	cleanup=1
}
[ "$cleanup" -eq 0 ] || exit 1
say "removed $wt and $branch"
