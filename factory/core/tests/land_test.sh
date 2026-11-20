# land.sh: rebase onto dev, full verify, push, fast-forward dev, remove the worktree.

run_land() {
	run_cmd bash "$FACTORY_CORE/land.sh" "$@"
}

# started <n> [kind]: start issue <n> and set $wt to its worktree; with a kind,
# as an issue whose body is `Kind: <kind>` (start.sh starts only a cleanup while
# the Baseline holds findings).
started() {
	if [ "$#" -ge 2 ]; then
		wt="$(printf 'Kind: %s\n' "$2" | bash "$FACTORY_CORE/start.sh" "$1" --title "Issue $1" 2> /dev/null)" || fail "start.sh failed"
	else
		wt="$(bash "$FACTORY_CORE/start.sh" "$1" 2> /dev/null)" || fail "start.sh failed"
	fi
}

# remote_dev: origin's dev SHA.
remote_dev() {
	git --git-dir="$TEST_TMP/origin.git" rev-parse dev
}

test_lands_a_green_branch_rebased_onto_a_moved_dev() {
	fixture_repo
	export FACTORY_NOW=1000
	started 7
	commit_in "$wt" c.txt work
	seal_stub --issue 7
	bash "$FACTORY_CORE/state.sh" --issue 7 set phase green
	bash "$FACTORY_CORE/state.sh" --issue 7 incr fails-brief > /dev/null
	push_from_elsewhere b.txt upstream
	run_land 7
	assert_status 0
	assert_eq "$(remote_dev)" "$(git rev-parse dev)" "local dev is not origin/dev"
	assert_eq "work" "$(git show dev:c.txt)" "the branch's commit did not land"
	assert_eq "upstream" "$(git show dev:b.txt)" "the landed dev dropped upstream work"
	assert_eq "work" "$(cat c.txt)" "the main checkout's dev was not fast-forwarded"
	assert_line "  state: phase=green"
	assert_line "  state: fails-brief=1"
	assert_line "factory-stats: issue=7 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=1 rejected=0 uncounted=0 escalations=0 self-ruled=0 minutes=0 minutes-brief=0 minutes-green=0"
	[ ! -e "$wt" ] || fail "the worktree is still there"
	git show-ref --verify --quiet refs/heads/issue/7 && fail "the branch is still there"
	git config branch.issue/7.factory-phase > /dev/null && fail "the run state outlived the branch"
	return 0
}

# The verify Land runs is the branch's own copy of the gate, so a branch that
# changed the gate would grade itself: Land refuses it unless the Driver sealed a
# Kind amend brief.
test_refuses_a_branch_that_changes_the_gate_unless_a_sealed_amend() {
	fixture_repo
	started 7
	mkdir -p "$wt/tools/verify" "$wt/factory/core"
	commit_in "$wt" tools/verify/lint "exit 0"
	commit_in "$wt" factory/core/verify.sh "echo verify: PASS"
	commit_in "$wt" c.txt work
	local before brief
	before="$(remote_dev)"
	run_land 7
	assert_status 1
	assert_line "  gate: tools/verify/lint"
	assert_line "  gate: factory/core/verify.sh"
	assert_no_line "  gate: c.txt"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
	brief="$(git -C "$wt" rev-parse --path-format=absolute --git-dir)/factory/brief.md"
	mkdir -p "$(dirname "$brief")"
	printf '# Build Brief: #7 An amend\n\nKind: amend. Phase: green.\n' > "$brief"
	seal_stub --issue 7
	run_land 7
	assert_status 1
	assert_line "  gate: tools/verify/lint"
	bash "$FACTORY_CORE/state.sh" --issue 7 set brief-sha "$(git hash-object --no-filters "$brief")" > /dev/null || fail "could not seal"
	run_land 7
	assert_status 0
	assert_line "land: this amend changes the gate's own files:"
	assert_line "  gate: tools/verify/lint"
	assert_eq "exit 0" "$(git show dev:tools/verify/lint)" "the amend did not land"
}

