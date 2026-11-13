# The red gate (verify.sh --red, lib/red.sh) on the fixture project as a git repo.
# The base tests/a_test.txt holds test_old_one and test_old_two on lines 1-2; the
# red phase adds test_new on line 3 and stubs src/a.txt.

# red_brief: tests and the src/a.txt stub in scope; one test, test_new.
red_brief() {
	brief "scope tests/**" "scope src/a.txt" "test test_new" "seam src/a.txt A.stub"
}

# result <name> <status> <file:line>: add a line to the fixture's results.
result() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> .fixture/results
}

# red_phase [status of test_new]: write the red phase (stub plus the new test) and
# its results, test_new with the given status (default FAILURE).
red_phase() {
	echo stub > src/a.txt
	echo test_new >> tests/a_test.txt
	: > .fixture/results
	result test_old_one PASS tests/a_test.txt:1
	result test_old_two PASS tests/a_test.txt:2
	result test_new "${1:-FAILURE}" tests/a_test.txt:3
}

# shellcheck disable=SC2120 # an optional message; most calls take the default
commit_all() {
	git add -A && git commit -q -m "${1:-red}" || fail "commit failed"
}

# generated <glob...>: the project's tools/verify/generated, in the base commit, so
# it isn't itself in the diff.
generated() {
	printf '%s\n' "$@" > tools/verify/generated
	git add -A && git commit -q --amend -m fixture || fail "commit failed"
	git branch -f dev HEAD
}

test_red_phase_with_failing_named_tests_passes() {
	fixture_git_project
	red_brief
	red_phase
	commit_all
	run_verify --red
	assert_status 0
	assert_line "== test PASS"
	assert_last_line "verify: PASS"
}

