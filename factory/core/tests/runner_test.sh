# The gate runner: step order, subsets, no-op and missing steps, findings output.

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_full_run_runs_every_step_in_contract_order() {
	fixture_project
	run_verify
	assert_status 0
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)" "wrong steps or order"
	assert_eq "== prepare PASS
== format PASS
== typecheck PASS
== lint PASS
== arch SKIP
== deviation PASS
== test PASS
== mutate SKIP
== smoke PASS
verify: PASS" "$out" "wrong report"
}

# land.sh's step marks: with FACTORY_STEP_MARK set, a line on stderr before each
# step and one after the last, so Land can bound each step's output; stdout is
# the same verdict, and no step sees the mark.
test_a_step_mark_bounds_each_steps_output_on_stderr() {
	fixture_project
	printf 'env > .fixture/env-lint\n' > .fixture/run-lint
	run_verify
	local plain="$out"
	FACTORY_STEP_MARK=mark-1 run_verify
	assert_status 0
	assert_eq "mark-1 prepare
stub prepare done
mark-1 format
stub format done
mark-1 typecheck
stub typecheck done
mark-1 lint
stub lint done
mark-1 arch
mark-1 deviation
stub deviation done
mark-1 test
stub test done
mark-1 mutate
mark-1 smoke
stub smoke done
mark-1" "$(grep -e '^mark-1' -e '^stub .* done$' "$TEST_TMP/stderr")" "the marks don't bound each step's output"
	assert_eq "$plain" "$out" "the mark changed the verdict"
	[ -s .fixture/env-lint ] || fail "the lint step kept no environment"
	grep -q "FACTORY_STEP_MARK" .fixture/env-lint && fail "a step saw the mark"
	return 0
}

test_usage_lists_the_steps_with_mutate_after_test() {
	fixture_project
	run_verify --help
	assert_status 2
	stderr_has "steps, in order: prepare format typecheck lint arch deviation test mutate smoke"
}

test_stops_at_first_failing_step_and_names_it() {
	fixture_project
	echo "src/a.txt:3 too-long line is too long" > .fixture/fail-lint
	echo "src/b.txt:1 untyped no types" > .fixture/fail-typecheck
	run_verify
	assert_status 1
	assert_eq "prepare format typecheck" "$(ran_steps)" "ran past the failing step"
	assert_line "== typecheck FAIL"
	assert_line "src/b.txt:1 untyped no types"
	assert_no_line "== lint FAIL"
	assert_last_line "verify: FAILED at step typecheck"
}

test_subset_runs_only_those_steps_in_contract_order() {
	fixture_project
	run_verify test format lint
	assert_status 0
	assert_eq "format lint test" "$(ran_steps)" "wrong subset or order"
	assert_eq "== format PASS
== lint PASS
== test PASS
verify: PASS" "$out" "wrong report"
}

test_subset_stops_at_its_first_failing_step() {
	fixture_project
	: > .fixture/fail-format
	run_verify smoke format
	assert_status 1
	assert_eq "format" "$(ran_steps)"
	assert_last_line "verify: FAILED at step format"
}

test_noop_step_passes_and_is_reported_skipped() {
	fixture_project
	run_verify arch
	assert_status 0
	assert_eq "== arch SKIP
verify: PASS" "$out" "wrong report"
}

test_missing_step_script_fails_naming_it() {
	fixture_project
	rm tools/verify/deviation
	run_verify
	assert_status 1
	assert_eq "prepare format typecheck lint" "$(ran_steps)"
	assert_line "== deviation FAIL"
	printf '%s\n' "$out" | grep -q '^tools/verify/deviation:1 step-missing ' || fail "no step-missing finding:"$'\n'"$out"
	assert_last_line "verify: FAILED at step deviation"
}

test_findings_print_sorted() {
	fixture_project
	printf '%s\n' "src/z.txt:2 rule-b second" "src/a.txt:10 rule-a third" "src/a.txt:1 rule-a first" > .fixture/output-lint
	run_verify lint
	assert_status 0
	assert_eq "== lint PASS
src/a.txt:1 rule-a first
src/a.txt:10 rule-a third
src/z.txt:2 rule-b second
verify: PASS" "$out" "findings not sorted byte-wise"
}

test_step_stderr_stays_out_of_stdout() {
	fixture_project
	run_verify lint
	assert_no_line "stub lint done"
	grep -qxF "stub lint done" "$TEST_TMP/stderr" || fail "step stderr was not passed through"
}

