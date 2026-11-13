# The results Seam and the green gate (lib/results.sh): the default run judges
# the test step from its results file.

# result <name> <status> <file:line>: add a line to the fixture's results.
result() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> .fixture/results
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_all_tests_passing_passes() {
	fixture_project
	result test_one PASS tests/a_test.txt:1
	result "a describe > a test with spaces" PASS tests/b_test.txt:7
	run_verify test
	assert_status 0
	assert_eq "== test PASS
verify: PASS" "$out"
}

test_any_test_that_isnt_pass_fails_naming_it_and_its_status() {
	fixture_project
	result test_one PASS tests/a_test.txt:1
	result test_two FAILURE tests/a_test.txt:5
	result test_three ERROR tests/b_test.txt:2
	result test_four SKIP tests/b_test.txt:9
	run_verify test
	assert_status 1
	assert_eq "== test FAIL
tests/a_test.txt:5 green-not-pass test_two is FAILURE; the green gate needs every test to PASS
tests/b_test.txt:2 green-not-pass test_three is ERROR; the green gate needs every test to PASS
tests/b_test.txt:9 green-not-pass test_four is SKIP; the green gate needs every test to PASS
verify: FAILED at step test" "$out"
}

test_full_run_stops_at_a_red_test_step() {
	fixture_project
	result test_two FAILURE tests/a_test.txt:5
	run_verify
	assert_status 1
	assert_eq "prepare format typecheck lint deviation test" "$(ran_steps)"
	assert_last_line "verify: FAILED at step test"
}

test_missing_results_file_fails() {
	fixture_project
	: > .fixture/no-results
	run_verify test
	assert_status 1
	assert_eq "== test FAIL
tools/verify/test:1 results-missing the test step wrote no results file; it writes one line per test to \$FACTORY_RESULTS_FILE
verify: FAILED at step test" "$out"
}

test_malformed_results_line_fails() {
	fixture_project
	result test_one PASS tests/a_test.txt:1
	result test_two PASSED tests/a_test.txt:2
	printf 'test_three PASS tests/a_test.txt:3\n' >> .fixture/results
	result test_four PASS tests/a_test.txt
	run_verify test
	assert_status 1
	assert_line "tools/verify/test:1 results-format results line 2: expected '<name><TAB><PASS|FAILURE|ERROR|SKIP><TAB><file:line>', got: test_two	PASSED	tests/a_test.txt:2"
	assert_line "tools/verify/test:1 results-format results line 3: expected '<name><TAB><PASS|FAILURE|ERROR|SKIP><TAB><file:line>', got: test_three PASS tests/a_test.txt:3"
	assert_line "tools/verify/test:1 results-format results line 4: expected '<name><TAB><PASS|FAILURE|ERROR|SKIP><TAB><file:line>', got: test_four	PASS	tests/a_test.txt"
}

test_test_listed_twice_fails() {
	fixture_project
	result test_one PASS tests/a_test.txt:1
	result test_one PASS tests/a_test.txt:8
	run_verify test
	assert_status 1
	assert_line "tests/a_test.txt:8 results-duplicate test_one is listed twice in the results"
}

test_failing_test_script_fails_even_when_every_test_passes() {
	fixture_project
	: > .fixture/fail-test
	run_verify test
	assert_status 1
	assert_eq "== test FAIL
verify: FAILED at step test" "$out"
}

test_old_results_file_is_removed_before_the_step() {
	fixture_project
	export FACTORY_RESULTS_FILE="$TEST_TMP/results"
	printf 'test_one\tPASS\ttests/a_test.txt:1\n' > "$FACTORY_RESULTS_FILE"
	: > .fixture/no-results
	run_verify test
	assert_status 1
	assert_line "tools/verify/test:1 results-missing the test step wrote no results file; it writes one line per test to \$FACTORY_RESULTS_FILE"
}

test_noop_test_step_needs_no_results() {
	fixture_project
	printf '#!/usr/bin/env bash\n# factory: no-op\n' > tools/verify/test
	run_verify test
	assert_status 0
	assert_eq "== test SKIP
verify: PASS" "$out"
}
