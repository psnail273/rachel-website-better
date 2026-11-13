# The run-twice mode: two runs on the same tree must print the same bytes.

test_twice_passes_when_runs_match() {
	fixture_project
	run_verify --twice
	assert_status 0
	assert_last_line "verify: two runs match"
	assert_line "verify: PASS"
	assert_eq "prepare format typecheck lint deviation test smoke prepare format typecheck lint deviation test smoke" "$(ran_steps)" "did not run verify twice"
}

test_twice_fails_when_runs_differ() {
	fixture_project
	echo 0 > .fixture/vary-lint
	run_verify --twice
	assert_status 1
	assert_last_line "verify: two runs differ"
	assert_line "  < src/vary.txt:1 vary run 1"
	assert_line "  > src/vary.txt:2 vary run 2"
}

test_twice_keeps_a_red_verdict_that_repeats() {
	fixture_project
	echo "src/a.txt:1 rule broken" > .fixture/fail-test
	run_verify --twice
	assert_status 1
	assert_line "verify: FAILED at step test"
	assert_last_line "verify: two runs match"
}

test_twice_runs_a_subset() {
	fixture_project
	run_verify --twice lint
	assert_status 0
	assert_eq "lint lint" "$(ran_steps)"
}

test_twice_passes_keep_going_to_both_runs() {
	fixture_project
	echo "src/a.txt:1 lint-a first" > .fixture/fail-lint
	run_verify --twice --keep-going
	assert_status 1
	assert_eq "prepare format typecheck lint deviation test smoke prepare format typecheck lint deviation test smoke" "$(ran_steps)" "a run stopped at the failure"
	assert_line "verify: FAILED at step lint"
	assert_last_line "verify: two runs match"
}
