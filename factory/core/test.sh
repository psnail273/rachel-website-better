#!/usr/bin/env bash
# The Core's and the adapters' tests, then two checks of the tree. Run from anywhere,
# in a project (factory/core/test.sh) or in a clone of the factory's repo
# (core/test.sh, run from the clone's top):
#   bash factory/core/test.sh              every test file
#   bash factory/core/test.sh runner pins  only tests/runner_test.sh and tests/pins_test.sh
#   bash factory/core/test.sh <a>/<suite>  only factory/adapters/<a>/tests/<suite>_test.sh
#   bash factory/core/test.sh --jobs 4 ... at most 4 tests at once (default 8)
#   bash factory/core/test.sh --skip-real <a> ...  every test but adapter <a>'s
#                                          real-tool tests (repeat it for more adapters)
#   bash factory/core/test.sh --skip-adapter <a> ...  every test but adapter <a>'s
#                                          (repeat it for more adapters)
#
# A partial run (suite names) runs at low priority: test.sh starts itself again
# under nice -n 10, so its tests do too, and a full run (a land's, say) gets the
# machine first. A full run is not niced.
#
# An adapter's real-tool tests are the ones that start its stack's real tool: it
# names them *_with_<tool>, one word after the last _with_, and no other test so
# (its tests/names_test.sh holds that, with misnamed_tests in tests/lib.sh; the
# Godot adapter's tools are godot, formatter and gdmutant, the Next.js
# adapter's node). --skip-real <a> leaves out those of
# factory/adapters/<a>/tests/, and the run says how many, after its tests:
# `test.sh: skipped <n> real-tool tests of the <a> adapter (--skip-real <a>)`.
# --skip-adapter <a> leaves out every suite of factory/adapters/<a>/tests/ (its
# lib.sh unchecked too), named or not, and the run says how many, after its
# tests: `test.sh: skipped the <a> adapter's <n> suites (--skip-adapter <a>)`.
# A run with no suite names and --skip-real or --skip-adapter is still a full
# run (the lock, the shared times file). amend.sh land passes them for an
# adapter its diff can't affect; no other caller does, so a run by hand and
# stress.sh run every test of their suites.
#
# After the tests come two checks of the tree: the skill size budget
# (skill-budget.sh), and raw-waits.sh: no test file sleeps for a fixed time or
# reads the clock.
#
# Test files are factory/core/tests/<name>_test.sh and
# factory/adapters/<adapter>/tests/<name>_test.sh; each defines test_* functions
# (helpers in factory/core/tests/lib.sh). Add a test by adding a function, and a
# suite by adding a file. Exits 1 if any test fails, 2 on a usage error or when
# refused.
#
# A test file that doesn't parse would lose the tests after its error, silently:
# bash -n checks each file the run loads first (factory/core/tests/lib.sh, each
# test file, and an adapter's tests/lib.sh when one sources it; a file that parses
# only with extglob, which it may turn on itself, is sourced to settle it). One
# that doesn't parse, or a test file whose loading exits, is a failure, `FAIL <suite> (load)` (`lib`, or `<adapter>/lib`, for a lib.sh), where
# its tests print, with bash's message (file and line). The other tests still run.
#
# Each test runs in its own subshell and temp folder ($TEST_TMP), with stdin from
# /dev/null and git isolated from the runner's config, global ignore and attributes
# (isolate_git), over a pool of workers. Its stdout and stderr are captured, and the
# results print in a fixed order (core files, then adapter files; test names in
# LC_ALL=C order), so two runs print the same log whatever the timing. A test's
# stdout prints before its result line; its stderr after a FAIL or SKIP.
# Per-test times go to a side file (its path printed at the end), never the log:
# $TMPDIR/factory-test-times.txt for a full run, a file of its own in
# $TMPDIR/factory-test-times.<uid>.d/ for any other (one folder per user, so
# another user's never refuses it). Every run removes the files in that folder
# older than a day (FACTORY_TEST_TIMES_AGE, in minutes; default
# 1440), and those older runs left in $TMPDIR itself (factory-test-times.XXXXXX).
# The last line is the run's wall time and its tests' seconds, summed:
#   test.sh: wall time <s> s, <s> test-seconds summed
#
# Tests share the run's folder, $FACTORY_TEST_RUN, removed at the end. Each test
# runs in its own process group, so an INT or TERM to test.sh stops every running
# test, the processes it started included, before the folder goes. A KILL can't
# be caught: its tests run on, and its folder and lock stay behind.
#
# A full run (no file names) takes a lock, $FACTORY_TEST_LOCK (default
# $TMPDIR/factory-test.lock), and a second full run is refused while it's held:
# two at once would slow both past their budget. Run single suites alongside. A
# lock whose run is gone (killed) is taken over, with a note on stderr.
#
# It runs outside the Editor's loop: FACTORY_GATE_LOOP (hooks/editor-gate.sh),
# when the gate that runs it set it, is unset, so a test's step runs as the
# test sets it up, not lighter.
set -u
unset FACTORY_GATE_LOOP

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A clone of the factory's repo has VERSION and core/ at the top of its checkout;
# in a project, factory/ sits in the project's root.
if cdup="$(git -C "$core/.." rev-parse --show-cdup 2> /dev/null)" && [ -z "$cdup" ] && [ -f "$core/../VERSION" ]; then
	cd "$core/.." || exit 1
