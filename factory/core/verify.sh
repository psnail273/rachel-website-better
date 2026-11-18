#!/usr/bin/env bash
# The gate runner. Run from the project root:
#   bash factory/core/verify.sh                 every step, in the fixed order
#   bash factory/core/verify.sh lint test       only those steps, still in that order
#   bash factory/core/verify.sh --twice [step…] run twice and fail if the outputs differ
#   bash factory/core/verify.sh --keep-going    run every step even after one fails
#                                               (baseline.sh uses it to see every finding)
#   bash factory/core/verify.sh --all-static    run every static step even after one
#                                               fails, then stop (the Editor's gate)
#   bash factory/core/verify.sh --red [step…]   the red gate (lib/red.sh)
#   bash factory/core/verify.sh --reuse …       print the gate stamp's verdict when
#                                               a run on these same inputs left one
#   bash factory/core/verify.ps1 …              the same, from PowerShell
#
# Steps run in the order of FACTORY_STEPS (lib/steps.sh); the run stops at the
# first failing step and names it (with --keep-going it runs on and names the
# first). With --all-static a failing static step (FACTORY_STATIC_STEPS: format,
# typecheck, lint, arch, deviation) doesn't stop the run: the other static steps
# still run, so every static finding shows at once, and the long steps after them
# (test, mutate, smoke) don't, as a red static step already fails the run; prepare
# and the long steps stop it at once, as without it. Such a run counts as a plain
# one, under the plain run's stamp key, and keeps a stamp only when its verdict is
# the plain run's (it went on past no failure), so the Driver's --reuse reads it
# (#15, ruled 2026-11-13). Before any step it sources the gitignored
# tools/verify/local.env (tool locations), and warns on stderr, in one line, when
# it still sets FACTORY_EDITOR or FACTORY_VERIFIER, the retired role lists, which
# nothing reads; prepare first runs the pin check
# (pins.sh) and the hook drift check (hooks.sh check), then the project's own
# prepare script.
#
# The parallel steps (FACTORY_PARALLEL_STEPS, lib/steps.sh: typecheck, lint, arch,
# deviation, test; #57 item 3, ruled 2026-11-17) run at once, each in the
# background in a process group of its own with no stdin, as the project's
# no-overlap file (FACTORY_NO_OVERLAP) lets them: steps a line of it names, as
# they write the same place, run one at a time, in the fixed order. With no such
# file, or with FACTORY_SERIAL_STEPS=1, they run one by one, as the rest do. The
# runner keeps each one's stdout and stderr and passes them on whole, step by
# step in the fixed order, once each step's turn comes, so stdout, the exit code,
# the step marks, the stamp and the counts are what a run one by one gives. A
# step past the one that stops the run (or, with --all-static, a long step past a
# red static one) may have run, but it shows nothing, counts nothing, and its
# transient exit keeps no stamp from being written: the runner stops it once its
# result can't show (TERM to its group, TERM again 2 s on for what missed it,
# then KILL to what is left: once its run ends, or FACTORY_STEP_STOP_GRACE s
# later; stop_steps), as it stops every step still running when it gets INT,
# TERM or HUP itself. What such
# a step wrote stays, though: one that wrote into the tree (a test runner's new
# snapshot) changed the run's inputs, so the run keeps no stamp and says so, as
# any run that changes them does; one by one, that step would not have run.
#
# The optional mutate step (lib/mutate.sh) runs only in an issue's Green phase,
# on a tree changed since the diff base; else it is `== mutate SKIP`, the reason
# on stderr. A run whose steps include it first removes the survivors file
# ($FACTORY_SURVIVORS_FILE, which the runner sets); the step must write it when
# it runs. A project without the step's script skips it, as it skips a no-op.
#
# The test step writes its results to $FACTORY_RESULTS_FILE (lib/results.sh); the
# runner points that at a fresh file of its own unless the caller set it, and
# removes any old file there before the step runs. The Core judges the step from
# it: by default the green gate (every test PASSes, and the script exits 0); with
# --red, the red judgement (lib/red.sh) alone, against the Build Brief
# ($FACTORY_BRIEF, else <git-dir>/factory/brief.md). Either way a stray stdout line
# still fails the step.
#
# stdout is the verdict and nothing else, so two runs on the same tree print the
# same bytes: a `== <step> PASS|FAIL|SKIP` line per step run, that step's findings
# sorted beneath it, then `verify: PASS` or `verify: FAILED at step <step>`.
# Steps' other output goes to stderr. With FACTORY_STEP_MARK set (land.sh sets
# it), stderr also gets `<the mark> <step>` before each step and `<the mark>`
# after the last, so the caller can bound each step's output exactly: the runner
# unsets it first, so no step sees the mark and the stamp's key leaves it out.
#
# Each run keeps its verdict and exit code in a gate stamp (lib/stamp.sh), under a
# key of everything the verdict depends on: the commit, the working tree, the
# brief, the diff base, the run state and the FACTORY_ variables. With --reuse,
# a stamp whose key matches is printed again and its exit code returned, with a
# note on stderr, once the survivors file is as that run left it (when mutate is
# one of its steps); with none, the run goes ahead. --reuse never applies when the
# caller set FACTORY_RESULTS_FILE (only a fresh run writes it), and --twice
# keeps no stamp and refuses --reuse. A run that changes its own inputs keeps no
# stamp, nor does one in which a step failed for a transient cause, exiting
# FACTORY_TRANSIENT_EXIT (75; lib/steps.sh): a build lock held too long or a
# refused connection says nothing about the code, so --reuse runs it again.
# FACTORY_NO_STAMP=1 keeps none either. A stamp that can't be written (a
# read-only git dir) is skipped with one line on stderr, and the run's verdict
# and exit code stand.
#
# On an issue branch (issue/<n>) a run counts in the run state what the Retro
# reads (factory_gate_count, lib/run.sh): gate-runs, one caught-<step> for the
# step that stopped a red run, and seconds-<step> for each step it shows (not a
# SKIP), its own time from its start to its end, so steps run at once add up to
# more than the run took, timed with EPOCHREALTIME (FACTORY_STEP_CLOCK names a file holding the
# time instead: a test's clock). A run counts once per stamp key, the one it
# started with: a run on inputs a counted run had (lib/stamp.sh keeps their
# keys) counts nothing, so a fresh rerun on the same tree, the stop hook's then
# the Driver's or lock.sh record's, counts once, and so does a tree changed and
# changed back. A run with no key (a checkout that can't be keyed, or
# FACTORY_NO_STAMP) counts nothing, nor does a verdict --reuse prints from a
# stamp, --twice or --keep-going (baseline.sh's, so the Partial gate's). No
# catch is counted in the partial phase, nor in the red phase for a run without
# --red stopped at test: the full verify is red there by design. The counts are
# left out of the stamp's key. A count that can't be written (a read-only git
# dir) is skipped with one line on stderr, and the verdict and exit code stand.
#
# Exit codes: 0 pass, 1 a step failed (or --twice saw different outputs), 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/diff.sh"
. "$core/lib/results.sh"
. "$core/lib/red.sh"
. "$core/lib/run.sh"
. "$core/lib/scenarios.sh"
. "$core/lib/stamp.sh"
. "$core/lib/mutate.sh"

