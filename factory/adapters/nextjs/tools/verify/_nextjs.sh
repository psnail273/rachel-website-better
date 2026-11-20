# Shared by the Next.js adapter's step scripts. Sourced; its only side effects
# are sourcing the Core's glob matcher, Scenario folder reader and run lib,
# reading the Scenario folder, the build lock's path and the slot pool's, putting local.env's Node and pnpm
# first on PATH and turning Next.js's telemetry off. Run from the project root.
#
# NODE_BIN and PNPM_BIN (local.env) name the Node and pnpm binaries; empty means
# the ones on PATH. Their versions are pinned in tools/verify/pins. The steps run
# the project's own tools (tsc, eslint, prettier, next) from node_modules/.bin,
# which bootstrap installs and prepare keeps in step with pnpm-lock.yaml.

# The scope: what the gates check, meaning what ships plus the tests. One glob per
# line (the Build Brief's glob syntax: `*` and `?` stay in one folder, `**` crosses
# folders, a trailing / means the whole folder); a line starting with ! takes the
# paths it matches back out. The last line that matches a path decides; a path no
# line matches is out of scope. Blank lines and # comments are ignored.
# shellcheck disable=SC2034 # these settings are read by the steps that source this
NX_SCOPE="tools/verify/scope"

# Which files are tests, and which the project's tools generate: one glob per
# line, the same syntax (the Core reads both too).
NX_TEST_PATHS="tools/verify/test-paths"
NX_GENERATED="tools/verify/generated"

# The format-exclude list: a ratchet file (it may only shrink). One
# project-relative path per line; blank lines and # comments are ignored.
NX_FORMAT_EXCLUDE="tools/verify/ratchet/format_exclude.txt"

# The files each tool reads, by extension: ESLint the code, Prettier the code and
# its JSON and CSS, and the scope cross-check the TypeScript.
NX_CODE_EXT="ts tsx mts cts js jsx mjs cjs"
NX_FORMAT_EXT="$NX_CODE_EXT json css scss"
NX_TS_EXT="ts tsx mts cts"

# Next.js sends nothing home from a gate.
export NEXT_TELEMETRY_DISABLED=1

