# The gate stamp (lib/stamp.sh): verify keeps each verdict, and --reuse prints it
# again while everything the verdict depends on is unchanged.

ALL_STEPS="prepare format typecheck lint deviation test smoke"

# stamped: a git fixture whose last full verify left a stamp; .fixture/ran is
# cleared, so ran_steps names only what runs after.
# shellcheck disable=SC2120 # the options are optional; most calls pass none
stamped() {
	fixture_git_project
	run_verify "$@"
	rm -f .fixture/ran
}

# assert_reused: the last run printed a stamp's verdict and ran no step.
assert_reused() {
	assert_eq "" "$(ran_steps)" "a step ran instead of the stamp's verdict"
	stderr_has "this is the verdict of the run at"
}

# assert_fresh: the last run ran every step.
assert_fresh() {
	assert_eq "$ALL_STEPS" "$(ran_steps)" "the run reused a verdict it should not have"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_reuse_prints_the_same_verdict_without_running_a_step() {
	stamped
	first="$out"
	run_verify --reuse
	assert_status 0
	assert_eq "$first" "$out" "the reused verdict differs"
	assert_reused
}

test_reuse_keeps_a_failed_verdict_and_its_exit_code() {
	fixture_git_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	first="$out"
	rm -f .fixture/ran .fixture/fail-lint
	run_verify --reuse
	assert_status 1
	assert_eq "$first" "$out" "the reused verdict differs"
	assert_last_line "verify: FAILED at step lint"
	assert_reused
}

test_reuse_runs_fresh_with_no_stamp() {
	fixture_git_project
	run_verify --reuse
	assert_status 0
	assert_fresh
	stderr_has "no gate stamp for these inputs"
}

test_reuse_runs_fresh_after_a_tracked_file_changes() {
	stamped
	echo two > src/a.txt
	run_verify --reuse
	assert_fresh
}

test_reuse_runs_fresh_after_a_staged_change() {
	stamped
	echo two > src/a.txt
	git add src/a.txt
	run_verify --reuse
	assert_fresh
}

# The index alone differs: the working file and its status are the same.
test_reuse_runs_fresh_after_only_the_index_changes() {
	fixture_git_project
	echo two > src/a.txt
	git add src/a.txt
	echo three > src/a.txt
	run_verify
	rm -f .fixture/ran
	echo four > src/a.txt
	git add src/a.txt
	echo three > src/a.txt
	run_verify --reuse
	assert_fresh
}

# A tracked file that is also ignored: unstaging its removal changes only its
# status, which a step that lists the index's files sees.
test_reuse_runs_fresh_after_a_staged_removal_is_undone() {
	fixture_git_project
	echo src/a.txt >> .git/info/exclude
	echo two > src/a.txt
	git rm -q --cached src/a.txt || fail "no git rm"
	run_verify
	rm -f .fixture/ran
	git reset -q HEAD -- src/a.txt
	run_verify --reuse
	assert_fresh
}

test_reuse_runs_fresh_after_the_hooks_path_changes() {
	stamped
	git config core.hooksPath /nowhere
	run_verify --reuse
	assert_fresh
}

test_a_changed_nested_repo_gets_no_stamp() {
	fixture_git_project
	git init -q src/inner || fail "no nested repo"
	echo one > src/inner/x.txt
	run_verify
	stderr_has "this checkout can't be keyed"
	ls .git/factory/*.stamp > /dev/null 2>&1 && fail "a stamp was kept for a tree the key can't read"
	rm -f .fixture/ran
	run_verify --reuse
	assert_fresh
}

# git status skips a submodule that .gitmodules marks ignore=all; the key reads it anyway.
test_an_ignored_submodule_change_gets_no_stamp() {
	fixture_git_project
	local dep="$TEST_TMP/dep"
	mkdir -p "$dep" && git -C "$dep" init -q && echo one > "$dep/value" &&
		git -C "$dep" add value && git -C "$dep" commit -q -m one || fail "no submodule repo"
	git -c protocol.file.allow=always submodule add -q "$dep" vendor/dep > /dev/null 2>&1 || fail "no submodule"
	git config -f .gitmodules submodule.vendor/dep.ignore all
	git add -A && git commit -q -m dep || fail "could not commit the submodule"
	run_verify
	[ -f .git/factory/verify-green.all.stamp ] || fail "no stamp for a clean submodule:"$'\n'"$(cat "$TEST_TMP/stderr")"
	echo two > vendor/dep/value
	rm -f .fixture/ran
	run_verify --reuse
	assert_fresh
	stderr_has "this checkout can't be keyed"
}

# git status stops reading a tracked file marked assume-unchanged or skip-worktree.
test_a_file_git_status_skips_gets_no_stamp() {
	local flag
	for flag in --assume-unchanged --skip-worktree; do
		fixture_git_project
		git update-index "$flag" src/a.txt || fail "could not mark src/a.txt $flag"
		run_verify
		stderr_has "this checkout can't be keyed"
		ls .git/factory/*.stamp > /dev/null 2>&1 && fail "a stamp was kept with a file marked $flag"
		cd "$TEST_TMP" && rm -rf "${TEST_TMP:?}/project"
	done
}

# scenario_worktree: fixture_git_project whose tools/verify/scenario-folder names
# scenarios/, which holds two tracked Scenarios (one with a name git quotes
# unless core.quotePath is off), pushed as an origin's dev; then
# start.sh makes issue 7's worktree, whose sparse checkout leaves the folder out
# (git ls-files -v tags the Scenario S), and the test runs there.
scenario_worktree() {
	fixture_git_project
	printf 'scenarios/\n' > tools/verify/scenario-folder
	printf '#!/usr/bin/env bash\n# factory: no-op\n' > tools/verify/bootstrap
	mkdir -p scenarios && echo play > scenarios/serve.gd && echo play > scenarios/réserve.gd
	echo /.claude/worktrees/ >> .gitignore
	git add -A && git commit -q -m scenarios || fail "could not commit the Scenario"
	git init -q --bare -b dev "$TEST_TMP/origin.git" && git remote add origin "$TEST_TMP/origin.git" &&
		git push -q origin HEAD:dev 2> /dev/null || fail "could not push dev"
	run_cmd bash "$FACTORY_CORE/start.sh" 7
	assert_status 0
	cd "$out" || fail "no issue worktree"
	[ ! -e scenarios ] || fail "the worktree holds the Scenario folder"
	git ls-files -v | grep -qx 'S scenarios/serve.gd' || fail "git doesn't skip the Scenario:"$'\n'"$(git ls-files -v)"
}

# stamp_key: the key the green stamp of every step was kept under.
stamp_key() {
	sed -n 's/^key //p' "$(git rev-parse --git-dir)/factory/verify-green.all.stamp"
}

# #13: an issue's worktree that leaves only the Scenario folder out is keyed, so
# --reuse prints the Editor's verdict and the gate's counts are kept.
test_an_issue_worktree_without_its_scenario_folder_keeps_its_stamp_and_counts() {
	scenario_worktree
	mkdir -p .fixture
	echo 100 > "$TEST_TMP/clock"
	printf 'echo 102 > %q\n' "$TEST_TMP/clock" > .fixture/run-prepare
	export FACTORY_STEP_CLOCK="$TEST_TMP/clock"
	run_verify
	assert_status 0
	! grep -qF "can't be keyed" "$TEST_TMP/stderr" || fail "the worktree got no key:"$'\n'"$(cat "$TEST_TMP/stderr")"
	[ -f "$(git rev-parse --git-dir)/factory/verify-green.all.stamp" ] || fail "no stamp in the worktree's git dir"
	first="$out"
	local counted
	counted="$(issue_counts)"
	printf '%s\n' "$counted" | grep -qx 'gate-runs=1' || fail "the run wasn't counted: $counted"
	printf '%s\n' "$counted" | grep -qx 'seconds-prepare=2' || fail "no seconds counted: $counted"
	rm -f .fixture/ran
	run_verify --reuse
	assert_status 0
	assert_eq "$first" "$out" "the reused verdict differs"
	assert_reused
	assert_eq "$counted" "$(issue_counts)" "a reused verdict counted"
	echo two > src/a.txt
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	assert_status 1
	issue_counts | grep -qx 'caught-lint=1' || fail "no catch counted: $(issue_counts)"
	rm -f .fixture/ran
	run_verify --reuse
	assert_status 1
	assert_reused
}

# Only the Scenario folder may be skipped, and only by start.sh's own sparse
# rule: any other skipped path, or another rule, gets no key, as before.
test_a_worktree_that_skips_more_than_the_scenario_folder_gets_no_stamp() {
	scenario_worktree
	local gitdir
	gitdir="$(git rev-parse --git-dir)"
	run_verify
	[ -f "$gitdir/factory/verify-green.all.stamp" ] || fail "no stamp for start.sh's own sparse checkout"
	rm -rf "$gitdir/factory"
	# git keeps the mark only on a file the checkout lacks: so git status
	# doesn't list it as deleted.
	rm src/a.txt && git update-index --skip-worktree src/a.txt || fail "could not skip src/a.txt"
	git ls-files -v | grep -qx 'S src/a.txt' || fail "git doesn't skip src/a.txt"
	run_verify
	stderr_has "this checkout can't be keyed"
	[ ! -e "$gitdir/factory/verify-green.all.stamp" ] || fail "a stamp was kept with src/a.txt skipped"
	git update-index --no-skip-worktree src/a.txt && git checkout -q -- src/a.txt || fail "could not stop skipping src/a.txt"
	local rule
	for rule in '!/tests/' '!/nothing/'; do
		git sparse-checkout set --no-cone '/*' '!/scenarios/' "$rule" 2> /dev/null || fail "could not set the rule $rule"
		run_verify
		stderr_has "this checkout can't be keyed"
		[ ! -e "$gitdir/factory/verify-green.all.stamp" ] || fail "a stamp was kept under the sparse rule ending $rule"
	done
	git sparse-checkout set --no-cone '/*' '!/scenarios/' || fail "could not restore the rule"
	git update-index --assume-unchanged tools/verify/lint || fail "could not mark a file assume-unchanged"
	run_verify
	stderr_has "this checkout can't be keyed"
	[ ! -e "$gitdir/factory/verify-green.all.stamp" ] || fail "a stamp was kept with a file marked assume-unchanged"
}

# A full checkout of the same commit doesn't take a sparse one's verdict: the
# sparse rule is in the key, though the gate's steps never read the folder.
test_a_full_checkout_of_the_same_commit_keys_apart_from_the_sparse_one() {
	scenario_worktree
	run_verify
	local sparse_key
	sparse_key="$(stamp_key)"
	[ -n "$sparse_key" ] || fail "no stamp for the sparse checkout"
	git sparse-checkout disable || fail "could not undo the sparse checkout"
	[ -f scenarios/serve.gd ] || fail "the full checkout has no Scenario"
	rm -f .fixture/ran
	run_verify --reuse
	assert_fresh
	[ "$(stamp_key)" != "$sparse_key" ] || fail "the full checkout kept the sparse checkout's key"
}

# The sparse rule is in the key: with every other input the same, a changed
# rule runs fresh.
test_reuse_runs_fresh_after_the_sparse_rule_changes() {
	fixture_git_project
	git sparse-checkout set --no-cone '/*' 2> /dev/null || fail "could not set a sparse rule"
	run_verify
	rm -f .fixture/ran
	git sparse-checkout set --no-cone '/*' '!/nothing/' 2> /dev/null || fail "could not change the sparse rule"
	run_verify --reuse
	assert_fresh
}

# git config lists a key's values in its own order, and the last one wins.
test_reuse_runs_fresh_after_the_winning_config_value_changes() {
	fixture_git_project
	git config --add core.factorytest one && git config --add core.factorytest two
	run_verify
	rm -f .fixture/ran
	git config --unset-all core.factorytest && git config --add core.factorytest two && git config --add core.factorytest one
	run_verify --reuse
	assert_fresh
}

# A base given by name is keyed by the commit it names.
test_reuse_runs_fresh_after_a_named_base_moves() {
	fixture_git_project
	git commit -q --allow-empty -m two && git branch cmp-base HEAD~1 || fail "no base branch"
	FACTORY_BASE=cmp-base run_verify
	rm -f .fixture/ran
	git branch -f cmp-base HEAD
	FACTORY_BASE=cmp-base run_verify --reuse
	assert_fresh
	rm -f .fixture/ran
	FACTORY_BASE=no-such-base run_verify
	stderr_has "this checkout can't be keyed"
}

test_a_factory_variable_from_local_env_keeps_the_stamp() {
	fixture_git_project
	echo "FACTORY_BASE_BRANCH=dev" >> tools/verify/local.env
	run_verify
	[ -f .git/factory/verify-green.all.stamp ] || fail "no stamp:"$'\n'"$(cat "$TEST_TMP/stderr")"
	rm -f .fixture/ran
	run_verify --reuse
	assert_reused
}

test_reuse_runs_fresh_after_an_untracked_file_appears() {
	stamped
	echo new > src/b.txt
	run_verify --reuse
	assert_fresh
}

test_reuse_runs_fresh_after_a_file_is_deleted() {
	stamped
	rm src/a.txt
	run_verify --reuse
	assert_fresh
}

test_reuse_runs_fresh_after_a_mode_change() {
	stamped
	chmod +x src/a.txt
	git config core.fileMode true
	run_verify --reuse
	assert_fresh
}

test_the_key_writes_nothing_to_the_repo() {
	fixture_git_project
	echo two > src/a.txt
	echo new > src/b.txt
	before="$(git count-objects -v | grep '^count:')"
	run_verify
	[ -f .git/factory/verify-green.all.stamp ] || fail "no stamp"
	assert_eq "$before" "$(git count-objects -v | grep '^count:')" "the key wrote objects to the repo"
}

test_reuse_ignores_an_ignored_file() {
	stamped
	echo scratch > .fixture/scratch.txt
	run_verify --reuse
	assert_reused
}

test_reuse_runs_fresh_after_a_commit_of_the_same_tree() {
	stamped
	git commit -q --allow-empty -m "same tree" || fail "no commit"
	run_verify --reuse
	assert_fresh
}

test_reuse_runs_fresh_after_the_brief_changes() {
	fixture_git_project
	brief "Phase: green"
	run_verify
	rm -f .fixture/ran
	brief "Phase: red"
	run_verify --reuse
	assert_fresh
}

test_reuse_runs_fresh_after_the_run_state_changes() {
	stamped
	git config branch.work.factory-red-commit "$(git rev-parse HEAD)"
	run_verify --reuse
	assert_fresh
}

test_reuse_ignores_the_round_count() {
	stamped
	git config branch.work.factory-rounds-green 1
	run_verify --reuse
	assert_reused
}

test_reuse_runs_fresh_after_the_diff_base_moves() {
	stamped
	FACTORY_BASE="$(git rev-parse HEAD)" run_verify --reuse
	assert_fresh
}

test_reuse_runs_fresh_after_local_env_changes() {
	stamped
	echo "EXTRA_TOOL=/opt/tool" >> tools/verify/local.env
	run_verify --reuse
	assert_fresh
}

test_each_mode_and_step_list_keeps_its_own_stamp() {
	stamped
	run_verify lint
	run_verify --keep-going
	rm -f .fixture/ran
	run_verify --reuse
	assert_reused
	run_verify --reuse lint
	assert_reused
	run_verify --reuse --keep-going
	assert_reused
	run_verify --reuse --red
	[ -n "$(ran_steps)" ] || fail "a red run reused a green verdict"
	stderr_has "no gate stamp for these inputs"
}

test_reuse_runs_fresh_when_the_caller_wants_the_results_file() {
	stamped
	FACTORY_RESULTS_FILE="$TEST_TMP/results" run_verify --reuse
	assert_fresh
	[ -s "$TEST_TMP/results" ] || fail "no results file"
	stderr_has "only a fresh run writes"
}

test_a_run_that_changes_its_inputs_keeps_no_stamp() {
	fixture_git_project
	printf '%s\n' '#!/usr/bin/env bash' 'echo changed >> src/a.txt' '. "$(dirname "$0")/_stub.sh" smoke' > tools/verify/smoke
	git commit -qam "a smoke step that writes" || fail "no commit"
	run_verify
	stderr_has "the run changed its own inputs"
	git checkout -q -- src/a.txt
	rm -f .fixture/ran
	run_verify --reuse
	stderr_has "no gate stamp for these inputs"
}

test_twice_keeps_no_stamp_and_refuses_reuse() {
	fixture_git_project
	run_verify --twice
	assert_status 0
	ls .git/factory/*.stamp > /dev/null 2>&1 && fail "--twice kept a stamp"
	run_verify --twice --reuse
	assert_status 2
}

test_no_stamp_variable_keeps_none() {
	fixture_git_project
	FACTORY_NO_STAMP=1 run_verify
	ls .git/factory/*.stamp > /dev/null 2>&1 && fail "FACTORY_NO_STAMP=1 kept a stamp"
	return 0
}

test_a_stamp_whose_verdict_disagrees_with_its_exit_code_is_not_reused() {
	stamped
	stamp=.git/factory/verify-green.all.stamp
	[ -f "$stamp" ] || fail "no stamp at $stamp"
	sed -i 's/^exit 0$/exit 1/' "$stamp"
	run_verify --reuse
	assert_status 0
	assert_fresh
}

test_a_stamp_under_another_key_is_not_reused() {
	stamped
	stamp=.git/factory/verify-green.all.stamp
	sed -i 's/^key .*/key 0000000000000000000000000000000000000000/' "$stamp"
	run_verify --reuse
	assert_fresh
}

test_the_stamp_lives_in_the_worktrees_own_git_dir() {
	fixture_git_project
	git worktree add -q -b other ../other || fail "no worktree"
	cd ../other || fail "no worktree folder"
	cp ../project/tools/verify/local.env tools/verify/local.env
	run_verify
	[ -f "$(git rev-parse --git-dir)/factory/verify-green.all.stamp" ] || fail "no stamp in the worktree's git dir"
	[ -f ../project/.git/factory/verify-green.all.stamp ] && fail "the worktree wrote the main checkout's stamp"
	return 0
}

test_baseline_gate_passes_reuse_to_verify() {
	fixture_git_project
	bash "$FACTORY_CORE/baseline.sh" record > /dev/null 2>&1 || fail "no baseline"
	git commit -qm "baseline" || fail "no commit"
	run_cmd bash "$FACTORY_CORE/baseline.sh" gate
	assert_status 0
	rm -f .fixture/ran
	run_cmd bash "$FACTORY_CORE/baseline.sh" --reuse gate
	assert_status 0
	assert_last_line "baseline: PASS"
	assert_eq "" "$(ran_steps)" "baseline.sh --reuse ran the steps"
}

# --- a git dir the run can't write ---------------------------------------------------

# stderr_notes: run_cmd's stderr without the stub steps' own lines.
stderr_notes() {
	grep -v '^stub [a-z]* done$' "$TEST_TMP/stderr"
}

# green_mutate_project: fixture_git_project with a mutate stub, in the green
# phase, with a change since the base, so the mutate step runs and writes
# .fixture/survivors to the survivors file.
green_mutate_project() {
	fixture_git_project
	printf '#!/usr/bin/env bash\n. "$(dirname "$0")/_stub.sh" mutate\n' > tools/verify/mutate
	git add tools/verify/mutate && git commit -q -m "mutate stub" || fail "could not commit the stub"
	seal_stub
	bash "$FACTORY_CORE/state.sh" set phase green || fail "could not set the phase"
	echo two > src/a.txt
	echo "src/a.txt:1 survived kept" > .fixture/survivors
	mkdir -p "$TEST_TMP/job"
}

# A stamp that can't be written costs one line on stderr, and never the verdict.
test_a_stamp_the_git_dir_cannot_hold_costs_one_line_not_the_verdict() {
	fixture_git_project
	rm -rf .git/factory && : > .git/factory
	run_verify
	assert_status 0
	assert_last_line "verify: PASS"
	assert_eq "verify: could not write the gate stamp .git/factory/verify-green.all.stamp; --reuse will run fresh" "$(stderr_notes)" "the notes on stderr"
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_eq "verify: could not write the gate stamp .git/factory/verify-green.all.stamp; --reuse will run fresh" "$(stderr_notes)" "the notes on stderr"
	[ -f .git/factory ] || fail "the run replaced the file standing in for the stamps' folder"
	return 0
}

# A git dir that can't hold the stamps (a file where its factory/ folder goes),
# and the survivors file set to one of the caller's own: a fresh green run
# mutates and writes it there.
test_a_git_dir_that_cannot_hold_the_factory_folder_writes_the_survivors_file_where_the_caller_says() {
	green_mutate_project
	rm -rf .git/factory && : > .git/factory
	FACTORY_SURVIVORS_FILE="$TEST_TMP/job/survivors.txt" run_verify
	assert_status 0
	assert_line "== mutate PASS"
	assert_last_line "verify: PASS"
	assert_eq "src/a.txt:1 survived kept" "$(cat "$TEST_TMP/job/survivors.txt")" "the job's survivors file"
	assert_eq "verify: could not write the gate stamp .git/factory/verify-green.all.stamp; --reuse will run fresh" "$(stderr_notes)" "the notes on stderr"
	[ -f .git/factory ] || fail "the run replaced the file standing in for the stamps' folder"
}

# The Driver's run kept the stamp; the git dir's survivors file has gone since.
# --reuse with the git dir read-only puts the verdict's file back where the
# caller reads it.
test_reuse_with_a_read_only_git_dir_puts_the_survivors_file_where_the_caller_says() {
	green_mutate_project
	run_verify
	first="$out"
	rm -f .fixture/ran .git/factory/survivors.txt
	chmod -R a-w .git
	FACTORY_SURVIVORS_FILE="$TEST_TMP/job/survivors.txt" run_verify --reuse
	chmod -R u+w .git
	assert_status 0
	assert_eq "$first" "$out" "the reused verdict differs"
	assert_reused
	assert_eq "src/a.txt:1 survived kept" "$(cat "$TEST_TMP/job/survivors.txt")" "the job's survivors file"
}

# --- the gate's counts (verify.sh, lib/run.sh) ----------------------------------------

# issue_counts: issue 7's gate counts in its run state, one key=value a line, sorted.
issue_counts() {
	bash "$FACTORY_CORE/state.sh" --branch issue/7 list | grep -e '^gate-runs=' -e '^caught-' -e '^seconds-'
}

# A run that counts itself in the run state, which the key reads, keeps its
# stamp; --reuse prints it and counts nothing more.
test_a_counted_run_keeps_its_stamp_and_a_reused_one_counts_nothing() {
	fixture_git_project
	git checkout -q -b issue/7 || fail "no issue branch"
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	run_verify
	first="$out"
	! grep -qF "the run changed its own inputs" "$TEST_TMP/stderr" || fail "the counts cost the stamp"
	[ -f .git/factory/verify-green.all.stamp ] || fail "no stamp"
	local counted
	counted="$(issue_counts)"
	printf '%s\n' "$counted" | grep -qx 'caught-lint=1' || fail "no catch counted: $counted"
	rm -f .fixture/ran
	run_verify --reuse
	assert_status 1
	assert_eq "$first" "$out" "the reused verdict differs"
	assert_reused
	assert_eq "$counted" "$(issue_counts)" "a reused verdict counted"
}

# A git dir that can't hold the counted keys or the stamps (a file where its
# factory/ folder goes): the count is skipped with one line, as the stamp is,
# and the verdict and exit code stand.
test_a_count_the_git_dir_cannot_hold_costs_one_line_not_the_verdict() {
	fixture_git_project
	git checkout -q -b issue/7 || fail "no issue branch"
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	rm -rf .git/factory && : > .git/factory
	run_verify
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_eq "verify: could not count this run in the run state of issue/7 (gate-runs, caught-<step>, seconds-<step>) or list its key as counted; the verdict stands
verify: could not write the gate stamp .git/factory/verify-green.all.stamp; --reuse will run fresh" "$(stderr_notes)" "the notes on stderr"
	assert_eq "" "$(issue_counts)" "counts in a git dir that can't be written"
}

# The counted keys can't be written (a folder where their file goes) while the
# run state can: the run counts nothing, with the one line, so a rerun on its inputs can't count it twice.
test_a_run_that_cannot_list_its_key_counts_nothing() {
	fixture_git_project
	git checkout -q -b issue/7 || fail "no issue branch"
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	mkdir -p .git/factory/gate-counted
	run_verify lint
	run_verify lint
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
	assert_eq "verify: could not count this run in the run state of issue/7 (gate-runs, caught-<step>, seconds-<step>) or list its key as counted; the verdict stands" "$(stderr_notes)" "the notes on stderr"
	assert_eq "" "$(issue_counts)" "a run counted with no key listed"
}

# --all-static (#15): its green verdict is the plain run's, so plain --reuse
# reads it; one that went on past a failure keeps no stamp.
test_reuse_reads_a_green_all_static_runs_stamp() {
	stamped --all-static
	assert_status 0
	run_verify --reuse
	assert_status 0
	assert_reused
}

test_an_all_static_run_that_went_on_past_a_failure_keeps_no_stamp() {
	fixture_git_project
	echo "src/a.txt:1 lint-a broken" > .fixture/fail-lint
	echo "src/a.txt:1 type-a broken" > .fixture/fail-typecheck
	run_verify --all-static
	assert_status 1
	stderr_has "verify: no gate stamp: --all-static went on past the failing step typecheck"
	rm -f .fixture/ran
	run_verify --reuse
	assert_eq "prepare format typecheck" "$(ran_steps)" "a plain --reuse read the all-static run's verdict"
}
