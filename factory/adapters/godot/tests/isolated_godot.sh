#!/usr/bin/env bash
# GODOT_BIN under the Godot adapter's tests (tests/lib.sh sets it): the real Godot,
# $FACTORY_TEST_GODOT, run with the test's own user data, and at most
# $FACTORY_TEST_GODOT_JOBS (default 4) at once on the machine, across every test.sh
# run. Both defaults, here and test.sh's --jobs 8, are the fastest measured in WSL
# on a 16-thread machine.
#
# Godot keeps user:// (app_userdata/<config/name>) and its editor settings under
# %APPDATA%\Godot on Windows (the XDG folders elsewhere), shared by every project
# of the same name. Tests run at once, so each gets its own, under
# $TEST_TMP/appdata. Windows Godot reads APPDATA and LOCALAPPDATA as Windows paths.
#
# Fresh editor settings would find the human's Android SDK (at ~/Android/Sdk) and
# start its adb, which reads their ~/.android/adbkey (#10). tests/lib.sh exports
# ANDROID_HOME, a folder that never exists, so they find none: it is set there,
# not here, as the mutate tests run the real Godot without this wrapper.
#
# A self-contained Godot (a _sc_ or ._sc_ file beside its executable) keeps its
# editor settings and user data in editor_data/ beside it, whatever the folders
# above: a test can keep neither apart, and an Android SDK saved there starts
# adb (pass 1's review). So this refuses one, exit 78 and a note on stderr,
# before it runs anything. A test that asks it for --version first then skips;
# one that doesn't (arch's needs_godot) fails, the note in its message. Either
# way no Godot of a test runs: a self-contained GODOT_BIN isn't one the tests
# support.
#
# Under test.sh ($FACTORY_TEST_RUN) a pool of mkdir locks caps the Godots, so a
# test whose verify runs Godot for minutes isn't slowed by every other at once.
# The pool is the machine's, not a run's: one folder, $FACTORY_TEST_GODOT_SLOTS,
# by default /tmp/factory-godot-slots.<uid>, whatever TMPDIR a run or a test has
# (the mutate step sets one for gdmutant; two sessions may set two), and one per
# user so another user's folder never blocks a claim. Every run on the machine
# shares it, so a land and the builders' runs beside it share the cap. Its slots are numbered 1, 2, ...;
# a run tries only slots 1 to its own $FACTORY_TEST_GODOT_JOBS. Runs that set
# different figures share the low slots, so at most the largest figure among the
# runs at work run Godot at once, and a run with 1 (stress.sh) waits for slot 1
# alone.
#
# A slot is a folder holding its holder's pid, and its EXIT trap removes both. A
# holder killed hard (KILL) leaves its slot behind (#193 item 4), so a waiter clears
# a stale slot and takes it, whichever run left it: one whose pid file names a
# process that is gone, or one with no pid file older than 10 s. Every claim,
# stale or free, happens under one more mkdir lock, $slots/lock, so no slot is
# taken between a waiter reading its pid and clearing it. A slot without a pid file is then one whose holder was killed
# while claiming it, or is freeing it (the pid file first, then the folder): the
# 10 s keep a waiter off the second. A lock older than 10 s was left by a waiter
# killed while it held it (that takes milliseconds) and is removed. Its age is the
# only sign: a pid would let a waiter that read a finished holder's pid remove the
# lock the next waiter just took (pass 2's review). A slot's pid is this shell, not
# its Godot: a Godot outliving a killed shell runs on beside the slot's next holder,
# one over the cap.
#
# Three settings, for the tests of the slots: FACTORY_TEST_GODOT_SLOTS, the pool's
# folder (above); FACTORY_TEST_GODOT_STALE, the age in seconds past which a slot
# with no pid file, or the lock, is stale (default 10); and
# FACTORY_TEST_GODOT_TRIES, the most claims to try before giving up with exit 75
# and a note on stderr (default: no limit).
set -u

