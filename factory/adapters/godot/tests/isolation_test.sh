# The Godot tests' isolation (tests/lib.sh, isolated_godot.sh): Godot run by a test
# keeps its user data and editor settings in the test's own folder, so tests
# running at once share neither, and the user's own Godot folders stay untouched;
# and it finds no Android SDK, so it runs no adb (#10).

. "$FACTORY_CORE/../adapters/godot/tests/lib.sh"

# user_godot_data: the user's own Godot data folder, which tests must not write.
user_godot_data() {
	if [ -n "${APPDATA:-}" ] && command -v cygpath > /dev/null 2>&1; then
		echo "$(cygpath -u "$APPDATA")/Godot"
	else
		echo "${XDG_DATA_HOME:-$HOME/.local/share}/godot"
	fi
}

test_godot_keeps_user_data_and_editor_settings_in_the_test_folder_with_godot() {
	[ -n "${GODOT_BIN:-}" ] || skip "GODOT_BIN is not set"
	"$GODOT_BIN" --headless --version 2> /dev/null | grep -q '^4\.7\.1\.stable' || skip "GODOT_BIN is not Godot 4.7.1"
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "no project"
	printf 'config_version=5\n\n[application]\nconfig/name="IsolationProbe"\n' > project.godot
	printf 'extends SceneTree\n\nfunc _init() -> void:\n\tFileAccess.open("user://probe.txt", FileAccess.WRITE).store_string(OS.get_cmdline_user_args()[0])\n\tquit()\n' > probe.gd
	# A token only this test writes, so a probe.txt some earlier run left in the
	# user's folder can't pass for, or fail, this one.
	local token="probe-$BASHPID-${EPOCHREALTIME/./}"
	"$GODOT_BIN" --headless --path . --import > "$TEST_TMP/import.log" 2>&1 || fail "the import failed: $(tail -5 "$TEST_TMP/import.log")"
	"$GODOT_BIN" --headless --path . -s res://probe.gd -- "$token" > "$TEST_TMP/probe.log" 2>&1 || fail "the probe failed: $(tail -5 "$TEST_TMP/probe.log")"
	local found probe
	found="$(cd "$TEST_TMP/appdata" 2> /dev/null && find . -type f | sed 's#^\./##' | LC_ALL=C sort)"
	probe="$(printf '%s\n' "$found" | grep '/app_userdata/IsolationProbe/probe\.txt$')" ||
		fail "user:// isn't under the test's appdata; it holds:"$'\n'"$found"
	assert_eq "$token" "$(cat "$TEST_TMP/appdata/$probe")" "the probe's user:// file"
	printf '%s\n' "$found" | grep -q '/editor_settings-4[^/]*\.tres$' ||
		fail "the editor settings aren't under the test's appdata; it holds:"$'\n'"$found"
	! grep -qxF "$token" "$(user_godot_data)/app_userdata/IsolationProbe/probe.txt" 2> /dev/null ||
		fail "the probe wrote the user's own Godot folder $(user_godot_data)"
}

# --- adb (#10) ------------------------------------------------------------------------

# Every Godot a test starts inherits an ANDROID_HOME that never exists, whatever
# the runner's own.
test_godot_tests_point_android_home_at_a_folder_that_never_exists() {
	assert_eq "$TEST_TMP/no-android-sdk" "${ANDROID_HOME:-}" "ANDROID_HOME"
	[ ! -e "$ANDROID_HOME" ] || fail "ANDROID_HOME exists: $ANDROID_HOME"
	local got
	got="$(env FACTORY_CORE="$FACTORY_CORE" TEST_TMP="$TEST_TMP" ANDROID_HOME=/opt/android-sdk \
		bash -c '. "$FACTORY_CORE/../adapters/godot/tests/lib.sh" && printenv ANDROID_HOME')" ||
		fail "lib.sh exported no ANDROID_HOME"
	assert_eq "$TEST_TMP/no-android-sdk" "$got" "a Godot's ANDROID_HOME under a runner with its own"
}

