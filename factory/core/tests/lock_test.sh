# The Lock (lock.sh, lib/lock.sh) and its check in the deviation step. The
# fixture's base has src/a.txt and tests/a_test.txt; the red commit adds a line to
# the test and stubs src/a.txt, in the red phase, with results in which test_new
# fails, so the red gate that lock.sh record runs passes.

# commit_all <subject> [<paragraph>...]: commit everything.
commit_all() {
	local args=() p
	for p in "$@"; do args+=(-m "$p"); done
	git add -A && git commit -q "${args[@]}" || fail "commit failed"
}

# result <name> <status> <file:line>: add a line to the fixture's results.
result() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> .fixture/results
}

# editor_gate_stamped: the run state holds the Editor's gate's stamp for HEAD in
# the phase now, as its stop hook leaves it after a green round.
editor_gate_stamped() {
	git config branch.work.factory-editor-gate "$(git config branch.work.factory-phase || echo -) $(git rev-parse HEAD)"
}

# red_branch [status of test_new]: the red commit in the red phase, its results
# giving test_new that status (default FAILURE), the Editor's gate stamped; not
# locked.
red_branch() {
	red_commit "$@"
	editor_gate_stamped
}

# red_commit [status of test_new]: red_branch, with no stamp.
red_commit() {
	fixture_git_project
	git config branch.work.factory-phase red
	brief "scope tests/**" "scope src/**" "test test_new" "seam src/a.txt A.stub"
	echo stub > src/a.txt
	echo test_new >> tests/a_test.txt
	: > .fixture/results
	result test_old_one PASS tests/a_test.txt:1
	result test_old_two PASS tests/a_test.txt:2
	result test_new "${1:-FAILURE}" tests/a_test.txt:3
	commit_all "red"
}

# locked_branch: the red commit, locked.
locked_branch() {
	red_branch
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
}

run_deviation() {
	run_cmd bash "$FACTORY_CORE/deviation.sh"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_record_locks_head_and_prints_the_locked_tests() {
	locked_branch
	assert_eq "tests/a_test.txt" "$out"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	run_cmd bash "$FACTORY_CORE/lock.sh" files
	assert_status 0
	assert_eq "tests/a_test.txt" "$out"
}

# The Lock rests on a fresh run of the red gate, never on a verdict a stamp kept.
test_record_runs_the_red_gate_fresh_and_locks_only_when_it_passes() {
	red_branch PASS
	run_verify --red
	assert_status 1
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
	assert_eq "" "$out"
	stderr_has "lock: running verify --red (the red phase: the brief's new tests must fail, everything else pass) fresh at $(git rev-parse --short HEAD)"
	stderr_has "lock: that gate fails at $(git rev-parse --short HEAD), so nothing is locked:"
	stderr_has "tests/a_test.txt:3 red-not-failure test_new is PASS; in the red phase a test the brief names fails with FAILURE"
	git config branch.work.factory-red-commit > /dev/null && fail "recorded a Lock anyway"
	result test_new FAILURE tests/a_test.txt:3
	sed -i '/^test_new\tPASS/d' .fixture/results
	: > .fixture/ran
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)" "the gate's steps"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
}

# A stamp from an earlier run on the same tree is not reused: the steps run again.
test_record_never_reuses_a_kept_verdict() {
	red_branch
	run_verify --red
	assert_status 0
	: > .fixture/ran
	echo "src/a.txt:1 fixture-lint broken since" > .fixture/fail-lint
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
	stderr_has "src/a.txt:1 fixture-lint broken since"
	assert_eq "prepare format typecheck lint" "$(ran_steps)" "the gate's steps"
}