# A ratchet folder made a symlink, or a submodule under factory/, is read by
# nothing the deviation step runs: only an amend lands it.
test_refuses_a_ratchet_symlink_and_a_gate_submodule() {
	fixture_repo
	mkdir -p tools/verify/ratchet && printf 'a\n' > tools/verify/ratchet/baseline.txt
	git add -A && git commit -q -m baseline && git push -q origin dev 2> /dev/null || fail "could not push the Baseline"
	started 7 cleanup
	mkdir -p "$wt/src" && git -C "$wt" mv tools/verify/ratchet src/ratchet && printf 'a\nb\n' > "$wt/src/ratchet/baseline.txt" &&
		ln -s ../../src/ratchet "$wt/tools/verify/ratchet" && git -C "$wt" add -A && git -C "$wt" commit -q -m move || fail "could not move the ratchet"
	run_land 7
	assert_status 1
	assert_line "  gate: tools/verify/ratchet"
	git -C "$wt" reset -q --hard origin/dev || fail "could not reset"
	local dep="$TEST_TMP/dep"
	mkdir -p "$dep" && git -C "$dep" init -q && echo one > "$dep/value" && git -C "$dep" add value && git -C "$dep" commit -q -m one || fail "no submodule repo"
	git -C "$wt" -c protocol.file.allow=always submodule add -q "$dep" factory/plugin > /dev/null 2>&1 || fail "no submodule"
	git -C "$wt" config -f .gitmodules submodule.factory/plugin.ignore all
	git -C "$wt" add -A && git -C "$wt" commit -q -m plugin || fail "could not commit the submodule"
	run_land 7
	assert_status 1
	assert_line "  gate: factory/plugin"
}

# Ratchet files and the Baseline are the deviation step's: they shrink on any
# issue (a cleanup's Driver commits the Baseline's shrink).
test_lands_a_branch_that_changes_only_ratchet_files() {
	fixture_repo
	mkdir -p tools/verify/ratchet && printf 'a\nb\n' > tools/verify/ratchet/baseline.txt
	git add -A && git commit -q -m baseline && git push -q origin dev 2> /dev/null || fail "could not push the Baseline"
	started 7 cleanup
	commit_in "$wt" tools/verify/ratchet/baseline.txt a
	run_land 7
	assert_status 0
	assert_eq "a" "$(git show dev:tools/verify/ratchet/baseline.txt)"
}

test_lands_with_dev_not_checked_out() {
	fixture_repo
	git checkout -q --detach
	started 7
	commit_in "$wt" c.txt work
	run_land 7
	assert_status 0
	assert_eq "$(remote_dev)" "$(git rev-parse dev)"
	assert_eq "work" "$(git show dev:c.txt)"
}

test_red_verify_refuses_to_fast_forward() {
	fixture_repo
	started 7
	commit_in "$wt" red bad
	before_remote="$(remote_dev)"
	before_local="$(git rev-parse dev)"
	run_land 7
	assert_status 1
	assert_line "land: verify is red on the rebased branch; dev not moved"
	assert_line "  red:1 fixture-red the tree holds red"
	assert_last_line "land: the steps printed nothing else; the log is $TEST_TMP/main/.git/factory/land-7.log"
	assert_eq "$before_remote" "$(remote_dev)" "origin/dev moved"
	assert_eq "$before_local" "$(git rev-parse dev)" "local dev moved"
	[ -e "$wt/.git" ] || fail "the worktree was removed"
}

# verify_stub: fixture_repo with stdin as its tools/verify.sh, committed and pushed,
# so Land can be seen choosing between the full run and `--red`.
verify_stub() {
	fixture_repo
	cat > tools/verify.sh
	git add -A && git commit -q -m "stub verify" && git push -q origin dev 2> /dev/null || fail "could not commit the stub verify"
}