step_mark="${FACTORY_STEP_MARK:-}"
unset FACTORY_STEP_MARK

usage() {
	cat >&2 << EOF
usage: bash factory/core/verify.sh [--twice] [--keep-going] [--all-static] [--red] [--reuse] [step...]
steps, in order: ${FACTORY_STEPS[*]}
EOF
	exit 2
}

twice=0
keep_going=0
all_static=0
red=0
reuse=0
flags=()
requested=()
for arg in "$@"; do
	case "$arg" in
		--twice) twice=1 ;;
		--keep-going)
			keep_going=1
			flags+=(--keep-going)
			;;
		--all-static)
			all_static=1
			flags+=(--all-static)
			;;
		--red)
			red=1
			flags+=(--red)
			;;
		--reuse) reuse=1 ;;
		--version)
			cat "$core/../VERSION"
			exit 0
			;;
		-h | --help) usage ;;
		-*)
			echo "verify: unknown option '$arg'" >&2
			usage
			;;
		*)
			factory_is_step "$arg" || {
				echo "verify: unknown step '$arg'" >&2
				usage
			}
			requested+=("$arg")
			;;
	esac
done

if [ "$twice" -eq 1 ] && [ "$reuse" -eq 1 ]; then
	echo "verify: --twice runs every step twice to compare them, so it takes no --reuse" >&2
	usage