# In the green phase a Lock is recorded again over code that passes: the full verify.
test_record_runs_the_full_verify_in_the_green_phase() {
	red_branch PASS
	git config branch.work.factory-phase green
	editor_gate_stamped
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	stderr_has "lock: running verify (the green phase: every step must pass) fresh at $(git rev-parse --short HEAD)"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	echo "src/a.txt:1 fixture-lint broken" > .fixture/fail-lint
	git config --unset branch.work.factory-red-commit
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
	stderr_has "src/a.txt:1 fixture-lint broken"
	git config branch.work.factory-red-commit > /dev/null && fail "recorded a Lock anyway"
	return 0
}

# --- the Editor's gate stamp (#60) -------------------------------------------------
# record goes on only with the Editor's gate's stamp for HEAD; without it, it runs
# that gate itself.

# A current stamp: the Editor's gate does not run again, only the Lock's own gate.
test_record_with_the_stamp_for_head_runs_only_its_own_gate() {
	red_branch
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	[ ! -s "$TEST_TMP/stderr" ] || ! grep -qF "Editor's gate" "$TEST_TMP/stderr" || fail "the Editor's gate ran: $(cat "$TEST_TMP/stderr")"
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)" "the gate's steps"
}

# No stamp (the Editor's stop hook did not run): record runs the Editor's gate,
# which is the red gate run fresh, so it is not run twice, and locks.
test_record_without_a_stamp_runs_the_editors_gate_and_locks_when_it_passes() {
	red_commit
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	stderr_has "lock: the run state holds no Editor's gate stamp for $(git rev-parse --short HEAD)"
	stderr_has "lock: the Editor's gate just ran verify --red"
	assert_eq "tests/a_test.txt" "$out"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	assert_eq "red $(git rev-parse HEAD)" "$(git config branch.work.factory-editor-gate)"
	assert_eq 1 "$(grep -cx test .fixture/ran)" "the red gate's test step ran other than once"
}

# A stamp for an older commit is no stamp for HEAD.
test_record_with_a_stale_stamp_runs_the_editors_gate() {
	red_commit
	git config branch.work.factory-editor-gate "red $(git rev-parse HEAD~1)"
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	stderr_has "lock: the run state holds no Editor's gate stamp for $(git rev-parse --short HEAD)"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	# A stamp of another phase is none either.
	git config --unset branch.work.factory-red-commit
	git config branch.work.factory-editor-gate "green $(git rev-parse HEAD)"
	: > .fixture/ran
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	stderr_has "lock: the run state holds no Editor's gate stamp for $(git rev-parse --short HEAD)"
	assert_eq 1 "$(grep -cx test .fixture/ran)" "the red gate's test step ran other than once"
}

# No stamp, and the Editor's gate fails: nothing is locked, and its findings are
# the Editor's next round.
test_record_without_a_stamp_refuses_when_the_editors_gate_fails() {
	red_commit
	echo "src/a.txt:1 fixture-lint broken" > .fixture/fail-lint
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
	assert_eq "" "$out"
	stderr_has "lock: the Editor's gate fails at $(git rev-parse --short HEAD), so this does not go on; send these findings to the Editor as a fix round, then run this again:"
	stderr_has "src/a.txt:1 fixture-lint broken"
	git config branch.work.factory-red-commit > /dev/null && fail "recorded a Lock anyway"
	git config branch.work.factory-editor-gate > /dev/null && fail "a failing gate left a stamp"
	return 0
}

# No stamp, and the Editor's gate was busy (a step failed only on the build
# lock's wait): nothing is locked, and it is no fix round.
test_record_without_a_stamp_says_a_busy_gate_is_no_fix_round() {
	red_commit
	echo "package.json:1 smoke-build-lock the build lock stayed held" > .fixture/transient-smoke
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
	stderr_has "lock: the Editor's gate was busy at $(git rev-parse --short HEAD), not red"
	grep -qF "as a fix round" "$TEST_TMP/stderr" && fail "sent a busy gate to the Editor: $(cat "$TEST_TMP/stderr")"
	git config branch.work.factory-red-commit > /dev/null && fail "recorded a Lock anyway"
	return 0
}