# The red gate passes while the brief's new tests fail: it must never land a branch.
test_red_phase_is_refused_when_only_the_red_gate_passes() {
	verify_stub << 'SH'
if [ "${1:-}" = --red ] || [ "${1:-}" = prepare ]; then echo "verify: PASS"; exit 0; fi
echo "c.txt:1 fixture-full the full run ran"; echo "verify: FAILED at step test"; exit 1
SH
	started 7
	commit_in "$wt" c.txt work
	seal_stub --issue 7
	bash "$FACTORY_CORE/state.sh" --issue 7 set phase red
	before_remote="$(remote_dev)"
	before_local="$(git rev-parse dev)"
	run_land 7
	assert_status 1
	assert_line "land: verify is red on the rebased branch; dev not moved"
	assert_line "  c.txt:1 fixture-full the full run ran"
	assert_eq "$before_remote" "$(remote_dev)" "origin/dev moved"
	assert_eq "$before_local" "$(git rev-parse dev)" "local dev moved"
	[ -e "$wt/.git" ] || fail "the worktree was removed"
}

test_red_phase_lands_when_the_full_verify_passes() {
	verify_stub << 'SH'
if [ "${1:-}" = --red ]; then echo "c.txt:1 fixture-red-gate the red gate ran"; echo "verify: FAILED at step test"; exit 1; fi
echo "verify: PASS"
SH
	started 7
	commit_in "$wt" c.txt work
	seal_stub --issue 7
	bash "$FACTORY_CORE/state.sh" --issue 7 set phase red
	run_land 7
	assert_status 0
	assert_eq "$(remote_dev)" "$(git rev-parse dev)" "local dev is not origin/dev"
	assert_eq "work" "$(git show dev:c.txt)" "the branch's commit did not land"
}

# noisy_verify <exit>: a tools/verify.sh that prints its verdict as verify does,
# each line after the step it judges, and marks each step on stderr as verify
# does under FACTORY_STEP_MARK: prepare prints 5 lines to stderr and passes, then
# test prints 30, the last in colour with a CRLF, as an engine and a test runner
# do, and passes (0) or fails.
noisy_verify() {
	verify_stub << SH
if [ "\${1:-}" = prepare ]; then echo "== prepare PASS"; echo "verify: PASS"; exit 0; fi
m="\${FACTORY_STEP_MARK:-}"
unset FACTORY_STEP_MARK
[ -z "\$m" ] || echo "\$m prepare" >&2
for i in \$(seq 1 5); do echo "prepare noise \$i" >&2; done
echo "== prepare PASS"
[ -z "\$m" ] || echo "\$m test" >&2
for i in \$(seq 1 29); do echo "step noise \$i" >&2; done
printf '\\033[90mstep noise 30\\033[0m\\r\\n' >&2
[ -z "\$m" ] || echo "\$m" >&2
if [ $1 -eq 0 ]; then echo "== test PASS"; echo "verify: PASS"; exit 0; fi
echo "== test FAIL"; echo "tests/a_test.gd:3 test-failed test_it fails"; echo "verify: FAILED at step test"; exit 1
SH
}

# #157's Land printed the whole verify log, about 300 KB: the steps' output goes
# to a log that outlives the worktree, and stdout keeps the verdict.
# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_a_green_land_keeps_the_steps_output_in_a_log() {
	local log="$TEST_TMP/main/.git/factory/land-7.log"
	noisy_verify 0
	started 7
	commit_in "$wt" c.txt work
	run_land 7
	assert_status 0
	assert_line "land: verify passed on the rebased branch; the steps' output is in $log"
	assert_line "  == prepare PASS"
	assert_line "  == test PASS"
	assert_line "  verify: PASS"
	assert_line "land: landed issue/7 on origin/dev at $(remote_dev)"
	grep -q "noise" <<< "$out" && fail "the steps' output reached stdout:"$'\n'"$out"
	grep -q "noise" "$TEST_TMP/stderr" && fail "the steps' output reached stderr"
	[ ! -e "$wt" ] || fail "the worktree is still there"
	assert_eq "land.sh 7: verify (the green phase: every step must pass), on issue/7 at $(remote_dev)" "$(head -n 1 "$log")" "the log's header"
	assert_eq "prepare noise 1" "$(sed -n 2p "$log")" "the log doesn't hold the steps' output"
	assert_eq "step noise 1" "$(sed -n 7p "$log")" "the log kept the runner's mark between the steps"
	grep -q "land.sh-mark-" "$log" && fail "a mark line reached the log"
	assert_eq "land.sh: the gate exited 0; its verdict:
