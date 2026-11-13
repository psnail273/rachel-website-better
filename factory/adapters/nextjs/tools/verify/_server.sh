# The production server, shared by the smoke step and the Scenario driver
# (tools/verify/smoke, tools/verify/scenarios). Sourced after _nextjs.sh; its only
# side effect is reading the limit. Run from the project root.
#
#   1. nx_build: next build (offline: NEXT_TELEMETRY_DISABLED, and arch's R10
#      keeps fonts local), its output on stderr;
#   2. nx_start: next start on 127.0.0.1, on a port the OS picks free (--port 0;
#      nx_await reads the port from the URL next start prints), so runs side by
#      side never meet; nx_await polls until the port takes a connection;
#   3. the caller's client (the smoke step's browser script, the driver's
#      Playwright runs), started with nx_client.
# nx_stop stops what was started, the server's whole process group: the caller
# runs it from its EXIT trap (trap 'nx_stop; ...' EXIT, then nx_on_signal), so it
# runs on a pass, a finding, an error, and on INT, TERM or HUP.
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
# server's whole process group, stopped and reaped. A signal now is kept, not
# acted on, so a second TERM can't cut the stop short.
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

# nx_build: next build, its output on stderr; its exit status.
nx_build() {
	tool next build >&2
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
