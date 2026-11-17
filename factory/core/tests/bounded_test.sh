# factory_run_bounded (lib/bounded.sh): a command under a time limit, with
# `timeout` on PATH and, through the fallback, on a PATH without it (stock macOS).

# bounded <seconds> <command...>: factory_run_bounded, from this Core's lib.
bounded() {
	. "$FACTORY_CORE/lib/bounded.sh" || fail "could not load lib/bounded.sh"
	factory_run_bounded "$@"
}

# errexit_bounded <seconds> <command...>: factory_run_bounded called from a
# script under set -e, its exit status the call's.
errexit_bounded() {
	printf 'set -e\n. %q\nfactory_run_bounded "$@"\necho "the call returned 0"\n' "$FACTORY_CORE/lib/bounded.sh" > "$TEST_TMP/errexit.sh"
	bash "$TEST_TMP/errexit.sh" "$@"
}

# timeout_on_path: the machine's own timeout, or the test skips.
timeout_on_path() {
	command -v timeout > /dev/null 2>&1 || skip "no timeout on this machine's PATH"
}

# assert_ends_in_time: through $BOUNDED (bounded by default), a command that
# ends well inside its limit ($LIMIT, 6171 by default) keeps its exit status,
# its stdin, stdout and stderr, and the call returns when it ends, not at the
# limit (a watchdog left running would hold it there).
assert_ends_in_time() {
	local call
	printf 'in\n' > "$TEST_TMP/in"
	"${BOUNDED:-bounded}" "${LIMIT:-6171}" bash -c 'echo out; echo err >&2; read -r line; echo "$line"; exit 7' \
		< "$TEST_TMP/in" > "$TEST_TMP/out" 2> "$TEST_TMP/stderr" &
	call=$!
	wait_until "the call to return" not_running "$call"
	wait "$call"
	# shellcheck disable=SC2034 # read by assert_status, in factory/core/tests/lib.sh
	status=$?
	out="$(cat "$TEST_TMP/out")"
	assert_status 7
	assert_eq "out"$'\n'"in" "$out" "the command's stdout"
	assert_eq err "$(cat "$TEST_TMP/stderr")" "the command's stderr"
}

# not_running <pid>: no process <pid> (or only a zombie).
not_running() {
	! kill -0 "$1" 2> /dev/null || [ "$(ps -o stat= -p "$1" 2> /dev/null | cut -c1)" = Z ]
}

# assert_overrun_is_stopped: through $BOUNDED (bounded by default), a command
# still running at its limit (a script whose child, a blocking stand-in, is
# never released) is stopped, its child too, and the call returns 124. The child's stdout is not the call's, so the
# call returns even when the child is left running, and the wait for it fails.
# The limit may end the command before it starts its child, on a loaded
# machine: then there is no child to look for.
assert_overrun_is_stopped() {
	blocking_stand_in "$TEST_TMP/hang" "$TEST_TMP/never"
	cat > "$TEST_TMP/cmd" << SH
#!/usr/bin/env bash
echo "\$\$" > $(printf '%q' "$TEST_TMP/cmd.pid")
$(printf '%q' "$TEST_TMP/hang") > /dev/null &
wait "\$!"
echo "\$?" > $(printf '%q' "$TEST_TMP/hang.end")
SH
	chmod 755 "$TEST_TMP/cmd" || fail "could not make the command"
	run_cmd "${BOUNDED:-bounded}" 1 "$TEST_TMP/cmd"
	assert_status 124
	[ ! -e "$TEST_TMP/hang.end" ] || fail "the stand-in ended on its own: $(cat "$TEST_TMP/hang.end")"
	wait_until "the command and its child to be gone" pids_gone "$TEST_TMP/cmd.pid" "$TEST_TMP/hang.pid"
}

# pids_gone <pid file...>: no process left of those the files name (a file not
# written yet names none).
pids_gone() {
	local file pid
	for file in "$@"; do
		pid="$(cat "$file" 2> /dev/null)" || continue
		not_running "$pid" || return 1
	done
}

# no_watchdog_left: no process is the fallback's watchdog for a ${LIMIT:-6171} s
# limit (each test that looks has a limit of its own).
no_watchdog_left() {
	! pgrep -fx "[s]leep ${LIMIT:-6171}" > /dev/null
}

# strace_on_path: strace, able to trace a child and delay its syscalls, or the
# test skips.
strace_on_path() {
	command -v strace > /dev/null 2>&1 || skip "no strace on this machine's PATH"
	strace -f -o /dev/null -e trace=clone -e inject=clone:delay_enter=1:when=1 bash -c '(:)' 2> "$TEST_TMP/strace.err" ||
		skip "strace can't trace a child here: $(cat "$TEST_TMP/strace.err")"
}

