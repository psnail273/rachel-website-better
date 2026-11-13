# test.sh itself: its options, the lock that keeps one full run at a time, and
# what an interrupted run does. The lock tests that need a full run run test.sh
# copied into a small tree of its own (mini_factory), never this factory's suite.

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_a_second_full_run_is_refused_while_the_lock_is_held() {
	export FACTORY_TEST_LOCK="$TEST_TMP/lock"
	mkdir "$FACTORY_TEST_LOCK" && echo "$BASHPID" > "$FACTORY_TEST_LOCK/pid"
	run_cmd bash "$FACTORY_CORE/test.sh"
	assert_status 2
	assert_eq "" "$out" "a refused run printed results"
	stderr_has "refused: another full run is in progress (pid $BASHPID"
	[ -d "$FACTORY_TEST_LOCK" ] || fail "the refused run removed the holder's lock"
}

# A lock with no pid is being taken, or was left by a run that died at once: the
# run refuses, and says how to clear a stale one.
test_a_lock_with_no_pid_is_refused_saying_it_may_be_stale() {
	export FACTORY_TEST_LOCK="$TEST_TMP/lock"
	mkdir "$FACTORY_TEST_LOCK"
	run_cmd bash "$FACTORY_CORE/test.sh"
	assert_status 2
	stderr_has "names no run (pid unknown)"
	stderr_has "the lock is stale; remove it (rm -rf $FACTORY_TEST_LOCK)"
	[ -d "$FACTORY_TEST_LOCK" ] || fail "the refused run removed the lock"
}

test_bad_options_are_usage_errors() {
	run_cmd bash "$FACTORY_CORE/test.sh" --jobs 0 state
	assert_status 2
	run_cmd bash "$FACTORY_CORE/test.sh" --jobs
	assert_status 2
	run_cmd bash "$FACTORY_CORE/test.sh" --fast
	assert_status 2
	run_cmd bash "$FACTORY_CORE/test.sh" no_such_suite
	assert_status 2
}

# mini_factory: $TEST_TMP/mini, a factory tree holding test.sh, its helpers and
# one suite, tests/mini_test.sh, with a quick test; its runs use $TEST_TMP as
# TMPDIR and $TEST_TMP/lock as the lock.
mini_factory() {
	mkdir -p "$TEST_TMP/mini/core/tests" "$TEST_TMP/mini/core/lib" "$TEST_TMP/tmp" || fail "no mini factory"
	cp "$FACTORY_CORE/test.sh" "$FACTORY_CORE/skill-budget.sh" "$FACTORY_CORE/raw-waits.sh" "$TEST_TMP/mini/core/" &&
		cp "$FACTORY_CORE/tests/lib.sh" "$TEST_TMP/mini/core/tests/" &&
		cp "$FACTORY_CORE/lib/findings.sh" "$TEST_TMP/mini/core/lib/" || fail "could not copy test.sh"
	printf 'test_quick() {\n\ttrue\n}\n' > "$TEST_TMP/mini/core/tests/mini_test.sh"
	export TMPDIR="$TEST_TMP/tmp" FACTORY_TEST_LOCK="$TEST_TMP/lock"
}

# A lock whose run is gone (killed with KILL, say) is taken over, saying so.
test_a_stale_lock_is_taken_over_with_a_note() {
	mini_factory
	bash -c 'exit 0' &
	local gone=$!
	wait "$gone"
	mkdir "$FACTORY_TEST_LOCK" && echo "$gone" > "$FACTORY_TEST_LOCK/pid"
	run_cmd bash "$TEST_TMP/mini/core/test.sh"
	assert_status 0
	assert_line "PASS mini test_quick"
	stderr_has "took over the stale lock $FACTORY_TEST_LOCK: its run (pid $gone) is gone"
	[ ! -e "$FACTORY_TEST_LOCK" ] || fail "the run left its lock"
}