# The real Godot's editor, on the fixture project (an Android preset), with a home
# whose Android SDK holds an adb that notes each call: the test's Godot runs it
# never. The control, the same Godot with ANDROID_HOME unset (in user data of its
# own, as the first run saved its SDK path in its editor settings), runs it, so a
# call would be seen.
test_godot_runs_no_adb_on_a_project_with_an_android_preset_with_godot() {
	[ -n "${GODOT_BIN:-}" ] || skip "GODOT_BIN is not set"
	"$GODOT_BIN" --headless --version 2> /dev/null | grep -q '^4\.7\.1\.stable' || skip "GODOT_BIN is not Godot 4.7.1"
	! command -v cygpath > /dev/null 2>&1 || skip "the stand-in adb is a shell script, and Windows Godot runs adb.exe"
	local sdk="$TEST_TMP/home/Android/Sdk" f
	mkdir -p "$sdk/platform-tools" "$TEST_TMP/project" || fail "no home or project"
	printf '#!/bin/sh\necho "$*" >> "%s/adb.calls"\n' "$TEST_TMP" > "$sdk/platform-tools/adb"
	chmod 755 "$sdk/platform-tools/adb"
	for f in project.godot export_presets.cfg main.gd main.tscn; do
		cp "$FACTORY_CORE/../adapters/godot/tests/fixture/project/$f.txt" "$TEST_TMP/project/$f" || fail "no fixture $f"
	done
	cd "$TEST_TMP/project" || fail "no project"
	grep -qx 'platform="Android"' export_presets.cfg || fail "the fixture has no Android preset"
	HOME="$TEST_TMP/home" "$GODOT_BIN" --headless --path . --import > "$TEST_TMP/import.log" 2>&1 ||
		fail "the import failed: $(tail -5 "$TEST_TMP/import.log")"
	[ ! -e "$TEST_TMP/adb.calls" ] || fail "the test's Godot ran adb:"$'\n'"$(cat "$TEST_TMP/adb.calls")"
	env -u ANDROID_HOME HOME="$TEST_TMP/home" TEST_TMP="$TEST_TMP/control" \
		"$GODOT_BIN" --headless --path . --import > "$TEST_TMP/control.log" 2>&1 ||
		fail "the control's import failed: $(tail -5 "$TEST_TMP/control.log")"
	grep -qx 'kill-server' "$TEST_TMP/adb.calls" 2> /dev/null ||
		fail "the control's Godot didn't run the home's adb, so the test can't see a call: '$(cat "$TEST_TMP/adb.calls" 2> /dev/null)'"
}

# A self-contained Godot keeps its editor settings, and any Android SDK saved in
# them, beside it (pass 1's review): the wrapper refuses one, by either marker,
# and through a link to it, before it runs anything.
test_a_self_contained_godot_is_refused() {
	local marker dir
	for marker in _sc_ ._sc_ none; do
		dir="$TEST_TMP/$marker"
		mkdir -p "$dir/sc" "$dir/bin"
		printf '#!/usr/bin/env bash\necho "$*" > "%s/ran"\n' "$dir" > "$dir/sc/godot"
		chmod 755 "$dir/sc/godot"
		[ "$marker" = none ] || : > "$dir/sc/$marker"
		ln -s "$dir/sc/godot" "$dir/bin/godot"
		FACTORY_TEST_GODOT="$dir/bin/godot" run_cmd bash "$FACTORY_CORE/../adapters/godot/tests/isolated_godot.sh" --headless --version
		if [ "$marker" = none ]; then
			assert_status 0
			assert_eq "--headless --version" "$(cat "$dir/ran" 2> /dev/null)" "the Godot's arguments, with no _sc_ beside it"
		else
			assert_status 78
			stderr_has "isolated_godot.sh: $dir/bin/godot is a self-contained Godot (a _sc_ file beside it)"
			[ ! -e "$dir/ran" ] || fail "the wrapper ran a self-contained Godot ($marker)"
		fi
	done
}

# --- the Godot slots ------------------------------------------------------------------

# slot_machine: a run folder of the test's own, a pool of the test's own
# ($SLOTS, outside the run's folder, as the machine's is) with one Godot slot, and
# a stand-in Godot that notes it ran in $TEST_TMP/ran. A slot with no pid file, or
# the lock, is stale once an hour old, so one the test just made is new however
# slow the machine.
slot_machine() {
	export FACTORY_TEST_RUN="$TEST_TMP/run" FACTORY_TEST_GODOT="$TEST_TMP/godot" FACTORY_TEST_GODOT_JOBS=1
	export FACTORY_TEST_GODOT_SLOTS="$TEST_TMP/slots" FACTORY_TEST_GODOT_STALE=3600
	SLOTS="$FACTORY_TEST_GODOT_SLOTS"
	mkdir -p "$FACTORY_TEST_RUN" "$SLOTS"
	printf '#!/usr/bin/env bash\necho "$*" > "$TEST_TMP/ran"\n' > "$FACTORY_TEST_GODOT"
	chmod 755 "$FACTORY_TEST_GODOT"
}

