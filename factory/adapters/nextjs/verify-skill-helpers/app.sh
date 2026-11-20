#!/usr/bin/env bash
# The app for a check by hand: the production build, started on a free port as
# the smoke step starts it, left running until stopped. The verify skill's
# generator (factory/adapters/nextjs/verify-skill.sh) copies it into the skill's
# folder. Run from the project root:
#   bash .claude/skills/verify-<project>/app.sh start
#   bash .claude/skills/verify-<project>/app.sh run <command...>
#   bash .claude/skills/verify-<project>/app.sh contrast <route> <selector> [option...]
#   bash .claude/skills/verify-<project>/app.sh stop
#
# It reads tools/verify/local.env and uses the gate's own pieces
# (tools/verify/_nextjs.sh, _server.sh): the app's environment from
# tools/verify/smoke-env, with its fixture server when a value names
# {fixtures} (nx_step_env); next build under the machine-wide build lock
# (nx_build); next start on 127.0.0.1 with --port 0, so the OS picks a free
# port and two checks never race for one (nx_start); and the wait until the
# server has printed its URL and its port takes a connection, its Ready
# (nx_await, bounded by FACTORY_SMOKE_TIMEOUT). Its state is in the checkout's
# own git dir, <git-dir>/factory/app/ (each worktree its own, never committed):
# server.log, env, and the pids.
#
# start: refuses while the server it started still runs; once that is gone,
# first stops what else it kept that runs (the fixture server). stdout, on
# success:
#   url http://127.0.0.1:<port>
#   pid <the server's pid>
#   env <git-dir>/factory/app/env
#   log <git-dir>/factory/app/server.log
# The build's output goes to stderr. env holds APP_URL and
# PLAYWRIGHT_BROWSERS_PATH (local.env's own, else its
# FACTORY_PLAYWRIGHT_BROWSERS), for `set -a; . <env>; set +a`. On a failure it
# stops what it started and exits 1 (75, NX_TRANSIENT, when the build lock was
# held past FACTORY_BUILD_WAIT or another build ran in the checkout).
# run: the command, with that env exported and Node and pnpm first on PATH, as
#   the steps have them; its exit status. For a Playwright script: it reads
#   process.env.APP_URL.
# contrast: contrast.mjs (beside this script) on APP_URL<route>, its options
#   after the selector; its output and exit status.
# stop: stops the process group of the server it started (next start and the
#   workers it forked, nothing else: next start leads its own group), then the
#   fixture server's, each only while its pid still names the process it
#   started (its start time, as ps gives it, is kept), TERM first and KILL once
#   FACTORY_SMOKE_TIMEOUT runs out. stdout: `stopped <pid>` for each, or
#   `nothing to stop`. Never a pkill: nothing it didn't start is touched.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f tools/verify/local.env ]; then
	set -a
	# shellcheck disable=SC1091 # the machine's own, gitignored
	. ./tools/verify/local.env
	set +a
fi
[ -f tools/verify/_server.sh ] || {
	echo "app.sh: run it from the project root (no tools/verify/_server.sh here)" >&2
	exit 2
}
# shellcheck disable=SC1091 # the project's own
. tools/verify/_nextjs.sh
# shellcheck disable=SC1091 # the project's own
. tools/verify/_server.sh
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-${FACTORY_PLAYWRIGHT_BROWSERS:-}}"
[ -n "$PLAYWRIGHT_BROWSERS_PATH" ] || unset PLAYWRIGHT_BROWSERS_PATH

gitdir="$(git rev-parse --absolute-git-dir 2> /dev/null)" || {
	echo "app.sh: the project is no git checkout, and the app's state goes in its git dir" >&2
	exit 1
}
state="$gitdir/factory/app"

# started <pid>: the process's start time, empty when it is gone.
started() {
	ps -o lstart= -p "$1" 2> /dev/null
}

# alive <name>: the pid in $state/<name>.pid, when it still names the process
# that was started (its start time in $state/<name>.started).
alive() {
	local pid
	[ -f "$state/$1.pid" ] || return 1
	pid="$(cat "$state/$1.pid")"
	[ -n "$pid" ] && [ -n "$(started "$pid")" ] && [ "$(started "$pid")" = "$(cat "$state/$1.started" 2> /dev/null)" ] || return 1
	printf '%s\n' "$pid"
}

