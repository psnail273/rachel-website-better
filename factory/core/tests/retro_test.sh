# retro.sh: total the factory-stats lines of a Feature's close comments.

# run_retro <file>: retro.sh with that file on stdin.
run_retro() {
	run_cmd bash "$FACTORY_CORE/retro.sh" < "$1"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_totals_counts_lanes_and_lists_each_issue_by_number() {
	cat > comments.txt << 'TXT'
Landed at abc123. Red 1 round, green 0.
factory-stats: issue=12 lane=standard rounds-red=1 rounds-green=0 fails-red=1 rejected=0 uncounted=1 escalations=0
Some other comment.
factory-stats: issue=9 lane=standard rounds-red=0 rounds-green=2 fails-red=0 rejected=1 uncounted=0 escalations=1
factory-stats: issue=100 lane=cleanup rounds-red=0 rounds-green=0 fails-red=0 rejected=0 uncounted=0 escalations=0
TXT
	run_retro comments.txt
	assert_status 0
	assert_eq "retro: 3 issues
lane cleanup: 1
lane standard: 2
gate counts: 0 of 3 issues
rounds-red: 1
rounds-green: 2
fails-red: 1
rejected: 1
uncounted: 1
escalations: 1
issue 9: rounds-green=2 rejected=1 escalations=1
issue 12: rounds-red=1 fails-red=1 uncounted=1" "$out"
}

test_an_issues_last_line_counts_once() {
	cat > comments.txt << 'TXT'
factory-stats: issue=7 lane=standard rounds-red=1
factory-stats: issue=7 lane=standard rounds-red=2
TXT
	run_retro comments.txt
	assert_status 0
	assert_line "retro: 1 issues"
	assert_line "rounds-red: 2"
	assert_line "issue 7: rounds-red=2"
}

test_reads_the_line_inside_markdown_quotes_and_code_marks() {
	printf '%s\r\n' \
		'> factory-stats: issue=4 lane=standard rounds-red=1' \
		'Stats: `factory-stats: issue=5 lane=standard rounds-red=2` (from land.sh)' > comments.txt
	run_retro comments.txt
	assert_status 0
	assert_line "retro: 2 issues"
	assert_line "rounds-red: 3"
	assert_line "issue 5: rounds-red=2"
}

test_reads_the_line_inside_bold() {
	echo '**factory-stats: issue=9 lane=standard rounds-red=1**' > comments.txt
	run_retro comments.txt
	assert_status 0
	assert_line "issue 9: rounds-red=1"
}

test_a_line_naming_a_field_twice_is_skipped() {
	printf '%s\n' \
		'factory-stats: issue=7 lane=standard rounds-red=1 rounds-red=2' \
		'factory-stats: issue=8 lane=standard lane=cleanup rounds-red=1' \
		'factory-stats: issue=9 lane=standard rounds-red=1' > comments.txt
	run_retro comments.txt
	assert_status 0
	assert_line "retro: 1 issues"
	assert_line "rounds-red: 1"
	[ "$(grep -c 'skipped a stats line' "$TEST_TMP/stderr")" -eq 2 ] || fail "not every repeated field was named:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

test_a_line_that_does_not_parse_is_named_and_skipped() {
	cat > comments.txt << 'TXT'
factory-stats: issue=<n> lane=<lane> rounds-red=<n>
factory-stats: issue=3 rounds-red=1
factory-stats: issue=3 lane=standard rounds-red=two
factory-stats: issue=8 lane=standard rounds-red=1
TXT
	run_retro comments.txt
	assert_status 0
	assert_line "retro: 1 issues"
	assert_line "rounds-red: 1"
	stderr_has "skipped a stats line"
	[ "$(grep -c 'skipped a stats line' "$TEST_TMP/stderr")" -eq 3 ] || fail "not every bad line was named:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

test_no_stats_line_exits_1() {
	echo "a comment with no stats" > comments.txt
	run_retro comments.txt
	assert_status 1
	assert_eq "" "$out"
	stderr_has "no factory-stats line found"
}

test_arguments_are_a_usage_error() {
	run_cmd bash "$FACTORY_CORE/retro.sh" 'Milestone 3'
	assert_status 2
}

# land.sh's line, read back by retro.sh, gives the run state's counts.
test_reads_the_line_lib_run_prints() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	bash "$FACTORY_CORE/state.sh" set phase green || fail "no phase"
	bash "$FACTORY_CORE/state.sh" incr rounds-red > /dev/null
	bash "$FACTORY_CORE/state.sh" incr fails-red > /dev/null
	bash "$FACTORY_CORE/state.sh" incr uncounted > /dev/null
	bash -c '. "$1/lib/steps.sh"; . "$1/lib/run.sh"; factory_stats_line issue/7 7' _ "$FACTORY_CORE" > comments.txt || fail "no stats line"
	run_retro comments.txt
	assert_status 0
	assert_line "lane standard: 1"
	assert_line "issue 7: rounds-red=1 fails-red=1 uncounted=1"
}

# A brief review's FAIL, counted in the run state, reaches the retro's totals.
test_totals_the_brief_reviews_fails_from_the_run_state() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	bash "$FACTORY_CORE/state.sh" set phase red || fail "no phase"
	bash "$FACTORY_CORE/state.sh" incr fails-brief > /dev/null
	bash "$FACTORY_CORE/state.sh" incr fails-brief > /dev/null
	bash "$FACTORY_CORE/state.sh" incr uncounted > /dev/null
	bash "$FACTORY_CORE/state.sh" stats > comments.txt || fail "no stats line"
	run_retro comments.txt
	assert_status 0
	assert_line "fails-brief: 2"
	assert_line "uncounted: 1"
	assert_line "issue 7: fails-brief=2 uncounted=1"
}

# The minutes total like the counts and print after them; a line from before the
# start time was recorded has none, and an issue's row shows its minutes even at 0.
test_totals_the_minutes_after_the_counts() {
	cat > comments.txt << 'TXT'
factory-stats: issue=12 lane=standard rounds-red=1 rounds-green=0 escalations=0 minutes=56 minutes-brief=5 minutes-red=20 minutes-green=31
factory-stats: issue=9 lane=standard rounds-red=0 rounds-green=2 escalations=1
factory-stats: issue=14 lane=cleanup rounds-red=0 rounds-green=0 escalations=0 lifts=1 minutes=30 minutes-brief=4 minutes-partial=26
factory-stats: issue=15 lane=cleanup rounds-red=0 rounds-green=0 escalations=0 minutes=0 minutes-brief=0 minutes-partial=0
TXT
	run_retro comments.txt
	assert_status 0
	assert_eq "retro: 4 issues
lane cleanup: 2
lane standard: 2
gate counts: 0 of 4 issues
rounds-red: 1
rounds-green: 2
escalations: 1
lifts: 1
minutes: 86
minutes-brief: 9
minutes-red: 20
minutes-green: 31
minutes-partial: 26
issue 9: rounds-green=2 escalations=1
issue 12: rounds-red=1 minutes=56 minutes-brief=5 minutes-red=20 minutes-green=31
issue 14: lifts=1 minutes=30 minutes-brief=4 minutes-partial=26
issue 15: minutes=0" "$out"
}

# The line lib/run.sh prints with minutes reads back whole.
test_reads_the_minutes_lib_run_prints() {
	fixture_repo
	git checkout -q -b issue/7
	seal_stub
	bash "$FACTORY_CORE/state.sh" set started 1000 || fail "no start"
	FACTORY_NOW=1300 bash "$FACTORY_CORE/state.sh" set phase red || fail "no phase"
	bash "$FACTORY_CORE/state.sh" incr rounds-red > /dev/null
	FACTORY_NOW=4360 bash "$FACTORY_CORE/state.sh" stats > comments.txt || fail "no stats line"
	run_retro comments.txt
	assert_status 0
	assert_line "minutes: 56"
	assert_line "issue 7: rounds-red=1 minutes=56 minutes-brief=5 minutes-red=51"
	[ ! -s "$TEST_TMP/stderr" ] || fail "retro.sh skipped a line:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

# The Driver's calls (self-ruled) sit on the line lib/run.sh prints, after the
# escalations, and total like the other counts, so the retro shows how many calls
# its listing of them must hold; an older line without the field adds nothing.
test_totals_the_drivers_calls_from_the_line_lib_run_prints() {
	fixture_repo
	git checkout -q -b issue/7
	bash "$FACTORY_CORE/state.sh" incr escalations > /dev/null
	bash "$FACTORY_CORE/state.sh" incr self-ruled > /dev/null
	bash "$FACTORY_CORE/state.sh" incr self-ruled > /dev/null
	bash "$FACTORY_CORE/state.sh" stats > comments.txt || fail "no stats line"
	grep -qF " escalations=1 self-ruled=2" comments.txt || fail "self-ruled isn't after the escalations: $(cat comments.txt)"
	echo "factory-stats: issue=9 lane=small rounds-red=0 rounds-green=1 escalations=0 self-ruled=1" >> comments.txt
	echo "factory-stats: issue=4 lane=standard rounds-red=1 escalations=0" >> comments.txt
	run_retro comments.txt
	assert_status 0
	assert_line "self-ruled: 3"
	assert_line "issue 7: escalations=1 self-ruled=2"
	assert_line "issue 9: rounds-green=1 self-ruled=1"
	[ "$(printf '%s\n' "$out" | grep -n '^escalations: ' | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n '^self-ruled: ' | cut -d: -f1)" ] ||
		fail "self-ruled isn't totalled after the escalations:"$'\n'"$out"
	[ ! -s "$TEST_TMP/stderr" ] || fail "retro.sh skipped a line:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

# The gate's counts total like the others, over the issues that recorded them: a
# close comment from before verify.sh counted (no gate-runs) is "not recorded",
# so its steps add nothing and the recorded line names how many did.
test_totals_the_gates_counts_over_the_issues_that_recorded_them() {
	cat > comments.txt << 'TXT'
factory-stats: issue=3 lane=standard rounds-red=1 rounds-green=0 fails-green=1 escalations=0 minutes=40 minutes-brief=5 minutes-red=15 minutes-green=20
factory-stats: issue=5 lane=standard rounds-red=0 rounds-green=1 fails-green=0 escalations=0 gate-runs=4 caught-lint=1 caught-test=1 seconds-prepare=2 seconds-lint=6 seconds-test=30 minutes=20 minutes-brief=2 minutes-red=8 minutes-green=10
factory-stats: issue=6 lane=small rounds-red=0 rounds-green=0 fails-green=0 escalations=0 gate-runs=2 caught-test=2 seconds-prepare=1 seconds-test=14 seconds-smoke=3
TXT
	run_retro comments.txt
	assert_status 0
	assert_eq "retro: 3 issues
lane small: 1
lane standard: 2
gate counts: 2 of 3 issues
rounds-red: 1
rounds-green: 1
fails-green: 1
escalations: 0
gate-runs: 6
caught-lint: 1
caught-test: 3
seconds-prepare: 3
seconds-lint: 6
seconds-test: 44
seconds-smoke: 3
minutes: 60
minutes-brief: 7
minutes-red: 23
minutes-green: 30
issue 3: rounds-red=1 fails-green=1 minutes=40 minutes-brief=5 minutes-red=15 minutes-green=20
issue 5: rounds-green=1 gate-runs=4 caught-lint=1 caught-test=1 seconds-prepare=2 seconds-lint=6 seconds-test=30 minutes=20 minutes-brief=2 minutes-red=8 minutes-green=10
issue 6: gate-runs=2 caught-test=2 seconds-prepare=1 seconds-test=14 seconds-smoke=3" "$out"
}

# The gate's counts verify.sh keeps reach the retro through the stats line.
test_reads_the_gates_counts_lib_run_prints() {
	fixture_repo
	git checkout -q -b issue/7
	bash -c '. "$1/lib/run.sh"; factory_gate_count issue/7 lint prepare=1 lint=4 &&
		factory_gate_count issue/7 "" prepare=1 lint=2 test=9' _ "$FACTORY_CORE" || fail "no counts"
	bash "$FACTORY_CORE/state.sh" stats > comments.txt || fail "no stats line"
	run_retro comments.txt
	assert_status 0
	assert_line "gate counts: 1 of 1 issues"
	assert_line "issue 7: gate-runs=2 caught-lint=1 seconds-prepare=2 seconds-lint=6 seconds-test=9"
	[ ! -s "$TEST_TMP/stderr" ] || fail "retro.sh skipped a line:"$'\n'"$(cat "$TEST_TMP/stderr")"
}