fi

# The parallel steps' background runs (start_step), by index into steps: the
# run's pid, which is its process group's id too, and its state: started, then
# taken once its result is passed on, or stopped.
job_pid=()
job_state=()

# stop_steps [long]: stop each parallel step still running (with long, only the
# long ones: test): TERM (and CONT, for a stopped one) to its process group, so
# the step's script and its tools end as at a Ctrl-C; wait for its run to end;
# then KILL what is left of its group, so nothing it started outlives the run.
# One TERM can miss: bash forking a child as it comes leaves the child its own
# TERM handler (the job's trap) until its exec, so the child catches the TERM
# and loses it, and runs on, and with it the job, which waits for it. So a
# watchdog, in a process group of its own, sends the groups TERM again 2
# seconds on, and KILL FACTORY_STEP_STOP_GRACE seconds (default 10) after
# that; the waits end, the watchdog gets KILL to its group, its sleep with it.
stop_steps() {
	local i watchdog grace="${FACTORY_STEP_STOP_GRACE:-10}" stopping=()
	case "$grace" in '' | *[!0-9]*) grace=10 ;; esac
	for i in "${!job_state[@]}"; do
		[ "${job_state[$i]}" = started ] || continue
		[ "${1:-}" != long ] || ! factory_step_is_static "${steps[$i]}" || continue
		kill -TERM -- "-${job_pid[$i]}" 2> /dev/null
		kill -CONT -- "-${job_pid[$i]}" 2> /dev/null
		stopping+=("${job_pid[$i]}")
		job_state[i]=stopped
	done
	[ "${#stopping[@]}" -gt 0 ] || return 0
	set -m
	(
		sleep 2
		for i in "${stopping[@]}"; do
			kill -TERM -- "-$i"
			kill -CONT -- "-$i"
		done
		sleep "$grace"
		for i in "${stopping[@]}"; do
			kill -KILL -- "-$i"
		done
	) < /dev/null > /dev/null 2>&1 &
	watchdog=$!
	set +m
	for i in "${stopping[@]}"; do
		wait "$i" 2> /dev/null
		kill -KILL -- "-$i" 2> /dev/null
	done
	kill -KILL -- "-$watchdog" 2> /dev/null
	wait "$watchdog" 2> /dev/null
}

tmp="$(mktemp -d)"
trap 'stop_steps; rm -rf "$tmp"' EXIT

# --twice: two plain runs of this script, compared byte for byte, keeping no stamp.
if [ "$twice" -eq 1 ]; then
	FACTORY_NO_STAMP=1 bash "${BASH_SOURCE[0]}" "${flags[@]}" "${requested[@]}" > "$tmp/run1"
	status1=$?
	FACTORY_NO_STAMP=1 bash "${BASH_SOURCE[0]}" "${flags[@]}" "${requested[@]}" > "$tmp/run2"
	if ! cmp -s "$tmp/run1" "$tmp/run2"; then
		diff "$tmp/run1" "$tmp/run2" | sed 's/^/  /'
		echo "verify: two runs differ"
		exit 1
	fi
	cat "$tmp/run1"
	echo "verify: two runs match"
	exit "$status1"