== prepare PASS
== test PASS
verify: PASS" "$(tail -n 4 "$log")" "the log doesn't end with the exit code and the verdict"
}

# A red gate prints the verdict, then the failing step's last lines, none of an
# earlier step's, and the log's path, so the Driver can act without opening it.
test_a_red_land_prints_the_failing_steps_last_lines_and_the_log() {
	local log="$TEST_TMP/main/.git/factory/land-7.log" i
	noisy_verify 1
	started 7
	commit_in "$wt" c.txt work
	before="$(remote_dev)"
	run_land 7
	assert_status 1
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
	assert_line "land: verify is red on the rebased branch; dev not moved"
	assert_line "  == test FAIL"
	assert_line "  tests/a_test.gd:3 test-failed test_it fails"
	assert_line "  verify: FAILED at step test"
	assert_line "land: the last lines the failing step, test, printed, of the whole output in $log:"
	for i in $(seq 11 30); do
		assert_line "  | step noise $i"
	done
	assert_no_line "  | step noise 10"
	assert_last_line "  | step noise 30"
	grep -q "noise" "$TEST_TMP/stderr" && fail "the steps' output reached stderr"
	grep -qxF "step noise 1" "$log" || fail "the log lacks the steps' output"
	assert_eq "verify: FAILED at step test" "$(tail -n 1 "$log")" "the log doesn't end with the verdict"
	# A rerun writes the log afresh.
	run_land 7
	assert_eq 1 "$(grep -cxF "step noise 1" "$log")" "the log kept the last Land's output"
}

# real_runner <prepare's script> <lint's script> [tools/verify.sh]: fixture_repo
# with the Core's runner as its tools/verify.sh (or that script), over the
# fixture project's stub steps, but for a prepare and a lint that run that
# script first; lint fails with a finding once .fixture/fail-lint is there
# (gitignored, so the tree stays clean).
real_runner() {
	fixture_repo
	cp -R "$FIXTURE_SRC/tools/verify/." tools/verify/ || fail "could not copy the stub steps"
	cp tools/verify/local.env.example tools/verify/local.env
	# shellcheck disable=SC2016 # the script's own expansions
	local runner='exec bash "$FACTORY_CORE/verify.sh" "$@"'
	printf '%s\n' "${3:-$runner}" > tools/verify.sh
	# start.sh runs prepare too: the step's own script runs only at Land, once
	# .fixture/landing is there.
	printf 'if [ -e .fixture/landing ]; then\n%s\nfi\n. "$(dirname "$0")/_stub.sh" prepare\n' "$1" > tools/verify/prepare
	printf '%s\n. "$(dirname "$0")/_stub.sh" lint\n' "$2" > tools/verify/lint
	printf '/.fixture/\n' >> .gitignore
	git add -A && git commit -q -m "real runner" && git push -q origin dev 2> /dev/null || fail "could not commit the runner"
	started 7
	commit_in "$wt" c.txt work
	mkdir -p "$wt/.fixture"
	: > "$wt/.fixture/landing"
	echo "src/a.txt:1 lint-bad a lint finding" > "$wt/.fixture/fail-lint"
}

# shellcheck disable=SC2016 # each step's script, expanded by the step
PREPARE_NOISE='for i in $(seq 1 30); do echo "prepare noise $i" >&2; done'

# The step that fails printed nothing: Land says so, and prints no earlier
# step's output as its tail.
test_a_red_land_with_a_silent_failing_step_prints_no_other_steps_output() {
	local log="$TEST_TMP/main/.git/factory/land-7.log"
	real_runner "$PREPARE_NOISE" ''
	run_land 7
	assert_status 1
	assert_line "  == prepare PASS"
	assert_line "  == lint FAIL"
	assert_line "  src/a.txt:1 lint-bad a lint finding"
	assert_last_line "land: the failing step, lint, printed nothing else; the log is $log"
	grep -q "noise" <<< "$out" && fail "an earlier step's output reached stdout:"$'\n'"$out"
	grep -qxF "prepare noise 30" "$log" || fail "the log lacks prepare's output"
}

