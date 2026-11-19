# The Lock: the red commit, and the check that its tests stay as they were.
# Sourced by the Core's scripts (needs steps.sh, findings.sh, brief.sh, diff.sh and
# run.sh); defines no side effects.
#
# lock.sh records the red commit's SHA in the branch's run state (red-commit). The
# locked tests are the test files (tools/verify/test-paths) that the red commit
# changed since its own base, the merge-base of the red commit and the diff base.
#
# The check compares content, not ancestry: land.sh rebases the branch without
# updating red-commit, so the recorded SHA may no longer be in HEAD's history. A
# locked file passes while the branch's change to it (base..HEAD) is the same, line
# for line, as the red commit's change to it. Line numbers and context don't count,
# so a rebase that only moves the change keeps the Lock.

# The most times an issue's Lock may move (lock.sh lift), in any lane: once per
# issue, whether the Driver lifts it on its own call or the main session on the
# human's yes (the build skill's SKILL.md, Driver's calls).
# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_LOCK_LIFTS=1

# factory_lock_red_commit: print the checked-out branch's red commit; false when
# there is no Lock (no branch, or nothing recorded).
factory_lock_red_commit() {
	local branch
	branch="$(factory_current_branch)" || return 1
	factory_state_get "$branch" red-commit
}

# factory_lock_files <red> <base>: print the locked files, sorted. Needs TEST_PATHS
# loaded (factory_test_paths_load).
factory_lock_files() {
	local red_base file
	red_base="$(git merge-base "$1" "$2")" || return 1
	git diff --name-only --no-renames "$red_base" "$1" | tr -d '\r' | LC_ALL=C sort | while IFS= read -r file; do
		factory_is_test_file "$file" && printf '%s\n' "$file"
	done
	return 0
}

# factory_lock_record_check <base>: true when HEAD can be locked: the tree has no
# uncommitted change and no untracked file outside the ignore rules (the Lock is a
# commit, and a gate run on the tree must have judged HEAD alone), and HEAD changes
# at least one test file since <base>. Otherwise false, with a line on stderr.
factory_lock_record_check() {
	if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
		echo "lock: the tree has uncommitted changes or untracked files; commit the red phase first" >&2
		return 1
	fi
	factory_test_paths_load >&2 || return 1
	if [ -z "$(factory_lock_files HEAD "$1")" ]; then
		echo "lock: HEAD changes no test file since $(git rev-parse --short "$1"); nothing to lock" >&2
		return 1
	fi
}

# factory_lock_record <branch> <base>: lock HEAD as <branch>'s red commit and
# print the locked files, once factory_lock_record_check passes. It runs no gate:
# lock.sh record runs the phase's gate fresh first, and the small lane's stop hook
# (hooks/editor-gate.sh) calls it only once its own fresh run of the red gate
# passed on a clean tree.
factory_lock_record() {
	local red
	factory_lock_record_check "$2" || return 1
	red="$(git rev-parse HEAD)" || return 1
	factory_state_set "$1" red-commit "$red" || return 1
	factory_lock_files "$red" "$2"
}

# factory_locked_files: print the checked-out branch's locked files, sorted;
# nothing when there is no Lock, no diff base or no test-paths to tell tests by.
factory_locked_files() {
	local red base
	red="$(factory_lock_red_commit)" && base="$(factory_diff_base)" && factory_test_paths_load > /dev/null || return 0
	factory_lock_files "$red" "$base"
}

# factory_lock_change <from> <to> <file>: the change's added and removed lines,
# without line numbers or context. <to> is a commit, or :index for what is staged.
factory_lock_change() {
	if [ "$2" = :index ]; then
		git diff --no-color --no-ext-diff -U0 --cached "$1" -- "$3"
	else
		git diff --no-color --no-ext-diff -U0 "$1" "$2" -- "$3"
	fi | tr -d '\r' | awk '
		/^@@/ { hunk = 1; next }
		hunk && /^[-+]/
	'
}

# factory_lock_check <base> [<to>]: print a locked-test finding for each locked file
# the branch changed after the Lock, as of <to> (default HEAD; :index checks what
# is staged, for the pre-commit hook); return 1 if there were any. Passes when
# there is no Lock.
factory_lock_check() {
	local base="$1" to="${2:-HEAD}" red red_base file bad=0 short
	red="$(factory_lock_red_commit)" || return 0
	short="$(git rev-parse --short "$red" 2> /dev/null)" || short="$red"
	if ! git cat-file -e "$red^{commit}" 2> /dev/null; then
		factory_finding "$FACTORY_STEPS_DIR/deviation" 1 locked-test "the red commit $red is not in the repo; record the Lock again"
		return 1
	fi
	factory_test_paths_load || return 1
	red_base="$(git merge-base "$red" "$base")" || {
		factory_finding "$FACTORY_STEPS_DIR/deviation" 1 locked-test "the red commit $short shares no history with the base"
		return 1
	}
	while IFS= read -r file; do
		if [ "$(factory_lock_change "$red_base" "$red" "$file")" != "$(factory_lock_change "$base" "$to" "$file")" ]; then
			factory_finding "$file" 1 locked-test "changed after the Lock (red commit $short); a locked test stays as the red phase left it"
			bad=1
		fi
	done < <(factory_lock_files "$red" "$base")
	return "$bad"
}