fi

# The steps to run: the fixed order, filtered to the requested ones.
steps=()
for s in "${FACTORY_STEPS[@]}"; do
	if [ "${#requested[@]}" -eq 0 ]; then
		steps+=("$s")
		continue
	fi
	for r in "${requested[@]}"; do
		if [ "$r" = "$s" ]; then
			steps+=("$s")
			break
		fi
	done
done

# The machine's tool locations, before the stamp's key: the key reads the
# FACTORY_ variables local.env may set, the same before the run and after it.
caller_results="${FACTORY_RESULTS_FILE:-}"
local_env="$FACTORY_STEPS_DIR/local.env"
if [ -f "$local_env" ]; then
	set -a
	# shellcheck disable=SC1090
	. "./$local_env"
	set +a
	# The role lists of the retired Cursor Editor and Codex Verifier: ignored.
	retired="$(tr -d '\r' < "$local_env" | sed -nE 's/^[[:space:]]*(export[[:space:]]+)?(FACTORY_EDITOR|FACTORY_VERIFIER)=.*/\2/p' | sort -u | paste -sd ' ' -)"
	[ -z "$retired" ] ||
		echo "verify: $local_env sets ${retired// / and }, which the factory ignores now: the Editor is always the editor-sonnet subagent and the Verifier the verifier subagent; delete the line" >&2
fi

# The survivors file, when mutate is one of the steps (lib/mutate.sh).
survivors=""
for s in "${steps[@]}"; do
	if [ "$s" = mutate ]; then
		survivors="$(factory_survivors_file)" || survivors=""
	fi
done

# The gate stamp (lib/stamp.sh): its key, read before any step runs.
stamp_mode=green
[ "$red" -eq 0 ] || stamp_mode=red
[ "$keep_going" -eq 0 ] || stamp_mode="$stamp_mode-keep-going"
stamp_key=""
stamp_file=""
if { [ "$reuse" -eq 1 ] || [ -z "${FACTORY_NO_STAMP:-}" ]; } &&
	stamp_file="$(factory_stamp_file "$stamp_mode" "${steps[@]}")"; then
	stamp_key="$(factory_stamp_key "$stamp_mode" "${steps[@]}")" || {
		stamp_key=""
		echo "verify: no gate stamp: this checkout can't be keyed (git failed, a submodule or nested repo is changed, a tracked file is marked assume-unchanged, or skip-worktree outside the Scenario folder start.sh's sparse checkout leaves out, or the diff base names no commit)" >&2
	}
fi
if [ "$reuse" -eq 1 ]; then
	if [ -n "$caller_results" ]; then
		echo "verify: --reuse: the caller set FACTORY_RESULTS_FILE, which only a fresh run writes; running the steps" >&2
	elif [ -n "$stamp_key" ] && factory_stamp_read "$stamp_file" "$stamp_key" "$tmp/reused"; then
		if [ -z "$survivors" ] || factory_stamp_restore_survivors "$stamp_file" "$stamp_key" "$survivors"; then
			cat "$tmp/reused"
			echo "verify: --reuse: this is the verdict of the run at $STAMP_AT on these same inputs ($stamp_file); run without --reuse for a fresh one" >&2
			exit "$STAMP_EXIT"
		fi
		echo "verify: --reuse: the survivors file $survivors can't be put back as the gate stamp's run left it; running the steps" >&2
	else
		echo "verify: --reuse: no gate stamp for these inputs; running the steps" >&2
	fi
fi