# A full run writes the shared times file; a suite run one of its own, in one
# folder, so two at once don't overwrite each other's. The folder is the user's:
# another user's, which this one can't write, is no matter (pass 1's review).
test_only_a_full_run_writes_the_shared_times_file() {
	mini_factory
	local shared="$TMPDIR/factory-test-times.txt" one two
	mkdir -p "$TMPDIR/factory-test-times.99999.d" && chmod 555 "$TMPDIR/factory-test-times.99999.d"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	one="$(printf '%s\n' "$out" | sed -n 's/^test.sh: seconds per test, slowest first, in //p')"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	two="$(printf '%s\n' "$out" | sed -n 's/^test.sh: seconds per test, slowest first, in //p')"
	[ -n "$one" ] && [ "$one" != "$shared" ] && [ "$one" != "$two" ] || fail "suite runs share a times file: '$one', '$two'"
	assert_eq "$TMPDIR/factory-test-times.$(id -u).d" "$(dirname "$one")" "the suite run's times file's folder"
	assert_eq "$TMPDIR/factory-test-times.$(id -u).d" "$(dirname "$two")" "the second suite run's times file's folder"
	grep -q ' mini test_quick$' "$one" || fail "the suite run's times file lacks its test"
	run_cmd bash "$TEST_TMP/mini/core/test.sh"
	assert_line "test.sh: seconds per test, slowest first, in $shared"
}

# Every run removes the suite runs' times files older than a day: those in the
# folder, and those older runs left in TMPDIR itself (#6: 351 there). Newer
# ones, and the full run's shared file, stay.
test_a_run_removes_times_files_older_than_a_day() {
	mini_factory
	local dir f
	dir="$TMPDIR/factory-test-times.$(id -u).d"
	mkdir -p "$dir"
	for f in "$dir/factory-test-times.old111" "$TMPDIR/factory-test-times.old222" "$TMPDIR/factory-test-times.txt"; do
		echo "1.000 mini test_quick" > "$f"
		touch -d '2 days ago' "$f"
	done
	echo "1.000 mini test_quick" > "$dir/factory-test-times.new333"
	touch -d '23 hours ago' "$dir/factory-test-times.new333"
	echo "an older run's file" > "$TMPDIR/factory-test-times.new444"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	assert_status 0
	[ ! -e "$dir/factory-test-times.old111" ] || fail "a times file two days old stayed in the folder"
	[ ! -e "$TMPDIR/factory-test-times.old222" ] || fail "a times file two days old stayed in TMPDIR"
	[ -e "$dir/factory-test-times.new333" ] || fail "a times file 23 hours old was removed"
	[ -e "$TMPDIR/factory-test-times.new444" ] || fail "a new times file in TMPDIR was removed"
	[ -e "$TMPDIR/factory-test-times.txt" ] || fail "the full run's times file was removed"
	assert_eq 2 "$(find "$dir" -type f | wc -l | tr -d ' ')" "the folder's files (the 23-hour one and this run's)"
	# The age is a setting: at 0 minutes the 23-hour one goes too.
	FACTORY_TEST_TIMES_AGE=0 run_cmd bash "$TEST_TMP/mini/core/test.sh"
	assert_status 0
	[ ! -e "$dir/factory-test-times.new333" ] || fail "FACTORY_TEST_TIMES_AGE=0 kept a file 23 hours old"
}

# The last line is the run's wall time and the tests' seconds, summed.
test_the_last_line_gives_the_wall_time_and_the_summed_test_seconds() {
	mini_factory
	printf 'test_two() {\n\ttrue\n}\n' >> "$TEST_TMP/mini/core/tests/mini_test.sh"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	assert_status 0
	[[ $(printf '%s\n' "$out" | tail -n 1) =~ ^test\.sh:\ wall\ time\ [0-9]+\.[0-9]\ s,\ [0-9]+\.[0-9]\ test-seconds\ summed$ ]] ||
		fail "the last line isn't the wall time and the test-seconds:"$'\n'"$out"
	run_cmd bash "$TEST_TMP/mini/core/test.sh"
	assert_status 0
	[[ $(printf '%s\n' "$out" | tail -n 1) =~ ^test\.sh:\ wall\ time\ [0-9]+\.[0-9]\ s,\ [0-9]+\.[0-9]\ test-seconds\ summed$ ]] ||
		fail "a full run's last line isn't the wall time and the test-seconds:"$'\n'"$out"
}

# A suite run runs its tests under nice, 10 more than its caller's (19 at
# most); a full run doesn't. The test reads its own niceness to compare.
test_a_partial_run_runs_its_tests_under_nice_and_a_full_run_does_not() {
	mini_factory
	command -v nice > /dev/null 2>&1 || skip "no nice"
	cat > "$TEST_TMP/mini/core/tests/mini_test.sh" << 'SH'
test_niceness() {
	echo "niceness $(nice)"
}
SH
	local own expected
	own="$(nice)"
	expected=$((own + 10 > 19 ? 19 : own + 10))
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	assert_status 0
	assert_line "niceness $expected"
	run_cmd bash "$TEST_TMP/mini/core/test.sh"
	assert_status 0
	assert_line "niceness $own"
}

