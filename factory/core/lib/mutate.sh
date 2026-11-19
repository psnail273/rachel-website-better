# The mutate step's Seam: when the step runs, and the survivors file it writes.
# Sourced by verify.sh (needs steps.sh, diff.sh and run.sh); defines no side
# effects.
#
# mutate is an optional step (steps.sh): an adapter's mutation tester, run on the
# lines an issue's Green phase changed, whose surviving mutants go to the
# Verifier. No score gates anything: the step passes with survivors, and fails
# only when it can't run. The runner runs its script only when all of these hold,
# and otherwise reports `== mutate SKIP`, with the reason on stderr:
#   - the run isn't --red, and no earlier step of it failed (--keep-going);
#   - it isn't Land's verify: land.sh sets FACTORY_LAND (the issue's number)
#     for the verify it runs before it lands, and no Verifier reads survivors
#     after Land;
#   - the checked-out branch's run state has phase green (lib/run.sh);
#   - there is a diff base (lib/diff.sh: the deviation step's), and the working
#     tree differs from it: a tracked change, or a file git doesn't ignore.
# So it mutates nothing in the red or partial phase, off an issue's branch (no
# run state), on an empty diff (amend.sh land's FACTORY_BASE=HEAD verify), or in
# Land's verify; any other verify of a green issue branch with a change (the
# Editor's gate, the Driver's, the Verifier's) runs it. FACTORY_LAND is in the
# gate stamp's key (lib/stamp.sh), so no `verify.sh --reuse` without it takes
# Land's verdict, which mutated nothing, for its own.
# The script gets FACTORY_MUTATE_BASE, the base's commit, and mutates only the
# lines the working tree changed since then.
#
# The survivors file is $FACTORY_SURVIVORS_FILE: <git-dir>/factory/survivors.txt,
# beside the Build Brief, unless the caller set it. Each run whose steps include
# mutate removes it first, so after a run it is there only when the script ran;
# a script that passes without writing it fails the step (survivors-missing).
# The adapter writes:
#   # <a note: the tool and what it mutated>
#   # killed <n>, survived <n>, errored <n>, timed out <n>[, <more counts>]
#   <file>:<line> <status> <the mutation>; tests: <the tests run against it>
# Lines starting with # are notes, and each other line is one surviving mutant:
# its file relative to the project root, a status word (survived, or the tool's
# own word for a mutant the code marked to skip), the change, and the tests that
# didn't catch it. A mutant that doesn't compile or crashes the run is errored,
# not a survivor. The Verifier needs each line killed or justified
# (the build skill's verify-rubric.md). The gate stamp keeps a copy beside the
# verdict, so `verify.sh --reuse` puts back the file that verdict came with
# (lib/stamp.sh).

# factory_survivors_file: print the survivors file's path; false outside git.
factory_survivors_file() {
	local dir
	if [ -n "${FACTORY_SURVIVORS_FILE:-}" ]; then
		printf '%s\n' "$FACTORY_SURVIVORS_FILE"
		return 0
	fi
	dir="$(git rev-parse --path-format=relative --git-dir 2> /dev/null)" || return 1
	printf '%s/factory/survivors.txt\n' "$dir"
}

# factory_mutate_gate <red 0|1> <earlier failure, or empty>: whether the mutate
# step runs. True with MUTATE_BASE set to the diff base's commit; false with
# MUTATE_SKIP set to the reason it doesn't.
factory_mutate_gate() {
	local branch phase base
	MUTATE_BASE="" MUTATE_SKIP=""
	if [ "$1" -eq 1 ]; then
		MUTATE_SKIP="the red gate mutates nothing"
	elif [ -n "$2" ]; then
		MUTATE_SKIP="step $2 failed, and mutants need a green tree"
	elif [ -n "${FACTORY_LAND:-}" ]; then
		MUTATE_SKIP="Land's verify mutates nothing: no Verifier reads its survivors"
	elif ! branch="$(factory_current_branch)" || ! phase="$(factory_state_get "$branch" phase 2> /dev/null)"; then
		MUTATE_SKIP="no run state: this checkout is on no issue's branch"
	elif [ "$phase" != green ]; then
		MUTATE_SKIP="the $phase phase mutates nothing; only green does"
	elif ! base="$(factory_diff_base)" || ! base="$(git rev-parse -q --verify "$base^{commit}" 2> /dev/null)"; then
		MUTATE_SKIP="no diff base (no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}'; set FACTORY_BASE or FACTORY_BASE_BRANCH)"
	elif git --no-optional-locks diff --quiet "$base" -- 2> /dev/null &&
		[ -z "$(git --no-optional-locks ls-files --others --exclude-standard 2> /dev/null | head -n 1)" ]; then
		# shellcheck disable=SC2034 # read by verify.sh, which sources this lib
		MUTATE_SKIP="nothing changed since the base $(git rev-parse --short "$base")"
	else
		# shellcheck disable=SC2034 # read by verify.sh, which sources this lib
		MUTATE_BASE="$base"
		return 0
	fi
	return 1
}