# The gate's counts: on an issue branch, by a run with a stamp key that no
# counted run had (lib/stamp.sh, factory_stamp_counted).
count_branch=""
count_phase=""
if [ "$keep_going" -eq 0 ] && [ -n "$stamp_key" ] && [ -z "${FACTORY_NO_STAMP:-}" ] &&
	count_branch="$(factory_current_branch)" && factory_is_issue_branch "$count_branch" &&
	! factory_stamp_counted "$stamp_key"; then
	count_phase="$(factory_state_get "$count_branch" phase 2> /dev/null)" || count_phase=""
else
	count_branch=""
fi
step_seconds=()

export FACTORY_CORE="$core"
export FACTORY_RESULTS_FILE="${caller_results:-$tmp/results}"
if [ -n "$survivors" ]; then
	export FACTORY_SURVIVORS_FILE="$survivors"
	rm -f -- "$survivors"
fi

# judge_test <exit status of the test script>: print the Core's judgement of the
# test step's results; return 1 when the step fails.
judge_test() {
	local brief
	if [ "$red" -eq 1 ]; then
		brief="$(factory_brief_path)" || brief=".git/factory/brief.md"
		factory_red_judge "$FACTORY_RESULTS_FILE" "$brief"
		return
	fi
	factory_green_judge "$FACTORY_RESULTS_FILE" && [ "$1" -eq 0 ]
}

# run_step <step>: run one step, print its status line and sorted findings. Its
# scratch files are its own ($tmp/steps/<step>/), so steps can run at once.
run_step() {
	local step="$1" script status=0 code d="$tmp/steps/$1"
	script="$(factory_step_script "$step")"
	mkdir -p "$d"
	: > "$d/out"

	if [ ! -f "$script" ] && factory_step_is_optional "$step"; then
		echo "== $step SKIP"
		return 0
	elif [ ! -f "$script" ]; then
		factory_finding "$script" 1 step-missing "no script for step $step; a step the stack lacks holds '$FACTORY_NOOP_MARKER'" > "$d/out"
		status=1
	elif factory_step_is_noop "$script"; then
		echo "== $step SKIP"
		return 0
	elif [ "$step" = mutate ] && ! factory_mutate_gate "$red" "$failed_at"; then
		echo "verify: mutate: no mutants: $MUTATE_SKIP" >&2
		echo "== $step SKIP"
		return 0
	else
		if [ "$step" = prepare ]; then
			bash "$core/pins.sh" >> "$d/out" || status=1
			bash "$core/hooks.sh" check >> "$d/out" || status=1
		fi
		if [ "$status" -eq 0 ]; then
			[ "$step" = test ] && rm -f "$FACTORY_RESULTS_FILE"
			if [ "$step" = mutate ]; then
				FACTORY_MUTATE_BASE="$MUTATE_BASE" bash "$script" > "$d/raw"
			else
				bash "$script" > "$d/raw"
			fi
			code=$?
			[ "$code" -ne "$FACTORY_TRANSIENT_EXIT" ] || : > "$d/transient"
			if [ "$step" = test ]; then
				judge_test "$code" >> "$d/out" || status=1
			elif [ "$code" -ne 0 ]; then
				status=1
			elif [ "$step" = mutate ] && [ ! -f "${FACTORY_SURVIVORS_FILE:-}" ]; then
				factory_finding "$script" 1 survivors-missing "the mutate step wrote no survivors file; it writes one to \$FACTORY_SURVIVORS_FILE (factory/core/lib/mutate.sh)" >> "$d/out"
				status=1
			fi
			tr -d '\r' < "$d/raw" > "$d/step"
			factory_check_findings "$step" "$d/step" >> "$d/out" || status=1
			grep -E "$FACTORY_FINDING_RE" "$d/step" >> "$d/out"
		fi
	fi

	if [ "$status" -eq 0 ]; then echo "== $step PASS"; else echo "== $step FAIL"; fi
	factory_sort_findings < "$d/out"
	return "$status"
}

