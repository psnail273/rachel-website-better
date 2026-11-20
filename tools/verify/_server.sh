# The production server, shared by the smoke step and the Scenario driver
# (tools/verify/smoke, tools/verify/scenarios). Sourced after _nextjs.sh; its only
# side effect is reading the limit. Run from the project root.
#
#   1. nx_build: next build (offline: NEXT_TELEMETRY_DISABLED, and arch's R10
#      keeps fonts local), its output on stderr, under the machine-wide build
#      lock (_nextjs.sh's nx_next_build: FACTORY_BUILD_WAIT bounds the wait);
#   2. nx_start: next start on 127.0.0.1, on a port the OS picks free (--port 0;
#      nx_await reads the port from the URL next start prints), so runs side by
#      side never meet; nx_await polls until the port takes a connection;
#   3. the caller's client (the smoke step's browser script, the driver's
#      Playwright runs), started with nx_client.
# nx_stop stops what was started, the server's whole process group and the
# fixture server, and releases the build lock if a signal cut the build short
# (and the gate slot the smoke step holds, _nextjs.sh's pool):
# the caller runs it from its EXIT trap (trap 'nx_stop; ...' EXIT, then
# nx_on_signal), so it runs on a pass, a finding, an error, and on INT, TERM or
# HUP.
#
# The app's environment (scenario-env for the Scenario driver, smoke-env for
# smoke and the contact sheet): nx_env_read reads the file's NAME=value lines,
# nx_fixtures_up starts the fixture server (_scenario_fixtures.mjs) when a value
# names {fixtures}, and nx_env_export sets them, placeholders filled, before
# next build. nx_step_env does all three for smoke and the contact sheet.
#
# FACTORY_SMOKE_TIMEOUT (local.env; seconds, default 60) bounds each wait: the
# server's start, and the stop of the server and the client after TERM, when
# each is killed. NX_LIMIT holds it, or 0 when it isn't a whole number of
# seconds from 1 to 999999.