test_output_that_is_not_a_finding_fails_the_step() {
	fixture_project
	printf '%s\n' "src/a.txt:1 rule fine" "Loading project..." > .fixture/output-lint
	run_verify lint
	assert_status 1
	assert_line "src/a.txt:1 rule fine"
	assert_line "tools/verify/lint:1 finding-format not a 'file:line rule message' line: Loading project..."
	assert_no_line "Loading project..."
}

test_unknown_step_is_a_usage_error() {
	fixture_project
	run_verify lint deploy
	assert_status 2
	assert_eq "" "$(ran_steps)" "a step ran despite the usage error"
}

test_local_env_is_sourced_for_every_step() {
	fixture_project
	printf '#!/usr/bin/env bash\necho "src/env.txt:1 env FAKETOOL_VERSION=$FAKETOOL_VERSION"\n' > tools/verify/lint
	run_verify lint
	assert_status 0
	assert_line "src/env.txt:1 env FAKETOOL_VERSION=1.2.3"
}

# A local.env from before the Anthropic-only roles still names its Editor and
# Verifier lists; the gate runs on and says, once, that they are ignored.
test_local_env_with_the_retired_role_lists_warns_once() {
	fixture_project
	printf 'FACTORY_EDITOR=cursor,sonnet\nexport FACTORY_VERIFIER=codex\nFACTORY_EDITOR_LOOP_LIMIT=3\n' >> tools/verify/local.env
	run_verify lint
	assert_status 0
	assert_eq 1 "$(grep -c 'FACTORY_EDITOR and FACTORY_VERIFIER, which the factory ignores now' "$TEST_TMP/stderr")" "the warning lines: $(cat "$TEST_TMP/stderr")"
	stderr_has "verify: tools/verify/local.env sets FACTORY_EDITOR and FACTORY_VERIFIER, which the factory ignores now: the Editor is always the editor-sonnet subagent and the Verifier the verifier subagent; delete the line"
}

test_local_env_without_them_says_nothing_of_roles() {
	fixture_project
	run_verify lint
	assert_status 0
	! grep -q 'ignores now' "$TEST_TMP/stderr" || fail "a warning without the role lists: $(cat "$TEST_TMP/stderr")"
}

# --- the gate's counts (lib/run.sh, factory_gate_count) ------------------------------

# issue_project: the git fixture on issue 7's branch, with the step clock at
# $TEST_TMP/clock reading 100; .fixture/run-prepare sets it to 101.4 and
# .fixture/run-lint to 106.5, so prepare takes 1.4 seconds, lint 5.1, the rest 0.
issue_project() {
	fixture_git_project
	git checkout -q -b issue/7 || fail "no issue branch"
	echo 100 > "$TEST_TMP/clock"
	printf 'echo 101.4 > %q\n' "$TEST_TMP/clock" > .fixture/run-prepare
	printf 'echo 106.5 > %q\n' "$TEST_TMP/clock" > .fixture/run-lint
	export FACTORY_STEP_CLOCK="$TEST_TMP/clock"
}

# gate_counts: issue 7's gate counts, one key=value a line, sorted.
gate_counts() {
	bash "$FACTORY_CORE/state.sh" --branch issue/7 list | grep -e '^gate-runs=' -e '^caught-' -e '^seconds-'
}

test_a_red_run_counts_one_catch_for_its_step_and_each_steps_seconds() {
	issue_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_eq "caught-lint=1
gate-runs=1
seconds-lint=5
seconds-prepare=1" "$(gate_counts)" "the counts"
}

# Each step's seconds add up over the counted runs; a SKIP adds none, and a green
# run counts no catch.
test_each_steps_seconds_add_up_over_the_runs() {
	issue_project
	run_verify
	assert_status 0
	echo two > src/a.txt
	echo 100 > "$TEST_TMP/clock"
	printf 'echo 109.5 > %q\n' "$TEST_TMP/clock" > .fixture/run-smoke
	run_verify
	assert_status 0
	assert_eq "gate-runs=2
seconds-lint=10
seconds-prepare=2
seconds-smoke=3" "$(gate_counts)" "the counts"
}

# The stop hook's run, then the Driver's or lock.sh record's fresh one on the same
# inputs: the second counts nothing. Inputs that change count again.
test_a_fresh_rerun_on_the_same_inputs_counts_nothing_more() {
	issue_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	run_verify
	assert_status 1
	assert_eq "caught-lint=1
gate-runs=1
seconds-lint=5
seconds-prepare=1" "$(gate_counts)" "a rerun on the same inputs counted again"
	echo two > src/a.txt
	echo 100 > "$TEST_TMP/clock"
	run_verify
	assert_eq "caught-lint=2
gate-runs=2
seconds-lint=10
seconds-prepare=2" "$(gate_counts)" "a run on new inputs didn't count"
}