# No stamp in the small lane: the Editor's gate records the Lock itself and moves
# the issue to green; record says so and prints the locked files.
test_record_without_a_stamp_in_the_small_lane_takes_the_gates_lock() {
	red_commit
	git config branch.work.factory-lane small
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	stderr_has "send the Editor the green round that 'bash factory/core/prompt.sh green' prints"
	assert_eq "tests/a_test.txt" "$out"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	assert_eq green "$(git config branch.work.factory-phase)"
}

test_record_refuses_uncommitted_changes() {
	fixture_git_project
	echo test_new >> tests/a_test.txt
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
	git config branch.work.factory-red-commit > /dev/null && fail "recorded a Lock anyway"
	return 0
}

# The gate runs on the tree, so an untracked file would be judged but not locked.
test_record_refuses_an_untracked_file() {
	red_branch
	echo test_other > tests/new_test.txt
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
	stderr_has "lock: the tree has uncommitted changes or untracked files; commit the red phase first"
	git config branch.work.factory-red-commit > /dev/null && fail "recorded a Lock anyway"
	return 0
}

test_record_refuses_a_commit_with_no_test_change() {
	fixture_git_project
	echo stub > src/a.txt
	commit_all "stub only"
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 1
}

test_editing_a_locked_test_after_the_lock_fails() {
	locked_branch
	red="$(git rev-parse --short HEAD)"
	echo "test_new_changed" >> tests/a_test.txt
	commit_all "green"
	run_deviation
	assert_status 1
	assert_eq "tests/a_test.txt:1 locked-test changed after the Lock (red commit $red); a locked test stays as the red phase left it" "$out"
	run_cmd bash "$FACTORY_CORE/lock.sh" check
	assert_status 1
	assert_line "tests/a_test.txt:1 locked-test changed after the Lock (red commit $red); a locked test stays as the red phase left it"
}