# --skip-real <a> leaves out adapter <a>'s real-tool tests (*_with_<tool>) alone,
# says how many, and the run stays a full run: the lock, the shared times file.
test_skip_real_leaves_out_an_adapters_real_tool_tests() {
	mini_factory
	local a
	for a in one two; do
		mkdir -p "$TEST_TMP/mini/adapters/$a/tests"
		printf 'test_plain() {\n\ttrue\n}\ntest_build_with_tool() {\n\ttrue\n}\ntest_run_with_other() {\n\ttrue\n}\n' > "$TEST_TMP/mini/adapters/$a/tests/steps_test.sh"
	done
	printf 'test_core_with_tool() {\n\ttrue\n}\n' >> "$TEST_TMP/mini/core/tests/mini_test.sh"
	mkdir "$FACTORY_TEST_LOCK" && echo "$BASHPID" > "$FACTORY_TEST_LOCK/pid"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" --skip-real one
	assert_status 2
	stderr_has "refused: another full run is in progress"
	rm -rf "$FACTORY_TEST_LOCK"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" --skip-real one
	assert_status 0
	assert_eq "PASS mini test_core_with_tool
PASS mini test_quick
PASS one/steps test_plain
PASS two/steps test_build_with_tool
PASS two/steps test_plain
PASS two/steps test_run_with_other
PASS skill budget
PASS raw waits" "$(results)" "the results"
	assert_line "test.sh: skipped 2 real-tool tests of the one adapter (--skip-real one)"
	assert_line "test.sh: seconds per test, slowest first, in $TMPDIR/factory-test-times.txt"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" --skip-real two --skip-real one
	assert_status 0
	assert_line "test.sh: skipped 2 real-tool tests of the one adapter (--skip-real one)"
	assert_line "test.sh: skipped 2 real-tool tests of the two adapter (--skip-real two)"
	assert_no_line "PASS two/steps test_build_with_tool"
	assert_line "PASS two/steps test_plain"
	run_cmd bash "$TEST_TMP/mini/core/test.sh"
	assert_status 0
	assert_line "PASS one/steps test_build_with_tool"
	assert_no_line "test.sh: skipped 2 real-tool tests of the one adapter (--skip-real one)"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" --skip-real three
	assert_status 2
	stderr_has "--skip-real needs an adapter with tests (factory/adapters/<a>/tests), not 'three'"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" --skip-real
	assert_status 2
}

# TERM to test.sh stops its running tests, the processes they started included,
# before their folders go. The slow test's child is a stand-in blocked until
# killed, so a run that waited for it instead would outlast the hang guard. A
# process that outlives the run is left to its own guard.
test_term_stops_the_running_tests_and_what_they_started() {
	mini_factory
	export PROBE="$TEST_TMP/probe"
	mkdir -p "$PROBE"
	blocking_stand_in "$PROBE/block" "$PROBE/never"
	cat > "$TEST_TMP/mini/core/tests/slow_test.sh" << 'SH'
test_slow() {
	"$PROBE/block" &
	echo "$!" > "$PROBE/child"
	echo "$BASHPID" > "$PROBE/test"
	wait
}
SH
	bash "$TEST_TMP/mini/core/test.sh" slow > "$TEST_TMP/run.out" 2>&1 &
	local runner=$! pid
	wait_until "the slow test to start" test -s "$PROBE/test"
	kill -TERM "$runner"
	wait_until "the interrupted run to end" ended "$runner"
	wait "$runner"
	for pid in "$(cat "$PROBE/test")" "$(cat "$PROBE/child")"; do
		wait_until "process $pid to end with the interrupted run" ended "$pid"
	done
	assert_eq "" "$(find "$TMPDIR" -maxdepth 1 -name 'factory-test.*' -type d)" "the interrupted run left its folder"
}

# ended <pid>: that process is gone.
ended() {
	! kill -0 "$1" 2> /dev/null
}

# big_skill <factory dir>: a skill over the line budget in <factory dir>/skills.
big_skill() {
	mkdir -p "$1/skills/big" || fail "no skill folder"
	{
		printf -- '---\nname: big\ndescription: Too long.\n---\n'
		seq 1 120
	} > "$1/skills/big/SKILL.md"
}

