# stress.sh: the full suite, or the suites a diff can affect, repeated under load.
# Every test runs it in a small factory of its own (stress_factory, or the project
# stress_project vendors) against a stand-in test.sh, never this factory's suite,
# with FACTORY_STRESS_LOOPS at 0 or 1.

# shellcheck disable=SC2154 # out, status: set by run_cmd, in factory/core/tests/lib.sh

# stress_factory <stand-in body>: $TEST_TMP/mini/core holding stress.sh (with
# the libs it sources) and a stand-in test.sh with that body; its runs use $TEST_TMP/tmp as TMPDIR. The
# stand-in can read $STRESS_PROBE, a folder for what it records; it first adds its
# pid to $STRESS_PROBE/test.sh.pids, for start_stress's cleanup.
stress_factory() {
	mkdir -p "$TEST_TMP/mini/core/lib" "$TEST_TMP/tmp" "$TEST_TMP/probe" || fail "no mini factory"
	cp "$FACTORY_CORE/stress.sh" "$TEST_TMP/mini/core/" && cp "$FACTORY_CORE/lib/localenv.sh" "$FACTORY_CORE/lib/suites.sh" "$TEST_TMP/mini/core/lib/" ||
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

# --- scoped runs: named suites, --since -------------------------------------------

# stress_project: $TEST_TMP/proj, a git project vendoring a small factory in
# factory/: core with suites alpha (its test names the skills folder) and beta (its
# test, every adapter's skills folder), adapters web
# (the one in use, factory-version's adapter line) and game with suites one and
# two each, a skill, and a doc outside the factory; all committed, tagged base. Its
# test.sh is a stand-in writing its arguments to $STRESS_PROBE/args.
stress_project() {
	local p="$TEST_TMP/proj" a
	isolate_git
	mkdir -p "$p/factory/core/lib" "$p/factory/core/tests" "$p/factory/skills/s" "$p/tools/verify" "$p/docs" "$TEST_TMP/tmp" "$TEST_TMP/probe" ||
		fail "no project"
	cp "$FACTORY_CORE/stress.sh" "$p/factory/core/" && cp "$FACTORY_CORE/lib/localenv.sh" "$FACTORY_CORE/lib/suites.sh" "$p/factory/core/lib/" || fail "could not copy stress.sh"
	printf '%s\n' 'echo "$*" >> "$STRESS_PROBE/args"' > "$p/factory/core/test.sh"
	echo 'test_a() { grep -r gpt "$FACTORY_CORE/../skills"; }' > "$p/factory/core/tests/alpha_test.sh"
	echo 'test_b() { ls "$FACTORY_CORE"/../adapters/*/skills; }' > "$p/factory/core/tests/beta_test.sh"
	echo '# helpers' > "$p/factory/core/tests/lib.sh"
	echo 'echo helper' > "$p/factory/core/run.sh"
	for a in web game; do
		mkdir -p "$p/factory/adapters/$a/tests" "$p/factory/adapters/$a/tools/verify" || fail "no adapter $a"
		echo 'test_one() { :; }' > "$p/factory/adapters/$a/tests/one_test.sh"
		echo 'test_two() { :; }' > "$p/factory/adapters/$a/tests/two_test.sh"
		echo 'echo step' > "$p/factory/adapters/$a/tools/verify/step"
	done
	echo 'a skill' > "$p/factory/skills/s/SKILL.md"
	echo 'step' > "$p/tools/verify/step"
	printf 'version 0.1.0\nadapter web\n' > "$p/tools/verify/factory-version"
	echo 'a doc' > "$p/docs/readme.md"
	git init -q "$p" && git -C "$p" add -A && git -C "$p" commit -q -m base && git -C "$p" tag base || fail "could not commit the project"
	export TMPDIR="$TEST_TMP/tmp" STRESS_PROBE="$TEST_TMP/probe" FACTORY_STRESS_LOOPS=0
}

# stress_since <path below the project> [...]: commit an edit to each path, then
# run stress.sh 1 --since base.
stress_since() {
	local f
	for f in "$@"; do
		echo "# edited" >> "$TEST_TMP/proj/$f" || fail "could not edit $f"
	done
	git -C "$TEST_TMP/proj" commit -qam edit || fail "could not commit the edit"
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 --since base
}

# ran_with <args>: the stand-in test.sh ran once, with exactly <args>.
ran_with() {
	assert_eq "$1" "$(cat "$TEST_TMP/probe/args" 2> /dev/null)" "test.sh's suite names"
}

test_named_suites_run_only_those_as_a_partial_run() {
	stress_project
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 web/two beta
	assert_status 0
	assert_line "stress: chose 2 suites: beta web/two"
	assert_line "stress: 1 runs of the 2 chosen suites (a partial run: no full-run lock), FACTORY_TEST_GODOT_JOBS=1, 0 busy loops (pids none)"
	ran_with "beta web/two"
}

# A scoped run isn't niced (test.sh's partial runs are): the busy loops, at normal
# priority, would starve it. test.sh skips nice when FACTORY_TEST_NICED names its pid.
test_a_scoped_run_is_not_niced() {
	stress_project
	echo '[ "${FACTORY_TEST_NICED:-}" = "$$" ] && echo unniced > "$STRESS_PROBE/niced"' >> "$TEST_TMP/proj/factory/core/test.sh"
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 beta
	assert_status 0
	assert_eq "unniced" "$(cat "$TEST_TMP/probe/niced" 2> /dev/null)" "test.sh would nice the run"
}

test_since_a_changed_test_file_chooses_its_suite() {
	stress_project
	stress_since factory/core/tests/beta_test.sh factory/adapters/web/tests/one_test.sh
	assert_status 0
	assert_line "stress: chose 2 suites from the diff since base: beta web/one"
	ran_with "beta web/one"
}

test_since_an_adapters_script_chooses_its_suites() {
	stress_project
	stress_since factory/adapters/web/tools/verify/step
	assert_status 0
	ran_with "web/one web/two"
}

# The project's ported tools/verify/ is the adapter in use's; its factory-version
# record isn't.
test_since_the_projects_tools_verify_chooses_its_adapters_suites() {
	stress_project
	stress_since tools/verify/step tools/verify/factory-version
	assert_status 0
	ran_with "web/one web/two"
}

# A core script: every core suite and the suites of the adapter in use.
test_since_a_core_script_chooses_the_core_suites() {
	stress_project
	stress_since factory/core/run.sh
	assert_status 0
	ran_with "alpha beta web/one web/two"
	assert_line "stress: left out the game adapter's suites: the adapter in use is web, and land's one full run covers the rest"
}

# A change to tests/lib.sh brings its folder's suites.
test_since_an_adapters_test_lib_chooses_its_suites() {
	stress_project
	echo '# helpers' > "$TEST_TMP/proj/factory/adapters/web/tests/lib.sh"
	git -C "$TEST_TMP/proj" add -A || fail "could not add lib.sh"
	stress_since factory/adapters/web/tests/lib.sh
	assert_status 0
	ran_with "web/one web/two"
}

# Any other factory file: the suites whose test file names its folder.
test_since_a_skill_chooses_the_suites_naming_skills() {
	stress_project
	stress_since factory/skills/s/SKILL.md
	assert_status 0
	ran_with "alpha beta"
}

# An adapter's skill: its suites, and a core suite checking every adapter's skills.
test_since_an_adapters_skill_chooses_the_core_suites_checking_it() {
	stress_project
	mkdir -p "$TEST_TMP/proj/factory/adapters/web/skills/w" && echo 'a skill' > "$TEST_TMP/proj/factory/adapters/web/skills/w/SKILL.md" || fail "no skill"
	git -C "$TEST_TMP/proj" add -A || fail "could not add the skill"
	stress_since factory/adapters/web/skills/w/SKILL.md
	assert_status 0
	ran_with "beta web/one web/two"
}

# A test file in a fixture is a fixture: its folder's suites.
test_since_a_nested_test_file_chooses_its_folders_suites() {
	stress_project
	mkdir -p "$TEST_TMP/proj/factory/adapters/web/tests/fixture" "$TEST_TMP/proj/factory/core/tests/fixture" || fail "no fixture"
	echo '# fixture' > "$TEST_TMP/proj/factory/adapters/web/tests/fixture/x_test.sh"
	echo '# fixture' > "$TEST_TMP/proj/factory/core/tests/fixture/y_test.sh"
	git -C "$TEST_TMP/proj" add -A || fail "could not add the fixtures"
	stress_since factory/adapters/web/tests/fixture/x_test.sh factory/core/tests/fixture/y_test.sh
	assert_status 0
	ran_with "alpha beta web/one web/two"
}

# An uncommitted or untracked change counts as well as a committed one.
test_since_counts_the_uncommitted_changes() {
	stress_project
	echo '# edited' >> "$TEST_TMP/proj/factory/core/tests/beta_test.sh"
	echo 'test_c() { :; }' > "$TEST_TMP/proj/factory/core/tests/gamma_test.sh"
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 --since base
	assert_status 0
	ran_with "beta gamma"
}

# A folder outside the factory an adapter's tests read (the Godot adapter's
# gdUnit4 fallback, addons/gdUnit4/) chooses that adapter's suites.
test_since_a_folder_an_adapters_tests_read_chooses_its_suites() {
	stress_project
	local p="$TEST_TMP/proj"
	mkdir -p "$p/factory/adapters/godot/tests" "$p/addons/gdUnit4" || fail "no godot adapter"
	echo 'test_one() { :; }' > "$p/factory/adapters/godot/tests/one_test.sh"
	echo 'version="6.0.0"' > "$p/addons/gdUnit4/plugin.cfg"
	printf 'version 0.1.0\nadapter godot\n' > "$p/tools/verify/factory-version"
	git -C "$p" add -A && git -C "$p" commit -qm godot && git -C "$p" tag -f base > /dev/null 2>&1 || fail "could not commit the godot adapter"
	stress_since addons/gdUnit4/plugin.cfg
	assert_status 0
	ran_with "godot/one"
}

test_since_a_docs_only_change_runs_nothing() {
	stress_project
	stress_since docs/readme.md
	assert_status 0
	assert_last_line "stress: no suite to run: the diff since base touches no file a suite tests"
	[ ! -e "$TEST_TMP/probe/args" ] || fail "a docs-only change ran test.sh"
}

# In a project, only the adapter in use runs: another adapter's change chooses
# none of its suites, and says so.
test_since_in_a_project_another_adapters_change_chooses_none() {
	stress_project
	stress_since factory/adapters/game/tools/verify/step factory/adapters/game/tests/one_test.sh
	assert_status 0
	assert_line "stress: left out the game adapter's suites: the adapter in use is web, and land's one full run covers the rest"
	assert_last_line "stress: no suite to run: the diff since base touches no file a suite tests"
	[ ! -e "$TEST_TMP/probe/args" ] || fail "another adapter's change ran test.sh"
}

# In the factory's repo (.factory-repo at the top) no adapter is in use: each
# adapter's change chooses its suites.
test_since_in_the_factory_repo_every_adapters_change_counts() {
	stress_project
	touch "$TEST_TMP/proj/.factory-repo" && git -C "$TEST_TMP/proj" add .factory-repo && git -C "$TEST_TMP/proj" commit -qm marker || fail "no marker"
	git -C "$TEST_TMP/proj" tag -f base > /dev/null 2>&1 || fail "could not move base"
	stress_since factory/adapters/game/tools/verify/step
	assert_status 0
	assert_no_line "stress: left out the game adapter's suites: the adapter in use is web, and land's one full run covers the rest"
	ran_with "game/one game/two"
}

test_an_unknown_suite_or_a_bad_rev_is_a_usage_error() {
	stress_project
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 beta nosuch
	assert_status 2
	stderr_has "no suite 'nosuch'"
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 web/nosuch
	assert_status 2
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 --since no-such-rev
	assert_status 2
	stderr_has "--since: git can't resolve 'no-such-rev' to a commit"
	run_cmd bash "$TEST_TMP/proj/factory/core/stress.sh" 1 --since
	assert_status 2
	[ ! -e "$TEST_TMP/probe/args" ] || fail "a usage error ran test.sh"
}
