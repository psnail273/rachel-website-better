# A Run's per-issue names and its durable state. Sourced by start.sh, land.sh,
# state.sh, verify.sh and others; defines no side effects; the stats line needs
# steps.sh. Every function works on the git repo of the current directory, from
# its main checkout or any of its worktrees.
#
# Run state lives in the issue branch's git config, as branch.<branch>.factory-<key>.
# It sits in the repo's shared config, so every process and every worktree reads
# the same values, and it goes away with the branch when land.sh deletes it.
#
# Keys:
#   phase           red | green | partial
#   rounds-<phase>  counted fix rounds used in that phase (a whole number), at
#                   most FACTORY_ROUNDS_CEILING: state.sh incr refuses one more
#   red-commit      the Lock: the red commit's SHA
#   issue           the issue number (start.sh)
#   bootstrap       done once the adapter's bootstrap has passed (start.sh)
#   brief-sha       the Build Brief's seal: its git blob hash (brief.sh seal)
#   lane            small, for a brief in the small lane (brief.sh seal sets and
#                   clears it; state.sh doesn't set it)
#   started         when start.sh made the branch, in seconds since the epoch
#   began-<phase>   when the branch first entered that phase, in seconds since the
#                   epoch (factory_state_set_phase)
#   editor-gate     the Editor's gate stamp, `<phase> <sha>`: the run state's phase
#                   (- for none) and HEAD's full commit when the Editor's gate
#                   (hooks/editor-gate.sh) last passed there on a clean tree. Only
#                   that gate writes it, clearing it as each run starts; the small
#                   lane's handoff to green (its exit 3) writes none. The check
#                   after an Editor round (factory_editor_gate_check) reads it;
#                   state.sh doesn't set it
# and the counts the retro reads (factory_stats_line), each a whole number:
#   fails-<phase>   the Verifier's FAILs in that phase
#   fails-brief     the brief review's FAILs: the Verifier's check of a sealed
#                   brief, before the Lock (the build skill's SKILL.md)
#   rejected        Deviations the Driver rejected
#   uncounted       uncounted rounds: clarifications, rebase conflicts, brief fixes
#   escalations     times the issue went to the human
#   self-ruled      the Driver's calls inside the brief, each decided, logged and
#                   counted instead of escalated: an extra round, the Sonnet
#                   Takeover, a finding accepted as out of reach, a Lock lift
#                   (the build skill's SKILL.md, Driver's calls)
#   lifts           times the Lock moved (lock.sh lift), at most FACTORY_LOCK_LIFTS
# and the gate's own, which verify.sh counts on an issue branch
# (factory_gate_count) and the gate stamp's key leaves out:
#   gate-runs       counted gate runs, one per set of inputs
#   caught-<step>   red runs that step stopped
#   seconds-<step>  that step's run time over the counted runs, each run's
#                   rounded to the whole second, less what it waited for a
#                   shared resource (factory_step_waited)
#
# The time now is FACTORY_NOW when that is a whole number of seconds since the
# epoch (a test's clock), else the system clock (factory_now). A step's time is
# read from the file FACTORY_STEP_CLOCK names when it is set (a test's clock),
# else from EPOCHREALTIME (factory_clock_us).

# The most counted fix rounds a phase may use: the cap of 2 plus the Driver's 2
# extra rounds (the build skill's SKILL.md, Driver's calls).
# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_ROUNDS_CEILING=4

# The branch an issue lands on, and the remote it is fetched from and pushed to.
FACTORY_BASE_BRANCH="${FACTORY_BASE_BRANCH:-dev}"
FACTORY_REMOTE="${FACTORY_REMOTE:-origin}"

# Where an issue's worktrees live, relative to the main checkout.
FACTORY_WORKTREES_DIR=".claude/worktrees"

# factory_issue_branch <n>: the issue's branch name.
factory_issue_branch() {
	printf 'issue/%s\n' "$1"
}