# A name with spaces, as a TypeScript adapter reports it (`describe > test`).
test_a_named_test_with_spaces_in_its_name_is_judged() {
	fixture_git_project
	brief "scope tests/**" "scope src/a.txt" "test suite > test_new" "seam src/a.txt A.stub"
	red_phase
	: > .fixture/results
	result test_old_one PASS tests/a_test.txt:1
	result "suite > test_new" FAILURE tests/a_test.txt:3
	commit_all
	run_verify --red test
	assert_status 0
	assert_last_line "verify: PASS"
	: > .fixture/results
	result test_old_one PASS tests/a_test.txt:1
	result "suite > test_new" PASS tests/a_test.txt:3
	run_verify --red test
	assert_status 1
	assert_line "tests/a_test.txt:3 red-not-failure suite > test_new is PASS; in the red phase a test the brief names fails with FAILURE"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_red_ignores_the_test_scripts_failing_exit() {
	fixture_git_project
	red_brief
	red_phase
	echo "tests/a_test.txt:3 assert expected 1 got 0" > .fixture/fail-test
	run_verify --red test
	assert_status 0
	assert_eq "== test PASS
tests/a_test.txt:3 assert expected 1 got 0
verify: PASS" "$out"
}

test_named_test_that_passes_errors_or_skips_fails_naming_it_and_its_status() {
	fixture_git_project
	red_brief
	for s in PASS ERROR SKIP; do
		git checkout -q -- . && git clean -qfd src tests
		red_phase "$s"
		run_verify --red test
		assert_status 1
		assert_eq "== test FAIL
tests/a_test.txt:3 red-not-failure test_new is $s; in the red phase a test the brief names fails with FAILURE
verify: FAILED at step test" "$out"
	done
}

test_brief_test_with_no_results_line_fails() {
	fixture_git_project
	brief "scope tests/**" "scope src/a.txt" "test test_new" "test test_other" "seam src/a.txt A.stub"
	red_phase
	run_verify --red test
	assert_status 1
	assert_eq "== test FAIL
$BRIEF:6 red-missing test_other is named in the brief but has no line in the results
verify: FAILED at step test" "$out"
}

test_results_test_the_brief_doesnt_name_fails_when_new() {
	fixture_git_project
	red_brief
	red_phase
	echo test_extra >> tests/a_test.txt
	result test_extra PASS tests/a_test.txt:4
	run_verify --red test
	assert_status 1
	assert_line "tests/a_test.txt:4 red-unnamed test_extra is new but the brief doesn't name it; the red phase adds only the brief's tests"
}

test_results_test_the_brief_doesnt_name_fails_when_not_passing() {
	fixture_git_project
	red_brief
	red_phase
	: > .fixture/results
	result test_old_one PASS tests/a_test.txt:1
	result test_old_two FAILURE tests/a_test.txt:2
	result test_new FAILURE tests/a_test.txt:3
	run_verify --red test
	assert_status 1
	assert_eq "== test FAIL
tests/a_test.txt:2 red-unnamed test_old_two is FAILURE but the brief doesn't name it; only the brief's tests may fail
verify: FAILED at step test" "$out"
}

test_old_passing_tests_the_brief_doesnt_name_pass() {
	fixture_git_project
	red_brief
	red_phase
	run_verify --red test
	assert_status 0
}

test_diff_touching_a_non_test_non_stub_file_fails() {
	fixture_git_project
	brief "scope tests/**" "scope src/**" "test test_new" "seam src/a.txt A.stub"
	red_phase
	echo other > src/b.txt
	commit_all
	run_verify --red test
	assert_status 1
	assert_eq "== test FAIL
src/b.txt:1 red-diff neither a test file (tools/verify/test-paths), a seam's stub file in the brief nor one of the Driver's docs (docs/deviations.md docs/agents/facts.md); the red phase changes only those
verify: FAILED at step test" "$out"
}

test_diff_counts_uncommitted_and_untracked_files() {
	fixture_git_project
	red_brief
	red_phase
	echo other > src/untracked.txt
	echo edited > tools/verify/pins
	run_verify --red test
	assert_status 1
	assert_line "src/untracked.txt:1 red-diff neither a test file (tools/verify/test-paths), a seam's stub file in the brief nor one of the Driver's docs (docs/deviations.md docs/agents/facts.md); the red phase changes only those"
	assert_line "tools/verify/pins:1 red-diff neither a test file (tools/verify/test-paths), a seam's stub file in the brief nor one of the Driver's docs (docs/deviations.md docs/agents/facts.md); the red phase changes only those"
}

test_generated_files_outside_the_scope_pass_committed_and_untracked() {
	fixture_git_project
	generated '**/*.uid'
	red_brief
	red_phase
	echo uid > root.uid
	commit_all
	echo uid > docs.uid
	run_verify --red test
	assert_status 0
	assert_last_line "verify: PASS"
}

test_generated_files_in_the_scope_pass_committed_and_untracked() {
	fixture_git_project
	generated '**/*.uid'
	brief "scope tests/**" "scope src/**" "test test_new" "seam src/a.txt A.stub"
	red_phase
	echo uid > src/a.txt.uid
	commit_all
	echo uid > src/b.txt.uid
	run_verify --red test
	assert_status 0
	assert_last_line "verify: PASS"
}

test_with_no_generated_file_those_files_fail_committed_and_untracked() {
	fixture_git_project
	red_brief
	red_phase
	echo uid > root.uid
	commit_all
	echo uid > src/b.txt.uid
	run_verify --red test
	assert_status 1
	assert_line "root.uid:1 red-diff neither a test file (tools/verify/test-paths), a seam's stub file in the brief nor one of the Driver's docs (docs/deviations.md docs/agents/facts.md); the red phase changes only those"
	assert_line "src/b.txt.uid:1 red-diff neither a test file (tools/verify/test-paths), a seam's stub file in the brief nor one of the Driver's docs (docs/deviations.md docs/agents/facts.md); the red phase changes only those"
}

test_a_file_no_generated_glob_matches_still_fails() {
	fixture_git_project
	generated '**/*.uid'
	red_brief
	red_phase
	echo other > src/b.txt
	run_verify --red test
	assert_status 1
	assert_line "src/b.txt:1 red-diff neither a test file (tools/verify/test-paths), a seam's stub file in the brief nor one of the Driver's docs (docs/deviations.md docs/agents/facts.md); the red phase changes only those"
}

test_test_file_outside_the_scope_fails() {
	fixture_git_project
	brief "scope tests/a_test.txt" "scope src/a.txt" "test test_new" "seam src/a.txt A.stub"
	red_phase
	echo test_b > tests/b_test.txt
	run_verify --red test
	assert_status 1
	assert_line "tests/b_test.txt:1 red-diff outside the brief's scope; the red phase changes only tests, stubs and the Driver's docs in scope"
}

test_missing_results_file_fails() {
	fixture_git_project
	red_brief
	red_phase
	: > .fixture/no-results
	run_verify --red test
	assert_status 1
	assert_line "tools/verify/test:1 results-missing the test step wrote no results file; it writes one line per test to \$FACTORY_RESULTS_FILE"
}

test_brief_with_no_tests_fails() {
	fixture_git_project
	brief "scope tests/**" "scope src/a.txt" "seam src/a.txt A.stub"
	red_phase
	run_verify --red test
	assert_status 1
	assert_line "$BRIEF:1 red-no-tests the brief names no test; the red phase adds at least one"
}

test_missing_brief_fails() {
	fixture_git_project
	red_phase
	run_verify --red test
	assert_status 1
	assert_line "$BRIEF:1 brief-missing no Build Brief at this path"
}

test_missing_test_paths_fails() {
	fixture_git_project
	red_brief
	red_phase
	rm tools/verify/test-paths
	run_verify --red test
	assert_status 1
	assert_line "tools/verify/test-paths:1 test-paths-missing no test-paths file; it lists the globs of the project's test files, one per line"
}

test_red_still_gates_every_other_step() {
	fixture_git_project
	red_brief
	red_phase
	echo "src/a.txt:1 too-long line is too long" > .fixture/fail-lint
	run_verify --red
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
}

test_red_verdict_repeats_under_twice() {
	fixture_git_project
	red_brief
	red_phase PASS
	run_verify --twice --red test
	assert_status 1
	assert_last_line "verify: two runs match"
	assert_line "tests/a_test.txt:3 red-not-failure test_new is PASS; in the red phase a test the brief names fails with FAILURE"
}

test_the_drivers_docs_in_scope_pass() {
	fixture_git_project
	brief "scope tests/**" "scope src/a.txt" "scope docs/deviations.md" "scope docs/agents/facts.md" "test test_new" "seam src/a.txt A.stub"
	red_phase
	mkdir -p docs/agents
	echo "a ruling" > docs/deviations.md
	echo "a fact" > docs/agents/facts.md
	commit_all
	run_verify --red test
	assert_status 0
}

test_a_drivers_doc_outside_the_scope_fails() {
	fixture_git_project
	red_brief
	red_phase
	mkdir -p docs/agents
	echo "a fact" > docs/agents/facts.md
	run_verify --red test
	assert_status 1
	assert_line "docs/agents/facts.md:1 red-diff outside the brief's scope; the red phase changes only tests, stubs and the Driver's docs in scope"
}

test_another_doc_is_no_drivers_doc() {
	fixture_git_project
	brief "scope tests/**" "scope src/a.txt" "scope docs/**" "test test_new" "seam src/a.txt A.stub"
	red_phase
	mkdir -p docs/agents
	echo "notes" > docs/agents/notes.md
	run_verify --red test
	assert_status 1
	assert_line "docs/agents/notes.md:1 red-diff neither a test file (tools/verify/test-paths), a seam's stub file in the brief nor one of the Driver's docs (docs/deviations.md docs/agents/facts.md); the red phase changes only those"
}

# --- the gate's counts in the red phase (verify.sh) ----------------------------------

# red_issue: issue 7's branch in the red phase, its brief and the red phase
# committed; the brief's new test fails, as the red judgement wants.
red_issue() {
	fixture_git_project
	git checkout -q -b issue/7 || fail "no issue branch"
	red_brief
	seal_stub
	bash "$FACTORY_CORE/state.sh" set phase red || fail "no phase"
	red_phase
	commit_all
}

# red_counts: issue 7's catches and counted runs, one key=value a line, sorted.
red_counts() {
	bash "$FACTORY_CORE/state.sh" --branch issue/7 list | grep -e '^gate-runs=' -e '^caught-'
}

# The expected red is no catch: --red passing, or the full verify stopped at test
# by the brief's new tests. --red red on another step is one.
test_the_expected_red_counts_no_catch_and_another_step_does() {
	red_issue
	run_verify --red
	assert_status 0
	assert_eq "gate-runs=1" "$(red_counts)" "--red passing counted a catch"
	run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step test"
	assert_eq "gate-runs=2" "$(red_counts)" "the expected red through the full verify counted a catch"
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	echo three > src/a.txt
	run_verify --red
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_eq "caught-lint=1
gate-runs=3" "$(red_counts)" "--red red on lint"
}

# --red red on test, the red judgement failing (a named test passes), is a catch.
test_a_red_judgement_that_fails_is_a_catch() {
	red_issue
	red_phase PASS
	run_verify --red
	assert_status 1
	assert_last_line "verify: FAILED at step test"
	assert_eq "caught-test=1
gate-runs=1" "$(red_counts)" "the counts"
}