# From a clone of the factory's repo (VERSION and core/ at the top of a git
# checkout), test.sh runs there, and the skill budget reads its skills/.
test_a_clone_of_the_factory_repo_runs_from_its_top() {
	mini_factory
	isolate_git
	echo 0.1.0 > "$TEST_TMP/mini/VERSION"
	big_skill "$TEST_TMP/mini"
	git -C "$TEST_TMP/mini" init -q -b main || fail "could not make the clone"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	assert_status 1
	assert_line "PASS mini test_quick"
	assert_line "skills/big/SKILL.md:1 skill-too-long 124 lines; the budget is 100"
	assert_line "FAIL skill budget"
}

# Inside a project, from the project's root: the skills are factory/skills/.
test_a_vendored_factory_runs_from_the_project_root() {
	mini_factory
	isolate_git
	mkdir -p "$TEST_TMP/project" && mv "$TEST_TMP/mini" "$TEST_TMP/project/factory" || fail "could not vendor the mini factory"
	echo 0.1.0 > "$TEST_TMP/project/factory/VERSION"
	big_skill "$TEST_TMP/project/factory"
	git -C "$TEST_TMP/project" init -q -b dev || fail "could not make the project"
	run_cmd bash "$TEST_TMP/project/factory/core/test.sh" mini
	assert_status 1
	assert_line "factory/skills/big/SKILL.md:1 skill-too-long 124 lines; the budget is 100"
}

# --- git isolation --------------------------------------------------------------------

# hostile_git_config <file>: a global git config that breaks a test reading it: a
# commit must be signed, with a key that isn't there, and more.
hostile_git_config() {
	printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = NOPE\n\tname = Runner\n[core]\n\tautocrlf = true\n[init]\n\tdefaultBranch = trunk\n' > "$1"
}

