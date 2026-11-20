# state.sh: a Run's state in the issue branch's git config.

run_state() {
	run_cmd bash "$FACTORY_CORE/state.sh" "$@"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_a_value_set_in_one_process_is_read_by_a_fresh_one() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	run_state set phase red
	assert_status 0
	run_state set red-commit 0123abc
	run_state get phase
	assert_status 0
	assert_eq "red" "$out"
	run_state get red-commit
	assert_eq "0123abc" "$out"
}

test_state_is_shared_between_the_worktree_and_the_main_checkout() {
	fixture_repo
	wt="$(bash "$FACTORY_CORE/start.sh" 7 2> /dev/null)" || fail "start failed"
	(cd "$wt" && seal_stub && bash "$FACTORY_CORE/state.sh" set phase green) || fail "set failed"
	run_state --issue 7 get phase
	assert_status 0
	assert_eq "green" "$out"
	run_state --branch issue/7 get phase
	assert_eq "green" "$out"
	run_state get phase
	assert_status 1
	assert_eq "" "$out" "dev's state leaked from the issue branch"
}

test_incr_counts_rounds_per_phase_from_zero() {
	fixture_repo
	git checkout -q -b issue/7
	run_state incr rounds-red
	assert_eq "1" "$out"
	run_state incr rounds-red
	assert_eq "2" "$out"
	run_state incr rounds-green
	assert_eq "1" "$out"
	run_state get rounds-red
	assert_eq "2" "$out"
}

test_incr_counts_the_retros_counts_and_nothing_else() {
	fixture_repo
	git checkout -q -b issue/7
	for key in fails-red fails-green fails-brief rejected uncounted escalations self-ruled; do
		run_state incr "$key"
		assert_status 0
		assert_eq "1" "$out" "$key did not count from zero"
	done
	run_state incr rejected
	assert_eq "2" "$out"
	for key in bootstrap issue fails- fails-Red; do
		run_state incr "$key"
		assert_status 2
	done
	run_state set uncounted one
	assert_status 2
	run_state set escalations 3
	assert_status 0
}

# A phase's counted rounds stop at the ceiling of 4 (the cap of 2 and the
# Driver's 2 extra): a 5th is refused, its count left at 4, and the other phases
# count on as before.
test_incr_refuses_a_fifth_counted_round_in_a_phase() {
	fixture_repo
	git checkout -q -b issue/7
	for n in 1 2 3 4; do
		run_state incr rounds-green
		assert_status 0
		assert_eq "$n" "$out"
	done
	run_state incr rounds-green
	assert_status 1
	assert_eq "" "$out"
	stderr_has "state: rounds-green is at 4, the ceiling of 4 counted rounds in a phase; send no more counted rounds: the next step is the Sonnet Takeover or an escalation"
	run_state get rounds-green
	assert_eq "4" "$out" "a refused round was counted"
	run_state incr rounds-red
	assert_status 0
	assert_eq "1" "$out"
	run_state incr rounds-partial
	assert_status 0
	assert_eq "1" "$out"
	run_state incr fails-green
	assert_status 0
	run_state incr self-ruled
	assert_status 0
	run_state --issue 7 incr rounds-green
	assert_status 1
	run_state get rounds-green
	assert_eq "4" "$out"
}

# A parked issue never lands, so the retro reads its numbers from state.sh stats.
test_stats_prints_an_issues_stats_line() {
	fixture_repo
	git checkout -q -b issue/7
	run_state incr escalations
	run_state incr rounds-red
	run_state incr fails-brief
	run_state incr self-ruled
	run_state incr self-ruled
	run_state stats
	assert_status 0
	assert_eq "factory-stats: issue=7 lane=standard rounds-red=1 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=1 rejected=0 uncounted=0 escalations=1 self-ruled=2" "$out"
	git checkout -q dev
	run_state --issue 7 stats
	assert_status 0
	run_state --branch dev stats
	assert_status 2
}

test_list_prints_every_key_sorted_and_unset_removes_one() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	FACTORY_NOW=1000 run_state set phase red
	run_state incr rounds-red
	run_state set bootstrap 'done'
	run_state list
	assert_status 0
	assert_eq "began-red=1000
