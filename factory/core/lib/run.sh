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
# and the counts the retro reads (factory_stats_line), each a whole number:
#   fails-<phase>   the Verifier's FAILs in that phase
#   fails-brief     the brief review's FAILs: the Verifier's check of a sealed
#                   brief, before the Lock (factory-run's SKILL.md)
#   rejected        Deviations the Driver rejected
#   uncounted       uncounted rounds: clarifications, rebase conflicts, brief fixes
#   escalations     times the issue went to the human
#   self-ruled      the Driver's calls inside the brief, each decided, logged and
#                   counted instead of escalated: an extra round, the Sonnet
#                   Takeover, a finding accepted as out of reach, a Lock lift
#                   (factory-run's SKILL.md, Driver's calls)
#   lifts           times the Lock moved (lock.sh lift), at most FACTORY_LOCK_LIFTS
# and the gate's own, which verify.sh counts on an issue branch
# (factory_gate_count) and the gate stamp's key leaves out:
#   gate-runs       counted gate runs, one per set of inputs
#   caught-<step>   red runs that step stopped
#   seconds-<step>  that step's run time over the counted runs, each run's
#                   rounded to the whole second
#
# The time now is FACTORY_NOW when that is a whole number of seconds since the
# epoch (a test's clock), else the system clock (factory_now). A step's time is
# read from the file FACTORY_STEP_CLOCK names when it is set (a test's clock),
# else from EPOCHREALTIME (factory_clock_us).

# The most counted fix rounds a phase may use: the cap of 2 plus the Driver's 2
# extra rounds (factory-run's SKILL.md, Driver's calls).
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
		phase | red-commit | issue | bootstrap | brief-sha | lane | started) return 0 ;;
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