NX_LIMIT="${FACTORY_SMOKE_TIMEOUT:-60}"
case "$NX_LIMIT" in
	'' | *[!0-9]* | ???????*) NX_LIMIT=0 ;;
	*) NX_LIMIT=$((10#$NX_LIMIT)) ;; # decimal, a leading 0 too
esac
NX_SERVER=""
NX_CLIENT=""
NX_CLIENT_GROUP=0
NX_FIXTURES=""
NX_CAUGHT=""

# nx_halt <pid> <target>: TERM to <target> (the pid, or -<pid> for its process
# group), KILL once the limit runs out, then <pid> reaped.
# shellcheck disable=SC2317 # nx_stop, from the EXIT trap, calls it
nx_halt() {
	local end=$((SECONDS + NX_LIMIT))
	kill -TERM -- "$2" 2> /dev/null
	while kill -0 -- "$2" 2> /dev/null && [ "$SECONDS" -lt "$end" ]; do
		sleep 0.1
	done
	kill -KILL -- "$2" "$1" 2> /dev/null
	wait "$1" 2> /dev/null
}

# nx_stop: the client (its process group when nx_client gave it one), then the
# server's whole process group, then the fixture server, stopped and reaped. A
# signal now is kept, not acted on, so a second TERM can't cut the stop short.
# shellcheck disable=SC2317 # the EXIT trap calls it
nx_stop() {
	nx_hold
	if [ -n "$NX_CLIENT" ]; then
		if [ "$NX_CLIENT_GROUP" -eq 1 ]; then
			nx_halt "$NX_CLIENT" "-$NX_CLIENT"
		else
			nx_halt "$NX_CLIENT" "$NX_CLIENT"
		fi
	fi
	NX_CLIENT=""
	[ -z "$NX_SERVER" ] || nx_halt "$NX_SERVER" "-$NX_SERVER"
	NX_SERVER=""
	[ -z "$NX_FIXTURES" ] || nx_halt "$NX_FIXTURES" "$NX_FIXTURES"
	NX_FIXTURES=""
	nx_build_unlock
	nx_slot_free
}

# nx_on_signal: a signal ends the caller, and its EXIT trap stops what it started.
# nx_hold: a signal waits while a process starts and its pid is kept (a child
# would inherit a signal ignored, so it is caught and kept instead); nx_release
# then acts on it.
nx_on_signal() {
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM
}
nx_hold() {
	trap 'NX_CAUGHT=129' HUP
	trap 'NX_CAUGHT=130' INT
	trap 'NX_CAUGHT=143' TERM
}
nx_release() {
	nx_on_signal
	[ -z "$NX_CAUGHT" ] || exit "$NX_CAUGHT"
}

# nx_build: next build under the build lock, its output on stderr; its exit
# status, with NX_BUILD_WHY and NX_BUILD_MSG on a failure (nx_next_build).
nx_build() {
	nx_next_build
}

# nx_start <log>: next start in the background, its output in <log>, in a
# process group of its own (job control, for this one job), so nx_stop reaches
# whatever it starts; its pid in NX_SERVER.
nx_start() {
	nx_hold
	set -m
	tool next start --hostname 127.0.0.1 --port 0 > "$1" 2>&1 < /dev/null &
	NX_SERVER=$!
	set +m
	nx_release
}

# nx_await <log>: wait for the URL in the server's log, then for its port to take
# a connection. Returns 0 with the port in NX_PORT; 1 when the server exited
# first, its status in NX_SERVER_STATUS; 2 when the limit ran out. On 1 or 2 the
# log goes to stderr (what the server started may still run, in its group: nx_stop
# does that).
nx_await() {
	local end=$((SECONDS + NX_LIMIT))
	NX_PORT=""
	while :; do
		if [ -z "$NX_PORT" ]; then
			NX_PORT="$(tr -d '\r' < "$1" | sed -n 's#.*http://127\.0\.0\.1:\([0-9][0-9]*\).*#\1#p' | head -n 1)"
		fi
		if [ -n "$NX_PORT" ] && (exec 3<> "/dev/tcp/127.0.0.1/$NX_PORT") 2> /dev/null; then
			return 0
		fi
		if ! kill -0 "$NX_SERVER" 2> /dev/null; then
			wait "$NX_SERVER"
			# shellcheck disable=SC2034 # read by the caller
			NX_SERVER_STATUS=$?
			cat "$1" >&2
			return 1
		fi
		if [ "$SECONDS" -ge "$end" ]; then
			cat "$1" >&2
			return 2
		fi
		sleep 0.1
	done
}

# nx_client <group> <command...>: the command in the background, its pid in
# NX_CLIENT for nx_stop; with <group> 1, in a process group of its own, which
# nx_stop stops whole. Its stdin is /dev/null; the caller redirects the rest.
nx_client() {
	NX_CLIENT_GROUP="$1"
	shift
	nx_hold
	[ "$NX_CLIENT_GROUP" -eq 0 ] || set -m
	"$@" < /dev/null &
	NX_CLIENT=$!
	set +m
	nx_release
}

# nx_client_wait: wait for the client; its exit status. A client nx_client gave a
# process group of its own has that group stopped too (nx_halt), so nothing it
# left running outlives it. NX_CLIENT is cleared.
nx_client_wait() {
	local status
	wait "$NX_CLIENT"
	status=$?
	[ "$NX_CLIENT_GROUP" -eq 0 ] || nx_halt "$NX_CLIENT" "-$NX_CLIENT"
	NX_CLIENT=""
	return "$status"
}

# The folder this file is in, tools/verify/: its fixture server and smoke-env.
NX_SERVER_DIR="$(dirname "${BASH_SOURCE[0]}")"

# nx_env_read <file>: the app's environment file's NAME=value lines (blank lines
# and # comments skipped), in NX_ENV_NAMES, NX_ENV_VALUES (each value as written)
# and NX_ENV_AT (each one's line number); NX_ENV_FIXTURES is 1 when a value
# names {fixtures}. No file is no line. False at the first line that isn't
# NAME=value, NAME in capitals, digits and _ (not starting with a digit), or
# whose NAME is one of the steps' own (NX_*, FACTORY_*): NX_ENV_BAD holds its
# line number, NX_ENV_LINE the line.
nx_env_read() {
	local n=0 line name value
	NX_ENV_NAMES=() NX_ENV_VALUES=() NX_ENV_AT=() NX_ENV_FIXTURES=0 NX_ENV_BAD="" NX_ENV_LINE=""
	[ -f "$1" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		line="${line%$'\r'}"
		[[ $line =~ ^[[:space:]]*(#|$) ]] && continue
		name="" value=""
		if [[ $line =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
			name="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
		fi
		case "$name" in '' | NX_* | FACTORY_*)
			NX_ENV_BAD="$n" NX_ENV_LINE="$line"
			return 1
			;;
		esac
		case "$value" in *"{fixtures}"*) NX_ENV_FIXTURES=1 ;; esac
		NX_ENV_NAMES+=("$name")
		NX_ENV_VALUES+=("$value")
		NX_ENV_AT+=("$n")
	done < "$1"
}

# nx_env_export <state>: each line nx_env_read read, exported, with {fixtures}
# in its value the fixture server's origin (NX_FIXTURES_ORIGIN) and {state} the
# folder <state>.
nx_env_export() {
	local i value
	for i in "${!NX_ENV_NAMES[@]}"; do
		value="${NX_ENV_VALUES[i]//\{fixtures\}/"${NX_FIXTURES_ORIGIN:-}"}"
		export "${NX_ENV_NAMES[i]}=${value//\{state\}/"$1"}"
	done
}

# nx_fixtures_up <port> <folder> <log> [<seed>]: the fixture server
# (_scenario_fixtures.mjs) in the background on 127.0.0.1:<port> (0: one the OS
# picks), keeping its fixtures in <folder>, serving <seed>'s files from the
# start, its output in <log>, its pid in NX_FIXTURES for nx_stop. Returns 0 once
# it listens, with http://127.0.0.1:<the port it got> in NX_FIXTURES_ORIGIN; 1
# when it exited first, its status in NX_FIXTURES_STATUS and its log on stderr;
# 2 when the limit ran out.
nx_fixtures_up() {
	local end=$((SECONDS + NX_LIMIT))
	NX_FIXTURES_ORIGIN="" NX_FIXTURES_STATUS=""
	nx_hold
	"${NODE_BIN:-node}" "$NX_SERVER_DIR/_scenario_fixtures.mjs" "$1" "$2" ${4:+"$4"} > "$3" 2>&1 < /dev/null &
	NX_FIXTURES=$!
	nx_release
	while :; do
		NX_FIXTURES_ORIGIN="$(tr -d '\r' < "$3" | sed -n 's#^listening on \(http://127\.0\.0\.1:[0-9][0-9]*\)$#\1#p' | head -n 1)"
		[ -z "$NX_FIXTURES_ORIGIN" ] || return 0
		if ! kill -0 "$NX_FIXTURES" 2> /dev/null; then
			wait "$NX_FIXTURES"
			NX_FIXTURES_STATUS=$?
			NX_FIXTURES=""
			cat "$3" >&2
			return 1
		fi
		[ "$SECONDS" -lt "$end" ] || return 2
		sleep 0.1
	done
}

# nx_step_env <rule> <tmp>: the app's environment for smoke's and the contact
# sheet's next build and next start, from tools/verify/smoke-env (its header
# says how), exported; <tmp> is the step's own folder, where {state} is
# <tmp>/state. When a value names {fixtures}, each {fixtures}/<path> in it must
# be a file tools/verify/smoke-fixtures/<path>, with no query after it, and the
# fixture server starts on
# a free port serving that folder (nx_fixtures_up), before next build, so the
# build and the server read the same fixtures; nx_stop stops it. False on a
# finding, which it prints:
#   tools/verify/smoke-env:<line> <rule> <why>
nx_step_env() {
	local rule="$1" at=tools/verify/smoke-env i rest target first="" bad=0
	mkdir -p "$2/state" "$2/fixtures"
	if ! nx_env_read "$NX_SERVER_DIR/smoke-env"; then
		echo "$at:$NX_ENV_BAD $rule '$NX_ENV_LINE' is not NAME=value, NAME in capitals, digits and _, and none of the steps' own (NX_*, FACTORY_*)"
		return 1
	fi
	if [ "$NX_ENV_FIXTURES" -eq 1 ]; then
		for i in "${!NX_ENV_VALUES[@]}"; do
			rest="${NX_ENV_VALUES[i]}"
			while [[ $rest == *"{fixtures}"* ]]; do
				rest="${rest#*\{fixtures\}}"
				[ -n "$first" ] || first="${NX_ENV_AT[i]}"
				# The target's path: up to a space, a query or a fragment. A
				# query is sent, and the fixture server keys on path and query,
				# so it would answer 404.
				target="${rest%%[[:space:]?#]*}"
				case "${rest:${#target}:1}" in '?')
					echo "$at:${NX_ENV_AT[i]} $rule {fixtures}$target carries a query, but a smoke fixture answers its path alone"
					bad=1
					continue
					;;
				esac
				target="${target#/}"
				[ -n "$target" ] || continue
				if [ ! -f "$NX_SERVER_DIR/smoke-fixtures/$target" ]; then
					echo "$at:${NX_ENV_AT[i]} $rule {fixtures}/$target names no fixture: tools/verify/smoke-fixtures/$target is no file"
					bad=1
				fi
			done
		done
		[ "$bad" -eq 0 ] || return 1
		nx_fixtures_up 0 "$2/fixtures" "$2/fixtures.log" "$NX_SERVER_DIR/smoke-fixtures"
		case $? in
			1)
				echo "$at:$first $rule the fixture server (tools/verify/_scenario_fixtures.mjs) exited $NX_FIXTURES_STATUS before it listened (see stderr)"
				return 1
				;;
			2)
				echo "$at:$first $rule the fixture server (tools/verify/_scenario_fixtures.mjs) didn't listen within ${NX_LIMIT}s (FACTORY_SMOKE_TIMEOUT in tools/verify/local.env)"
				return 1
				;;
		esac
	fi
	nx_env_export "$2/state"
}