# A test body sees no global or system git config, whether the runner's is in
# HOME or named by GIT_CONFIG_GLOBAL, and commits as the fixed identity.
test_a_test_body_sees_no_global_git_config() {
	local how
	mini_factory
	export PROBE="$TEST_TMP/probe"
	mkdir -p "$PROBE" "$TEST_TMP/home"
	hostile_git_config "$TEST_TMP/home/.gitconfig"
	cat > "$TEST_TMP/mini/core/tests/mini_test.sh" << 'SH'
test_probe() {
	git config --list --show-origin > "$PROBE/config"
	git init -q "$TEST_TMP/repo" && git -C "$TEST_TMP/repo" commit -q --allow-empty -m probe || exit 1
	git -C "$TEST_TMP/repo" log -1 --format='%an %ae' > "$PROBE/author"
	git -C "$TEST_TMP/repo" symbolic-ref --short HEAD > "$PROBE/branch"
}
SH
	for how in home global; do
		rm -f "$PROBE"/*
		if [ "$how" = home ]; then
			unset GIT_CONFIG_GLOBAL
			HOME="$TEST_TMP/home" git config --global commit.gpgsign > /dev/null || fail "the runner's config in HOME is not read"
			HOME="$TEST_TMP/home" run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
		else
			GIT_CONFIG_GLOBAL="$TEST_TMP/home/.gitconfig" run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
		fi
		assert_line "PASS mini test_probe"
		assert_eq "" "$(cat "$PROBE/config")" "the git config a test body sees, the runner's in $how"
		assert_eq "Fixture fixture@example.com" "$(cat "$PROBE/author")" "the test's identity, the runner's config in $how"
		assert_eq master "$(cat "$PROBE/branch")" "the default branch, the runner's config in $how"
	done
}

# runner_git_files <how> <command...>: run the command as a runner whose global git
# ignore and attributes ($TEST_TMP/runner/) git finds by <how>: home
# (~/.config/git/), xdg ($XDG_CONFIG_HOME/git/), count (GIT_CONFIG_COUNT) or
# parameters (GIT_CONFIG_PARAMETERS, as `git -c` passes on to a hook it runs).
runner_git_files() {
	local how="$1" files="$TEST_TMP/runner"
	shift
	case "$how" in
		home) env -u XDG_CONFIG_HOME HOME="$files/home" "$@" ;;
		xdg) XDG_CONFIG_HOME="$files/home/.config" "$@" ;;
		count)
			GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$files/home/.config/git/ignore" \
				GIT_CONFIG_KEY_1=core.attributesFile GIT_CONFIG_VALUE_1="$files/home/.config/git/attributes" "$@"
			;;
		parameters)
			# Quoted as git quotes it: each ' in a path as '\''.
			files="${files//\'/\'\\\'\'}"
			GIT_CONFIG_PARAMETERS="'core.excludesfile'='$files/home/.config/git/ignore' 'core.attributesfile'='$files/home/.config/git/attributes'" "$@"
			;;
	esac
}

# A test body reads no global git ignore or attributes, the defaults of
# core.excludesFile and core.attributesFile, whether the runner's are in
# ~/.config/git/ or in $XDG_CONFIG_HOME/git/ (issue #10), nor any the runner names
# in git's environment config (pass 1's review).
test_a_test_body_reads_no_global_git_ignore_or_attributes() {
	local how
	mini_factory
	export PROBE="$TEST_TMP/probe"
	mkdir -p "$PROBE" "$TEST_TMP/runner/home/.config/git" "$TEST_TMP/control"
	printf 'probe.txt\n' > "$TEST_TMP/runner/home/.config/git/ignore"
	printf 'probe.txt diff=hostile\n' > "$TEST_TMP/runner/home/.config/git/attributes"
	git init -q "$TEST_TMP/control" || fail "could not make the control repo"
	cat > "$TEST_TMP/mini/core/tests/mini_test.sh" << 'SH'
test_probe() {
	git init -q "$TEST_TMP/repo" && cd "$TEST_TMP/repo" || exit 1
	echo probe > probe.txt
	git check-ignore -q probe.txt && echo ignored > "$PROBE/ignore" || echo seen > "$PROBE/ignore"
	git status --porcelain > "$PROBE/status"
	git check-attr diff probe.txt > "$PROBE/attr"
}
SH
	for how in home xdg count parameters; do
		# The control: outside a test, git reads both.
		(cd "$TEST_TMP/control" && runner_git_files "$how" git check-ignore -q probe.txt) || fail "the runner's ignore by $how is not read"
		assert_eq "probe.txt: diff: hostile" "$(cd "$TEST_TMP/control" && runner_git_files "$how" git check-attr diff probe.txt)" "the runner's attributes by $how, outside a test"
		rm -f "$PROBE"/*
		run_cmd runner_git_files "$how" bash "$TEST_TMP/mini/core/test.sh" mini
		assert_line "PASS mini test_probe"
		assert_eq seen "$(cat "$PROBE/ignore")" "git check-ignore in a test body, the runner's ignore by $how"
		assert_eq "?? probe.txt" "$(cat "$PROBE/status")" "git status in a test body, the runner's ignore by $how"
		assert_eq "probe.txt: diff: unspecified" "$(cat "$PROBE/attr")" "git check-attr in a test body, the runner's attributes by $how"
	done
}

# A suite that lists its tests from git at load time (shell_lint does) finds them
# whatever the runner's git config (pass 1's review: core.abbrev = garbage hid
# every per-script lint test).
test_tests_are_listed_with_no_global_git_config() {
	mini_factory
	printf '[core]\n\tabbrev = garbage\n' > "$TEST_TMP/garbage.gitconfig"
	cat > "$TEST_TMP/mini/core/tests/listed_test.sh" << 'SH'
if [ -z "$(git config --global --list 2> /dev/null)" ]; then
	test_listed() {
		true
	}
fi
SH
	GIT_CONFIG_GLOBAL="$TEST_TMP/garbage.gitconfig" run_cmd bash "$TEST_TMP/mini/core/test.sh" listed
	assert_status 0
	assert_line "PASS listed test_listed"
}

# --- the waiting helpers --------------------------------------------------------------

# third_call: true from its third call on, counted in $calls.
third_call() {
	calls=$((calls + 1))
	[ "$calls" -ge 3 ]
}

test_wait_until_runs_the_command_until_it_succeeds() {
	calls=0
	wait_until "the third call" third_call
	assert_eq 3 "$calls" "the calls wait_until made"
}

test_wait_until_fails_naming_what_once_the_hang_guard_runs_out() {
	run_cmd bash -c '. "$FACTORY_CORE/tests/lib.sh"; TEST_HANG_GUARD=0; wait_until "the moon" false; echo after'
	assert_status 1
	assert_eq "" "$out" "wait_until went on after its guard ran out"
	stderr_has "gave up waiting for the moon: the hang guard ran out (0s)"
}

test_a_blocking_stand_in_runs_until_released() {
	local pid code=0
	blocking_stand_in "$TEST_TMP/block" "$TEST_TMP/release"
	"$TEST_TMP/block" some args &
	pid=$!
	wait_until "the stand-in to start" test -s "$TEST_TMP/block.pid"
	assert_eq "$pid" "$(cat "$TEST_TMP/block.pid")" "the pid the stand-in wrote"
	kill -0 "$pid" 2> /dev/null || fail "the stand-in ended before its release"
	: > "$TEST_TMP/release"
	wait "$pid" || code=$?
	assert_eq 0 "$code" "the released stand-in's exit code"
}

test_a_blocking_stand_in_ends_when_killed() {
	local pid code=0
	blocking_stand_in "$TEST_TMP/block" "$TEST_TMP/release"
	"$TEST_TMP/block" &
	pid=$!
	wait_until "the stand-in to start" test -s "$TEST_TMP/block.pid"
	kill -TERM "$pid"
	wait "$pid" || code=$?
	assert_eq 143 "$code" "the killed stand-in's exit code"
	[ ! -e "$TEST_TMP/release" ] || fail "the test released the stand-in"
}

test_a_blocking_stand_in_gives_up_once_the_hang_guard_runs_out() {
	TEST_HANG_GUARD=0 blocking_stand_in "$TEST_TMP/block" "$TEST_TMP/release"
	run_cmd "$TEST_TMP/block"
	assert_status 124
	stderr_has "never released; its hang guard ran out (0s)"
}

# --- the cached project ---------------------------------------------------------------

# counting_build: a project in $TEST_TMP/project holding a.txt, its build counted
# by a line in $TEST_TMP/../builds; cd there.
counting_build() {
	echo built >> "$TEST_TMP/../builds"
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" && echo built > a.txt || fail "could not build"
}

test_cached_project_builds_once_per_run_and_gives_each_caller_its_own_copy() {
	local base="$TEST_TMP/callers"
	mkdir -p "$base/one" "$base/two" "$base/three" "$base/run" "$base/other-run"
	export FACTORY_TEST_RUN="$base/run"
	TEST_TMP="$base/one" cached_project k counting_build
	assert_eq "$base/one/project" "$PWD" "the first caller's folder"
	echo changed > a.txt && echo new > b.txt
	TEST_TMP="$base/two" cached_project k counting_build
	assert_eq "$base/two/project" "$PWD" "the second caller's folder"
	assert_eq built "$(cat a.txt)" "the second copy's a.txt"
	[ ! -e b.txt ] || fail "the first caller's write reached the second copy"
	assert_eq 1 "$(wc -l < "$base/builds")" "the builds in one run"
	export FACTORY_TEST_RUN="$base/other-run"
	TEST_TMP="$base/three" cached_project k counting_build
	assert_eq 2 "$(wc -l < "$base/builds")" "the builds once another run asks"
}

# racing_build <n>: counting_build, once caller <n> has said it started and the
# other caller has too, so both build before either publishes.
racing_build() {
	: > "$TEST_TMP/../started-$1"
	wait_until "both callers to start" test -e "$TEST_TMP/../started-$((3 - $1))"
	counting_build
	echo "$1" > who.txt
}

test_cached_project_callers_racing_to_build_each_get_their_own_and_one_is_cached() {
	local base="$TEST_TMP/race" pid1 pid2 code1=0 code2=0
	mkdir -p "$base/one" "$base/two" "$base/three" "$base/run"
	export FACTORY_TEST_RUN="$base/run"
	(TEST_TMP="$base/one" cached_project k racing_build 1) &
	pid1=$!
	(TEST_TMP="$base/two" cached_project k racing_build 2) &
	pid2=$!
	wait "$pid1" || code1=$?
	wait "$pid2" || code2=$?
	assert_eq "0 0" "$code1 $code2" "the callers' exit codes"
	assert_eq 2 "$(wc -l < "$base/builds")" "the racing builds"
	assert_eq 1 "$(cat "$base/one/project/who.txt")" "the first caller's own project"
	assert_eq 2 "$(cat "$base/two/project/who.txt")" "the second caller's own project"
	assert_eq "k" "$(cd "$base/run/fixtures" && find . -mindepth 1 -maxdepth 1 ! -name '.*' | sed 's#^\./##')" "the cached keys"
	assert_eq 1 "$(cd "$base/run/fixtures" && find . -mindepth 1 -maxdepth 1 -name '.k.*' | wc -l)" "the cached copies left"
	TEST_TMP="$base/three" cached_project k counting_build
	assert_eq 2 "$(wc -l < "$base/builds")" "the builds once one is cached"
	assert_eq built "$(cat a.txt)" "the cached copy's a.txt"
	assert_eq "a.txt who.txt" "$(find . -mindepth 1 | LC_ALL=C sort | sed 's#^\./##' | tr '\n' ' ' | sed 's/ $//')" "the cached copy's files"
}

# --- raw waits ------------------------------------------------------------------------

RAW_WAITS_FIXTURE="$FACTORY_CORE/tests/fixture/raw-waits"

# Each raw wait in the fixture is flagged, by its line, and nothing else.
test_raw_waits_flags_sleep_timeout_and_seconds_by_line() {
	local f="$RAW_WAITS_FIXTURE/flagged.txt" n expected=""
	run_cmd bash "$FACTORY_CORE/raw-waits.sh" "$f"
	assert_status 1
	for n in 10 11 12 13 14 15 16 3 4 5 6 7 8 9; do
		expected+="$f:$n raw-wait a sleep, a timeout or bash's clock in a test; wait for a condition with wait_until, and make a stand-in that must keep running with blocking_stand_in (factory/core/tests/lib.sh)"$'\n'
	done
	assert_eq "${expected%$'\n'}" "$out" "the findings"
}

# The words as a variable, a key, an option, prose or a comment are no raw wait.
test_raw_waits_passes_the_words_used_otherwise() {
	run_cmd bash "$FACTORY_CORE/raw-waits.sh" "$RAW_WAITS_FIXTURE/clean.txt"
	assert_status 0
	assert_eq "" "$out" "the findings"
}

# test.sh runs the check over every test file, the adapters' included, after the
# tests: a test file that sleeps fails the run, named by file and line.
test_a_test_file_that_sleeps_fails_the_run() {
	mini_factory
	mkdir -p "$TEST_TMP/mini/adapters/fake/tests"
	cp "$RAW_WAITS_FIXTURE/flagged.txt" "$TEST_TMP/mini/adapters/fake/tests/slow_test.sh"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	assert_status 1
	assert_line "PASS mini test_quick"
	assert_line "mini/adapters/fake/tests/slow_test.sh:3 raw-wait a sleep, a timeout or bash's clock in a test; wait for a condition with wait_until, and make a stand-in that must keep running with blocking_stand_in (factory/core/tests/lib.sh)"
	assert_line "FAIL raw waits"
	rm "$TEST_TMP/mini/adapters/fake/tests/slow_test.sh"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	assert_status 0
	assert_line "PASS raw waits"
}

# --- loading the test files -----------------------------------------------------------

PARSE_FIXTURE="$FACTORY_CORE/tests/fixture/parse"

# results: the run's result lines, in order.
results() {
	printf '%s\n' "$out" | grep -E '^(PASS|FAIL|SKIP) '
}

# A test file that doesn't parse fails the run, named with bash's own message,
# where its tests print; the tests bash loaded from it, and the other files', still
# run (issue #4: its tests vanished and the run reported green).
test_a_test_file_that_does_not_parse_fails_the_run_naming_it() {
	mini_factory
	cp "$PARSE_FIXTURE/broken.txt" "$TEST_TMP/mini/core/tests/broken_test.sh"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" broken mini
	assert_status 1
	assert_line "$TEST_TMP/mini/core/tests/broken_test.sh: line 6: syntax error near unexpected token \`then'"
	assert_eq "FAIL broken (load)
PASS broken test_before
PASS mini test_quick
PASS skill budget
PASS raw waits" "$(results)" "the results"
	assert_line "test.sh: 2 passed, 1 failed, 0 skipped"
}

# A file that parses but exits while it loads, with any status, lists none of its
# tests: that fails the run too, saying so (pass 1's review: exit 0 went unseen).
test_a_test_file_that_exits_while_loading_fails_the_run() {
	local fixture code
	mini_factory
	for fixture in exits:3 exits0:0; do
		code="${fixture#*:}" fixture="${fixture%:*}"
		cp "$PARSE_FIXTURE/$fixture.txt" "$TEST_TMP/mini/core/tests/${fixture}_test.sh"
		run_cmd bash "$TEST_TMP/mini/core/test.sh" "$fixture" mini
		assert_status 1
		assert_line "test.sh: loading $TEST_TMP/mini/core/tests/${fixture}_test.sh exited $code before its tests were listed"
		assert_eq "FAIL $fixture (load)
PASS mini test_quick
PASS skill budget
PASS raw waits" "$(results)" "the results, $fixture"
	done
}

# A file may turn on extglob before it uses it, though bash -n never runs the shopt:
# it loads (pass 1's review). One that uses extglob without turning it on doesn't
# parse (pass 2's review).
test_a_test_file_that_turns_on_extglob_loads() {
	mini_factory
	cp "$PARSE_FIXTURE/extglob.txt" "$TEST_TMP/mini/core/tests/glob_test.sh"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" glob
	assert_status 0
	assert_line "PASS glob test_glob"
	assert_no_line "FAIL glob (load)"
}

# Sourced to settle its parse, it sees no runner's git config either (pass 3's
# review: its top-level git config --global wrote to the runner's).
test_an_extglob_test_file_sourced_to_check_it_writes_no_runner_git_config() {
	mini_factory
	cp "$PARSE_FIXTURE/extglob-git.txt" "$TEST_TMP/mini/core/tests/glob_test.sh"
	: > "$TEST_TMP/runner.gitconfig"
	GIT_CONFIG_GLOBAL="$TEST_TMP/runner.gitconfig" run_cmd bash "$TEST_TMP/mini/core/test.sh" glob
	assert_status 0
	assert_line "PASS glob test_glob"
	assert_eq "" "$(cat "$TEST_TMP/runner.gitconfig")" "the runner's git config"
}

test_a_test_file_that_uses_extglob_without_turning_it_on_fails_the_run() {
	mini_factory
	cp "$PARSE_FIXTURE/no-extglob.txt" "$TEST_TMP/mini/core/tests/glob_test.sh"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" glob
	assert_status 1
	assert_line "$TEST_TMP/mini/core/tests/glob_test.sh: line 7: syntax error near unexpected token \`('"
	assert_eq "FAIL glob (load)
PASS glob test_before
PASS skill budget
PASS raw waits" "$(results)" "the results"
}

# The Core's tests/lib.sh, sourced before every test file: one that doesn't parse
# fails the run, once, ahead of every test.
test_a_tests_lib_that_does_not_parse_fails_the_run() {
	mini_factory
	local lib="$TEST_TMP/mini/core/tests/lib.sh" n
	n=$(($(wc -l < "$lib") + 3))
	cat "$PARSE_FIXTURE/lib.txt" >> "$lib"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini
	assert_status 1
	assert_line "$lib: line $n: syntax error near unexpected token \`then'"
	assert_eq "FAIL lib (load)
PASS mini test_quick
PASS skill budget
PASS raw waits" "$(results)" "the results"
}

# An adapter's tests/lib.sh: checked once, ahead of the first test file in the run
# that sources it; a test file that doesn't source it is not held up by it (pass
# 1's review).
test_an_adapter_tests_lib_that_does_not_parse_fails_the_run() {
	mini_factory
	local tests="$TEST_TMP/mini/adapters/fake/tests"
	mkdir -p "$tests"
	cp "$PARSE_FIXTURE/lib.txt" "$tests/lib.sh"
	printf 'test_alone() {\n\ttrue\n}\n' > "$tests/alone_test.sh"
	# shellcheck disable=SC2016 # the test file's text, expanded when it loads
	printf '. "$FACTORY_CORE/../adapters/fake/tests/lib.sh"\ntest_one() {\n\ttrue\n}\n' > "$tests/one_test.sh"
	cp "$tests/one_test.sh" "$tests/two_test.sh"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" mini fake/alone fake/one fake/two
	assert_status 1
	assert_line "$tests/lib.sh: line 3: syntax error near unexpected token \`then'"
	assert_eq "PASS mini test_quick
PASS fake/alone test_alone
FAIL fake/lib (load)
PASS fake/one test_one
PASS fake/two test_one
PASS skill budget
PASS raw waits" "$(results)" "the results"
	run_cmd bash "$TEST_TMP/mini/core/test.sh" fake/alone
	assert_status 0
}