bootstrap=done
brief-sha=0123abcd
phase=red
rounds-red=1" "$out"
	run_state unset bootstrap
	assert_status 0
	run_state unset bootstrap
	assert_status 0
	run_state get bootstrap
	assert_status 1
}

test_unset_key_reads_as_exit_1() {
	fixture_repo
	git checkout -q -b issue/7
	run_state get red-commit
	assert_status 1
	assert_eq "" "$out"
}

test_unknown_keys_and_bad_values_are_usage_errors() {
	fixture_repo
	git checkout -q -b issue/7
	run_state set colour red
	assert_status 2
	run_state set phase blue
	assert_status 2
	run_state set brief-sha not-a-hash
	assert_status 2
	run_state set rounds-red two
	assert_status 2
	run_state incr phase
	assert_status 2
	run_state get rounds-
	assert_status 2
	# The retired keys: the Cursor Editor's chat, and the roles an issue once chose.
	for key in chat-id editor verifier; do
		run_state set "$key" sonnet
		assert_status 2
	done
	run_state list
	assert_eq "" "$out" "a refused write was stored"
}

test_detached_head_needs_a_branch() {
	fixture_repo
	git checkout -q --detach
	run_state get phase
	assert_status 2
}

# The Driver seals the brief (brief.sh seal) before any round: until then no
# phase is set, so no gate runs on a brief the Driver hasn't checked.
test_a_phase_waits_for_the_sealed_brief() {
	fixture_repo
	git checkout -q -b issue/7
	run_state set phase red
	assert_status 1
	stderr_has "issue/7's Build Brief isn't sealed; run bash factory/core/brief.sh seal in its worktree first"
	run_state get phase
	assert_status 1
	run_state set bootstrap 'done'
	assert_status 0
	seal_stub
	run_state set phase red
	assert_status 0
}

# The lane is the sealed brief's (brief.sh seal); the stats line names it, and a
# lift of its Lock counts after the fixed counts.
test_the_small_lane_comes_from_the_brief_and_shows_in_the_stats() {
	fixture_repo
	git checkout -q -b issue/7
	run_state set lane small
	assert_status 2
	stderr_has "state: the lane is the Build Brief's; add 'lane small' to its block and run bash factory/core/brief.sh seal"
	run_state get lane
	assert_status 1
	git config branch.issue/7.factory-lane small
	run_state incr lifts
	assert_eq "1" "$out"
	run_state stats
	assert_status 0
	assert_eq "factory-stats: issue=7 lane=small rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0 lifts=1" "$out"
	run_state unset lane
	assert_status 0
	run_state stats
	assert_eq "factory-stats: issue=7 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0 lifts=1" "$out"
}

# The Editor's gate's stamp is that gate's to record (#60): set refuses it, get
# and unset take it, and the stats line leaves it out.
test_the_editors_gate_stamp_is_the_gates_alone() {
	local sha
	fixture_repo
	git checkout -q -b issue/7
	sha="$(git rev-parse HEAD)"
	run_state set editor-gate "- $sha"
	assert_status 2
	stderr_has "state: editor-gate is the Editor's gate's stamp: only that gate records it as it passes"
	run_state get editor-gate
	assert_status 1
	git config branch.issue/7.factory-editor-gate "- $sha"
	run_state get editor-gate
	assert_status 0
	assert_eq "- $sha" "$out"
	run_state stats
	assert_eq "factory-stats: issue=7 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0" "$out"
	run_state unset editor-gate
	assert_status 0
	git config branch.issue/7.factory-editor-gate > /dev/null && fail "unset left the stamp"
	return 0
}

# The stats line's minutes read when each phase began: the first set of it.
test_set_phase_records_when_the_branch_first_entered_each_phase() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	FACTORY_NOW=1000 run_state set phase red
	assert_status 0
	FACTORY_NOW=2500 run_state set phase green
	FACTORY_NOW=3000 run_state set phase red
	assert_status 0
	run_state get began-red
	assert_eq "1000" "$out" "setting red again moved when it began"
	run_state get began-green
	assert_eq "2500" "$out"
	run_state get phase
	assert_eq "red" "$out"
	run_state set started 900
	assert_status 0
	for bad in "began-red soon" "started 9.5" "began- 1" "began-Red 1"; do
		# shellcheck disable=SC2086 # each case is its words
		run_state set $bad
		assert_status 2
	done
}