test_editing_other_files_after_the_lock_passes() {
	locked_branch
	echo real > src/a.txt
	echo test_more > tests/b_test.txt
	commit_all "green"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

test_a_trailer_does_not_excuse_a_locked_test_edit() {
	locked_branch
	echo "test_new_changed" >> tests/a_test.txt
	commit_all "green" "Deviation: tests/a_test.txt: the test was wrong"
	run_deviation
	assert_status 1
	assert_line "tests/a_test.txt:1 deviation-declared the test was wrong (commit $(git rev-parse --short HEAD))"
	printf '%s\n' "$out" | grep -q '^tests/a_test.txt:1 locked-test ' || fail "no locked-test finding:"$'\n'"$out"
}

test_lock_survives_a_rebase_that_leaves_the_recorded_sha_stale() {
	locked_branch
	echo real > src/a.txt
	commit_all "green"
	git checkout -q dev
	echo upstream > src/up.txt
	printf 'test_old_zero\n' | cat - tests/a_test.txt > tests/tmp && mv tests/tmp tests/a_test.txt
	commit_all "upstream"
	git checkout -q work
	git rebase -q dev || fail "rebase failed"
	git merge-base --is-ancestor "$(git config branch.work.factory-red-commit)" HEAD && fail "the red commit should be off HEAD's history"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

test_without_a_lock_the_check_passes() {
	fixture_git_project
	brief "scope tests/**"
	echo test_new >> tests/a_test.txt
	commit_all "red"
	run_deviation
	assert_status 0
	run_cmd bash "$FACTORY_CORE/lock.sh" files
	assert_status 1
}

test_lock_on_a_missing_red_commit_fails() {
	locked_branch
	git config branch.work.factory-red-commit 0123456789abcdef0123456789abcdef01234567
	run_deviation
	assert_status 1
	assert_eq "tools/verify/deviation:1 locked-test the red commit 0123456789abcdef0123456789abcdef01234567 is not in the repo; record the Lock again" "$out"
}

test_check_staged_looks_at_the_index() {
	locked_branch
	red="$(git rev-parse --short HEAD)"
	echo "test_new_changed" >> tests/a_test.txt
	run_cmd bash "$FACTORY_CORE/lock.sh" check --staged
	assert_status 0
	git add tests/a_test.txt
	run_cmd bash "$FACTORY_CORE/lock.sh" check --staged
	assert_status 1
	assert_eq "tests/a_test.txt:1 locked-test changed after the Lock (red commit $red); a locked test stays as the red phase left it" "$out"
	run_cmd bash "$FACTORY_CORE/lock.sh" check
	assert_status 0
}

test_check_takes_only_the_staged_flag() {
	locked_branch
	run_cmd bash "$FACTORY_CORE/lock.sh" files --staged
	assert_status 2
	run_cmd bash "$FACTORY_CORE/lock.sh" check --cached
	assert_status 2
}

# --- lift: an issue's one move of the Lock, in any lane ------------------------------

# small_locked: locked_branch in the small lane's green phase.
small_locked() {
	locked_branch
	git config branch.work.factory-lane small
	git config branch.work.factory-phase green
}

run_lift() {
	run_cmd bash "$FACTORY_CORE/lock.sh" lift
}

test_lift_moves_a_small_lane_lock_once() {
	small_locked
	red="$(git rev-parse --short HEAD)"
	run_lift
	assert_status 0
	assert_eq "lock: lifted the Lock at $red; after the fix round, record it again with lock.sh record" "$out"
	git config branch.work.factory-red-commit > /dev/null && fail "the Lock is still recorded"
	assert_eq 1 "$(git config branch.work.factory-lifts)"
	echo "test_new_fixed" >> tests/a_test.txt
	commit_all "fix the test"
	run_deviation
	assert_status 0
	# Recorded again in the green phase, over code that now passes the full verify.
	sed -i 's/^test_new\tFAILURE/test_new\tPASS/' .fixture/results
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	run_lift
	assert_status 1
	stderr_has "lock: this issue's Lock moved 1 time(s) already, the most it may (once per issue); a second wrong locked test escalates"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	assert_eq 1 "$(git config branch.work.factory-lifts)"
}

# The Driver's own call on a locked test that contradicts the brief reaches the
# standard lane too, and holds it to once per issue the same way.
test_lift_moves_a_standard_lane_lock_once_per_issue() {
	locked_branch
	git config branch.work.factory-phase green
	git config branch.work.factory-lane > /dev/null && fail "the fixture isn't in the standard lane"
	red="$(git rev-parse --short HEAD)"
	run_lift
	assert_status 0
	assert_eq "lock: lifted the Lock at $red; after the fix round, record it again with lock.sh record" "$out"
	git config branch.work.factory-red-commit > /dev/null && fail "the Lock is still recorded"
	echo "test_new_fixed" >> tests/a_test.txt
	commit_all "fix the test"
	sed -i 's/^test_new\tFAILURE/test_new\tPASS/' .fixture/results
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
	run_lift
	assert_status 1
	stderr_has "(once per issue); a second wrong locked test escalates"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	assert_eq 1 "$(git config branch.work.factory-lifts)"
}

test_lift_refuses_outside_the_green_phase() {
	locked_branch
	git config branch.work.factory-lane small
	git config branch.work.factory-phase red
	run_lift
	assert_status 1
	stderr_has "lock: lift comes in the green phase, once a locked test proves wrong"
	git config --unset branch.work.factory-lane
	run_lift
	assert_status 1
	stderr_has "lock: lift comes in the green phase, once a locked test proves wrong"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	git config branch.work.factory-lifts > /dev/null && fail "a refused lift was counted"
	return 0
}

test_lift_needs_a_lock() {
	small_locked
	git config --unset branch.work.factory-red-commit
	run_lift
	assert_status 1
	stderr_has "lock: no Lock on work to lift"
}