else
	cd "$core/../.." || exit 1
fi

began="$EPOCHREALTIME"
args=("$@")
jobs=8
names=()
skip_real=()    # --skip-real's adapters
skip_adapter=() # --skip-adapter's
while [ "$#" -gt 0 ]; do
	case "$1" in
		--skip-real | --skip-adapter)
			[ "$#" -ge 2 ] && [ -n "$2" ] && [ -d "$core/../adapters/$2/tests" ] && [[ $2 != */* ]] || {
				echo "test.sh: $1 needs an adapter with tests (factory/adapters/<a>/tests), not '${2:-}'" >&2
				exit 2
			}
			if [ "$1" = --skip-real ]; then skip_real+=("$2"); else skip_adapter+=("$2"); fi
			shift 2
			;;
		-j | --jobs)
			[ "$#" -ge 2 ] || {
				echo "test.sh: $1 needs a number" >&2
				exit 2
			}
			jobs="$2"
			shift 2
			;;
		--jobs=*)
			jobs="${1#--jobs=}"
			shift
			;;
		-*)
			echo "test.sh: unknown option $1" >&2
			exit 2
			;;
		*)
			names+=("$1")
			shift
			;;
	esac
done
case "$jobs" in '' | *[!0-9]* | 0)
	echo "test.sh: --jobs takes a positive number, not '$jobs'" >&2
	exit 2
	;;
esac

# A partial run, at low priority: this script again under nice, with the same pid
# (exec), which FACTORY_TEST_NICED names so that it isn't niced twice; a test.sh a
# test runs is another process, niced in its turn.
if [ "${#names[@]}" -gt 0 ] && [ "${FACTORY_TEST_NICED:-}" != "$$" ] && command -v nice > /dev/null 2>&1; then
	export FACTORY_TEST_NICED="$$"
	exec nice -n 10 bash "$core/test.sh" "${args[@]}"
fi

files=()
if [ "${#names[@]}" -gt 0 ]; then
	for name in "${names[@]}"; do
		case "$name" in
			*/*) f="$core/../adapters/${name%%/*}/tests/${name#*/}_test.sh" ;;
			*) f="$core/tests/${name}_test.sh" ;;
		esac
		[ -f "$f" ] || {
			echo "test.sh: no test file $f" >&2
			exit 2
		}
		files+=("$f")
	done
else
	while IFS= read -r f; do
		files+=("$f")
	done < <(
		find "$core/tests" -maxdepth 1 -name '*_test.sh' | LC_ALL=C sort
		find "$core/../adapters" -mindepth 3 -maxdepth 3 -path '*/tests/*_test.sh' 2> /dev/null | LC_ALL=C sort
	)
fi

