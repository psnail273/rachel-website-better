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

# A step's wait for a resource other gates share (the adapter's gate slots),
# kept in its wait record (factory_step_waited), is no part of its seconds: smoke
# runs from 106.5 to 149.5, 40 of it waiting.
test_a_steps_wait_for_a_shared_resource_is_left_out_of_its_seconds() {
	issue_project
	{
		printf '. %q\n' "$FACTORY_CORE/lib/run.sh"
		echo 'from="$(factory_clock_us)"'
		printf 'echo 146.5 > %q\n' "$TEST_TMP/clock"
		echo 'factory_step_waited "$from"'
		printf 'echo 149.5 > %q\n' "$TEST_TMP/clock"
	} > .fixture/run-smoke
	run_verify
	assert_status 0
	assert_eq "gate-runs=1
seconds-lint=5
seconds-prepare=1
seconds-smoke=3" "$(gate_counts)" "the counts"
}

# The gate's wait record (lib/run.sh), as the Editor's stop hook keeps it: a
# step's wait goes in it (factory_wait_begin, then factory_step_waited), and the
# time waited is the union of its waits, ended and going, within the span asked.
# shellcheck disable=SC2030,SC2031 # each test sets its clock in a subshell of its own
test_the_gate_wait_record_counts_overlapping_waits_once() {
	mkdir -p "$TEST_TMP/record"
	echo 100 > "$TEST_TMP/clock"
	(
		. "$FACTORY_CORE/lib/run.sh"
		export FACTORY_STEP_CLOCK="$TEST_TMP/clock" FACTORY_GATE_WAITS="$TEST_TMP/record"
		factory_wait_begin from
		[ -e "$TEST_TMP/record/waiting.$$.$from" ] || fail "no mark for the wait going"
		echo 130 > "$TEST_TMP/clock"
		factory_step_waited "$from"
		[ -e "$TEST_TMP/record/waiting.$$.$from" ] && fail "the ended wait's mark stayed"
		assert_eq "100000000 130000000" "$(cat "$TEST_TMP/record/waits")" "the ended wait"
		echo "120000000 140000000" >> "$TEST_TMP/record/waits"
		: > "$TEST_TMP/record/waiting.1.150000000"
		assert_eq 60000000 "$(factory_gate_waited_us "$TEST_TMP/record" 90000000 170000000)" "100-140 and 150-170"
		assert_eq 35000000 "$(factory_gate_waited_us "$TEST_TMP/record" 115000000 160000000)" "115-140 and 150-160"
		assert_eq 0 "$(factory_gate_waited_us "$TEST_TMP/no-record" 0 170000000)" "no record"
	)
}

