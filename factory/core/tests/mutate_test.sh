# The optional mutate step's slot (lib/mutate.sh): when the runner runs it, the
# survivors file it must write, and the gate stamp's copy of that file.

SURVIVORS=.git/factory/survivors.txt
STAMP=.git/factory/verify-green.all.stamp

# mutate_project [phase]: fixture_git_project with a mutate stub (_stub.sh), and
# the work branch's phase set (green by default; none for no run state).
mutate_project() {
	fixture_git_project
	printf '#!/usr/bin/env bash\n. "$(dirname "$0")/_stub.sh" mutate\n' > tools/verify/mutate
	git add tools/verify/mutate && git commit -q -m "mutate stub" || fail "could not commit the stub"
	if [ "${1:-green}" != none ]; then
		seal_stub
		bash "$FACTORY_CORE/state.sh" set phase "${1:-green}" || fail "could not set the phase"
	fi
}

# assert_mutate_skipped <reason>: the step was reported skipped for that reason,
# and its stub didn't run.
assert_mutate_skipped() {
	assert_line "== mutate SKIP"
	stderr_has "verify: mutate: no mutants: $1"
	[[ " $(ran_steps) " != *" mutate "* ]] || fail "the mutate stub ran: $(ran_steps)"
}

test_without_a_mutate_script_the_step_is_skipped() {
	fixture_git_project
	seal_stub
	bash "$FACTORY_CORE/state.sh" set phase green || fail "could not set the phase"
	echo two > src/a.txt
	run_verify
	assert_status 0
	assert_line "== mutate SKIP"
	assert_last_line "verify: PASS"
	[ ! -e "$SURVIVORS" ] || fail "a survivors file without a mutate step"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_a_noop_mutate_script_is_skipped() {
	mutate_project
	printf '#!/usr/bin/env bash\n# factory: no-op\n' > tools/verify/mutate
	run_verify mutate
	assert_status 0
	assert_eq "== mutate SKIP
verify: PASS" "$out"
}

test_the_green_phase_mutates_the_change_since_the_base() {
	mutate_project
	echo two > src/a.txt
	printf '%s\n' "# a note" "src/a.txt:1 survived numeric: \`1\` -> \`2\`; tests: tests/a_test.txt" > .fixture/survivors
	echo "src/a.txt:1 mutant-survived numeric" > .fixture/output-mutate
	run_verify
	assert_status 0
	assert_eq "prepare format typecheck lint deviation test mutate smoke" "$(ran_steps)"
	assert_line "== mutate PASS"
	assert_line "src/a.txt:1 mutant-survived numeric"
	assert_eq "$(git rev-parse dev)"$'\n'"$SURVIVORS" "$(cat .fixture/mutate-env)" "the step's base or survivors file"
	assert_eq "$(cat .fixture/survivors)" "$(cat "$SURVIVORS")" "the survivors file"
}

test_an_untracked_file_is_a_change() {
	mutate_project
	echo new > src/b.txt
	run_verify mutate
	assert_status 0
	assert_line "== mutate PASS"
}

test_the_red_phase_mutates_nothing() {
	mutate_project red
	echo two > src/a.txt
	run_verify mutate
	assert_status 0
	assert_mutate_skipped "the red phase mutates nothing; only green does"
	[ ! -e "$SURVIVORS" ] || fail "a survivors file in the red phase"
}

test_the_partial_phase_mutates_nothing() {
	mutate_project partial
	echo two > src/a.txt
	run_verify mutate
	assert_status 0
	assert_mutate_skipped "the partial phase mutates nothing; only green does"
}

test_the_red_gate_mutates_nothing() {
	mutate_project
	echo two > src/a.txt
	run_verify --red mutate
	assert_status 0
	assert_mutate_skipped "the red gate mutates nothing"
}

test_no_run_state_mutates_nothing() {
	mutate_project none
	echo two > src/a.txt
	run_verify mutate
	assert_status 0
	assert_mutate_skipped "no run state: this checkout is on no issue's branch"
}

# amend.sh land verifies with FACTORY_BASE=HEAD: a clean tree has no change.
test_an_empty_diff_mutates_nothing() {
	mutate_project
	FACTORY_BASE=HEAD run_verify mutate
	assert_status 0
	assert_mutate_skipped "nothing changed since the base $(git rev-parse --short HEAD)"
}

# land.sh sets FACTORY_LAND for its verify: no Verifier reads survivors after
# Land, so the step is skipped there, and every other step runs.
test_lands_verify_mutates_nothing() {
	mutate_project
	echo two > src/a.txt
	FACTORY_LAND=7 run_verify
	assert_status 0
	assert_mutate_skipped "Land's verify mutates nothing: no Verifier reads its survivors"
	assert_eq "prepare format typecheck lint deviation test smoke" "$(ran_steps)"
	assert_last_line "verify: PASS"
	[ ! -e "$SURVIVORS" ] || fail "a survivors file from Land's verify"
}

# FACTORY_LAND is in the gate stamp's key: a later --reuse without it, the
# Driver's or the Verifier's, runs fresh and mutates instead of taking Land's
# verdict, which mutated nothing.
test_a_reuse_outside_land_does_not_take_lands_verdict() {
	mutate_project
	echo two > src/a.txt
	FACTORY_LAND=7 run_verify
	rm -f .fixture/ran
	run_verify --reuse
	assert_status 0
	stderr_has "verify: --reuse: no gate stamp for these inputs; running the steps"
	assert_line "== mutate PASS"
	[ -e "$SURVIVORS" ] || fail "the fresh run wrote no survivors file"
}

test_a_failed_step_before_it_under_keep_going_mutates_nothing() {
	mutate_project
	echo two > src/a.txt
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify --keep-going
	assert_status 1
	assert_mutate_skipped "step lint failed, and mutants need a green tree"
	assert_last_line "verify: FAILED at step lint"
}

test_a_step_that_writes_no_survivors_file_fails() {
	mutate_project
	echo two > src/a.txt
	: > .fixture/no-survivors
	run_verify mutate
	assert_status 1
	assert_eq "== mutate FAIL
tools/verify/mutate:1 survivors-missing the mutate step wrote no survivors file; it writes one to \$FACTORY_SURVIVORS_FILE (factory/core/lib/mutate.sh)
verify: FAILED at step mutate" "$out"
}

test_a_run_with_mutate_removes_the_old_survivors_file_first() {
	mutate_project red
	mkdir -p .git/factory && echo stale > "$SURVIVORS"
	run_verify mutate
	assert_status 0
	[ ! -e "$SURVIVORS" ] || fail "the old survivors file outlived a run that didn't mutate"
}

test_a_run_without_mutate_leaves_the_survivors_file() {
	mutate_project
	mkdir -p .git/factory && echo kept > "$SURVIVORS"
	run_verify lint test
	assert_status 0
	assert_eq kept "$(cat "$SURVIVORS")"
}

# The Editor's gate keeps the stamp; a red run then removes the file; the
# Driver's --reuse must put back the file the green verdict came with.
test_reuse_puts_back_the_survivors_file_its_verdict_came_with() {
	mutate_project
	echo two > src/a.txt
	echo "src/a.txt:1 survived kept" > .fixture/survivors
	run_verify
	first="$out"
	run_verify --red
	[ ! -e "$SURVIVORS" ] || fail "the red run left the survivors file"
	rm -f .fixture/ran
	run_verify --reuse
	assert_status 0
	assert_eq "$first" "$out" "the reused verdict differs"
	assert_eq "" "$(ran_steps)" "a step ran instead of the stamp's verdict"
	assert_eq "src/a.txt:1 survived kept" "$(cat "$SURVIVORS")" "the survivors file wasn't put back"
}

test_reuse_of_a_verdict_without_mutants_removes_a_later_file() {
	mutate_project red
	echo two > src/a.txt
	run_verify
	echo stale > "$SURVIVORS"
	rm -f .fixture/ran
	run_verify --reuse
	assert_status 0
	assert_eq "" "$(ran_steps)" "a step ran instead of the stamp's verdict"
	[ ! -e "$SURVIVORS" ] || fail "the reused verdict mutated nothing, but a survivors file is there"
}

test_reuse_without_the_stamps_copy_of_the_file_runs_fresh() {
	mutate_project
	echo two > src/a.txt
	run_verify
	rm -f "$STAMP.survivors" .fixture/ran
	run_verify --reuse
	assert_status 0
	[[ " $(ran_steps) " == *" mutate "* ]] || fail "the run reused a verdict whose survivors file it can't put back: $(ran_steps)"
	stderr_has "can't be put back as the gate stamp's run left it; running the steps"
}

# The Verifier's sandbox can read the git dir but not write it: a file that
# already matches needs no write.
test_reuse_with_a_read_only_git_dir_reads_a_matching_file() {
	mutate_project
	echo two > src/a.txt
	run_verify
	first="$out"
	rm -f .fixture/ran
	chmod a-w .git/factory
	run_verify --reuse
	chmod u+w .git/factory
	assert_status 0
	assert_eq "$first" "$out" "the reused verdict differs"
	assert_eq "" "$(ran_steps)" "a step ran instead of the stamp's verdict"
}