test_a_red_land_under_the_runner_prints_only_the_failing_steps_lines() {
	# shellcheck disable=SC2016
	real_runner "$PREPARE_NOISE" 'for i in $(seq 1 3); do echo "lint noise $i" >&2; done'
	run_land 7
	assert_status 1
	assert_line "  | lint noise 1"
	assert_last_line "  | lint noise 3"
	grep -q "prepare noise" <<< "$out" && fail "an earlier step's output reached stdout:"$'\n'"$out"
	return 0
}

# A step's text never moves the bounds of its output: a line that reads like
# verify's, or a last line with no newline, stays in the step's tail.
test_a_red_land_bounds_a_steps_output_whatever_it_prints() {
	local log="$TEST_TMP/main/.git/factory/land-7.log"
	real_runner "printf '== prepare FAIL\\ncompiler missing\\n' >&2; exit 1" ''
	run_land 7
	assert_status 1
	assert_line "  == prepare FAIL"
	assert_line "land: the last lines the failing step, prepare, printed, of the whole output in $log:"
	assert_line "  | == prepare FAIL"
	assert_last_line "  | compiler missing"
}

# A step that prints the instant it starts: Land read verify's line for the step
# before only after that, so its first lines were counted as the step before's
# and left its tail. Here the project's verify hands its verdict on only once
# it ends, so Land reads every line of it after every step has printed: the
# bounds come from the runner's marks on stderr, not from when Land reads it.
test_a_red_land_bounds_a_step_that_prints_the_instant_it_starts() {
	local log="$TEST_TMP/main/.git/factory/land-7.log"
	# shellcheck disable=SC2016 # each script's own expansions
	real_runner "$PREPARE_NOISE" 'for i in 1 2 3; do echo "lint noise $i" >&2; done' \
		'verdict="$(bash "$FACTORY_CORE/verify.sh" "$@")"; status=$?; printf "%s\n" "$verdict"; exit "$status"'
	run_land 7
	assert_status 1
	assert_line "  == typecheck PASS"
	assert_line "  == lint FAIL"
	assert_eq "land: the last lines the failing step, lint, printed, of the whole output in $log:
  | lint noise 1
  | lint noise 2
  | lint noise 3" "$(printf '%s\n' "$out" | sed -n '/^land: the last lines/,$p')" "the tail isn't lint's lines alone"
	grep -qxF "stub typecheck done" "$log" || fail "the log lacks the step before's output"
	grep -q "land.sh-mark-" "$log" && fail "a mark line reached the log"
	return 0
}

# A step that prints its environment shows no mark: the runner keeps it from the
# steps, so their text can't move the bounds.
test_a_red_land_keeps_the_mark_from_the_steps() {
	# shellcheck disable=SC2016
	real_runner "$PREPARE_NOISE" 'env | grep "^FACTORY_" | sed "s/^/lint env: /" >&2; echo "lint noise" >&2'
	run_land 7
	assert_status 1
	assert_line "  | lint env: FACTORY_LAND=7"
	assert_last_line "  | lint noise"
	grep -q "STEP_MARK" <<< "$out" && fail "a step saw the mark:"$'\n'"$out"
	return 0
}

test_a_red_land_keeps_a_steps_unended_last_line_apart() {
	local log="$TEST_TMP/main/.git/factory/land-7.log"
	real_runner "printf 'compiler missing' >&2; exit 1" ''
	run_land 7
	assert_status 1
	assert_last_line "  | compiler missing"
	assert_eq "compiler missing" "$(sed -n 2p "$log")" "the step's unended line ran into the next"
	assert_eq "land.sh: the gate exited 1; its verdict:" "$(sed -n 3p "$log")" "the verdict doesn't start on a line of its own"
}