# self_contained <godot>: a _sc_ or ._sc_ sits beside it, or beside the file its
# links lead to (Godot looks beside its own executable).
self_contained() {
	local path dir
	path="$(command -v -- "$1")" || return 1
	for path in "$path" "$(readlink -f -- "$path")"; do
		[ -n "$path" ] || continue
		dir="$(dirname -- "$path")"
		[ ! -e "$dir/_sc_" ] && [ ! -e "$dir/._sc_" ] || return 0
	done
	return 1
}

real="${FACTORY_TEST_GODOT:?no real Godot in FACTORY_TEST_GODOT}"
if self_contained "$real"; then
	echo "isolated_godot.sh: $real is a self-contained Godot (a _sc_ file beside it): its editor settings and user data stay beside it, out of the test's reach" >&2
	exit 78
fi

data="${TEST_TMP:?isolated_godot.sh runs under a test}/appdata"
mkdir -p "$data/roaming" "$data/local" "$data/cache"
if command -v cygpath > /dev/null 2>&1; then
	{ read -r APPDATA && read -r LOCALAPPDATA; } < <(cygpath -w "$data/roaming" "$data/local")
	export APPDATA LOCALAPPDATA
else
	export XDG_DATA_HOME="$data/roaming" XDG_CONFIG_HOME="$data/local" XDG_CACHE_HOME="$data/cache"
fi

# older <path>: it was last changed more than $FACTORY_TEST_GODOT_STALE (10) s ago.
older() {
	local changed
	changed="$(stat -c %Y -- "$1" 2> /dev/null || stat -f %m -- "$1" 2> /dev/null)" || return 1
	[ $(($(date +%s) - changed)) -gt "${FACTORY_TEST_GODOT_STALE:-10}" ]
}

# gone <slot>: its holder is gone. Its pid file names a process that has ended, or
# it has none and is older than the stale age.
gone() {
	local pid
	pid="$(cat -- "$1/pid" 2> /dev/null)"
	if [ -n "$pid" ]; then
		! kill -0 "$pid" 2> /dev/null
	else
		older "$1"
	fi
}

# unlock: give back the lock.
unlock() {
	rmdir "$locked" 2> /dev/null
	locked=""
}

# claim: under the lock, take the first slot that is free or stale. False when
# none is, or another waiter holds the lock.
claim() {
	local n s
	if ! mkdir "$slots/lock" 2> /dev/null; then
		! older "$slots/lock" || rmdir "$slots/lock" 2> /dev/null
		return 1
	fi
	locked="$slots/lock"
	for ((n = 1; n <= ${FACTORY_TEST_GODOT_JOBS:-4}; n++)); do
		s="$slots/$n"
		if ! mkdir "$s" 2> /dev/null; then
			gone "$s" || continue
			rm -f -- "$s/pid"
			if ! rmdir "$s" 2> /dev/null || ! mkdir "$s" 2> /dev/null; then
				continue
			fi
		fi
		slot="$s"
		echo "$$" > "$slot/pid"
		break
	done
	unlock
	[ -n "$slot" ]
}

# free: give back the lock if held, and this shell's slot. A slot whose pid file
# names another holder was cleared and taken: it is theirs now.
free() {
	[ -z "$locked" ] || unlock
	[ -n "$slot" ] || return 0
	case "$(cat -- "$slot/pid" 2> /dev/null)" in
		"" | "$$") rm -f -- "$slot/pid" && rmdir "$slot" 2> /dev/null ;;
	esac
	return 0
}

slot=""
locked=""
if [ -n "${FACTORY_TEST_RUN:-}" ]; then
	slots="${FACTORY_TEST_GODOT_SLOTS:-/tmp/factory-godot-slots.$(id -u)}"
	mkdir -p "$slots"
	trap free EXIT
	trap 'exit 143' INT TERM
	# Wait for a free slot; no timeout, as a slot frees when its Godot exits, or is
	# cleared once its holder is gone.
	tries=0
	while ! claim; do
		tries=$((tries + 1))
		if [ -n "${FACTORY_TEST_GODOT_TRIES:-}" ] && [ "$tries" -ge "$FACTORY_TEST_GODOT_TRIES" ]; then
			echo "isolated_godot.sh: no free Godot slot after $tries tries" >&2
			exit 75
		fi
		sleep 0.5
	done
fi

"$real" "$@"