# A wait's setting is cut to the seconds left until the record's `until`; without
# a record, or once `until` has passed, it is the setting, or 0.
# shellcheck disable=SC2030,SC2031 # each test sets its clock in a subshell of its own
test_a_wait_is_cut_to_the_records_time_left() {
	mkdir -p "$TEST_TMP/record"
	echo 1000 > "$TEST_TMP/clock"
	(
		. "$FACTORY_CORE/lib/run.sh"
		export FACTORY_STEP_CLOCK="$TEST_TMP/clock"
		assert_eq 900 "$(factory_wait_cap 900)" "no record"
		export FACTORY_GATE_WAITS="$TEST_TMP/record"
		assert_eq 900 "$(factory_wait_cap 900)" "a record without until"
		echo 1100500000 > "$TEST_TMP/record/until"
		assert_eq 100 "$(factory_wait_cap 900)" "100.5 s left"
		assert_eq 30 "$(factory_wait_cap 30)" "a setting under the time left"
		echo 1200 > "$TEST_TMP/clock"
		assert_eq 0 "$(factory_wait_cap 900)" "until passed"
	)
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

# --- the parallel steps at once (#57 item 3) ----------------------------------------

# parallel_project: the fixture with a no-overlap file that names no step, so the
# five parallel steps (typecheck lint arch deviation test) run at once.
parallel_project() {
	fixture_project
	echo "# the stubs share nothing" > tools/verify/no-overlap
}

# both_ways <verify args...>: run the gate with the step mark set, one by one
# (FACTORY_SERIAL_STEPS=1), then at once from the same .fixture state; fail unless
# stdout, the exit code and stderr (marks, the steps' own lines, the runner's
# notes) are the same. out and status are the run at once's.
both_ways() {
	local serial_out serial_status
	rm -rf "$TEST_TMP/fixture-state" && cp -R .fixture "$TEST_TMP/fixture-state" || fail "could not keep .fixture"
	FACTORY_SERIAL_STEPS=1 FACTORY_STEP_MARK=mark-1 run_verify "$@"
	serial_out="$out"
	serial_status="$status"
	cp "$TEST_TMP/stderr" "$TEST_TMP/serial-stderr"
	rm -rf .fixture && cp -R "$TEST_TMP/fixture-state" .fixture || fail "could not put .fixture back"
	FACTORY_STEP_MARK=mark-1 run_verify "$@"
	assert_eq "$serial_out" "$out" "stdout at once differs from one by one"
	assert_eq "$serial_status" "$status" "the exit code at once differs from one by one"
	assert_eq "$(cat "$TEST_TMP/serial-stderr")" "$(cat "$TEST_TMP/stderr")" "stderr at once differs from one by one"
}

# block_step <step> <release>: the stub step runs a blocking stand-in before it
# ends, until <release> exists; the stand-in's pid is in .fixture/block-<step>.pid,
# and .fixture/unreleased-<step> says it gave up, its hang guard run out.
block_step() {
	blocking_stand_in "$PWD/.fixture/block-$1" "$PWD/$2"
	echo "bash .fixture/block-$1 || touch .fixture/unreleased-$1" > ".fixture/run-$1"
}

# step_ended <step>: the step's process has ended; its run hook wrote its pid
# (the stub's) to .fixture/<step>.pid (keep_pid).
step_ended() {
	[ -s ".fixture/$1.pid" ] && ! kill -0 "$(cat ".fixture/$1.pid")" 2> /dev/null
}

# keep_pid <step>: the step's run hook writes the step's pid to .fixture/<step>.pid.
keep_pid() {
	echo "echo \$PPID > .fixture/$1.pid" >> ".fixture/run-$1"
}

# stand_in_ended <step>: block_step's stand-in for the step has ended.
stand_in_ended() {
	[ -s ".fixture/block-$1.pid" ] && ! kill -0 "$(cat ".fixture/block-$1.pid")" 2> /dev/null
}

test_the_parallel_steps_print_as_they_do_one_by_one() {
	parallel_project
	both_ways
	assert_status 0
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

# typecheck, the first of them, waits for test, the last, to have run: only steps
# that overlap pass.
test_the_parallel_steps_overlap() {
	parallel_project
	block_step typecheck .fixture/test-ran
	echo "touch .fixture/test-ran" > .fixture/run-test
	run_verify
	assert_status 0
	[ ! -e .fixture/unreleased-typecheck ] || fail "typecheck waited for test until its hang guard ran out"
	assert_line "== typecheck PASS"
	assert_last_line "verify: PASS"
	assert_eq "prepare format smoke" "$(grep -vx -e typecheck -e lint -e deviation -e test .fixture/ran | paste -sd ' ' -)" "the other steps"
	assert_eq "deviation lint test typecheck" "$(grep -x -e typecheck -e lint -e deviation -e test .fixture/ran | LC_ALL=C sort | paste -sd ' ' -)" "the parallel steps that ran"
}

test_one_failing_step_prints_as_it_does_one_by_one() {
	parallel_project
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	both_ways
	assert_status 1
	assert_eq "== prepare PASS
== format PASS
== typecheck PASS
== lint FAIL
src/a.txt:2 lint-bad a lint finding
verify: FAILED at step lint" "$out" "wrong report"
}

test_two_steps_failing_at_once_print_the_first_as_one_by_one() {
	parallel_project
	echo "src/a.txt:1 type-bad a type finding" > .fixture/fail-typecheck
	echo "src/a.txt:3 dev-bad a deviation finding" > .fixture/fail-deviation
	both_ways
	assert_status 1
	assert_eq "== prepare PASS
== format PASS
== typecheck FAIL
src/a.txt:1 type-bad a type finding
verify: FAILED at step typecheck" "$out" "wrong report"
}

# lint fails and ends while typecheck, before it in the order, still runs: the
# verdict is typecheck's, as one by one.
test_a_later_step_failing_first_leaves_the_verdict_to_the_earlier() {
	parallel_project
	echo "src/a.txt:1 type-bad a type finding" > .fixture/fail-typecheck
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	block_step typecheck .fixture/release-typecheck
	keep_pid lint
	touch .fixture/release-typecheck
	FACTORY_SERIAL_STEPS=1 FACTORY_STEP_MARK=mark-1 run_verify
	local serial_out="$out" serial_status="$status" pid
	cp "$TEST_TMP/stderr" "$TEST_TMP/serial-stderr"
	rm -f .fixture/release-typecheck .fixture/ran .fixture/lint.pid .fixture/block-typecheck.pid
	FACTORY_STEP_MARK=mark-1 bash "$FACTORY_CORE/verify.sh" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr" &
	pid=$!
	wait_until "typecheck to block" test -s .fixture/block-typecheck.pid
	wait_until "lint to fail and end" step_ended lint
	touch .fixture/release-typecheck
	wait "$pid"
	status=$?
	out="$(cat "$TEST_TMP/stdout")"
	assert_eq "$serial_out" "$out" "stdout at once differs from one by one"
	assert_eq "$serial_status" "$status" "the exit code at once differs from one by one"
	assert_eq "$(cat "$TEST_TMP/serial-stderr")" "$(cat "$TEST_TMP/stderr")" "stderr at once differs from one by one"
	assert_last_line "verify: FAILED at step typecheck"
	assert_no_line "== lint FAIL"
}

# A step that stops the run stops the steps after it, which can't show: test
# would block until the hang guard, and the run ends without it.
test_a_failing_step_stops_the_steps_after_it() {
	parallel_project
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	block_step test .fixture/never
	run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_no_line "== test FAIL"
	[ ! -e .fixture/unreleased-test ] || fail "the run waited for test until its hang guard ran out"
	[ -s .fixture/block-test.pid ] || return 0
	wait_until "the stopped test step's stand-in to end" stand_in_ended test
}

test_a_transient_step_prints_as_it_does_one_by_one() {
	parallel_project
	echo "src/a.txt:1 test-flaky the lock was held" > .fixture/transient-test
	both_ways
	assert_status 1
	assert_line "== test FAIL"
	assert_last_line "verify: FAILED at step test"
}

# On a git project: the transient step's note that no stamp is kept, both ways.
test_a_transient_step_keeps_no_stamp_as_one_by_one() {
	fixture_git_project
	echo "# the stubs share nothing" > tools/verify/no-overlap
	echo "src/a.txt:1 lint-flaky the lock was held" > .fixture/transient-lint
	both_ways
	assert_status 1
	stderr_has "verify: no gate stamp: step lint failed for a transient cause (exit 75)"
}

# A transient step past the one that stops the run, which ran at once but doesn't
# show, keeps no stamp from being written: one by one it would not have run.
test_a_transient_step_that_does_not_show_leaves_the_stamp() {
	fixture_git_project
	echo "# the stubs share nothing" > tools/verify/no-overlap
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	echo "src/a.txt:1 test-flaky the lock was held" > .fixture/transient-test
	block_step lint .fixture/release-lint
	keep_pid test
	local pid
	bash "$FACTORY_CORE/verify.sh" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr" &
	pid=$!
	wait_until "test to exit transient" step_ended test
	touch .fixture/release-lint
	wait "$pid"
	status=$?
	out="$(cat "$TEST_TMP/stdout")"
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	! grep -q transient "$TEST_TMP/stderr" || fail "a step that doesn't show voided the stamp: $(cat "$TEST_TMP/stderr")"
	run_verify --reuse
	assert_status 1
	stderr_has "verify: --reuse: this is the verdict of the run at"
}

test_all_static_prints_as_it_does_one_by_one() {
	parallel_project
	echo "src/a.txt:1 type-bad a type finding" > .fixture/fail-typecheck
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	both_ways --all-static
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
}

# --all-static past a red static step: test can't show, so the run stops it and
# ends, while deviation, a static step after it, still shows.
test_all_static_stops_the_test_step_after_a_red_static_step() {
	parallel_project
	echo "src/a.txt:1 type-bad a type finding" > .fixture/fail-typecheck
	echo "src/a.txt:3 dev-bad a deviation finding" > .fixture/fail-deviation
	block_step test .fixture/never
	run_verify --all-static
	assert_status 1
	assert_line "== deviation FAIL"
	assert_no_line "== test FAIL"
	assert_last_line "verify: FAILED at step typecheck"
	[ ! -e .fixture/unreleased-test ] || fail "the run waited for test until its hang guard ran out"
	[ -s .fixture/block-test.pid ] || return 0
	wait_until "the stopped test step's stand-in to end" stand_in_ended test
}

test_keep_going_prints_as_it_does_one_by_one() {
	parallel_project
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	echo "src/a.txt:1 test-bad a test finding" > .fixture/fail-test
	both_ways --keep-going
	assert_status 1
	assert_line "== test FAIL"
	assert_line "== smoke PASS"
	assert_last_line "verify: FAILED at step lint"
}

test_a_subset_prints_as_it_does_one_by_one() {
	parallel_project
	echo "src/a.txt:1 test-bad a test finding" > .fixture/fail-test
	both_ways test lint
	assert_status 1
	assert_eq "== lint PASS
== test FAIL
src/a.txt:1 test-bad a test finding
verify: FAILED at step test" "$out" "wrong report"
}

test_twice_prints_as_it_does_one_by_one() {
	parallel_project
	echo "src/a.txt:3 dev-bad a deviation finding" > .fixture/fail-deviation
	both_ways --twice
	assert_status 1
	assert_last_line "verify: two runs match"
}

# The runner stopped by a TERM (a timeout) or a Ctrl-C stops the steps running in
# their own process groups too.
test_a_term_to_the_runner_stops_the_parallel_steps() {
	parallel_project
	block_step test .fixture/never
	local pid
	bash "$FACTORY_CORE/verify.sh" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr" &
	pid=$!
	wait_until "the test step to block" test -s .fixture/block-test.pid
	kill -TERM "$pid"
	wait "$pid"
	status=$?
	assert_status 143
	wait_until "the test step's stand-in to end" stand_in_ended test
}

# Two steps a no-overlap line names never run at the same time, and run in the
# fixed order; the others still run at once with them.
test_steps_a_no_overlap_line_names_run_one_at_a_time() {
	parallel_project
	echo "typecheck test # they share a cache" > tools/verify/no-overlap
	block_step typecheck .fixture/release-typecheck
	keep_pid lint
	keep_pid deviation
	local pid
	bash "$FACTORY_CORE/verify.sh" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr" &
	pid=$!
	wait_until "lint and deviation to run beside typecheck" eval 'step_ended lint && step_ended deviation'
	! grep -qx test .fixture/ran || fail "test ran while typecheck did: $(cat .fixture/ran)"
	touch .fixture/release-typecheck
	wait "$pid"
	status=$?
	out="$(cat "$TEST_TMP/stdout")"
	assert_status 0
	assert_line "== test PASS"
	assert_eq "typecheck test" "$(grep -x -e typecheck -e test .fixture/ran | paste -sd ' ' -)" "typecheck and test out of order"
}

# overlap_hook <step> <other>: the step's run hook notes in .fixture/overlapped
# when the other step has started before it ended.
overlap_hook() {
	echo "! grep -qx $2 .fixture/ran || touch .fixture/overlapped" >> ".fixture/run-$1"
}

test_with_no_no_overlap_file_the_steps_run_one_by_one() {
	fixture_project
	overlap_hook typecheck test
	run_verify
	assert_status 0
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)" "wrong steps or order"
	[ ! -e .fixture/overlapped ] || fail "test started before typecheck ended"
}

test_factory_serial_steps_runs_them_one_by_one() {
	parallel_project
	overlap_hook typecheck test
	FACTORY_SERIAL_STEPS=1 run_verify
	assert_status 0
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)" "wrong steps or order"
	[ ! -e .fixture/overlapped ] || fail "test started before typecheck ended"
}

