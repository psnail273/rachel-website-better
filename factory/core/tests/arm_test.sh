# arm.sh: an Adopted project (adopt_project, then adopt.sh, committed) switched to
# enforce, or refused.

arm() {
	run_cmd bash factory/core/arm.sh "$@"
}

hook_mode() {
	grep -v '^#' tools/verify/hook-mode
}

test_a_green_project_is_armed_and_pre_commit_then_blocks() {
	adopted
	arm
	assert_status 0
	assert_eq enforce "$(hook_mode)" "the hook mode"
	assert_eq "M  tools/verify/hook-mode" "$(git status --porcelain)" "arm left more than the staged hook mode"
	stderr_has "verify: verify: two runs match"
	git commit -q -m arm || fail "could not commit the arming"
	# A locked test, then an edit to it.
	git checkout -q -b work || fail "no work branch"
	mkdir -p tests && echo test_new > tests/a_test.txt
	git add -A && git commit -q -m red || fail "could not commit the red phase"
	run_cmd bash factory/core/lock.sh record
	assert_status 0
	echo test_changed >> tests/a_test.txt
	git add tests/a_test.txt
	head="$(git rev-parse HEAD)"
	run_cmd git commit -q -m "edit the locked test"
	assert_status 1
	stderr_has "pre-commit: refused (the project is Armed)"
	assert_eq "$head" "$(git rev-parse HEAD)" "the commit went in"
}

test_arm_refuses_a_red_verify() {
	adopted
	mkdir -p .fixture && echo "src/a.txt:1 fake-rule a finding" > .fixture/fail-lint
	arm
	assert_status 1
	stderr_has "refused: verify is red (verify: FAILED at step lint)"
	assert_eq report "$(hook_mode)" "the refused arm changed the hook mode"
	assert_eq "" "$(git status --porcelain)" "the refused arm changed the tree"
}

test_arm_refuses_differing_outputs() {
	adopted
	mkdir -p .fixture && echo 0 > .fixture/vary-lint
	arm
	assert_status 1
	stderr_has "refused: two verify runs gave different output"
	assert_eq report "$(hook_mode)" "the refused arm changed the hook mode"
}

test_arm_refuses_a_non_empty_baseline_before_running_verify() {
	adopted finding
	arm
	assert_status 1
	stderr_has "refused: the Baseline (tools/verify/ratchet/baseline.txt) still holds 1 entries"
	[ ! -e .fixture/ran ] || fail "verify ran"
	assert_eq report "$(hook_mode)" "the refused arm changed the hook mode"
}

test_an_armed_project_stays_armed() {
	adopted
	arm
	assert_status 0
	git commit -q -m arm || fail "could not commit the arming"
	mkdir -p .fixture && echo "src/a.txt:1 fake-rule a finding" > .fixture/fail-lint
	arm
	assert_status 0
	stderr_has "already Armed"
	assert_eq "" "$(git status --porcelain)" "arming twice changed the tree"
}

test_arm_refuses_a_project_that_has_not_adopted() {
	adopt_project
	arm
	assert_status 1
	stderr_has "hasn't adopted the factory"
}

test_arm_takes_no_arguments() {
	adopted
	arm now
	assert_status 2
}