# hold_slot <pid> [<n>]: slot <n> (1), held by that pid.
hold_slot() {
	mkdir -p "$SLOTS/${2:-1}"
	echo "$1" > "$SLOTS/${2:-1}/pid"
}

# dead_pid: the pid of a process that has ended.
dead_pid() {
	: &
	local pid=$!
	wait "$pid"
	echo "$pid"
}

# run_isolated <arg>: isolated_godot.sh, giving up after two claims. A slot free
# or stale is taken at the first; a stale lock is cleared at the first, and the
# slot taken at the second. Neither waits on the clock.
run_isolated() {
	FACTORY_TEST_GODOT_TRIES=2 run_cmd bash "$FACTORY_CORE/../adapters/godot/tests/isolated_godot.sh" "$1"
}

# assert_gave_up: run_isolated found no slot it could take, and said so.
assert_gave_up() {
	assert_status 75
	stderr_has "isolated_godot.sh: no free Godot slot after 2 tries"
}

# A holder killed hard leaves its slot (#193 item 4): the next Godot clears it and
# runs, and frees the slot when it ends.
test_a_slot_whose_holder_is_gone_is_cleared_and_taken() {
	slot_machine
	hold_slot "$(dead_pid)"
	run_isolated probe
	assert_status 0
	assert_eq probe "$(cat "$TEST_TMP/ran" 2> /dev/null)" "the stand-in Godot's arguments"
	[ ! -e "$SLOTS/1" ] || fail "the slot outlived its Godot: $(ls -A "$SLOTS/1")"
}

test_a_slot_whose_holder_is_alive_is_waited_on() {
	slot_machine
	hold_slot "$$"
	run_isolated probe
	assert_gave_up
	[ ! -e "$TEST_TMP/ran" ] || fail "Godot ran in a slot held by a live process"
	assert_eq "$$" "$(cat "$SLOTS/1/pid" 2> /dev/null)" "the live holder's pid file"
}

# A slot with no pid file is a holder starting, until it is older than the stale
# age (10 s; an hour here): then the holder died before writing it.
test_a_slot_with_no_pid_is_cleared_only_once_old() {
	slot_machine
	mkdir "$SLOTS/1"
	run_isolated probe
	assert_gave_up
	[ ! -e "$TEST_TMP/ran" ] || fail "Godot ran in a slot that a holder may be starting in"
	[ -d "$SLOTS/1" ] || fail "the new slot was removed"
	touch -d '2 hours ago' "$SLOTS/1"
	run_isolated probe
	assert_status 0
	assert_eq probe "$(cat "$TEST_TMP/ran" 2> /dev/null)" "the stand-in Godot's arguments"
}

# Every claim waits on the lock, so none lands between a waiter reading a slot's
# pid and clearing the slot (pass 1's review: it cleared a holder's new claim). A
# lock older than the stale age was left by a waiter killed while it held it: it
# is removed.
test_a_slot_is_claimed_only_under_the_lock() {
	slot_machine
	mkdir "$SLOTS/lock"
	run_isolated probe
	assert_gave_up
	[ ! -e "$TEST_TMP/ran" ] || fail "Godot took a free slot while another waiter held the lock"
	[ -d "$SLOTS/lock" ] || fail "the new lock was removed"
	hold_slot "$(dead_pid)"
	touch -d '2 hours ago' "$SLOTS/lock"
	run_isolated probe
	assert_status 0
	assert_eq probe "$(cat "$TEST_TMP/ran" 2> /dev/null)" "the stand-in Godot's arguments"
	[ -z "$(ls -A "$SLOTS")" ] || fail "slots left: $(ls -A "$SLOTS")"
}

# With no stale age set, the default (10 s) holds: a slot with no pid file a
# minute old is stale.
test_a_slot_with_no_pid_a_minute_old_is_stale_by_default() {
	slot_machine
	unset FACTORY_TEST_GODOT_STALE
	mkdir "$SLOTS/1"
	touch -d '1 minute ago' "$SLOTS/1"
	run_isolated probe
	assert_status 0
	assert_eq probe "$(cat "$TEST_TMP/ran" 2> /dev/null)" "the stand-in Godot's arguments"
}

