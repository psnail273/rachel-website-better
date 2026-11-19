#!/usr/bin/env bash
# The stress run: the suites a batch can affect (or the full suite), repeated on a
# loaded machine, so a test whose outcome hangs on timing fails here, where it
# can be seen, rather than now and then. Run from anywhere, on demand only: when
# the human asks, or for a suspected flake (a test that failed, then passed on
# rerun), narrowed to its suites; never as a step of a batch, never by land:
#   bash factory/core/stress.sh [runs] [--since <rev>] [<suite>...]
#   bash factory/core/stress.sh                 3 runs of the full suite
#   bash factory/core/stress.sh 5               5 runs of it
#   bash factory/core/stress.sh runner nextjs/smoke   3 runs of those suites
#   bash factory/core/stress.sh --since origin/dev    3 runs of the suites the
#                                               diff since origin/dev can affect
#
# Suites are spelled as test.sh spells them: <name> for factory/core/tests/
# <name>_test.sh, <a>/<name> for factory/adapters/<a>/tests/<name>_test.sh. With
# --since <rev>, the suites are chosen from the paths `git diff --name-only
# <rev>...HEAD` lists, with the worktree's uncommitted and untracked files, by the
# rules of lib/suites.sh (factory_suites_affected), which amend.sh land skips an
# adapter's suites by too: a test file chooses its suite; core/tests/lib.sh,
# core/test.sh or any other file in core/ outside core/tests/, every suite; a
# file in an adapter's folder, that adapter's suites (and the core suites naming
# it); another factory file, the suites naming its folder; the project's ported
# tools/verify/, the adapter in use's; a folder outside the factory an adapter's
# tests read (the Godot adapter's addons/gdUnit4/), that adapter's; any other
# file outside the factory, none.
# In a project (tools/verify/factory-version, and no .factory-repo at the top),
# only the adapter in use runs: --since chooses no other adapter's suites, and
# says which adapters it left out (land's one full run covers them). Named suites
# run as named. It prints the suites it chose; when it chose none, it says so and
# exits 0, running nothing.
#
# Each run is test.sh with those suite names (with neither --since nor names, no
# names: the full suite), with FACTORY_TEST_GODOT_JOBS=1, one Godot at a time,
# while busy loops keep every thread busy: twice as many as the machine has
# threads (nproc), or $FACTORY_STRESS_LOOPS. The loops start before the first run,
# and every one is stopped when the script exits, on INT or TERM too (a running
# test.sh gets a TERM and stops its tests). A KILL can't be caught: its loops run
# on. test.sh runs in a process group of its own, not deaf to INT, as from a
# terminal.
#
# Each run gets every variable the machine's local.env sets (factory_load_env,
# lib/localenv.sh; the environment wins), so the real-tool tests it is there to
# shake run: the one at the top of the checkout core/ is in (the factory's repo),
# else its tools/verify/local.env (a project). FACTORY_TEST_GODOT_JOBS stays 1.
# It says which file it loaded, or that none was there.
#
# A full run takes test.sh's lock: a run refused because another full run holds
# it is a failed run, with test.sh's reason; it doesn't wait. A scoped run (suite
# names, or --since) is a partial run: no lock. test.sh would start a partial run
# under nice -n 10, where the busy loops, at normal priority, would starve it (a
# 52-suite run took 66 minutes, its cleanup 40 more); stress.sh sets
# FACTORY_TEST_NICED to test.sh's pid, so it runs at the loops' priority, as a
# full run does.
#
# It prints the loops' pids, then for each run every line of test.sh's output
# (stdout and stderr) that isn't a PASS, and the run's result:
#   stress: run <i> of <n> passed
#   stress: run <i> of <n> FAILED (test.sh exit <code>)
# then `stress: <k> of <n> runs passed`. Every run runs, with no retries. Exits 1
# if any run failed, 2 on a usage error (an unknown suite, a --since rev git
# can't resolve).
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/localenv.sh"
. "$core/lib/suites.sh"

usage() {
	echo "stress.sh: $1" >&2
	echo "usage: bash factory/core/stress.sh [runs] [--since <rev>] [<suite>...]   (default 3 runs of the full suite)" >&2
	exit 2
}

runs=3
if [ "$#" -gt 0 ] && [[ $1 =~ ^[0-9]+$ ]]; then
	[ "$((10#$1))" -gt 0 ] || usage "runs is a positive number, not '$1'"
	runs=$((10#$1))
	shift
fi
since=""
names=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--since)
			[ "$#" -ge 2 ] && [ -n "$2" ] || usage "--since needs a revision"
			since="$2"
			shift 2
			;;
		--since=*)
			since="${1#--since=}"
			[ -n "$since" ] || usage "--since needs a revision"
			shift
			;;
		-*) usage "unknown option $1" ;;
		*)
			names+=("$1")
			shift
			;;
	esac
done

# suite_file <suite>: its test file, as test.sh finds it; empty for no spelling of one.
suite_file() {
	case "$1" in
		*/*/* | */ | /* | *..*) ;;
		*/*) echo "$core/../adapters/${1%%/*}/tests/${1#*/}_test.sh" ;;
		*) echo "$core/tests/$1_test.sh" ;;
	esac
}
for name in ${names[@]+"${names[@]}"}; do
	f="$(suite_file "$name")"
	[ -n "$f" ] && [ -f "$f" ] || usage "no suite '$name' (no test file ${f:-for it})"