# finish <exit> <last line>: print the verdict's last line, keep the stamp when
# the run left its inputs as it found them, and exit.
finish() {
	local caught="$failed_at"
	printf '%s\n' "$2" | tee -a "$tmp/verdict"
	if [ -n "$count_branch" ]; then
		if [ "$count_phase" = partial ] || { [ "$count_phase" = red ] && [ "$red" -eq 0 ] && [ "$caught" = test ]; }; then
			caught=""
		fi
		# The key first: a run that can't list it counts nothing, so none counts twice.
		{ factory_stamp_mark_counted "$stamp_key" && factory_gate_count "$count_branch" "$caught" "${step_seconds[@]}"; } 2> /dev/null ||
			echo "verify: could not count this run in the run state of $count_branch (gate-runs, caught-<step>, seconds-<step>) or list its key as counted; the verdict stands" >&2
	fi
	if [ -n "$went_on" ]; then
		echo "verify: no gate stamp: --all-static went on past the failing step $failed_at, so its verdict is not the plain run's" >&2
	elif [ -s "$tmp/transient" ]; then
		echo "verify: no gate stamp: step $(paste -sd ' ' "$tmp/transient") failed for a transient cause (exit $FACTORY_TRANSIENT_EXIT), not the code's, so --reuse will run it again" >&2
	elif [ -n "$stamp_key" ] && [ -z "${FACTORY_NO_STAMP:-}" ]; then
		if [ "$(factory_stamp_key "$stamp_mode" "${steps[@]}")" = "$stamp_key" ]; then
			if [ -z "$survivors" ] || factory_stamp_write_survivors "$stamp_file" "$stamp_key" "$survivors"; then
				factory_stamp_write "$stamp_file" "$stamp_key" "$1" "$tmp/verdict"
			fi
		else
			echo "verify: no gate stamp: the run changed its own inputs (the tree, the brief or the run state)" >&2
		fi
	fi
	exit "$1"
}

: > "$tmp/verdict"
failed_at=""
went_on=""

# The parallel steps of this run (FACTORY_PARALLEL_STEPS, lib/steps.sh), by index
# into steps, and whether they run at once: unless FACTORY_SERIAL_STEPS=1, when
# the project's no-overlap file names only them and lets some two overlap. Each
# pair's answer, at may[10 * i + k].
group=()
for i in "${!steps[@]}"; do
	! factory_step_is_parallel "${steps[$i]}" || group+=("$i")
done
at_once=0
may=()
if [ "${FACTORY_SERIAL_STEPS:-}" != 1 ] && [ "${#group[@]}" -ge 2 ] && [ -f "$FACTORY_NO_OVERLAP" ]; then
	if unknown="$(factory_no_overlap_check)"; then
		for i in "${group[@]}"; do
			for k in "${group[@]}"; do
				if [ "$k" -gt "$i" ] && factory_steps_may_overlap "${steps[$i]}" "${steps[$k]}"; then
					may[10 * i + k]=1
					may[10 * k + i]=1
					at_once=1
				fi
			done
		done
	else
		echo "verify: $FACTORY_NO_OVERLAP names $(printf '%s\n' "$unknown" | LC_ALL=C sort -u | paste -sd ' ' -), which is no step that may run at once ($FACTORY_PARALLEL_STEPS); the steps run one by one" >&2
	fi
fi

# start_step <index>: run that parallel step in the background, in a process
# group of its own (job control on just for its start), with no stdin: its
# stdout, stderr and exit status, and when the run counts its own start and end
# times, go to its scratch folder. A TERM (stop_steps) ends the run only once
# the step's script has ended.
start_step() {
	local i="$1" d="$tmp/steps/${steps[$1]}"
	mkdir -p "$d"
	set -m
	(
		trap : TERM
		[ -z "$count_branch" ] || factory_clock_us > "$d/began"
		run_step "${steps[$i]}" > "$d/stdout" 2> "$d/stderr"
		echo "$?" > "$d/status"
		[ -z "$count_branch" ] || factory_clock_us > "$d/ended"
	) < /dev/null &
	job_pid[i]=$!
	set +m
	job_state[i]=started
}

