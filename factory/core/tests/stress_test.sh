# stress.sh: the full suite repeated under load. Every test runs it in a small
# factory of its own (stress_factory) against a stand-in test.sh, never this
# factory's suite, with FACTORY_STRESS_LOOPS at 0 or 1.

# shellcheck disable=SC2154 # out, status: set by run_cmd, in factory/core/tests/lib.sh

# stress_factory <stand-in body>: $TEST_TMP/mini/core holding stress.sh (with
# the lib it sources) and a stand-in test.sh with that body; its runs use $TEST_TMP/tmp as TMPDIR. The
# stand-in can read $STRESS_PROBE, a folder for what it records; it first adds its
# pid to $STRESS_PROBE/test.sh.pids, for start_stress's cleanup.
stress_factory() {
	mkdir -p "$TEST_TMP/mini/core/lib" "$TEST_TMP/tmp" "$TEST_TMP/probe" || fail "no mini factory"
	cp "$FACTORY_CORE/stress.sh" "$TEST_TMP/mini/core/" && cp "$FACTORY_CORE/lib/localenv.sh" "$TEST_TMP/mini/core/lib/" ||
		fail "could not copy stress.sh"
	printf '%s\n' 'echo "$$" >> "$STRESS_PROBE/test.sh.pids"' "$1" > "$TEST_TMP/mini/core/test.sh"
	export TMPDIR="$TEST_TMP/tmp" STRESS_PROBE="$TEST_TMP/probe" FACTORY_STRESS_LOOPS=0
}

# ended <pid>: that process is gone.
ended() {
	! kill -0 "$1" 2> /dev/null
}

# loop_pids: the busy loops' pids, from the header line in $out.
loop_pids() {
	printf '%s\n' "$out" | sed -n 's/^stress: .* busy loops (pids \(.*\))$/\1/p'
}

test_a_passing_run_prints_its_result_and_no_pass_lines() {
	stress_factory 'echo "PASS a test_one"; echo "== skill budget"; echo "test.sh: 1 passed, 0 failed, 0 skipped"'
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 0
	assert_no_line "PASS a test_one"
	assert_line "== skill budget"
	assert_line "test.sh: 1 passed, 0 failed, 0 skipped"
	assert_line "stress: run 1 of 1 passed"
	assert_last_line "stress: 1 of 1 runs passed"
}

# A failing run: its non-PASS lines, stderr included, and exit 1.
test_a_failing_run_prints_what_failed_and_exits_1() {
	stress_factory 'echo "PASS a test_one"; echo "FAIL a test_two"; echo "    why it failed" >&2; exit 1'
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 1
	assert_no_line "PASS a test_one"
	assert_line "FAIL a test_two"
	assert_line "    why it failed"
	assert_line "stress: run 1 of 1 FAILED (test.sh exit 1)"
	assert_last_line "stress: 0 of 1 runs passed"
}

# A test that prints a NUL doesn't hide the lines after it: the log is read as text.
test_a_nul_in_the_output_hides_no_line() {
	stress_factory 'printf "PASS a test_one\n\0tool output\n"; echo "FAIL a test_two"; echo "    why it failed" >&2; exit 1'
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 1
	assert_no_line "PASS a test_one"
	assert_line "FAIL a test_two"
	assert_line "    why it failed"
}

# Three runs by default, each run once with no retry: run 2 fails and run 3 still runs.
test_every_run_runs_once_with_no_retry() {
	stress_factory 'echo x >> "$STRESS_PROBE/runs"; [ "$(wc -l < "$STRESS_PROBE/runs")" -ne 2 ] || { echo "FAIL a test_flaky"; exit 1; }'
	run_cmd bash "$TEST_TMP/mini/core/stress.sh"
	assert_status 1
	assert_eq 3 "$(wc -l < "$TEST_TMP/probe/runs" | tr -d ' ')" "the stand-in ran a wrong number of times"
	assert_line "stress: run 1 of 3 passed"
	assert_line "stress: run 2 of 3 FAILED (test.sh exit 1)"
	assert_line "stress: run 3 of 3 passed"
	assert_last_line "stress: 2 of 3 runs passed"
}

