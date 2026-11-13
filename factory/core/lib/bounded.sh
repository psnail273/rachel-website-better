# Running a command with a time limit, on a machine with `timeout` (coreutils)
# or without it (stock macOS). Sourced by sync.sh, the update-check hook and the
# hooks that load lib/round.sh; defines no side effects. Bash 3.2 or later.

# factory_run_bounded <seconds> <command...>: run <command> and return its exit
# status, its stdin, stdout and stderr its own; when it runs past <seconds>, stop
# it with TERM and return 124. A limit of 0 runs it unbounded, as timeout does.
#
# With `timeout` on PATH it is `timeout <seconds> <command...>`. Without it, the
# command runs as a background job in a process group of its own (job control on
# just for its start), beside a watchdog, a second background job that sleeps
# <seconds>, then sends TERM (and CONT, for a stopped one) to the command's
# group and exits 0. The function waits for the command, stops the watchdog
# (its group: the subshell and its sleep) and returns 124 when the watchdog had
# already fired, else the command's status; the command's stdout is passed
# through as it is. A limit that is not a number (digits, an optional fraction)
# returns 125 there, as timeout refuses one, with the reason on stderr.
#
# The fallback's limit is as fine as sleep's. A process the command started that
# left its group (setsid, a daemon) survives the TERM, as it does under timeout.
# If the caller is killed first, the command and its watchdog run on in their
# own groups, and the watchdog still stops the command at the limit. A caller
# that ignores TERM passes that on to the watchdog, which then can't be stopped
# early: the call returns at the limit even when the command ended before it.
factory_run_bounded() {
	if command -v timeout > /dev/null 2>&1; then
		timeout "$@"
	else
		_factory_run_bounded_fallback "$@"
	fi
}

# _factory_run_bounded_fallback <seconds> <command...>: factory_run_bounded with
# no `timeout`. A subshell, so job control and the job table stay in it, and
# errexit off in it: a caller's set -e would end it at the command's failure,
# before it stopped the watchdog and gave the status.
_factory_run_bounded_fallback() (
	set +e
	limit="$1"
	shift
	case "$limit" in
		'' | *[!0-9.]* | *.*.* | . | .* | *.)
			echo "factory_run_bounded: invalid time limit: '$limit'" >&2
			exit 125
			;;
	esac
	case "$limit" in *[1-9]*) ;; *)
		"$@"
		exit
		;;
	esac
	# A background job's stdin is /dev/null unless it names one: <&0 keeps the
	# caller's. Job control is on only for the two starts, so each job leads a
	# process group of its own and no job's end is reported on stderr.
	set -m
	"$@" <&0 &
	pid=$!
	# The watchdog. Until its sleep is over, TERM (the function stopping it)
	# ends it and its sleep at once, as no trap defers it; from then on it
	# ignores TERM, so once it fires it always ends in exit 0, whichever comes
	# first, the command's end or its stop.
	(
		sleep "$limit" || exit 1
		trap '' TERM
		kill -TERM -"$pid" 2> /dev/null
		kill -CONT -"$pid" 2> /dev/null
		exit 0
	) < /dev/null > /dev/null 2>&1 &
	watchdog=$!
	set +m
	wait "$pid"
	status=$?
	kill -TERM -"$watchdog" 2> /dev/null
	if wait "$watchdog"; then
		status=124
	fi
	exit "$status"
)