# factory_issue_worktree <main> <n>: the issue's worktree path.
factory_issue_worktree() {
	printf '%s/%s/issue-%s\n' "$1" "$FACTORY_WORKTREES_DIR" "$2"
}

# factory_is_issue <n>: true when <n> is an issue number.
factory_is_issue() {
	case "$1" in
		'' | 0* | *[!0-9]*) return 1 ;;
	esac
}

# factory_is_issue_branch <branch>: true when <branch> is an issue's, issue/<n>.
factory_is_issue_branch() {
	case "$1" in
		issue/*) factory_is_issue "${1#issue/}" ;;
		*) return 1 ;;
	esac
}

# factory_main_checkout: the absolute path of the repo's main checkout.
factory_main_checkout() {
	local common
	common="$(git rev-parse --git-common-dir 2> /dev/null)" || return 1
	(cd "$common/.." && pwd)
}

# factory_current_branch: the checked-out branch, or nothing on a detached HEAD.
factory_current_branch() {
	git symbolic-ref --short -q HEAD
}

# factory_state_key_ok <key>: true when <key> is a run-state key.
factory_state_key_ok() {
	case "$1" in
		phase | red-commit | issue | bootstrap | brief-sha | lane | started | editor-gate) return 0 ;;
		rejected | uncounted | escalations | self-ruled | lifts | gate-runs) return 0 ;;
		rounds-* | fails-* | began-* | caught-* | seconds-*) case "${1#*-}" in '' | *[!a-z]*) return 1 ;; esac ;;
		*) return 1 ;;
	esac
}

# factory_state_is_time <key>: true when <key> is a time (seconds since the epoch).
factory_state_is_time() {
	case "$1" in
		started | began-*) factory_state_key_ok "$1" ;;
		*) return 1 ;;
	esac
}

# factory_state_is_count <key>: true when <key> is a count (state.sh incr).
factory_state_is_count() {
	case "$1" in
		rounds-* | fails-* | rejected | uncounted | escalations | self-ruled | lifts) factory_state_key_ok "$1" ;;
		gate-runs | caught-* | seconds-*) factory_state_key_ok "$1" ;;
		*) return 1 ;;
	esac
}

# factory_state_value_ok <key> <value>: true when <value> fits <key>.
factory_state_value_ok() {
	case "$1" in
		phase) case "$2" in red | green | partial) return 0 ;; *) return 1 ;; esac ;;
		lane) [ "$2" = small ] ;;
		issue) case "$2" in '' | *[!0-9]*) return 1 ;; esac ;;
		brief-sha) case "$2" in '' | *[!0-9a-f]*) return 1 ;; esac ;;
		editor-gate)
			case "${2%% *}" in red | green | partial | -) ;; *) return 1 ;; esac
			case "${2#* }" in '' | *[!0-9a-f]* | "$2") return 1 ;; esac
			;;
		*)
			if factory_state_is_count "$1" || factory_state_is_time "$1"; then
				case "$2" in '' | *[!0-9]*) return 1 ;; esac
			fi
			case "$2" in '' | *"
"*) return 1 ;; esac
			;;
	esac
}

# factory_state_get <branch> <key>: print the value; false when it is unset.
factory_state_get() {
	git config --get "branch.$1.factory-$2"
}

# factory_state_set <branch> <key> <value>
factory_state_set() {
	git config "branch.$1.factory-$2" "$3"
}

# factory_state_unset <branch> <key>: succeeds when the key was already unset.
factory_state_unset() {
	local s=0
	git config --unset "branch.$1.factory-$2" || s=$?
	[ "$s" -eq 0 ] || [ "$s" -eq 5 ]
}

# factory_state_incr <branch> <key>: add one (unset counts as 0); print the new value.
factory_state_incr() {
	local n
	n="$(factory_state_get "$1" "$2")" || n=0
	n=$((n + 1))
	factory_state_set "$1" "$2" "$n" && printf '%s\n' "$n"
}

# factory_now: the time now, in whole seconds since the epoch: FACTORY_NOW when it
# is one (a test's clock), else the system clock.
factory_now() {
	case "${FACTORY_NOW:-}" in
		'' | *[!0-9]*) date +%s ;;
		*) printf '%s\n' "$((10#$FACTORY_NOW))" ;;
	esac
}

# factory_clock_us: the time now in microseconds since the epoch, for timing a
# step: the file FACTORY_STEP_CLOCK names when it is set (a test's clock: seconds,
# with an optional fraction after a dot), else EPOCHREALTIME, else whole seconds.
factory_clock_us() {
	local t="${EPOCHREALTIME:-}" whole frac=""
	if [ -n "${FACTORY_STEP_CLOCK:-}" ]; then
		t="$(cat -- "$FACTORY_STEP_CLOCK" 2> /dev/null)" || t=""
	fi
	t="${t/,/.}"
	case "$t" in '' | .* | *[!0-9.]* | *.*.*) t="$(date +%s)" ;; esac
	whole="${t%%.*}"
	[ "$whole" = "$t" ] || frac="${t#*.}"
	frac="${frac}000000"
	printf '%s\n' "$((10#$whole * 1000000 + 10#${frac:0:6}))"
}

# factory_seconds_between <from-us> <to-us>: the whole seconds between two
# factory_clock_us times, rounded to the nearest (0 when <to> is earlier).
factory_seconds_between() {
	local d=$(($2 - $1))
	[ "$d" -gt 0 ] || d=0
	printf '%s\n' "$(((d + 500000) / 1000000))"
}

# factory_step_waited <from-us>: add the time since <from-us> (a factory_clock_us
# time) to the step's wait record, the file FACTORY_STEP_WAIT_FILE names, in
# microseconds; nothing when that is unset. A step script runs it after a wait
# for a shared resource the machine's other gates hold (the adapter's slot pool
# and build lock): verify.sh sets the file on each step's command line and takes
# what it holds off the step's seconds-<step>, so the counts measure the step,
# not the queue. With FACTORY_GATE_WAITS set it also ends the wait in the gate's
# wait record: the wait's `<from-us> <to-us>` line, and its mark
# (factory_wait_begin) removed.
factory_step_waited() {
	local now d had=0
	now="$(factory_clock_us)"
	if [ -n "${FACTORY_GATE_WAITS:-}" ] && [ -d "$FACTORY_GATE_WAITS" ]; then
		printf '%s %s\n' "$1" "$now" >> "$FACTORY_GATE_WAITS/waits" 2> /dev/null
		rm -f "$FACTORY_GATE_WAITS/waiting.$$.$1"
	fi
	[ -n "${FACTORY_STEP_WAIT_FILE:-}" ] || return 0
	d=$((now - $1))
	[ "$d" -gt 0 ] || return 0
	had="$(cat -- "$FACTORY_STEP_WAIT_FILE" 2> /dev/null)" || had=0
	case "$had" in '' | *[!0-9]*) had=0 ;; esac
	printf '%s\n' "$((had + d))" > "$FACTORY_STEP_WAIT_FILE" 2> /dev/null || true
}

# --- the Editor's stop hook and its time ---------------------------------------
#
# Claude Code kills the Editor's stop hook (hooks/claude-subagent-stop.sh) at its
# timeout in hooks/claude-hooks.json, a hard limit that leaves nothing out. So
# the hook splits that time three ways, from its own start:
#   waits   every wait for what the machine's other gates hold (a gate in flight
#           in the same worktree, the adapter's gate slots and build lock) ends
#           by the timeout less the margin and the work budget: 1500 s in.
#           A step's wait is cut to the time left (factory_wait_cap) and, past
#           it, fails for a transient cause (FACTORY_TRANSIENT_EXIT): a busy
#           gate, not a red one (editor-gate.sh's exit 4);
#   work    the gate's work budget, 1800 s: its run time less the time some
#           wait in its record went on (factory_gate_budget_run);
#   margin  300 s, for what the hook does around the gate and for stopping a
#           gate past its budget.
# The waits end by 1500 s in and the work after them takes 1800 s at most, so
# the gate ends by 3300 s in, whatever the queue; the hook also stops it there
# (its `stop`), should it start late. hooks_test checks claude-hooks.json's
# timeout against these three.
# shellcheck disable=SC2034 # read by the hook and the tests
factory_editor_hook_timeout=3600
# shellcheck disable=SC2034
factory_editor_gate_budget=1800
# shellcheck disable=SC2034
factory_editor_hook_margin=300

# The gate's wait record: FACTORY_GATE_WAITS, when set (the Editor's stop hook
# sets it for its gate; lib/stamp.sh leaves it out of the stamp key), names a
# folder holding
#   until                    the factory_clock_us time by which every wait ends
#   waits                    a `<from-us> <to-us>` line per wait that ended
#   waiting.<pid>.<from-us>  a wait still going, begun at <from-us>
#   work                     the gate's work in whole seconds at
#                            factory_gate_budget_run's last check
#   over                     written by factory_gate_budget_run when it stops
#                            the gate: `budget|stop <waited-s>`

# factory_wait_begin <var>: set the variable named <var> to the time now
# (factory_clock_us) and, with FACTORY_GATE_WAITS set, mark a wait as going in
# the gate's wait record. factory_step_waited "$<var>" ends it.
factory_wait_begin() {
	local now
	now="$(factory_clock_us)"
	printf -v "$1" '%s' "$now"
	if [ -n "${FACTORY_GATE_WAITS:-}" ] && [ -d "$FACTORY_GATE_WAITS" ]; then
		: > "$FACTORY_GATE_WAITS/waiting.$$.$now" 2> /dev/null
	fi
	return 0
}

# factory_wait_cap <seconds>: <seconds>, a wait's setting, cut to the whole
# seconds left until the gate's wait record's `until` (0 once it has passed);
# <seconds> itself without a record or an `until`.
factory_wait_cap() {
	local until left
	until="$(cat -- "${FACTORY_GATE_WAITS:-/nonexistent}/until" 2> /dev/null)" || until=""
	case "$until" in '' | *[!0-9]*)
		printf '%s\n' "$1"
		return 0
		;;
	esac
	left=$(((until - $(factory_clock_us)) / 1000000))
	[ "$left" -gt 0 ] || left=0
	[ "$left" -lt "$1" ] || left="$1"
	printf '%s\n' "$left"
}

# factory_gate_waited_us <waits> <from-us> <to-us>: the time from <from-us> to
# <to-us> during which some wait in the record <waits> went on (the union of its
# waits, ended and going), in microseconds. Waits that overlap count once.
factory_gate_waited_us() {
	local f
	{
		cat -- "$1/waits" 2> /dev/null
		for f in "$1"/waiting.*; do
			[ -e "$f" ] && printf '%s %s\n' "${f##*.}" "$3"
		done
	} | awk -v lo="$2" -v hi="$3" '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
		a = $1 + 0; b = $2 + 0
		if (a < lo + 0) a = lo + 0
		if (b > hi + 0) b = hi + 0
		if (b > a) printf "%.0f %.0f\n", a, b
	}' | LC_ALL=C sort -n -k1,1 | awk '
		{ a = $1 + 0; b = $2 + 0
		  if (n && a <= e) { if (b > e) e = b }
		  else { if (n) t += e - s; s = a; e = b; n = 1 } }
		END { if (n) t += e - s; printf "%.0f\n", t }'
}

# factory_gate_budget_run <waits> <budget-s> <stop-us> <command...>: run
# <command>, with FACTORY_GATE_WAITS=<waits> exported to it, in a process group
# of its own (job control on just for its start), its stdout and stderr its own,
# and return its status. Beside it a watchdog checks each second: once the
# command's work, the time since it started less the time some wait in <waits>
# went on (factory_gate_waited_us), passes <budget-s>, or the clock
# (factory_clock_us) reaches <stop-us>, it writes `budget` or `stop` and the
# seconds waited to <waits>/over, sends TERM and CONT to the command's group,
# and KILL 10 s later to whatever of the group is left; the call then returns
# 124. As in factory_run_bounded's fallback (lib/bounded.sh), the watchdog,
# once it fires, ignores TERM, and the call ends it and its sleep with KILL.
factory_gate_budget_run() (
	set +e
	waits="$1" budget="$2" stop="$3"
	shift 3
	export FACTORY_GATE_WAITS="$waits"
	rm -f "$waits/over"
	began="$(factory_clock_us)"
	set -m
	"$@" <&0 &
	pid=$!
	(
		while sleep 1; do
			now="$(factory_clock_us)"
			waited="$(factory_gate_waited_us "$waits" "$began" "$now")"
			case "$waited" in '' | *[!0-9]*) waited=0 ;; esac
			echo "$(((now - began - waited) / 1000000))" > "$waits/work" 2> /dev/null
			if [ "$now" -ge "$stop" ]; then
				over=stop
			elif [ $((now - began - waited)) -gt $((budget * 1000000)) ]; then
				over=budget
			else
				continue
			fi
			trap '' TERM
			echo "$over $(((waited + 500000) / 1000000))" > "$waits/over" 2> /dev/null
			kill -TERM -"$pid" 2> /dev/null
			kill -CONT -"$pid" 2> /dev/null
			n=0
			while [ "$n" -lt 10 ] && kill -0 -"$pid" 2> /dev/null; do
				sleep 1
				n=$((n + 1))
			done
			kill -KILL -"$pid" 2> /dev/null
			exit 0
		done
		exit 1
	) < /dev/null > /dev/null 2>&1 &
	watchdog=$!
	set +m
	wait "$pid"
	status=$?
	kill -TERM -"$watchdog" 2> /dev/null
	if wait "$watchdog"; then
		status=124
	fi
	kill -KILL -"$watchdog" 2> /dev/null
	exit "$status"
)

# factory_gate_count <branch> <step, or nothing> [<step>=<seconds>...]: count one
# gate run in the branch's run state (verify.sh says which runs count): a catch
# for the step that stopped it, when one did (caught-<step>), each step's seconds
# added to seconds-<step> (0 adds nothing), then the run (gate-runs). False at the
# first write that fails, as in a read-only git dir; what it wrote stays.
factory_gate_count() {
	local branch="$1" caught="$2" kv step n
	shift 2
	if [ -n "$caught" ]; then
		factory_state_incr "$branch" "caught-$caught" > /dev/null || return 1
	fi
	for kv in "$@"; do
		step="${kv%%=*}"
		[ "${kv#*=}" -gt 0 ] 2> /dev/null || continue
		n="$(factory_state_get "$branch" "seconds-$step")" || n=0
		factory_state_set "$branch" "seconds-$step" "$((10#$n + ${kv#*=}))" || return 1
	done
	factory_state_incr "$branch" gate-runs > /dev/null
}

# factory_state_set_phase <branch> <phase>: set the phase and, the first time the
# branch enters it, record when (began-<phase>). state.sh set phase and the small
# lane's stop hook both set the phase through it.
factory_state_set_phase() {
	factory_state_set "$1" phase "$2" || return 1
	factory_state_get "$1" "began-$2" > /dev/null 2>&1 && return 0
	factory_state_set "$1" "began-$2" "$(factory_now)"
}

# factory_gate_name <phase>: what the gate a branch in <phase> must pass checks.
# The one place a phase picks its gate: factory_gate runs it, and the Editor's
# gate (hooks/editor-gate.sh) and land.sh both use the two. land.sh only ever
# passes partial or green: nothing lands on the red gate.
#   red          verify --red: the brief's new tests fail, everything else passes
#   partial      the Baseline gate: no finding outside the Baseline (Partial mode)
#   green, none  verify: every step passes
factory_gate_name() {
	case "$1" in
		red) echo "verify --red (the red phase: the brief's new tests must fail, everything else pass)" ;;
		partial) echo "the Baseline gate (Partial mode: no finding outside the Baseline, and none of the entries the brief removes)" ;;
		*) echo "verify (the green phase: every step must pass)" ;;
	esac
}

# factory_gate <phase> <verify> [--removes] [--all-static]: run that gate in the
# current checkout, with stdin from /dev/null, and return its status; stdout is
# the gate's own. <verify> is the runner it calls: the Core's verify.sh, or the
# project's tools/verify.sh. With --removes the Baseline gate also refuses the
# entries the brief removes (brief.sh removes), and a brief it can't read fails
# it; without, the Baseline is taken as already shrunk (land.sh, after the
# Driver's `baseline.sh shrink`). --all-static goes to verify (the Editor's
# gate: every static step's findings at once); the Baseline gate, which runs
# every step already, takes none.
factory_gate() {
	local core removes status phase="$1" verify="$2" opt with_removes="" flags=()
	core="$(dirname "${BASH_SOURCE[0]}")/.."
	shift 2
	for opt in "$@"; do
		case "$opt" in
			--removes) with_removes=1 ;;
			--all-static) flags+=(--all-static) ;;
		esac
	done
	case "$phase" in
		red) bash "$verify" --red "${flags[@]}" < /dev/null ;;
		partial)
			if [ -z "$with_removes" ]; then
				bash "$core/baseline.sh" gate < /dev/null
				return
			fi
			removes="$(mktemp)" || return 1
			if bash "$core/brief.sh" removes > "$removes"; then
				bash "$core/baseline.sh" gate "$removes" < /dev/null
				status=$?
			else
				echo "the Build Brief can't be read (it is the Driver's; report this and stop):"
				cat "$removes"
				status=1
			fi
			rm -f "$removes"
			return "$status"
			;;
		*) bash "$verify" "${flags[@]}" < /dev/null ;;
	esac
}

# factory_editor_gate_stamp <branch> <phase> <sha>: record that the Editor's gate
# (hooks/editor-gate.sh) passed at <sha> in <phase> (- for none), as the run
# state's editor-gate.
factory_editor_gate_stamp() {
	factory_state_set "$1" editor-gate "${2:--} $3"
}

# factory_editor_gate_current <branch>: true when the run state holds the Editor's
# gate's stamp for HEAD in the branch's phase now.
factory_editor_gate_current() {
	local phase head
	phase="$(factory_state_get "$1" phase 2> /dev/null)" || phase=""
	head="$(git rev-parse --verify -q HEAD)" || return 1
	[ "$(factory_state_get "$1" editor-gate 2> /dev/null)" = "${phase:--} $head" ]
}

# factory_editor_gate_check <who>: the check after an Editor round, before the
# Verifier's prompt (prompt.sh verifier) and the Lock (lock.sh record), run in
# the issue's worktree: the Editor's gate must have passed at HEAD. The Editor's
# stop hook (claude-subagent-stop.sh) runs that gate, which records its stamp as
# it passes. Without the stamp for HEAD in the phase now (the hook did not run,
# or a commit came after it), the check runs the gate itself, from the
# worktree's root, and goes on when it passes; the Driver never runs it by hand.
# What it says goes to stderr, its own lines headed `<who>: `, then the gate's stdout
# when the gate fails or moved the small lane on.
#   0  the stamp holds for HEAD; FACTORY_EDITOR_GATE_RAN is 1 when the check ran
#      the gate to get it, else empty
#   1  no stamp, and the gate fails: its findings are the Editor's next fix
#      round (or it passed but HEAD moved while it ran: run the check again; or
#      the brief changed after its seal: the Driver seals it again; or it was
#      busy, editor-gate.sh's exit 4: a step failed only for a transient cause
#      with only a wait's findings, a gate slot or the build lock held past its
#      wait: no fix round, run the check again)
#   3  the small lane's gate passed in the red phase: it recorded the Lock and
#      moved the issue to green (editor-gate.sh's exit 3); the Editor's next round
#      is the green one
factory_editor_gate_check() {
	local who="$1" branch top core short out status
	FACTORY_EDITOR_GATE_RAN=""
	branch="$(factory_current_branch)" || {
		echo "$who: HEAD is detached; check out the issue's branch" >&2
		return 1
	}
	factory_editor_gate_current "$branch" && return 0
	top="$(git rev-parse --show-toplevel)" || return 1
	core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || return 1
	short="$(git rev-parse --short HEAD 2> /dev/null)" || short=HEAD
	echo "$who: the run state holds no Editor's gate stamp for $short (the Editor's stop hook records one when its gate passes there), so it runs the Editor's gate now" >&2
	FACTORY_EDITOR_GATE_RAN=1
	out="$(cd "$top" && bash "$core/hooks/editor-gate.sh" < /dev/null 2> /dev/null)"
	status=$?
	case "$status" in
		0)
			factory_editor_gate_current "$branch" && return 0
			echo "$who: the Editor's gate passed, but HEAD moved while it ran, so no stamp holds for HEAD; run this again" >&2
			return 1
			;;
		3)
			{
				echo "$who: the Editor's gate passed in the small lane's red phase, so it recorded the Lock and moved the issue to green; send the Editor the green round that 'bash factory/core/prompt.sh green' prints, as editor.md says. Its output:"
				printf '%s\n' "$out"
			} >&2
			return 3
			;;
	esac
	if [ "$status" = 4 ]; then
		{
			echo "$who: the Editor's gate was busy at $short, not red: a step failed only because a gate slot or the build lock stayed held by the machine's other gates past its wait, so it judged nothing of the code; this is no fix round: run this again once the machine is less busy. Its output:"
			printf '%s\n' "$out"
		} >&2
		return 1
	fi
	if [ "$(printf '%s\n' "$out" | head -n 1)" = "gate: the Build Brief's seal" ]; then
		{
			echo "$who: the Build Brief changed after its seal, so the Editor's gate stops on it: the brief is yours, so this is no Editor round; seal it again (bash factory/core/brief.sh seal in this worktree), then run this again:"
			printf '%s\n' "$out"
		} >&2
		return 1
	fi
	{
		echo "$who: the Editor's gate fails at $short, so this does not go on; send these findings to the Editor as a fix round, then run this again:"
		printf '%s\n' "$out"
	} >&2
	return 1
}

# factory_state_list <branch>: print every key=value, sorted by key.
factory_state_list() {
	local re prefix="branch.$1.factory-" line name
	re="$(printf '%s' "$1" | sed 's/[][\\.*^$+?(){}|]/\\&/g')"
	git config --get-regexp "^branch\\.$re\\.factory-" | while IFS= read -r line; do
		name="${line%% *}"
		printf '%s=%s\n' "${name#"$prefix"}" "${line#* }"
	done | LC_ALL=C sort
}

# factory_stats_line <branch> <issue>: the issue's numbers from its run state,
# as one line for the close comment, which retro.sh totals. The phases' counts,
# the brief review's and the other counts always appear, 0 when unset; a count
# of another phase follows them. The lane is cleanup in Partial mode, small in
# the small lane, else standard. Then the gate's counts that aren't 0:
# gate-runs, each caught-<step>, then each seconds-<step>, in the gate's step
# order (needs steps.sh); a line with none says the issue counted no gate run.
#
# The minutes follow the counts, when start.sh recorded the start (an issue
# started before it did has none): minutes=<start to now>, then
# minutes-brief=<start to the first phase> and minutes-<phase>=<that phase to the
# next one, or to now> for each phase the issue had, in the order they began
# (phases that began in the same second in the flow's order: red, partial, green).
# land.sh prints the line as it lands, so now is the landing. Each mark is
# rounded to the whole minute from the start, so the parts add up to minutes.
factory_stats_line() {
	local branch="$1" line lane=standard key fixed extra="" gate="" kv list value kind step
	if [ "$(factory_state_get "$branch" phase 2> /dev/null)" = partial ]; then
		lane=cleanup
	elif [ "$(factory_state_get "$branch" lane 2> /dev/null)" = small ]; then
		lane=small
	fi
	line="factory-stats: issue=$2 lane=$lane"
	fixed="rounds-red rounds-green rounds-partial fails-red fails-green fails-partial fails-brief rejected uncounted escalations self-ruled"
	for key in $fixed; do
		line="$line $key=$(factory_state_get "$branch" "$key" 2> /dev/null || echo 0)"
	done
	list="$(factory_state_list "$branch")"
	while IFS= read -r kv; do
		key="${kv%%=*}"
		factory_state_is_count "$key" || continue
		case " $fixed " in *" $key "*) continue ;; esac
		case "$key" in
			gate-runs) continue ;;
			caught-* | seconds-*) factory_is_step "${key#*-}" && continue ;;
		esac
		extra="$extra $kv"
	done <<< "$list"
	for key in gate-runs $(for kind in caught seconds; do
		for step in "${FACTORY_STEPS[@]}"; do echo "$kind-$step"; done
	done); do
		value="$(printf '%s\n' "$list" | sed -n "s/^$key=//p")"
		case "$value" in '' | *[!0-9]*) continue ;; esac
		[ "$((10#$value))" -eq 0 ] || gate="$gate $key=$value"
	done
	printf '%s%s%s%s\n' "$line" "$extra" "$gate" "$(factory_stats_minutes "$branch")"
}

# factory_stats_minutes <branch>: the stats line's minutes fields, each after a
# space; nothing without a start time (factory_stats_line).
factory_stats_minutes() {
	local start at rank phase mark prev=brief prev_mark=0 parts=""
	start="$(factory_state_get "$1" started 2> /dev/null)" || return 0
	case "$start" in '' | *[!0-9]*) return 0 ;; esac
	# shellcheck disable=SC2034 # rank: a sort key the loop skips
	while read -r at rank phase; do
		mark="$(factory_minutes_mark "$start" "$at" "$prev_mark")"
		parts="$parts minutes-$prev=$((mark - prev_mark))"
		prev="$phase" prev_mark="$mark"
	done < <(factory_state_list "$1" | awk -F= '/^began-[a-z]+=[0-9]+$/ {
		p = substr($1, 7)
		print $2, (p == "red" ? 1 : p == "partial" ? 2 : p == "green" ? 3 : 4), p
	}' | LC_ALL=C sort -k1,1n -k2,2n -k3,3)
	mark="$(factory_minutes_mark "$start" "$(factory_now)" "$prev_mark")"
	printf ' minutes=%s%s minutes-%s=%s' "$mark" "$parts" "$prev" "$((mark - prev_mark))"
}

# factory_minutes_mark <start> <time> <floor>: the whole minutes from <start> to
# <time>, rounded to the nearest (0 for a time before the start), and at least <floor>.
factory_minutes_mark() {
	local m=0
	[ "$2" -lt "$1" ] || m=$(((10#$2 - 10#$1 + 30) / 60))
	[ "$m" -ge "$3" ] || m="$3"
	printf '%s\n' "$m"
}