# Each run gets every variable the checkout's local.env sets (at its top, else
# in tools/verify/), the environment winning and one Godot slot all the same.
test_each_run_loads_the_checkouts_local_env() {
	stress_factory 'echo "node=${NODE_BIN:-unset} godot=${GODOT_BIN:-unset} guard=${FACTORY_TEST_HANG_GUARD:-unset} godot_jobs=${FACTORY_TEST_GODOT_JOBS:-unset}" >> "$STRESS_PROBE/env"'
	unset NODE_BIN FACTORY_TEST_HANG_GUARD
	local top
	git init -q "$TEST_TMP/mini" && top="$(git -C "$TEST_TMP/mini" rev-parse --show-toplevel)" || fail "git init failed"
	printf 'NODE_BIN=/opt/node/bin/node\nGODOT_BIN=/opt/local-godot\nFACTORY_TEST_HANG_GUARD=30\nFACTORY_TEST_GODOT_JOBS=4\n' > "$TEST_TMP/mini/local.env"
	run_cmd env GODOT_BIN=/opt/env-godot bash "$TEST_TMP/mini/core/stress.sh" 2
	assert_status 0
	assert_line "stress: each run loads $top/local.env (the environment wins over it)"
	assert_eq "node=/opt/node/bin/node godot=/opt/env-godot guard=30 godot_jobs=1
node=/opt/node/bin/node godot=/opt/env-godot guard=30 godot_jobs=1" "$(cat "$TEST_TMP/probe/env")" "the runs' environment"
	mkdir -p "$TEST_TMP/mini/tools/verify" && mv "$TEST_TMP/mini/local.env" "$TEST_TMP/mini/tools/verify/" || fail "could not move local.env"
	rm "$TEST_TMP/probe/env"
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 0
	assert_line "stress: each run loads $top/tools/verify/local.env (the environment wins over it)"
	assert_eq "node=/opt/node/bin/node godot=${GODOT_BIN:-/opt/local-godot} guard=30 godot_jobs=1" "$(cat "$TEST_TMP/probe/env")" "a project's local.env"
	rm "$TEST_TMP/mini/tools/verify/local.env" "$TEST_TMP/probe/env"
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 0
	assert_line "stress: no local.env at the checkout's top ($top) or in its tools/verify/, so the real-tool tests skip"
}

# test.sh runs with no suite names (a full run) and one Godot slot.
test_test_sh_gets_a_full_run_with_one_godot_slot() {
	stress_factory 'echo "args=$# godot_jobs=${FACTORY_TEST_GODOT_JOBS:-unset}" > "$STRESS_PROBE/env"'
	export FACTORY_TEST_GODOT_JOBS=4
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 0
	assert_eq "args=0 godot_jobs=1" "$(cat "$TEST_TMP/probe/env")"
}

# A run refused by the real test.sh's lock, held by another full run, is a failed
# run with its reason; stress.sh doesn't wait for the lock.
test_a_run_refused_by_the_full_run_lock_is_a_failed_run() {
	stress_factory ''
	cp "$FACTORY_CORE/test.sh" "$TEST_TMP/mini/core/test.sh" || fail "could not copy test.sh"
	export FACTORY_TEST_LOCK="$TEST_TMP/lock"
	mkdir "$FACTORY_TEST_LOCK" && echo "$BASHPID" > "$FACTORY_TEST_LOCK/pid"
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 1
	assert_line "test.sh: refused: another full run is in progress (pid $BASHPID, lock $FACTORY_TEST_LOCK)."
	assert_line "stress: run 1 of 1 FAILED (test.sh exit 2)"
	[ -d "$FACTORY_TEST_LOCK" ] || fail "the refused run removed the holder's lock"
}

test_bad_arguments_are_usage_errors() {
	stress_factory 'echo ran >> "$STRESS_PROBE/runs"'
	local args
	for args in 0 00 abc -1 "1 2"; do
		# shellcheck disable=SC2086 # "1 2" is two arguments on purpose
		run_cmd bash "$TEST_TMP/mini/core/stress.sh" $args
		assert_status 2
	done
	FACTORY_STRESS_LOOPS=many run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 2
	stderr_has "FACTORY_STRESS_LOOPS is a number, not 'many'"
	[ ! -e "$TEST_TMP/probe/runs" ] || fail "a usage error ran the suite"
}