# --skip-adapter: leave out its adapters' test files, counted by adapter.
declare -A skipped_suites=()
if [ "${#skip_adapter[@]}" -gt 0 ]; then
	kept=()
	for f in "${files[@]}"; do
		case "$f" in */adapters/*/tests/*)
			adapter="$(basename "$(dirname "$(dirname "$f")")")"
			if [[ " ${skip_adapter[*]} " == *" $adapter "* ]]; then
				skipped_suites[$adapter]=$((${skipped_suites[$adapter]:-0} + 1))
				continue
			fi
			;;
		esac
		kept+=("$f")
	done
	files=(${kept[@]+"${kept[@]}"})
fi

# The lock: a folder (mkdir is atomic; there's no flock under Git Bash) holding the
# holder's pid. A lock whose holder is gone is stale and taken over.
lock=""
if [ "${#names[@]}" -eq 0 ]; then
	lock="${FACTORY_TEST_LOCK:-${TMPDIR:-/tmp}/factory-test.lock}"
	if ! mkdir "$lock" 2> /dev/null; then
		holder="$(cat "$lock/pid" 2> /dev/null)"
		if [ -z "$holder" ]; then
			# A run writes its pid right after taking the lock, so this one is starting,
			# or died in between.
			echo "test.sh: refused: the lock $lock names no run (pid unknown): another full run may be starting." >&2
			echo "test.sh: if none is, the lock is stale; remove it (rm -rf $lock) and run again." >&2
			exit 2
		fi
		if kill -0 "$holder" 2> /dev/null; then
			echo "test.sh: refused: another full run is in progress (pid $holder, lock $lock)." >&2
			echo "test.sh: wait for it, or run single suites: bash factory/core/test.sh <suite>..." >&2
			exit 2
		fi
		echo "test.sh: took over the stale lock $lock: its run (pid $holder) is gone, killed perhaps." >&2
		rm -rf "$lock"
		mkdir "$lock" 2> /dev/null || {
			echo "test.sh: refused: another full run took the lock $lock" >&2
			exit 2
		}
	fi
	echo "$$" > "$lock/pid"
fi

run="$(mktemp -d "${TMPDIR:-/tmp}/factory-test.XXXXXX")" || exit 1
export FACTORY_TEST_RUN="$run"
mkdir "$run/out" "$run/err" "$run/status"
pids=()
# cleanup: stop the tests still running, each a process group, and wait until
# every process of theirs is gone (KILL after 10 s more, a hang guard) before
# removing their folders.
cleanup() {
	local pid n alive
	for pid in "${pids[@]}"; do
		kill -TERM -- "-$pid" 2> /dev/null
	done
	wait 2> /dev/null
	for ((n = 0; n < 50; n++)); do
		alive=0
		for pid in "${pids[@]}"; do
			kill -0 -- "-$pid" 2> /dev/null && alive=1
		done
		[ "$alive" -eq 1 ] || break
		sleep 0.2
	done
	for pid in "${pids[@]}"; do
		kill -KILL -- "-$pid" 2> /dev/null
	done
	wait 2> /dev/null
	rm -rf "$run"
	[ -n "$lock" ] && rm -rf "$lock"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# The tests, in print order: test_file[i], test_suite[i], test_name[i].
test_file=() test_suite=() test_name=()
# The real-tool tests --skip-real leaves out, by adapter.
declare -A skipped_real=()
# A file the run sources that doesn't parse would drop the tests after its error,
# and a test file whose loading exits, with any status, would list none: either
# fails the run instead, as a "(load)" entry at that point of the print order,
# never launched.
# load_failed <suite> <message>: that entry, failed with <message> as its stderr.
load_failed() {
	local i="${#test_name[@]}"
	test_file+=("") test_suite+=("$1") test_name+=("(load)")
	printf '%s\n' "$2" > "$run/err/$i"
	echo 1 > "$run/status/$i"
}
# full_path <file>: <file> with its folder resolved, as bash's messages name it.
full_path() {
	echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}
# parse_error <file>: bash's own message (file and line) when <file> doesn't parse.
# bash -n runs no shopt, so a file that parses only with extglob on may turn it on
# itself: then bash sources it, after tests/lib.sh and isolate_git as the run
# does, and a syntax error there makes the source fail (status 2; a file whose last
# command fails fails too).
parse_error() {
	local path msg
	path="$(full_path "$1")"
	msg="$(bash -n "$path" 2>&1)" && return 0
	if bash -O extglob -n "$path" > /dev/null 2>&1 &&
		(
			exec > /dev/null 2>&1 < /dev/null
			if [ "$path" != "$(full_path "$core/tests/lib.sh")" ]; then
				. "$core/tests/lib.sh"
				TEST_TMP="$run" isolate_git
			fi
			# shellcheck disable=SC1090 # a test file, or a tests/lib.sh, by path
			. "$path"
		); then
		return 0
	fi
	echo "$msg"
	return 1
}
msg="$(parse_error "$core/tests/lib.sh")" || load_failed lib "$msg"
checked_libs=" " nl=$'\n'
for file in "${files[@]}"; do
	suite="$(basename "$file" _test.sh)"
	case "$file" in */adapters/*)
		adapter="$(basename "$(dirname "$(dirname "$file")")")"
		suite="$adapter/$suite"
		# The adapter's tests/lib.sh, checked once, ahead of the first test file that
		# sources it (a line `. ".../tests/lib.sh"` or `source ...`).
		lib="$(dirname "$file")/lib.sh"
		if [ -f "$lib" ] && [[ $checked_libs != *" $adapter "* ]] &&
			grep -qE '^[[:space:]]*(\.|source)[[:space:]].*tests/lib\.sh' "$file"; then
			checked_libs+="$adapter "
			msg="$(parse_error "$lib")" || load_failed "$adapter/lib" "$msg"
		fi
		;;
	esac
	msg="$(parse_error "$file")" # empty when it parses
	tests="$(
		exec 2> "$run/load-err"
		. "$core/tests/lib.sh"
		# A suite may list its tests from git: not from the runner's
		# config either.
		TEST_TMP="$run" isolate_git
		# shellcheck disable=SC1090 # each test file, by path
		. "$file"
		declare -F | awk '{ print $3 }' | grep '^test_' | LC_ALL=C sort
		echo "(loaded)"
	)"
	code=$?
	if [[ $tests != *"(loaded)" ]]; then
		[ -s "$run/load-err" ] && msg+="${msg:+$nl}$(cat "$run/load-err")"
		msg+="${msg:+$nl}test.sh: loading $(full_path "$file") exited $code before its tests were listed"
	elif [ -z "$msg" ]; then
		cat "$run/load-err" >&2
	fi
	tests="${tests%"(loaded)"}"
	[ -z "$msg" ] || load_failed "$suite" "$msg"
	for t in $tests; do
		if [ "$suite" != "${suite#*/}" ] && [[ " ${skip_real[*]} " == *" ${suite%%/*} "* ]] && [[ $t =~ _with_[a-z0-9]+$ ]]; then
			skipped_real[${suite%%/*}]=$((${skipped_real[${suite%%/*}]:-0} + 1))
			continue
		fi
		test_file+=("$file") test_suite+=("$suite") test_name+=("$t")
	done
done
total="${#test_name[@]}"

# Every test's temp folder, made in one go.
dirs=()
for ((i = 0; i < total; i++)); do
	dirs+=("$run/t$i")
done
[ "$total" -eq 0 ] || mkdir "${dirs[@]}" || exit 1

# Launch order: the tests that run a stack's real tool first, as they're the
# longest (an adapter names them *_with_<tool>, one word after the last _with_);
# then the rest in print order. Only the wall time depends on it.
queue=()
for ((i = 0; i < total; i++)); do
	[[ ${test_name[i]} =~ _with_[a-z0-9]+$ ]] && queue+=("$i")
done
for ((i = 0; i < total; i++)); do
	[ "${test_name[i]}" != "(load)" ] || continue
	[[ ${test_name[i]} =~ _with_[a-z0-9]+$ ]] || queue+=("$i")
done

# launch <i>: run test i in the background, in a process group of its own (job
# control on for the launch only); its exit code lands in status/<i>.
launch() {
	local i="$1"
	set -m
	{
		(
			export TEST_TMP="$run/t$i"
			cd "$TEST_TMP" || exit 1
			. "$core/tests/lib.sh"
			# No test reads the runner's git config: a test that wants one writes its own.
			isolate_git
			# shellcheck disable=SC1090 # each test file, by path
			. "${test_file[i]}"
			"${test_name[i]}"
		) > "$run/out/$i" 2> "$run/err/$i" < /dev/null
		echo "$?" > "$run/status/$i"
	} &
	pids[i]=$!
	set +m
	started[i]="$EPOCHREALTIME"
}

# finished <i>: true once test i's exit code is written; sets $status.
finished() {
	[ -s "$run/status/$1" ] || return 1
	read -r status < "$run/status/$1"
	[ -n "$status" ]
}

micros() {
	local t="${1/./}"
	echo "$((10#$t))"
}

passed=0 failed=0 skipped=0
started=() took=()
next=0    # the next queue entry to launch
printed=0 # the next test to print
running=0
while [ "$printed" -lt "$total" ]; do
	progress=0
	# Reap: a finished test frees its worker and gets its time.
	for i in "${!pids[@]}"; do
		if finished "$i"; then
			wait "${pids[i]}" 2> /dev/null
			unset 'pids[i]'
			took[i]=$(($(micros "$EPOCHREALTIME") - $(micros "${started[i]}")))
			running=$((running - 1))
			progress=1
		fi
	done
	while [ "$running" -lt "$jobs" ] && [ "$next" -lt "${#queue[@]}" ]; do
		launch "${queue[next]}"
		next=$((next + 1))
		running=$((running + 1))
		progress=1
	done
	# Print every finished test at the head of the print order.
	while [ "$printed" -lt "$total" ] && [ -z "${pids[printed]:-}" ] && finished "$printed"; do
		i="$printed"
		[ -s "$run/out/$i" ] && cat "$run/out/$i"
		case "$status" in
			0)
				echo "PASS ${test_suite[i]} ${test_name[i]}"
				passed=$((passed + 1))
				;;
			77)
				echo "SKIP ${test_suite[i]} ${test_name[i]}"
				cat "$run/err/$i"
				skipped=$((skipped + 1))
				;;
			*)
				echo "FAIL ${test_suite[i]} ${test_name[i]}"
				cat "$run/err/$i"
				failed=$((failed + 1))
				;;
		esac
		printed=$((printed + 1))
		progress=1
	done
	[ "$progress" -eq 1 ] || sleep 0.2
done

echo "== skill budget"
if bash "$core/skill-budget.sh"; then
	echo "PASS skill budget"
else
	echo "FAIL skill budget"
	failed=$((failed + 1))
fi

echo "== raw waits"
if bash "$core/raw-waits.sh"; then
	echo "PASS raw waits"
else
	echo "FAIL raw waits"
	failed=$((failed + 1))
fi

# One full run at a time (the lock) writes the shared times file; any other run
# writes its own, in one folder, so runs side by side never overwrite each
# other's. Each run first removes the files there older than a day, and those
# older runs left in $TMPDIR itself.
times_dir="${TMPDIR:-/tmp}/factory-test-times.$(id -u).d"
age="${FACTORY_TEST_TIMES_AGE:-1440}"
case "$age" in '' | *[!0-9]*) age=1440 ;; esac
mkdir -p "$times_dir" 2> /dev/null
find "$times_dir" -maxdepth 1 -type f -name 'factory-test-times.*' -mmin +"$age" -exec rm -f {} + 2> /dev/null
find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name 'factory-test-times.??????' ! -name 'factory-test-times.txt' -mmin +"$age" -exec rm -f {} + 2> /dev/null
if [ -n "$lock" ]; then
	times="${TMPDIR:-/tmp}/factory-test-times.txt"
else
	times="$(mktemp "$times_dir/factory-test-times.XXXXXX")" || times=/dev/null
fi
summed=0
for ((i = 0; i < total; i++)); do
	[ -n "${took[i]:-}" ] || continue # a "(load)" entry
	printf '%d.%03d %s %s\n' "$((took[i] / 1000000))" "$((took[i] / 1000 % 1000))" "${test_suite[i]}" "${test_name[i]}"
done | LC_ALL=C sort -rn > "$times"
for ((i = 0; i < total; i++)); do
	[ -z "${took[i]:-}" ] || summed=$((summed + took[i]))
done

[ "${#skip_real[@]}" -eq 0 ] || for adapter in $(printf '%s\n' "${skip_real[@]}" | LC_ALL=C sort -u); do
	echo "test.sh: skipped ${skipped_real[$adapter]:-0} real-tool tests of the $adapter adapter (--skip-real $adapter)"
done
[ "${#skip_adapter[@]}" -eq 0 ] || for adapter in $(printf '%s\n' "${skip_adapter[@]}" | LC_ALL=C sort -u); do
	echo "test.sh: skipped the $adapter adapter's ${skipped_suites[$adapter]:-0} suites (--skip-adapter $adapter)"
done
echo "test.sh: $passed passed, $failed failed, $skipped skipped"
echo "test.sh: seconds per test, slowest first, in $times"
# tenths <micros>: that many microseconds as seconds, to a tenth.
tenths() {
	printf '%d.%d' "$(($1 / 1000000))" "$(($1 / 100000 % 10))"
}
echo "test.sh: wall time $(tenths $(($(micros "$EPOCHREALTIME") - $(micros "$began")))) s, $(tenths "$summed") test-seconds summed"
[ "$failed" -eq 0 ]
