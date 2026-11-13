# verify.sh --keep-going: every step runs, and the verdict names the first failure.

test_keep_going_runs_every_step_after_a_failure() {
	fixture_project
	echo "src/a.txt:1 lint-a first" > .fixture/fail-lint
	echo "src/b.txt:2 smoke-b second" > .fixture/fail-smoke
	run_verify --keep-going
	assert_status 1
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)" "wrong steps ran"
	assert_line "src/a.txt:1 lint-a first"
	assert_line "src/b.txt:2 smoke-b second"
	assert_last_line "verify: FAILED at step lint"
}

test_keep_going_passes_a_green_project() {
	fixture_project
	run_verify --keep-going
	assert_status 0
	assert_last_line "verify: PASS"
}

test_without_keep_going_the_run_still_stops() {
	fixture_project
	echo "src/a.txt:1 lint-a first" > .fixture/fail-lint
	run_verify
	assert_status 1
	assert_eq "prepare format typecheck lint" "$(ran_steps)" "the run did not stop at lint"
}