# hears_int: skip when this test runs deaf to INT: test.sh was started in the
# background by a shell without job control, and no process it starts can trap INT.
hears_int() {
	[ "$(trap -p INT)" != "trap -- '' SIGINT" ] || skip "INT is ignored here (test.sh run in the background), so nothing it starts can trap it"
}

# test.sh doesn't start deaf to INT, as a background job of stress.sh would, so a
# test that sends INT runs as it does from a terminal.
test_test_sh_is_not_deaf_to_int() {
	hears_int
	stress_factory 'echo "[$(trap -p INT)]" > "$STRESS_PROBE/int"'
	run_cmd bash "$TEST_TMP/mini/core/stress.sh" 1
	assert_status 0
	assert_eq "[]" "$(cat "$TEST_TMP/probe/int")" "test.sh started with INT ignored"
}

# start_stress <args...>: stress.sh in the background, its output to
# $TEST_TMP/stress.out and its pid in $stress. Job control is on for the launch
# only, so the script doesn't start deaf to INT, as a background job of a shell
# without it does, and runs in its own process group, its loops in it; stress.sh
# starts each test.sh in a group of its own. If the test fails, every one of those
# groups is killed and nothing it started outlives it.
start_stress() {
	set -m
	bash "$TEST_TMP/mini/core/stress.sh" "$@" > "$TEST_TMP/stress.out" 2>&1 &
	stress=$!
	set +m
	trap stress_groups_killed EXIT
}

# stress_groups_killed: KILL stress.sh's process group and each stand-in test.sh's.
stress_groups_killed() {
	local pid
	kill -KILL -- "-$stress" 2> /dev/null
	[ -f "$STRESS_PROBE/test.sh.pids" ] || return 0
	while read -r pid; do
		kill -KILL -- "-$pid" 2> /dev/null
	done < "$STRESS_PROBE/test.sh.pids"
	return 0
}

# stress_ended <what>: wait for stress.sh to end, naming <what>, under the hang
# guard (a script waiting on a loop it never stopped fails here, not hangs); then
# its output in $out and its exit code in $status.
stress_ended() {
	wait_until "stress.sh to end$1" ended "$stress"
	wait "$stress"
	# shellcheck disable=SC2034 # read by assert_status
	status=$?
	out="$(cat "$TEST_TMP/stress.out")"
}

# Its loops end with it, and its work folder goes.
test_the_busy_loops_end_when_it_ends() {
	stress_factory 'true'
	export FACTORY_STRESS_LOOPS=2
	local stress pids pid
	start_stress 1
	stress_ended ""
	assert_status 0
	pids="$(loop_pids)"
	[ "$(printf '%s\n' "$pids" | wc -w)" -eq 2 ] || fail "not 2 busy loops: '$pids'"
	for pid in $pids; do
		ended "$pid" || fail "busy loop $pid outlived stress.sh"
	done
	assert_eq "" "$(find "$TMPDIR" -maxdepth 1 -name 'factory-stress.*')" "stress.sh left its work folder"
}

# stopped_mid_run <signal>: stress.sh, stopped with <signal> while its test.sh (a
# stand-in blocked until killed) runs, stops that and its loop and exits.
stopped_mid_run() {
	blocking_stand_in "$TEST_TMP/block" "$TEST_TMP/never"
	stress_factory "exec $(printf %q "$TEST_TMP/block")"
	export FACTORY_STRESS_LOOPS=1
	local stress pid
	start_stress 1
	wait_until "the stand-in test.sh to start" test -s "$TEST_TMP/block.pid"
	kill "-$1" "$stress"
	stress_ended " on $1"
	pid="$(loop_pids)"
	[ -n "$pid" ] || fail "no busy loop's pid in the output:"$'\n'"$out"
	wait_until "the stand-in test.sh to end with stress.sh" ended "$(cat "$TEST_TMP/block.pid")"
	ended "$pid" || fail "busy loop $pid outlived stress.sh"
	assert_no_line "stress: run 1 of 1 passed"
	assert_eq "" "$(find "$TMPDIR" -maxdepth 1 -name 'factory-stress.*')" "stress.sh left its work folder"
}

test_term_stops_the_run_and_the_busy_loops() {
	stopped_mid_run TERM
}

test_int_stops_the_run_and_the_busy_loops() {
	hears_int
	stopped_mid_run INT
}