test_a_command_that_ends_in_time_keeps_its_status_and_output_where_timeout_is_on_path() {
	timeout_on_path
	assert_ends_in_time
}

test_a_command_that_ends_in_time_keeps_its_status_and_output_where_timeout_is_missing() {
	path_without timeout
	assert_ends_in_time
	wait_until "the watchdog to be gone" no_watchdog_left
}

# The window the watchdog's sleep once outlived the call through, forced: bash
# blocks TERM while it forks, so a TERM that comes as the watchdog forks its
# sleep ends the watchdog just after, and the sleep, not yet in the group when
# the TERM went out, missed it. Here strace holds each process's first fork 2 s
# and its first kill 1 s: the watchdog's fork of its sleep is its first, held
# from just after it starts, and the call's TERM to it, the call's first kill,
# sent once `true` has ended, goes out a second into that hold. (The call's own
# fork of the command and the bash -c's of the call are held too, before.) strace
# lets go of each process at its exec, so it ends with the call, and a sleep left
# running is seen, not waited for.
test_a_watchdog_stopped_as_it_forks_its_sleep_leaves_no_sleep_where_timeout_is_missing() {
	strace_on_path
	path_without timeout
	LIMIT=6173
	run_cmd strace -f -b execve -o "$TEST_TMP/strace.log" -e trace=clone,kill \
		-e inject=clone:delay_enter=2000000:when=1 -e inject=kill:delay_enter=1000000:when=1 \
		bash -c '. "$1" && factory_run_bounded "$2" true' bounded "$FACTORY_CORE/lib/bounded.sh" "$LIMIT"
	assert_status 0
	wait_until "the watchdog to be gone" no_watchdog_left
}

# The other window, forced: called from a subshell of a caller that traps TERM
# (and EXIT, as test.sh does), the watchdog has bash's own TERM handler, and so
# has its sleep until its exec: a TERM the sleep got before its exec was caught
# and lost, the call's second TERM too. Here strace holds each
# process's first rt_sigaction 1 s and its first kill 0.25 s: the sleep's first
# rt_sigaction comes after it unblocks TERM and before its exec, so both TERMs,
# the first held 0.25 s once `true` has ended, reach it in that hold. (The
# shells' and the watchdog's own first ones are held too, before.)
test_a_watchdog_sleep_that_catches_term_before_its_exec_is_stopped_where_timeout_is_missing() {
	strace_on_path
	path_without timeout
	LIMIT=6174
	run_cmd strace -f -b execve -o "$TEST_TMP/strace.log" -e trace=rt_sigaction,kill \
		-e inject=rt_sigaction:delay_enter=1000000:when=1 -e inject=kill:delay_enter=250000:when=1 \
		bash -c 'trap : EXIT; trap "exit 130" INT TERM; (. "$1" && factory_run_bounded "$2" true)' \
		bounded "$FACTORY_CORE/lib/bounded.sh" "$LIMIT"
	assert_status 0
	wait_until "the watchdog to be gone" no_watchdog_left
}

test_a_command_past_its_limit_is_stopped_with_124_where_timeout_is_on_path() {
	timeout_on_path
	assert_overrun_is_stopped
}

test_a_command_past_its_limit_is_stopped_with_124_where_timeout_is_missing() {
	path_without timeout
	assert_overrun_is_stopped
}

# A limit of 0 is none, as for timeout: the command runs to its end.
test_a_limit_of_0_runs_the_command_unbounded_where_timeout_is_missing() {
	path_without timeout
	run_cmd bounded 0 bash -c 'echo out; exit 3'
	assert_status 3
	assert_eq out "$out"
}

test_a_limit_that_is_not_a_number_is_refused_with_125_where_timeout_is_missing() {
	path_without timeout
	run_cmd bounded 1x bash -c 'echo ran'
	assert_status 125
	assert_eq "" "$out" "the command ran"
	stderr_has "factory_run_bounded: invalid time limit: '1x'"
}

# A caller under set -e still gets the command's status, and no watchdog is left.
test_a_command_that_ends_in_time_keeps_its_status_under_errexit_where_timeout_is_missing() {
	path_without timeout
	BOUNDED=errexit_bounded LIMIT=6172
	assert_ends_in_time
	wait_until "the watchdog to be gone" no_watchdog_left
}

# ... and 124 at the limit, with the command and its child gone.
test_a_command_past_its_limit_is_stopped_with_124_under_errexit_where_timeout_is_missing() {
	path_without timeout
	BOUNDED=errexit_bounded
	assert_overrun_is_stopped
}