test_a_run_off_an_issue_branch_counts_nothing() {
	issue_project
	git checkout -q work || fail "no work branch"
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	assert_status 1
	assert_eq "" "$(bash "$FACTORY_CORE/state.sh" --branch work list)" "the work branch got counts"
	assert_eq "" "$(gate_counts)" "the issue branch got counts"
}

# baseline.sh's --keep-going and --twice's two runs count nothing.
test_keep_going_and_twice_count_nothing() {
	issue_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify --keep-going
	assert_status 1
	run_verify --twice
	assert_status 1
	assert_eq "" "$(gate_counts)" "the counts"
}

# The counts stay out of stdout: the verdict's bytes are a run's off the branch.
test_the_counts_leave_the_verdict_as_it_was() {
	issue_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	local counted="$out"
	assert_eq "" "$(grep -v '^stub [a-z]* done$' "$TEST_TMP/stderr")" "a counted run's notes"
	git checkout -q work || fail "no work branch"
	run_verify
	assert_eq "$out" "$counted" "the counted run's verdict differs"
}

# A tree changed and changed back is inputs a counted run had: the stamp now
# holds the other tree's key, but the counted keys still list the first.
test_a_tree_changed_and_changed_back_counts_once_per_tree() {
	issue_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify lint
	echo two > src/a.txt
	run_verify lint
	echo one > src/a.txt
	run_verify lint
	assert_status 1
	assert_eq "caught-lint=2
gate-runs=2" "$(gate_counts | grep -v '^seconds-')" "the counts"
}

# A run that changes its own inputs keeps no stamp but counts, under the key it
# started with: the same inputs again count nothing more.
test_a_run_that_changes_its_inputs_counts_once_for_the_inputs_it_began_with() {
	issue_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	echo 'echo changed >> src/a.txt' > .fixture/run-lint
	run_verify lint
	stderr_has "the run changed its own inputs"
	git checkout -q -- src/a.txt
	run_verify lint
	assert_status 1
	assert_eq "caught-lint=1
gate-runs=1" "$(gate_counts | grep -v '^seconds-')" "the counts"
}

# A run off the issue branch counted nothing, so the same inputs on the issue
# branch count, though the stamp under their key is the other run's.
test_a_run_off_the_issue_branch_leaves_the_same_inputs_to_count() {
	issue_project
	git checkout -q work || fail "no work branch"
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify lint
	git checkout -q issue/7 || fail "no issue branch"
	run_verify lint
	assert_status 1
	assert_eq "caught-lint=1
gate-runs=1" "$(gate_counts | grep -v '^seconds-')" "the counts"
}

# --all-static (#15): every static step's findings at once, then no long step.
test_all_static_runs_every_static_step_past_a_failure_and_no_long_step() {
	fixture_project
	echo "src/a.txt:1 type-bad a type finding" > .fixture/fail-typecheck
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	run_verify --all-static
	assert_status 1
	assert_eq "== prepare PASS
== format PASS
== typecheck FAIL
src/a.txt:1 type-bad a type finding
== lint FAIL
src/a.txt:2 lint-bad a lint finding
== arch SKIP
== deviation PASS
verify: FAILED at step typecheck" "$out" "wrong report"
	assert_eq "prepare format typecheck lint deviation" "$(ran_steps)" "wrong steps ran"
	rm -f .fixture/ran
	run_verify
	assert_status 1
	assert_eq "prepare format typecheck" "$(ran_steps)" "the plain run did not stop at the first failure"
}

test_all_static_stops_at_a_failing_prepare_or_long_step() {
	fixture_project
	echo "src/a.txt:1 prep-bad a prepare finding" > .fixture/fail-prepare
	run_verify --all-static
	assert_status 1
	assert_eq "prepare" "$(ran_steps)" "a step ran after prepare failed"
	rm -f .fixture/ran .fixture/fail-prepare
	echo "src/a.txt:1 test-bad a test finding" > .fixture/fail-test
	run_verify --all-static
	assert_status 1
	assert_eq "prepare format typecheck lint deviation test" "$(ran_steps)" "a step ran after test failed"
	assert_last_line "verify: FAILED at step test"
}