# start_ready: start each parallel step not yet started that can start now: one
# whose result can still show (past a red step, --all-static shows no long one)
# and that may overlap every step running and every earlier one not yet started,
# so steps that share state run one at a time, in the fixed order.
start_ready() {
	local i k
	for i in "${group[@]}"; do
		[ -z "${job_state[$i]:-}" ] || continue
		[ -z "$failed_at" ] || [ "$keep_going" -eq 1 ] || factory_step_is_static "${steps[$i]}" || continue
		for k in "${group[@]}"; do
			[ "$k" != "$i" ] && { [ "${job_state[$k]:-}" = started ] || { [ -z "${job_state[$k]:-}" ] && [ "$k" -lt "$i" ]; }; } || continue
			[ -n "${may[10 * i + k]:-}" ] || continue 2
		done
		start_step "$i"
	done
}

# take_step <index>: wait for that parallel step's run, then pass on its stderr
# and its verdict lines as a run one by one would have, and set step_status,
# began and ended.
take_step() {
	local d="$tmp/steps/${steps[$1]}"
	[ -n "${job_state[$1]:-}" ] || start_step "$1"
	wait "${job_pid[$1]}"
	job_state[$1]=taken
	cat "$d/stderr" >&2
	tee -a "$tmp/verdict" < "$d/stdout"
	step_status="$(cat "$d/status" 2> /dev/null)" || step_status=1
	if [ -n "$count_branch" ]; then
		began="$(cat "$d/began")"
		ended="$(cat "$d/ended")"
	fi
	start_ready
}

for i in "${!steps[@]}"; do
	step="${steps[$i]}"
	# --all-static: past a failing static step, only the other static steps run.
	if [ -n "$failed_at" ]; then
		[ "$keep_going" -eq 1 ] || factory_step_is_static "$step" || break
		[ "$keep_going" -eq 1 ] || went_on=1
	fi
	[ -z "$step_mark" ] || printf '%s %s\n' "$step_mark" "$step" >&2
	if [ "$at_once" -eq 1 ] && factory_step_is_parallel "$step"; then
		if [ "${#job_state[@]}" -eq 0 ]; then
			# A Ctrl-C or a TERM to the runner reaches the steps' own groups too.
			trap 'stop_steps; exit 130' INT
			trap 'stop_steps; exit 143' TERM
			trap 'stop_steps; exit 129' HUP
			start_ready
		fi
		take_step "$i"
	else
		[ -z "$count_branch" ] || began="$(factory_clock_us)"
		run_step "$step" | tee -a "$tmp/verdict"
		step_status="${PIPESTATUS[0]}"
		[ -z "$count_branch" ] || ended="$(factory_clock_us)"
	fi
	[ ! -f "$tmp/steps/$step/transient" ] || echo "$step" >> "$tmp/transient"
	if [ -n "$count_branch" ] && ! grep -qxF "== $step SKIP" "$tmp/verdict"; then
		step_seconds+=("$step=$(factory_seconds_between "$began" "$ended")")
	fi
	if [ "$step_status" -ne 0 ]; then
		[ -n "$failed_at" ] || failed_at="$step"
		[ "$keep_going" -eq 1 ] || { [ "$all_static" -eq 1 ] && factory_step_is_static "$step"; } || break
		# --all-static goes on through the static steps alone.
		[ "$keep_going" -eq 1 ] || stop_steps long
	fi
done
if [ "${#job_state[@]}" -gt 0 ]; then
	stop_steps
	trap - INT TERM HUP
fi
[ -z "$step_mark" ] || printf '%s\n' "$step_mark" >&2
[ -z "$failed_at" ] || finish 1 "verify: FAILED at step $failed_at"
finish 0 "verify: PASS"