# Nothing reads survivors after Land, so its verify skips mutate, saying why in
# the log, and runs every other step; a verify of the same green branch outside
# Land still mutates.
test_lands_verify_skips_the_mutate_step() {
	local log="$TEST_TMP/main/.git/factory/land-7.log"
	fixture_repo
	cp -R "$FIXTURE_SRC/tools/verify/." tools/verify/ || fail "could not copy the stub steps"
	cp tools/verify/local.env.example tools/verify/local.env
	# shellcheck disable=SC2016 # the scripts' own expansions
	printf 'exec bash "$FACTORY_CORE/verify.sh" "$@"\n' > tools/verify.sh
	# shellcheck disable=SC2016
	printf '#!/usr/bin/env bash\n. "$(dirname "$0")/_stub.sh" mutate\n' > tools/verify/mutate
	printf '/.fixture/\n' >> .gitignore
	git add -A && git commit -q -m "real runner" && git push -q origin dev 2> /dev/null || fail "could not commit the runner"
	started 7
	commit_in "$wt" c.txt work
	seal_stub --issue 7
	bash "$FACTORY_CORE/state.sh" --issue 7 set phase green
	(cd "$wt" && bash tools/verify.sh mutate > "$TEST_TMP/outside" 2> /dev/null)
	assert_eq "== mutate PASS
verify: PASS" "$(cat "$TEST_TMP/outside")" "a verify outside Land didn't mutate"
	run_land 7
	assert_status 0
	assert_line "  == test PASS"
	assert_line "  == mutate SKIP"
	assert_line "  == smoke PASS"
	assert_line "  verify: PASS"
	grep -qxF "verify: mutate: no mutants: Land's verify mutates nothing: no Verifier reads its survivors" "$log" ||
		fail "the log lacks the skip's reason:"$'\n'"$(cat "$log")"
	assert_eq "work" "$(git show dev:c.txt)" "the branch did not land"
}

test_rebase_conflict_is_reported_and_nothing_is_half_landed() {
	fixture_repo
	started 7
	commit_in "$wt" a.txt mine
	branch_head="$(git -C "$wt" rev-parse HEAD)"
	push_from_elsewhere a.txt theirs
	before_remote="$(remote_dev)"
	before_local="$(git rev-parse dev)"
	run_land 7
	assert_status 3
	assert_line "land: rebase conflict onto origin/dev (an uncounted round); rebase aborted, dev not moved"
	assert_line "  conflict: a.txt"
	assert_eq "$before_remote" "$(remote_dev)" "origin/dev moved"
	assert_eq "$before_local" "$(git rev-parse dev)" "local dev moved"
	assert_eq "$branch_head" "$(git -C "$wt" rev-parse HEAD)" "the branch was left rewritten"
	assert_eq "issue/7" "$(git -C "$wt" symbolic-ref --short HEAD)" "the rebase was left in progress"
	assert_eq "" "$(git -C "$wt" status --porcelain)" "the worktree was left dirty"
}

test_refuses_a_dirty_worktree() {
	fixture_repo
	started 7
	commit_in "$wt" c.txt work
	echo loose > "$wt/loose.txt"
	before_remote="$(remote_dev)"
	run_land 7
	assert_status 1
	assert_eq "$before_remote" "$(remote_dev)" "origin/dev moved"
	[ -e "$wt/loose.txt" ] || fail "the loose file was touched"
}

test_leaves_local_dev_alone_when_it_has_unpushed_commits() {
	fixture_repo
	started 7
	commit_in "$wt" c.txt work
	commit_in . d.txt local-only
	run_land 7
	assert_status 0
	assert_line "land: local dev has commits origin does not; left it alone"
	assert_eq "local-only" "$(git show dev:d.txt)"
	assert_eq "work" "$(git --git-dir="$TEST_TMP/origin.git" show dev:c.txt)"
}

test_keeps_a_copied_local_env_out_of_the_way() {
	fixture_repo
	echo "FIXTURE_TOOL=/opt/tool" > tools/verify/local.env
	started 7
	commit_in "$wt" c.txt work
	run_land 7
	assert_status 0
	[ ! -e "$wt" ] || fail "the worktree is still there"
}

test_missing_worktree_fails() {
	fixture_repo
	run_land 7
	assert_status 1
	run_land x
	assert_status 2
}

test_a_diff_base_in_factory_base_does_not_move_the_landing_branch() {
	fixture_repo
	started 7
	commit_in "$wt" c.txt work
	FACTORY_BASE="$(git rev-parse dev)" run_land 7
	assert_status 0
	assert_eq "work" "$(git --git-dir="$TEST_TMP/origin.git" show dev:c.txt)" "did not land on dev"
}

