#!/usr/bin/env bash
# The stress run: the full suite, repeated on a loaded machine, so a test whose
# outcome hangs on timing fails when it is written rather than at a release's land.
# Run from anywhere, on demand (never at land):
#   bash factory/core/stress.sh         3 runs
#   bash factory/core/stress.sh <runs>  that many runs
#
# Each run is test.sh with no suite names (the full suite), with
# FACTORY_TEST_GODOT_JOBS=1, one Godot at a time, while busy loops keep every
# thread busy: twice as many as the machine has threads (nproc), or
# $FACTORY_STRESS_LOOPS. The loops start before the first run, and every one is
# stopped when the script exits, on INT or TERM too (a running test.sh gets a TERM
# and stops its tests). A KILL can't be caught: its loops run on. test.sh runs in
# a process group of its own, not deaf to INT, as from a terminal.
#
# Each run gets every variable the machine's local.env sets (factory_load_env,
# lib/localenv.sh; the environment wins), so the real-tool tests it is there to
# shake run: the one at the top of the checkout core/ is in (the factory's repo),
# else its tools/verify/local.env (a project). FACTORY_TEST_GODOT_JOBS stays 1.
# It says which file it loaded, or that none was there.
#
# A run is a full run, so it takes test.sh's lock: a run refused because another
# full run holds it is a failed run, with test.sh's reason; it doesn't wait.
#
# It prints the loops' pids, then for each run every line of test.sh's output
# (stdout and stderr) that isn't a PASS, and the run's result:
#   stress: run <i> of <n> passed
#   stress: run <i> of <n> FAILED (test.sh exit <code>)
# then `stress: <k> of <n> runs passed`. Every run runs, with no retries. Exits 1
# if any run failed, 2 on a usage error.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/localenv.sh"

usage() {
	echo "stress.sh: $1" >&2
	echo "usage: bash factory/core/stress.sh [runs]   (default 3)" >&2
	exit 2
}

[ "$#" -le 1 ] || usage "too many arguments"
runs="${1:-3}"
case "$runs" in '' | *[!0-9]*) usage "runs is a positive number, not '$runs'" ;; esac
[ "$((10#$runs))" -gt 0 ] || usage "runs is a positive number, not '$runs'"
runs=$((10#$runs))

if [ -n "${FACTORY_STRESS_LOOPS+set}" ]; then
	loops="$FACTORY_STRESS_LOOPS"
	case "$loops" in '' | *[!0-9]*) usage "FACTORY_STRESS_LOOPS is a number, not '$loops'" ;; esac
	loops=$((10#$loops))
else
	threads="$(nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null)"
	case "$threads" in '' | *[!0-9]* | 0) usage "can't count the machine's threads (nproc); set FACTORY_STRESS_LOOPS" ;; esac
	loops=$((2 * threads))
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/factory-stress.XXXXXX")" || exit 1
loop_pids=()
suite=""
# cleanup: stop the running test.sh (it stops its own tests on TERM) and every
# loop, and wait for them before the work folder goes.
cleanup() {
	local pid
	[ -n "$suite" ] && kill -TERM "$suite" 2> /dev/null
	for pid in "${loop_pids[@]}"; do
		kill -TERM "$pid" 2> /dev/null
	done
	wait 2> /dev/null
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

for ((n = 0; n < loops; n++)); do
	while :; do :; done &
	loop_pids+=("$!")
done
env_file=""
if top="$(git -C "$core" rev-parse --show-toplevel 2> /dev/null)"; then
	for f in "$top/local.env" "$top/tools/verify/local.env"; do
		[ -f "$f" ] && env_file="$f" && break
	done
fi
if [ -n "$env_file" ]; then
	echo "stress: each run loads $env_file (the environment wins over it)"
else
	echo "stress: no local.env at the checkout's top${top:+ ($top)} or in its tools/verify/, so the real-tool tests skip"
fi
echo "stress: $runs runs of the full suite, FACTORY_TEST_GODOT_JOBS=1, $loops busy loops (pids ${loop_pids[*]:-none})"

passed=0
for ((i = 1; i <= runs; i++)); do
	echo "== run $i of $runs"
	# In the background, so a signal to this script is handled at once, not when
	# the run ends; with job control on for the launch only, so test.sh doesn't
	# start deaf to INT, as a background job of a shell without it does, and its
	# tests see the signals a run from a terminal sees.
	set -m
	(
		factory_load_env "$env_file"
		export FACTORY_TEST_GODOT_JOBS=1
		exec bash "$core/test.sh"
	) > "$work/run.log" 2>&1 &
	suite=$!
	set +m
	wait "$suite"
	code=$?
	suite=""
	# As text, whatever bytes a test printed (a NUL makes grep call it binary).
	grep -av '^PASS ' "$work/run.log"
	if [ "$code" -eq 0 ]; then
		echo "stress: run $i of $runs passed"
		passed=$((passed + 1))
	else
		echo "stress: run $i of $runs FAILED (test.sh exit $code)"
	fi
done

echo "stress: $passed of $runs runs passed"
[ "$passed" -eq "$runs" ]