# keep <name> <pid>: the pid and its start time, for stop.
keep() {
	printf '%s\n' "$2" > "$state/$1.pid" && started "$2" > "$state/$1.started"
}

# load: the running app's env, exported; false, saying so, when none runs.
load() {
	alive server > /dev/null && [ -f "$state/env" ] || {
		echo "app.sh: no app is running: bash $0 start" >&2
		return 1
	}
	set -a
	# shellcheck disable=SC1091 # written by start
	. "$state/env"
	set +a
}

start() {
	local pid status
	if pid="$(alive server)"; then
		echo "app.sh: the app it started still runs (pid $pid, $(sed -n 's/^APP_URL=//p' "$state/env" 2> /dev/null)): bash $0 stop first" >&2
		exit 1
	fi
	if [ "$NX_LIMIT" -eq 0 ]; then
		echo "app.sh: FACTORY_SMOKE_TIMEOUT is '${FACTORY_SMOKE_TIMEOUT:-}', not a number of seconds from 1 to 999999 (tools/verify/local.env)" >&2
		exit 1
	fi
	tool_ready next >&2 || exit 1
	# The server is gone (it crashed, or was killed by hand), but what else the
	# last start kept may still run: stopped now, before its pids are emptied.
	halt >&2
	rm -rf "$state" && mkdir -p "$state" || {
		echo "app.sh: could not empty $state" >&2
		exit 1
	}
	trap 'nx_stop' EXIT
	nx_on_signal
	# The fixture server in a process group of its own, as next start's is,
	# so stop reaches it whole, and the shell that ran start leaves it be.
	set -m
	nx_step_env verify-app "$state" >&2
	status=$?
	set +m
	[ "$status" -eq 0 ] || exit 1
	[ -z "$NX_FIXTURES" ] || keep fixtures "$NX_FIXTURES"
	nx_build
	status=$?
	if [ "$status" -ne 0 ]; then
		echo "app.sh: $NX_BUILD_MSG" >&2
		case "$NX_BUILD_WHY" in busy | collision) exit "$NX_TRANSIENT" ;; esac
		exit 1
	fi
	nx_start "$state/server.log"
	keep server "$NX_SERVER"
	nx_await "$state/server.log"
	case $? in
		1)
			echo "app.sh: next start exited $NX_SERVER_STATUS before it answered (its log above)" >&2
			exit 1
			;;
		2)
			echo "app.sh: next start didn't answer within ${NX_LIMIT}s (FACTORY_SMOKE_TIMEOUT in tools/verify/local.env)" >&2
			exit 1
			;;
	esac
	{
		printf 'APP_URL=%q\n' "http://127.0.0.1:$NX_PORT"
		[ -z "${PLAYWRIGHT_BROWSERS_PATH:-}" ] || printf 'PLAYWRIGHT_BROWSERS_PATH=%q\n' "$PLAYWRIGHT_BROWSERS_PATH"
	} > "$state/env"
	# Running: left for stop.
	NX_SERVER="" NX_FIXTURES=""
	trap - EXIT
	printf 'url http://127.0.0.1:%s\npid %s\nenv %s\nlog %s\n' "$NX_PORT" "$(cat "$state/server.pid")" "$state/env" "$state/server.log"
}

# halt: each process start kept that still runs, stopped (its whole process
# group), with a `stopped <pid>` line for each; its pid files removed. False
# when none ran.
halt() {
	local name pid any=1
	for name in server fixtures; do
		if pid="$(alive "$name")"; then
			nx_halt "$pid" "-$pid"
			echo "stopped $pid"
			any=0
		fi
		rm -f "$state/$name.pid" "$state/$name.started"
	done
	return "$any"
}

stop() {
	halt || echo "nothing to stop"
}

case "${1:-}" in
	start) start ;;
	stop) stop ;;
	run)
		shift
		[ "$#" -ge 1 ] || {
			echo "usage: bash $0 run <command...>" >&2
			exit 2
		}
		load || exit 1
		"$@"
		;;
	contrast)
		shift
		[ "$#" -ge 2 ] || {
			echo "usage: bash $0 contrast <route> <selector> [option...]" >&2
			exit 2
		}
		load || exit 1
		route="$1"
		shift
		"${NODE_BIN:-node}" "$here/contrast.mjs" "$APP_URL$route" "$@"
		;;
	*)
		echo "usage: bash $0 start|run <command...>|contrast <route> <selector> [option...]|stop" >&2
		exit 2
		;;
esac