# partial_repo: fixture_repo with the fixture project's stub steps, so the Core
# runner and baseline.sh run in it, and a Baseline of one lint finding.
partial_repo() {
	fixture_repo
	cp -R "$FIXTURE_SRC/tools/verify/." tools/verify/ || fail "could not copy the stub steps"
	cp tools/verify/local.env.example tools/verify/local.env
	mkdir -p tools/verify/ratchet
	echo "src/a.txt long-line line too long" > tools/verify/ratchet/baseline.txt
	printf '/.fixture/\n' >> .gitignore
	git add -A && git commit -q -m "stub steps" && git push -q origin dev 2> /dev/null || fail "could not commit the stub steps"
}

test_partial_mode_lands_on_the_baseline_gate() {
	partial_repo
	export FACTORY_NOW=1000
	started 7 cleanup
	seal_stub --issue 7
	bash "$FACTORY_CORE/state.sh" --issue 7 set phase partial
	bash "$FACTORY_CORE/state.sh" --issue 7 incr rounds-partial > /dev/null
	bash "$FACTORY_CORE/state.sh" --issue 7 incr fails-partial > /dev/null
	bash "$FACTORY_CORE/state.sh" --issue 7 incr escalations > /dev/null
	bash "$FACTORY_CORE/state.sh" --issue 7 incr self-ruled > /dev/null
	mkdir -p "$wt/.fixture"
	echo "src/a.txt:9 long-line line too long" > "$wt/.fixture/fail-lint"
	commit_in "$wt" c.txt cleanup
	run_land 7
	assert_status 0
	assert_eq "cleanup" "$(git show dev:c.txt)" "the branch's commit did not land"
	assert_line "factory-stats: issue=7 lane=cleanup rounds-red=0 rounds-green=0 rounds-partial=1 fails-red=0 fails-green=0 fails-partial=1 fails-brief=0 rejected=0 uncounted=0 escalations=1 self-ruled=1 minutes=0 minutes-brief=0 minutes-partial=0"
}

test_partial_mode_refuses_a_finding_outside_the_baseline() {
	partial_repo
	started 7 cleanup
	seal_stub --issue 7
	bash "$FACTORY_CORE/state.sh" --issue 7 set phase partial
	mkdir -p "$wt/.fixture"
	echo "src/b.txt:1 unused-var x is unused" > "$wt/.fixture/fail-lint"
	commit_in "$wt" c.txt cleanup
	before="$(remote_dev)"
	run_land 7
	assert_status 1
	assert_line "land: the Baseline gate is red on the rebased branch; dev not moved"
	assert_line "land: the last lines the steps printed, of the whole output in $TEST_TMP/main/.git/factory/land-7.log:"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

# The stats line's minutes: from start.sh to land, cut where each phase began.
test_the_stats_line_counts_the_minutes_from_start_to_land() {
	fixture_repo
	FACTORY_NOW=1000 started 7
	commit_in "$wt" c.txt work
	seal_stub --issue 7
	FACTORY_NOW=1300 bash "$FACTORY_CORE/state.sh" --issue 7 set phase red
	FACTORY_NOW=2500 bash "$FACTORY_CORE/state.sh" --issue 7 set phase green
	FACTORY_NOW=4360 run_land 7
	assert_status 0
	assert_line "  state: started=1000"
	assert_line "  state: began-red=1300"
	assert_line "factory-stats: issue=7 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0 minutes=56 minutes-brief=5 minutes-red=20 minutes-green=31"
}

# An issue started before start.sh recorded the time lands with no minutes, not 0.
test_an_issue_with_no_start_time_lands_with_no_minutes() {
	fixture_repo
	started 7
	commit_in "$wt" c.txt work
	git config --unset branch.issue/7.factory-started || fail "start.sh recorded no start"
	seal_stub --issue 7
	bash "$FACTORY_CORE/state.sh" --issue 7 set phase green
	run_land 7
	assert_status 0
	assert_line "factory-stats: issue=7 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0"
}