test_a_no_overlap_file_naming_another_step_runs_them_one_by_one() {
	parallel_project
	printf 'typecheck smoke\nlint deploy\n' > tools/verify/no-overlap
	overlap_hook typecheck test
	run_verify
	assert_status 0
	stderr_has "verify: tools/verify/no-overlap names deploy smoke, which is no step that may run at once (typecheck lint arch deviation test); the steps run one by one"
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)" "wrong steps or order"
	[ ! -e .fixture/overlapped ] || fail "test started before typecheck ended"
}

test_no_overlap_lines_say_which_steps_may_overlap() {
	fixture_project
	. "$FACTORY_CORE/lib/steps.sh"
	! factory_steps_may_overlap lint test || fail "with no file, lint and test may overlap"
	echo "# nothing shared" > tools/verify/no-overlap
	factory_steps_may_overlap lint test || fail "with no line, lint and test may not overlap"
	printf 'typecheck   test # tsbuildinfo\r\n\nlint arch\n' > tools/verify/no-overlap
	factory_no_overlap_check || fail "a file of parallel steps fails the check"
	local pair
	for pair in "typecheck test" "test typecheck" "lint arch" "lint lint" "lint smoke" "format lint" "prepare test"; do
		# shellcheck disable=SC2086 # the pair splits on purpose
		! factory_steps_may_overlap $pair || fail "$pair may overlap"
	done
	for pair in "typecheck lint" "arch test" "deviation typecheck" "test deviation"; do
		# shellcheck disable=SC2086 # the pair splits on purpose
		factory_steps_may_overlap $pair || fail "$pair may not overlap"
	done
	echo "lint smoke mutate" >> tools/verify/no-overlap
	! factory_no_overlap_check > "$TEST_TMP/unknown" || fail "the check passed a step outside the set"
	assert_eq "smoke
mutate" "$(cat "$TEST_TMP/unknown")" "the words named"
}