# The pool is the machine's: a run whose Godot holds the one slot keeps another
# run's Godot waiting, and a slot a gone holder of another run left is cleared.
test_two_runs_share_the_machines_slots() {
	slot_machine
	blocking_stand_in "$TEST_TMP/held" "$TEST_TMP/release"
	FACTORY_TEST_RUN="$TEST_TMP/run-a" FACTORY_TEST_GODOT="$TEST_TMP/held" \
		bash "$FACTORY_CORE/../adapters/godot/tests/isolated_godot.sh" first &
	local first=$!
	wait_until "the first run's Godot to start" test -s "$TEST_TMP/held.pid"
	FACTORY_TEST_RUN="$TEST_TMP/run-b" run_isolated second
	assert_gave_up
	[ ! -e "$TEST_TMP/ran" ] || fail "a second run's Godot ran beside the first, over the cap of 1"
	: > "$TEST_TMP/release"
	wait "$first" || fail "the first run's Godot failed"
	FACTORY_TEST_RUN="$TEST_TMP/run-b" run_isolated second
	assert_status 0
	assert_eq second "$(cat "$TEST_TMP/ran" 2> /dev/null)" "the stand-in Godot's arguments"
}

test_a_slot_another_runs_gone_holder_left_is_cleared() {
	slot_machine
	FACTORY_TEST_RUN="$TEST_TMP/run-a" hold_slot "$(dead_pid)"
	FACTORY_TEST_RUN="$TEST_TMP/run-b" run_isolated probe
	assert_status 0
	assert_eq probe "$(cat "$TEST_TMP/ran" 2> /dev/null)" "the stand-in Godot's arguments"
	[ -z "$(ls -A "$SLOTS")" ] || fail "slots left: $(ls -A "$SLOTS")"
}

# A run tries slots 1 to its own FACTORY_TEST_GODOT_JOBS: with slot 1 held, a run
# of 1 waits, and a run of 2 takes slot 2.
test_a_run_tries_only_the_slots_up_to_its_own_jobs() {
	slot_machine
	hold_slot "$$" 1
	printf '#!/usr/bin/env bash\nls "$FACTORY_TEST_GODOT_SLOTS" > "$TEST_TMP/ran"\n' > "$FACTORY_TEST_GODOT"
	run_isolated probe
	assert_gave_up
	[ ! -e "$TEST_TMP/ran" ] || fail "a run of one Godot took a slot past 1"
	FACTORY_TEST_GODOT_JOBS=2 run_isolated probe
	assert_status 0
	assert_eq "1"$'\n'"2" "$(cat "$TEST_TMP/ran" 2> /dev/null)" "the slots while the run of 2 ran Godot"
	assert_eq "1" "$(ls -A "$SLOTS")" "the slots after it"
}

# With no folder set, the pool is /tmp/factory-godot-slots.<uid>, whatever the
# run's or the test's TMPDIR (pass 1's review: two TMPDIRs made two pools). This
# is the machine's own pool, so the test may take any slot (a run of 1000) and
# holds it for a moment only: the stand-in Godot finds the slot that names its
# caller, isolated_godot.sh. Another run's waiter may hold the pool's lock for a
# moment, so it tries up to 1000 claims, not 2.
test_the_pool_defaults_to_one_folder_for_the_machine_whatever_tmpdir() {
	slot_machine
	unset FACTORY_TEST_GODOT_SLOTS
	SLOTS="/tmp/factory-godot-slots.$(id -u)"
	mkdir -p "$TEST_TMP/elsewhere"
	# Another run's slot may go between the glob and grep's read (pass 2's review):
	# what grep prints is the answer, not its exit code.
	printf '#!/usr/bin/env bash\ngrep -lxF "$PPID" "%s"/*/pid > "$TEST_TMP/ran" 2> /dev/null\nexit 0\n' "$SLOTS" > "$FACTORY_TEST_GODOT"
	FACTORY_TEST_GODOT_JOBS=1000 FACTORY_TEST_GODOT_TRIES=1000 TMPDIR="$TEST_TMP/elsewhere" \
		run_cmd bash "$FACTORY_CORE/../adapters/godot/tests/isolated_godot.sh" probe
	assert_status 0
	[[ $(cat "$TEST_TMP/ran" 2> /dev/null) =~ ^$SLOTS/[0-9]+/pid$ ]] || fail "Godot ran in no slot of $SLOTS: '$(cat "$TEST_TMP/ran" 2> /dev/null)'"
	assert_eq "" "$(ls -A "$TEST_TMP/elsewhere")" "the test's own TMPDIR"
}