# Minutes from the start to each phase, then to now; each mark is rounded from the
# start, so the parts add up to the whole: 90 s, 180 s and 270 s in are marks 2, 3
# and 5 (one minute apart each, rounded alone, would be 2+2+2).
test_stats_counts_the_minutes_from_the_start_through_each_phase_to_now() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	run_state set started 1000
	FACTORY_NOW=1300 run_state set phase red
	FACTORY_NOW=2500 run_state set phase green
	FACTORY_NOW=4360 run_state stats
	assert_status 0
	assert_eq "factory-stats: issue=7 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0 minutes=56 minutes-brief=5 minutes-red=20 minutes-green=31" "$out"
	git checkout -q -b issue/8 dev
	seal_stub
	run_state set started 1000
	FACTORY_NOW=1090 run_state set phase red
	FACTORY_NOW=1180 run_state set phase green
	FACTORY_NOW=1270 run_state stats
	assert_eq "factory-stats: issue=8 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0 minutes=5 minutes-brief=2 minutes-red=1 minutes-green=2" "$out"
	# Red and green in the same second: the time after is green's.
	git checkout -q -b issue/9 dev
	seal_stub
	run_state set started 1000
	FACTORY_NOW=1300 run_state set phase red
	FACTORY_NOW=1300 run_state set phase green
	FACTORY_NOW=2500 run_state stats
	assert_eq "factory-stats: issue=9 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0 minutes=25 minutes-brief=5 minutes-red=0 minutes-green=20" "$out"
}

# An issue start.sh began before it recorded the time has no minutes at all, not 0;
# a phase alone doesn't make them.
test_stats_has_no_minutes_without_a_start_time() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	FACTORY_NOW=1300 run_state set phase partial
	FACTORY_NOW=4360 run_state stats
	assert_status 0
	assert_eq "factory-stats: issue=7 lane=cleanup rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0" "$out"
}

# The gate's counts (verify.sh keeps them) are counts like the others; the stats
# line appends those that aren't 0 after the other counts, gate-runs first, then
# the catches and the seconds in the gate's step order, then the minutes.
test_stats_appends_the_gates_counts_in_step_order() {
	fixture_repo
	git checkout -q -b issue/7
	for key in gate-runs caught-lint seconds-test; do
		run_state incr "$key"
		assert_status 0
	done
	for key in caught- seconds-Lint gate-run; do
		run_state incr "$key"
		assert_status 2
	done
	run_state set seconds-prepare 4
	run_state set seconds-smoke 0
	run_state set caught-test 2
	run_state set gate-runs 3
	run_state incr lifts
	run_state set started 1000
	FACTORY_NOW=1300 run_state stats
	assert_status 0
	assert_eq "factory-stats: issue=7 lane=standard rounds-red=0 rounds-green=0 rounds-partial=0 fails-red=0 fails-green=0 fails-partial=0 fails-brief=0 rejected=0 uncounted=0 escalations=0 self-ruled=0 lifts=1 gate-runs=3 caught-lint=1 caught-test=2 seconds-prepare=4 seconds-test=1 minutes=5 minutes-brief=5" "$out"
}

# Each counted run's seconds add to the step's total; a step at 0 adds nothing.
test_gate_count_adds_a_runs_catch_and_seconds() {
	fixture_repo
	git checkout -q -b issue/7
	bash -c '. "$1/lib/run.sh"; factory_gate_count issue/7 lint prepare=2 format=0 lint=3 &&
		factory_gate_count issue/7 "" prepare=1 lint=4' _ "$FACTORY_CORE" || fail "no count"
	run_state list
	assert_eq "caught-lint=1
gate-runs=2
seconds-lint=7
seconds-prepare=3" "$out"
}