# The counts at once: each step's seconds are its own time. lint and test run
# through the same 5.1 seconds (lint moves the clock once test has started, and
# test ends after it), so each counts 5; typecheck and deviation are no-ops.
test_steps_at_once_count_their_own_seconds() {
	issue_project
	echo "# the stubs share nothing" > tools/verify/no-overlap
	echo "# factory: no-op" > tools/verify/typecheck
	echo "# factory: no-op" > tools/verify/deviation
	blocking_stand_in "$PWD/.fixture/wait-test" "$PWD/.fixture/test-began"
	printf 'bash .fixture/wait-test\necho 106.5 > %q\ntouch .fixture/clocked\n' "$TEST_TMP/clock" > .fixture/run-lint
	blocking_stand_in "$PWD/.fixture/wait-clock" "$PWD/.fixture/clocked"
	printf 'touch .fixture/test-began\nbash .fixture/wait-clock\n' > .fixture/run-test
	run_verify
	assert_status 0
	assert_eq "gate-runs=1
seconds-lint=5
seconds-prepare=1
seconds-test=5" "$(gate_counts)" "the counts"
}

# A red run at once counts the catch one by one would: lint's, not test's, though
# test ran and failed too.
test_a_red_run_at_once_counts_the_catch_one_by_one_would() {
	issue_project
	echo "# the stubs share nothing" > tools/verify/no-overlap
	echo "# factory: no-op" > tools/verify/typecheck
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	echo "src/a.txt:1 test-a broken" > .fixture/fail-test
	run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_eq "caught-lint=1
gate-runs=1
seconds-lint=5
seconds-prepare=1" "$(gate_counts)" "the counts"
}