# A tool named by a path puts its folder first on PATH, so pnpm and the tools it
# starts run that Node too.
for nx_bin in "${PNPM_BIN:-}" "${NODE_BIN:-}"; do
	case "$nx_bin" in */*) PATH="$(dirname "$nx_bin"):$PATH" ;; esac
done
unset nx_bin
export PATH

# The glob matcher is the Core's (lib/brief.sh), and so are the Scenario folder's
# reader (lib/scenarios.sh) and a step's wait record (lib/run.sh's
# factory_step_waited, which the slot pool keeps). The runner exports
# FACTORY_CORE; run by hand, a step finds the Core where adoption vendors it.
if ! declare -F factory_glob_regex > /dev/null || ! declare -F factory_scenario_folder > /dev/null ||
	! declare -F factory_wait_cap > /dev/null; then
	if [ ! -f "${FACTORY_CORE:-factory/core}/lib/brief.sh" ]; then
		echo "no factory Core at '${FACTORY_CORE:-factory/core}'; set FACTORY_CORE" >&2
		exit 2
	fi
	declare -F factory_glob_regex > /dev/null || . "${FACTORY_CORE:-factory/core}/lib/brief.sh"
	[ -n "${FACTORY_STEPS_DIR:-}" ] || . "${FACTORY_CORE:-factory/core}/lib/steps.sh"
	declare -F factory_scenario_folder > /dev/null || . "${FACTORY_CORE:-factory/core}/lib/scenarios.sh"
	declare -F factory_wait_cap > /dev/null || . "${FACTORY_CORE:-factory/core}/lib/run.sh"
fi

# The Scenario folder (tools/verify/scenario-folder), or empty when there is none.
# No gate step reads it: nx_all_files leaves it out, so neither the scope nor any
# step's own list can reach it, and the skeleton's tsconfig.json, vitest.config.ts
# and eslint.config.mjs leave it out of tsc (typecheck, next build), Vitest (test,
# mutate) and ESLint; prepare finds a config that doesn't (scenario-not-ignored).
# The Scenario driver (tools/verify/scenarios) alone runs it.
NX_SCENARIOS="$(factory_scenario_folder)" || NX_SCENARIOS=""

# node_ready: true when Node runs; else prints a finding and is false.
node_ready() {
	local node="${NODE_BIN:-node}"
	if ! command -v "$node" > /dev/null 2>&1; then
		if [ -n "${NODE_BIN:-}" ]; then
			echo "tools/verify/local.env:1 node-missing NODE_BIN '$NODE_BIN' is not a program; fix it in tools/verify/local.env"
		else
			echo "tools/verify/local.env:1 node-missing no node on PATH; install the pinned Node, or name it in NODE_BIN in tools/verify/local.env (see local.env.example)"
		fi
		return 1
	fi
}

# pnpm_ready: true when pnpm runs; else prints a finding and is false.
pnpm_ready() {
	if ! command -v "${PNPM_BIN:-pnpm}" > /dev/null 2>&1; then
		if [ -n "${PNPM_BIN:-}" ]; then
			echo "tools/verify/local.env:1 pnpm-missing PNPM_BIN '$PNPM_BIN' is not a program; fix it in tools/verify/local.env"
		else
			echo "tools/verify/local.env:1 pnpm-missing no pnpm on PATH; install pnpm, or name it in PNPM_BIN in tools/verify/local.env (see local.env.example)"
		fi
		return 1
	fi
}

# pnpm <args...>: the project's pnpm. package.json's packageManager field makes
# it run the pinned version (fetched once, by bootstrap).
pnpm() {
	command "${PNPM_BIN:-pnpm}" "$@"
}

# tool_ready <name>: true when node_modules/.bin/<name> is installed and Node
# runs; else prints a finding and is false.
tool_ready() {
	node_ready || return 1
	if [ ! -x "node_modules/.bin/$1" ]; then
		echo "package.json:1 tool-missing node_modules/.bin/$1 is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)"
		return 1
	fi
}

# tool <name> <args...>: run the project's installed tool.
tool() {
	local name="$1"
	shift
	"node_modules/.bin/$name" "$@"
}

# The build lock: one next build at a time on this machine, whichever checkout
# (worktree or clone) and whichever step starts it: smoke and the Scenario driver
# (_server.sh's nx_build) and playtest all build through nx_next_build. Two builds
# at once starve each other, and two in one checkout make next build refuse
# ("Another next build process is already running").
#
# The lock is a folder (mkdir is atomic; Git Bash has no flock) holding its
# holder's pid, at FACTORY_BUILD_LOCK (local.env), by default
# /tmp/factory-next-build.lock: a fixed path, not $TMPDIR, so sessions with temp
# folders of their own still meet there. A build waits for it up to
# FACTORY_BUILD_WAIT seconds (local.env; 0 to 999999, default 900), then gives up
# (a transient cause, NX_TRANSIENT). In the Editor's stop hook the wait is cut
# to the hook's time left for waits (nx_wait_cap), and the hook leaves it out
# of the gate's work budget, as it does a slot's.
# A lock whose holder is no process, or that names no holder a minute after it
# was made, is stale and taken over (nx_build_takeover, one waiter at a time). The build releases it when it ends; a caller
# runs nx_build_unlock from its EXIT trap too, so a signal mid-build releases it.
NX_BUILD_LOCK="${FACTORY_BUILD_LOCK:-/tmp/factory-next-build.lock}"
NX_BUILD_HELD=0

# The exit code a gate step gives a failure that is no fault of the code: the
# build lock held past its wait, another build in the checkout, a refused
# connection. The runner keeps no gate stamp of such a run, so --reuse runs it
# again (factory/core/lib/steps.sh, FACTORY_TRANSIENT_EXIT).
# shellcheck disable=SC2034 # read by the steps that source this
NX_TRANSIENT=75

# nx_wait_cap <setting> <seconds>: set NX_WAIT to <seconds>, the wait setting
# <setting> holds, cut to the time left for waits in the Editor's stop hook
# (factory_wait_cap, factory/core/lib/run.sh: the hook's gate wait record), and
# NX_WAIT_SAYS to how a message names that wait: `<setting>` alone, or, when
# cut, `<setting>'s <seconds>s, cut to the Editor's stop hook's time left for
# waits`.
nx_wait_cap() {
	NX_WAIT="$(factory_wait_cap "$2")"
	NX_WAIT_SAYS="$1"
	[ "$NX_WAIT" -ge "$2" ] || NX_WAIT_SAYS="$1's ${2}s, cut to the Editor's stop hook's time left for waits"
}

# nx_build_lock <wait>: take the build lock, waiting up to <wait> seconds (cut by
# nx_wait_cap) while another build holds it (one line on stderr when it starts
# waiting), its wait kept in the wait records (factory_wait_begin,
# factory_step_waited). False when it can't, with NX_BUILD_WHY and NX_BUILD_MSG
# set: busy (held past the wait) or lock (the folder can't be made).
nx_build_lock() {
	local end holder said="" gone=0 began
	nx_wait_cap FACTORY_BUILD_WAIT "$1"
	end=$((SECONDS + NX_WAIT))
	factory_wait_begin began
	while :; do
		if mkdir "$NX_BUILD_LOCK" 2> /dev/null; then
			NX_BUILD_HELD=1
			echo "$$" > "$NX_BUILD_LOCK/pid"
			factory_step_waited "$began"
			return 0
		fi
		# No lock after a failed mkdir: released or taken over in between, so try
		# again; five times running, and the folder can't be made.
		if [ ! -d "$NX_BUILD_LOCK" ]; then
			gone=$((gone + 1))
			[ "$gone" -ge 5 ] || continue
			NX_BUILD_WHY=lock
			NX_BUILD_MSG="could not make the build lock $NX_BUILD_LOCK; FACTORY_BUILD_LOCK in tools/verify/local.env names a folder to make, in a folder that exists"
			factory_step_waited "$began"
			return 1
		fi
		gone=0
		holder="$(nx_build_holder)"
		if nx_build_stale "$holder" && nx_build_takeover; then
			factory_step_waited "$began"
			return 0
		fi
		if [ "$SECONDS" -ge "$end" ]; then
			NX_BUILD_WHY=busy
			NX_BUILD_MSG="another next build held the build lock $NX_BUILD_LOCK (pid ${holder:-unknown}) past $NX_WAIT_SAYS (${NX_WAIT}s, tools/verify/local.env); run again once it ends, or remove the lock if no build is running"
			factory_step_waited "$began"
			return 1
		fi
		if [ -z "$said" ]; then
			said=1
			echo "next build: waiting for the build lock $NX_BUILD_LOCK, held by pid ${holder:-unknown} (up to ${NX_WAIT}s, $NX_WAIT_SAYS)" >&2
		fi
		sleep 0.2
	done
}

# A lock folder (the build lock, each of the slot pool's slots) holds its
# holder's pid in <lock>/pid.
# nx_lock_holder <lock>: print its holder pid; nothing when it names none.
nx_lock_holder() {
	local holder
	holder="$(cat "$1/pid" 2> /dev/null)"
	case "$holder" in '' | *[!0-9]*) return 0 ;; esac
	printf '%s\n' "$holder"
}

# nx_lock_stale <lock> <holder>: true when the lock is stale: its holder is no
# process, or it has named none for over a minute.
nx_lock_stale() {
	if [ -n "$2" ]; then
		! kill -0 "$2" 2> /dev/null
	else
		[ -n "$(find "$1" -maxdepth 0 -mmin +1 2> /dev/null)" ]
	fi
}

# nx_lock_takeover <lock> <held>: take a stale lock folder over, set the variable
# named <held> to 1 and hold it, the old holder's pid (or nothing) in
# NX_LOCK_FORMER. Takeovers run one at a time, under a guard folder beside the
# lock (<lock>.takeover), and each judges the lock stale again under it: a waiter
# that saw the old holder gone can't remove the lock another waiter has just
# taken over. A guard over a minute old was left by a takeover cut short, and is
# removed. False when the guard is busy or the lock is no longer stale (or gone:
# the next mkdir takes it).
nx_lock_takeover() {
	local guard="$1.takeover" holder taken=1
	if ! mkdir "$guard" 2> /dev/null; then
		[ -n "$(find "$guard" -maxdepth 0 -mmin +1 2> /dev/null)" ] &&
			rmdir "$guard" 2> /dev/null && mkdir "$guard" 2> /dev/null || return 1
	fi
	holder="$(nx_lock_holder "$1")"
	if [ -d "$1" ] && nx_lock_stale "$1" "$holder" &&
		rm -rf "$1" 2> /dev/null && mkdir "$1" 2> /dev/null; then
		printf -v "$2" 1
		echo "$$" > "$1/pid"
		NX_LOCK_FORMER="$holder"
		taken=0
	fi
	rmdir "$guard" 2> /dev/null
	return "$taken"
}

# nx_build_holder, nx_build_stale <holder>, nx_build_takeover: the build lock's.
nx_build_holder() {
	nx_lock_holder "$NX_BUILD_LOCK"
}
nx_build_stale() {
	nx_lock_stale "$NX_BUILD_LOCK" "$1"
}
nx_build_takeover() {
	nx_lock_takeover "$NX_BUILD_LOCK" NX_BUILD_HELD || return 1
	echo "next build: took over the stale build lock $NX_BUILD_LOCK (its holder${NX_LOCK_FORMER:+, pid $NX_LOCK_FORMER,} is gone)" >&2
}

# nx_build_unlock: release the build lock when this process holds it; else
# nothing. A lock that names no holder yet is this process's own, taken just now.
nx_build_unlock() {
	[ "$NX_BUILD_HELD" -eq 1 ] || return 0
	NX_BUILD_HELD=0
	case "$(cat "$NX_BUILD_LOCK/pid" 2> /dev/null)" in
		"$$" | "") rm -rf "$NX_BUILD_LOCK" 2> /dev/null ;;
	esac
	return 0
}

# nx_next_build: next build under the build lock, its output on stderr; its exit
# status. On a failure, NX_BUILD_WHY says what kind and NX_BUILD_MSG why (stderr
# gets it too, but for a plain build failure, whose output is there):
#   setting    FACTORY_BUILD_WAIT isn't whole seconds from 0 to 999999 (exit 1)
#   lock       the lock's folder can't be made (exit 1)
#   busy       the lock was held past the wait (exit NX_TRANSIENT)
#   collision  next build found another build running in the checkout (exit
#              NX_TRANSIENT)
#   build      next build failed (its own exit status)
nx_next_build() {
	local wait="${FACTORY_BUILD_WAIT:-900}" log status
	NX_BUILD_WHY=""
	NX_BUILD_MSG=""
	case "$wait" in
		'' | *[!0-9]* | ???????*)
			NX_BUILD_WHY=setting
			NX_BUILD_MSG="FACTORY_BUILD_WAIT is '$wait', not a number of seconds from 0 to 999999"
			echo "next build: $NX_BUILD_MSG (tools/verify/local.env)" >&2
			return 1
			;;
	esac
	if ! nx_build_lock "$((10#$wait))"; then
		echo "next build: $NX_BUILD_MSG" >&2
		[ "$NX_BUILD_WHY" = busy ] && return "$NX_TRANSIENT"
		return 1
	fi
	log="$(mktemp)" || {
		nx_build_unlock
		return 1
	}
	tool next build 2>&1 | tee "$log" >&2
	status="${PIPESTATUS[0]}"
	nx_build_unlock
	if [ "$status" -ne 0 ]; then
		NX_BUILD_WHY=build
		NX_BUILD_MSG="next build exited $status (see stderr)"
		# next's own lock, in the checkout's .next (colours or not).
		if grep -q 'Another .* is already running' "$log"; then
			NX_BUILD_WHY=collision
			NX_BUILD_MSG="next build exited $status: another next build was running in this checkout (see stderr)"
			echo "next build: $NX_BUILD_MSG" >&2
			status="$NX_TRANSIENT"
		fi
	fi
	rm -f "$log"
	return "$status"
}

# The slot pool: the heavy gate steps, mutate's Stryker run and smoke's browser
# checks, each run holding one of FACTORY_GATE_SLOTS slots on this machine,
# whichever checkout (worktree or clone) runs them, so a Run's issues gated at
# once queue for the cores instead of starving each other past their time
# budgets (Stryker's per-mutant timeouts, FACTORY_SMOKE_TIMEOUT's waits). Each
# slot is a lock folder like the build lock, <pool>/<n> for n from 1 to the
# count, holding its holder's pid; a slot whose holder is gone is stale and taken
# over, as the build lock is. The pool is the folder FACTORY_GATE_POOL
# (local.env) names, by default /tmp/factory-gate-slots, beside the build lock
# and fixed for the same reason.
#
# FACTORY_GATE_SLOTS (local.env; 1 to 999) is the count; empty means a quarter
# of the cores (nproc), at least 1: two on 8 cores. Why a quarter: a slot is
# about four cores' work, what smoke's three browsers and its server keep busy,
# and on 8 cores two Stryker runs at mutate's default concurrency (STRYKER_JOBS,
# half the cores) fill the machine. So the slots together keep the cores busy
# without oversubscribing them, and the gates' other steps (typecheck, lint,
# test), which take no slot, still get a share. On more cores, set STRYKER_JOBS
# to the cores over the slots, or Stryker runs side by side oversubscribe them.
#
# A step waits for a slot up to FACTORY_GATE_SLOT_WAIT seconds (local.env; 0 to
# 999999), saying so once on stderr; empty means 900, as the build lock's wait.
# In the Editor's stop hook both waits are cut to the hook's time left for waits
# (nx_wait_cap): Claude Code kills the hook at its 3600 s timeout, and the hook
# gives every wait the first 1500 s, the gate 1800 s of work with its waits left
# out, and keeps 300 s in hand (factory/core/lib/run.sh). It waits before any of
# its budgeted waits starts: the wait counts against none of them. It adds the
# wait to the runner's records of it (factory_wait_begin, factory_step_waited),
# which verify.sh takes off the step's seconds-<step>, so the Retro reads its
# own time, and the Editor's stop hook off the gate's work. A wait past the
# ceiling fails as a transient cause (NX_TRANSIENT): no gate stamp is kept,
# --reuse runs the step again, and the Editor's stop hook calls the gate busy,
# not red. The step releases its
# slot when its heavy part ends, and runs nx_slot_free from its EXIT trap too.
NX_SLOT_POOL="${FACTORY_GATE_POOL:-/tmp/factory-gate-slots}"
NX_SLOT=""
NX_SLOT_HELD=0

# nx_slot_count: set NX_SLOTS to the pool's slot count, FACTORY_GATE_SLOTS or a
# quarter of the cores; false, with NX_SLOT_MSG set, when the setting isn't 1 to
# 999.
nx_slot_count() {
	local n="${FACTORY_GATE_SLOTS:-}"
	if [ -z "$n" ]; then
		n=$(($(nproc 2> /dev/null || echo 4) / 4))
		[ "$n" -ge 1 ] || n=1
		NX_SLOTS="$n"
		return 0
	fi
	case "$n" in *[!0-9]* | ????*) n=0 ;; esac
	if [ "$((10#$n))" -lt 1 ]; then
		NX_SLOT_MSG="FACTORY_GATE_SLOTS is '${FACTORY_GATE_SLOTS}', not a number of slots from 1 to 999"
		return 1
	fi
	NX_SLOTS="$((10#$n))"
}

# nx_slot_take <step>: take one of the pool's slots, waiting up to
# FACTORY_GATE_SLOT_WAIT seconds (cut by nx_wait_cap) while all are held (one line on stderr when it
# starts waiting), its wait added to the step's (factory_step_waited). False when
# it can't, with NX_SLOT_WHY and NX_SLOT_MSG set:
#   setting  FACTORY_GATE_SLOTS or FACTORY_GATE_SLOT_WAIT is out of its range
#   pool     a slot's folder can't be made
#   busy     every slot was held past the wait (the step exits NX_TRANSIENT)
nx_slot_take() {
	local slots wait began end i holder holders said="" gone=0
	NX_SLOT_WHY="" NX_SLOT_MSG=""
	nx_slot_count || {
		NX_SLOT_WHY=setting
		return 1
	}
	slots="$NX_SLOTS"
	wait="${FACTORY_GATE_SLOT_WAIT:-900}"
	case "$wait" in
		'' | *[!0-9]* | ???????*)
			NX_SLOT_WHY=setting
			NX_SLOT_MSG="FACTORY_GATE_SLOT_WAIT is '$wait', not a number of seconds from 0 to 999999"
			return 1
			;;
	esac
	nx_wait_cap FACTORY_GATE_SLOT_WAIT "$((10#$wait))"
	wait="$NX_WAIT"
	mkdir -p "$NX_SLOT_POOL" 2> /dev/null
	factory_wait_begin began
	end=$((SECONDS + wait))
	while :; do
		holders=""
		for ((i = 1; i <= slots; i++)); do
			NX_SLOT="$NX_SLOT_POOL/$i"
			if mkdir "$NX_SLOT" 2> /dev/null; then
				NX_SLOT_HELD=1
				echo "$$" > "$NX_SLOT/pid"
				factory_step_waited "$began"
				return 0
			fi
			# No slot after a failed mkdir: freed or taken over in between, so
			# try again; five times running, and the folder can't be made.
			if [ ! -d "$NX_SLOT" ]; then
				gone=$((gone + 1))
				if [ "$gone" -lt 5 ]; then
					i=$((i - 1))
					continue
				fi
				NX_SLOT="" NX_SLOT_WHY=pool
				NX_SLOT_MSG="could not make the gate slot $NX_SLOT_POOL/$i; FACTORY_GATE_POOL in tools/verify/local.env names a folder to make, in a folder that exists"
				factory_step_waited "$began"
				return 1
			fi
			gone=0
			holder="$(nx_lock_holder "$NX_SLOT")"
			if nx_lock_stale "$NX_SLOT" "$holder" && nx_lock_takeover "$NX_SLOT" NX_SLOT_HELD; then
				echo "$1: took over the stale gate slot $NX_SLOT (its holder${NX_LOCK_FORMER:+, pid $NX_LOCK_FORMER,} is gone)" >&2
				factory_step_waited "$began"
				return 0
			fi
			holders+="${holders:+ }${holder:-unknown}"
		done
		NX_SLOT=""
		if [ "$SECONDS" -ge "$end" ]; then
			NX_SLOT_WHY=busy
			NX_SLOT_MSG="all $slots gate slots in $NX_SLOT_POOL (pids $holders) stayed held past $NX_WAIT_SAYS (${wait}s, tools/verify/local.env); run again once a gate ends, or remove a slot whose pid runs no gate"
			factory_step_waited "$began"
			return 1
		fi
		if [ -z "$said" ]; then
			said=1
			echo "$1: waiting for one of the $slots gate slots in $NX_SLOT_POOL, held by pids $holders (up to ${wait}s, $NX_WAIT_SAYS); the wait counts against no budget" >&2
		fi
		sleep 0.2
	done
}

# nx_slot_free: release the slot this process holds; else nothing. A slot that
# names no holder yet is this process's own, taken just now.
nx_slot_free() {
	[ "$NX_SLOT_HELD" -eq 1 ] || return 0
	NX_SLOT_HELD=0
	case "$(cat "$NX_SLOT/pid" 2> /dev/null)" in
		"$$" | "") rm -rf "$NX_SLOT" 2> /dev/null ;;
	esac
	NX_SLOT=""
	return 0
}

# nx_glob_rules <file>: the file's globs as `<+|-> <anchored regex>` lines, one per
# non-blank, non-# line; a leading ! gives `-`.
nx_glob_rules() {
	local line sign
	[ -f "$1" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in '' | '#'*) continue ;; esac
		sign=+
		if [ "${line:0:1}" = '!' ]; then
			sign=-
			line="${line:1}"
		fi
		printf '%s %s\n' "$sign" "$(factory_glob_regex "$line")"
	done < "$1"
}

# nx_filter <rules file>: the stdin paths the rules (nx_glob_rules) keep, in order.
nx_filter() {
	awk -v rules="$1" '
		BEGIN { while ((getline line < rules) > 0) { n++; sign[n] = substr(line, 1, 1); re[n] = substr(line, 3) } }
		{ keep = 0; for (i = 1; i <= n; i++) if ($0 ~ re[i]) keep = (sign[i] == "+"); if (keep) print }
	'
}

# nx_all_files <ext...>: every tracked or new (not ignored) file in the project
# with one of these extensions, one per line, sorted byte-wise; never one in the
# Scenario folder.
nx_all_files() {
	local ext
	local -a specs=()
	for ext in "$@"; do specs+=("*.$ext"); done
	git -c core.quotepath=off ls-files --cached --others --exclude-standard -- "${specs[@]}" |
		while IFS= read -r f; do
			[ -z "$NX_SCENARIOS" ] || case "$f" in "$NX_SCENARIOS"/*) continue ;; esac
			[ -f "$f" ] && printf '%s\n' "$f"
		done |
		LC_ALL=C sort -u
}

# nx_files <ext...>: the files with these extensions the gates check, one per
# line, sorted byte-wise: nx_all_files narrowed by the scope. With no scope file,
# everything outside factory/ and tools/ (prepare reports the missing scope).
nx_files() {
	if [ ! -f "$NX_SCOPE" ]; then
		nx_all_files "$@" | grep -Ev '^(factory|tools)/'
		return 0
	fi
	local rules
	rules="$(mktemp)"
	nx_glob_rules "$NX_SCOPE" > "$rules"
	nx_all_files "$@" | nx_filter "$rules"
	rm -f "$rules"
}

# nx_tests: the stdin paths that are tests, by NX_TEST_PATHS's globs (the seeded
# defaults when it holds none), in order.
nx_tests() {
	local rules
	rules="$(mktemp)"
	nx_glob_rules "$NX_TEST_PATHS" > "$rules"
	[ -s "$rules" ] || printf '+ %s\n' "$(factory_glob_regex '**/*.test.ts')" "$(factory_glob_regex '**/*.test.tsx')" "$(factory_glob_regex 'tests/**')" > "$rules"
	nx_filter "$rules"
	rm -f "$rules"
}

# nx_format_excluded: the format-exclude list's paths, one per line, as
# "<line number> <path>".
nx_format_excluded() {
	[ -f "$NX_FORMAT_EXCLUDE" ] || return 0
	awk '{ sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
		$0 != "" && $0 !~ /^#/ { print NR " " $0 }' "$NX_FORMAT_EXCLUDE"
}

# json_line <file> <key>: the line of the file's first "<key>": , else 1.
json_line() {
	[ -f "$1" ] || {
		echo 1
		return
	}
	awk -v k="\"$2\"" '{ i = index($0, k); if (i && substr($0, i + length(k)) ~ /^[ \t]*:/) { print NR; f = 1; exit } } END { if (!f) print 1 }' "$1"
}
