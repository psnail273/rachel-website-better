# Shared by the Next.js adapter's step scripts. Sourced; its only side effects
# are sourcing the Core's glob matcher and Scenario folder reader, reading the
# Scenario folder and the build lock's path, putting local.env's Node and pnpm
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

# The glob matcher is the Core's (lib/brief.sh), and so is the Scenario folder's
# reader (lib/scenarios.sh). The runner exports FACTORY_CORE; run by hand, a step
# finds the Core where adoption vendors it.
if ! declare -F factory_glob_regex > /dev/null || ! declare -F factory_scenario_folder > /dev/null; then
	if [ ! -f "${FACTORY_CORE:-factory/core}/lib/brief.sh" ]; then
		echo "no factory Core at '${FACTORY_CORE:-factory/core}'; set FACTORY_CORE" >&2
		exit 2
	fi
	declare -F factory_glob_regex > /dev/null || . "${FACTORY_CORE:-factory/core}/lib/brief.sh"
	[ -n "${FACTORY_STEPS_DIR:-}" ] || . "${FACTORY_CORE:-factory/core}/lib/steps.sh"
	. "${FACTORY_CORE:-factory/core}/lib/scenarios.sh"
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
# FACTORY_BUILD_WAIT seconds (local.env; 0 to 999999, default 900), then gives up.
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

# nx_build_lock <wait>: take the build lock, waiting up to <wait> seconds while
# another build holds it (one line on stderr when it starts waiting). False when
# it can't, with NX_BUILD_WHY and NX_BUILD_MSG set: busy (held past the wait) or
# lock (the folder can't be made).
nx_build_lock() {
	local end=$((SECONDS + $1)) holder said="" gone=0
	while :; do
		if mkdir "$NX_BUILD_LOCK" 2> /dev/null; then
			NX_BUILD_HELD=1
			echo "$$" > "$NX_BUILD_LOCK/pid"
			return 0
		fi
		# No lock after a failed mkdir: released or taken over in between, so try
		# again; five times running, and the folder can't be made.
		if [ ! -d "$NX_BUILD_LOCK" ]; then
			gone=$((gone + 1))
			[ "$gone" -ge 5 ] || continue
			NX_BUILD_WHY=lock
			NX_BUILD_MSG="could not make the build lock $NX_BUILD_LOCK; FACTORY_BUILD_LOCK in tools/verify/local.env names a folder to make, in a folder that exists"
			return 1
		fi
		gone=0
		holder="$(nx_build_holder)"
		if nx_build_stale "$holder" && nx_build_takeover; then
			return 0
		fi
		if [ "$SECONDS" -ge "$end" ]; then
			NX_BUILD_WHY=busy
			NX_BUILD_MSG="another next build held the build lock $NX_BUILD_LOCK (pid ${holder:-unknown}) past FACTORY_BUILD_WAIT (${1}s, tools/verify/local.env); run again once it ends, or remove the lock if no build is running"
			return 1
		fi
		if [ -z "$said" ]; then
			said=1
			echo "next build: waiting for the build lock $NX_BUILD_LOCK, held by pid ${holder:-unknown} (up to ${1}s, FACTORY_BUILD_WAIT)" >&2
		fi
		sleep 0.2
	done
}

# nx_build_holder: print the build lock's holder pid; nothing when it names none.
nx_build_holder() {
	local holder
	holder="$(cat "$NX_BUILD_LOCK/pid" 2> /dev/null)"
	case "$holder" in '' | *[!0-9]*) return 0 ;; esac
	printf '%s\n' "$holder"
}

# nx_build_stale <holder>: true when the lock is stale: its holder is no process,
# or it has named none for over a minute.
nx_build_stale() {
	if [ -n "$1" ]; then
		! kill -0 "$1" 2> /dev/null
	else
		[ -n "$(find "$NX_BUILD_LOCK" -maxdepth 0 -mmin +1 2> /dev/null)" ]
	fi
}

# nx_build_takeover: take a stale build lock over, and hold it. Takeovers run one
# at a time, under a guard folder beside the lock (<lock>.takeover), and each
# judges the lock stale again under it: a waiter that saw the old holder gone
# can't remove the lock another waiter has just taken over. A guard over a minute
# old was left by a takeover cut short, and is removed. False when the guard is
# busy or the lock is no longer stale (or gone: the next mkdir takes it).
nx_build_takeover() {
	local guard="$NX_BUILD_LOCK.takeover" holder taken=1
	if ! mkdir "$guard" 2> /dev/null; then
		[ -n "$(find "$guard" -maxdepth 0 -mmin +1 2> /dev/null)" ] &&
			rmdir "$guard" 2> /dev/null && mkdir "$guard" 2> /dev/null || return 1
	fi
	holder="$(nx_build_holder)"
	if [ -d "$NX_BUILD_LOCK" ] && nx_build_stale "$holder" &&
		rm -rf "$NX_BUILD_LOCK" 2> /dev/null && mkdir "$NX_BUILD_LOCK" 2> /dev/null; then
		NX_BUILD_HELD=1
		echo "$$" > "$NX_BUILD_LOCK/pid"
		echo "next build: took over the stale build lock $NX_BUILD_LOCK (its holder${holder:+, pid $holder,} is gone)" >&2
		taken=0
	fi
	rmdir "$guard" 2> /dev/null
	return "$taken"
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