# What a step that doesn't show wrote into the tree stays: test, past the red
# lint, writes a new file, so the run changed its own inputs and keeps no stamp,
# though one by one test would not have run (the cost the header names).
test_a_step_that_does_not_show_but_wrote_the_tree_keeps_no_stamp() {
	fixture_git_project
	echo "# the stubs share nothing" > tools/verify/no-overlap
	git add tools/verify/no-overlap && git commit -qm "no-overlap" || fail "could not commit the no-overlap file"
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	block_step lint .fixture/release-lint
	keep_pid test
	echo "echo snap > src/new.snap" >> .fixture/run-test
	local pid
	bash "$FACTORY_CORE/verify.sh" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr" &
	pid=$!
	wait_until "test to write the tree and end" step_ended test
	touch .fixture/release-lint
	wait "$pid"
	status=$?
	out="$(cat "$TEST_TMP/stdout")"
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_no_line "== test PASS"
	[ -f src/new.snap ] || fail "test wrote no file"
	stderr_has "verify: no gate stamp: the run changed its own inputs (the tree, the brief or the run state)"
}

# missed_term_project <trap>: parallel_project whose lint fails once test's script
# has started block-a, a blocking stand-in; test's script runs `trap <trap> TERM`
# first, then block-a, then block-b, and notes in .fixture/unreleased-<x> each
# stand-in its hang guard ended (exit 124). With `trap : TERM` it is a step that missed the
# stop's TERM, as one bash forks while the TERM comes does (bash's TERM handler,
# the job's trap, is still in place in the child until its exec, and catches it):
# it runs on past the TERM, and starts block-b, which never got it.
missed_term_project() {
	parallel_project
	echo "src/a.txt:2 lint-bad a lint finding" > .fixture/fail-lint
	blocking_stand_in "$PWD/.fixture/wait-a" "$PWD/.fixture/block-a.pid"
	echo "bash .fixture/wait-a" > .fixture/run-lint
	blocking_stand_in "$PWD/.fixture/block-a" "$PWD/.fixture/never"
	blocking_stand_in "$PWD/.fixture/block-b" "$PWD/.fixture/never"
	cat > tools/verify/test << SH
trap $1 TERM
bash .fixture/block-a; [ "\$?" -ne 124 ] || touch .fixture/unreleased-a
bash .fixture/block-b; [ "\$?" -ne 124 ] || touch .fixture/unreleased-b
SH
}

# The stop sends its TERM again: a process the step started after the first one
# (block-b) ends by it, and the run doesn't wait for its hang guard.
test_the_stop_reaches_a_process_started_after_its_first_term() {
	missed_term_project :
	run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	[ ! -e .fixture/unreleased-b ] || fail "the run waited for block-b until its hang guard ran out"
	[ -s .fixture/block-b.pid ] || fail "test never started block-b: the case is not under test"
	wait_until "block-b to end" stand_in_ended b
}

# A step that ignores TERM outright (its tools inherit that) gets KILL once the
# stop's grace (FACTORY_STEP_STOP_GRACE seconds after the second TERM) runs out.
test_the_stop_kills_a_step_that_ignores_term() {
	missed_term_project "''"
	FACTORY_STEP_STOP_GRACE=1 run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	[ ! -e .fixture/unreleased-a ] || fail "the run waited for block-a until its hang guard ran out"
	wait_until "block-a to end" stand_in_ended a
}