done

if [ -n "${FACTORY_STRESS_LOOPS+set}" ]; then
	loops="$FACTORY_STRESS_LOOPS"
	case "$loops" in '' | *[!0-9]*) usage "FACTORY_STRESS_LOOPS is a number, not '$loops'" ;; esac
	loops=$((10#$loops))
else
	threads="$(nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null)"
	case "$threads" in '' | *[!0-9]* | 0) usage "can't count the machine's threads (nproc); set FACTORY_STRESS_LOOPS" ;; esac
	loops=$((2 * threads))
fi

top="$(git -C "$core" rev-parse --show-toplevel 2> /dev/null)" || top=""

scope=""
left_out=()
chosen=()
if [ -n "$since" ]; then
	[ -n "$top" ] || usage "--since needs a git checkout; $core is in none"
	git -C "$top" rev-parse --verify --quiet "$since^{commit}" > /dev/null || usage "--since: git can't resolve '$since' to a commit"
	vend="$(git -C "$core" rev-parse --show-prefix)" && vend="${vend%core/}"
	# A project: its adapter in use, from factory-version's adapter line.
	in_use="" project=""
	if [ ! -f "$top/.factory-repo" ] && [ -f "$top/tools/verify/factory-version" ]; then
		project=1
		in_use="$(sed -n 's/^adapter  *//p' "$top/tools/verify/factory-version" | head -n 1)"
	fi
	diff_out="$(
		git -C "$top" diff --name-only --no-renames "$since...HEAD" -- &&
			git -C "$top" diff --name-only --no-renames HEAD -- &&
			git -C "$top" ls-files --others --exclude-standard
	)" || usage "--since: git can't list the diff since '$since'"
	picked="$(factory_suites_affected "$vend" "$in_use" <<< "$diff_out")"
	while IFS= read -r s; do
		[ -n "$s" ] || continue
		f="$(suite_file "$s")"
		[ -n "$f" ] && [ -f "$f" ] || continue
		if [ -n "$project" ] && [ -n "$in_use" ] && [[ $s == */* ]] && [ "${s%%/*}" != "$in_use" ]; then
			[[ " ${left_out[*]-} " == *" ${s%%/*} "* ]] || left_out+=("${s%%/*}")
			continue
		fi
		chosen+=("$s")
	done < <(printf '%s\n' "$picked" | LC_ALL=C sort -u)
	for a in ${left_out[@]+"${left_out[@]}"}; do
		echo "stress: left out the $a adapter's suites: the adapter in use is $in_use, and land's one full run covers the rest"
	done
	scope="the diff since $since"
fi
# Named suites join the chosen ones, as named.
for name in ${names[@]+"${names[@]}"}; do
	[[ " ${chosen[*]-} " == *" $name "* ]] || chosen+=("$name")
done
if [ -n "$since" ] || [ "${#names[@]}" -gt 0 ]; then
	# Core suites first, then the adapters', as test.sh orders them.
	mapfile -t chosen < <(
		printf '%s\n' ${chosen[@]+"${chosen[@]}"} | grep -v -e / -e '^$' | LC_ALL=C sort -u
		printf '%s\n' ${chosen[@]+"${chosen[@]}"} | grep / | LC_ALL=C sort -u
	)
	if [ "${#chosen[@]}" -eq 0 ]; then
		echo "stress: no suite to run: $scope touches no file a suite tests"
		exit 0
	fi
	echo "stress: chose ${#chosen[@]} suites${scope:+ from $scope}: ${chosen[*]}"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/factory-stress.XXXXXX")" || exit 1
loop_pids=()
suite=""
# cleanup: stop the running test.sh (it stops its own tests on TERM) and every
# loop, and wait for them before the work folder goes.
cleanup() {
	local pid
	[ -n "$suite" ] && kill -TERM "$suite" 2> /dev/null
	for pid in ${loop_pids[@]+"${loop_pids[@]}"}; do
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
if [ -n "$top" ]; then
	for f in "$top/local.env" "$top/tools/verify/local.env"; do
		[ -f "$f" ] && env_file="$f" && break
	done
fi
if [ -n "$env_file" ]; then
	echo "stress: each run loads $env_file (the environment wins over it)"
else
	echo "stress: no local.env at the checkout's top${top:+ ($top)} or in its tools/verify/, so the real-tool tests skip"
fi
if [ "${#chosen[@]}" -gt 0 ]; then
	what="the ${#chosen[@]} chosen suites (a partial run: no full-run lock)"
else
	what="the full suite"
fi
echo "stress: $runs runs of $what, FACTORY_TEST_GODOT_JOBS=1, $loops busy loops (pids ${loop_pids[*]:-none})"

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
		# Not niced: test.sh skips nice when this names its pid, which exec keeps.
		export FACTORY_TEST_NICED="$BASHPID"
		exec bash "$core/test.sh" ${chosen[@]+"${chosen[@]}"}
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
