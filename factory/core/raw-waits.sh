#!/usr/bin/env bash
# The raw-waits check: no test sleeps for a fixed time, or reads the clock, so no
# test's outcome depends on how loaded the machine is. A test waits for a condition
# through wait_until, and a stand-in that must still be running blocks until the
# test releases or kills it (blocking_stand_in); both are in tests/lib.sh, the one
# file exempt, as it is no *_test.sh.
#   bash factory/core/raw-waits.sh [file...]
# Default: every factory/core/tests/*_test.sh and factory/adapters/*/tests/*_test.sh;
# in a clone of the factory's repo (VERSION and core/ at the top of its checkout),
# core/tests and adapters/*/tests there. test.sh runs it after the tests.
#
# It is a text heuristic. It flags, outside a comment line:
# - sleep or timeout as a command: at the start of a line, after ; & | ( { ! ` $(
#   or an opening quote or a \n (a stand-in's text, a bash -c), after a keyword or
#   a wrapper (if, then, do, exec, env, run_cmd, timeout...) and after VAR=value
#   assignments. sleep or timeout as a word in prose, a variable or a JSON key
#   (local timeout, "$timeout", .timeout) is not a command.
# - bash's clock, SECONDS, as a variable: $SECONDS, ${SECONDS}, an assignment to
#   it, or the name inside (( )).
# Text a test writes to a stand-in counts too: a stand-in that sleeps makes the
# test's outcome hang on the sleep outlasting other work.
#
# Prints findings (`file:line raw-wait message`), sorted, and exits 1 on any.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/findings.sh"

if [ "$#" -ge 1 ]; then
	files=("$@")
else
	if cdup="$(git -C "$core/.." rev-parse --show-cdup 2> /dev/null)" && [ -z "$cdup" ] && [ -f "$core/../VERSION" ]; then
		cd "$core/.." || exit 1
		top=.
	else
		# From the folder holding factory/, so findings name factory/core/tests/....
		top="$(basename "$(cd "$core/.." && pwd)")"
		cd "$core/../.." || exit 1
	fi
	files=()
	for f in "$top"/core/tests/*_test.sh "$top"/adapters/*/tests/*_test.sh; do
		[ -f "$f" ] && files+=("${f#./}")
	done
fi

# Where a command starts, what may stand before the word on the way (wrappers and
# assignments), the words, and what may follow one.
start='(^|[;&|({!`'"'"'"]|\$\(|\\n)'
wrapper='(if|then|do|else|elif|while|until|exec|command|builtin|nohup|setsid|env|xargs|time|run_cmd|timeout)[[:space:]]+'
assignment='[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]*)[[:space:]]+'
word='(sleep|timeout)([[:space:];|&)`'"'"'"]|$)'
command_re="${start}[[:space:]]*(${wrapper}|${assignment})*${word}"
clock_re='\$\{?SECONDS([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])SECONDS\+?=|\(\(([^)]*[^A-Za-z0-9_$])?SECONDS([^A-Za-z0-9_]|$)'

for f in "${files[@]}"; do
	grep -nE -e "$command_re" -e "$clock_re" -- "$f" | grep -vE '^[0-9]+:[[:space:]]*#' |
		while IFS=: read -r n _; do
			factory_finding "$f" "$n" raw-wait "a sleep, a timeout or bash's clock in a test; wait for a condition with wait_until, and make a stand-in that must keep running with blocking_stand_in (factory/core/tests/lib.sh)"
		done
done | factory_sort_findings | grep . && exit 1
exit 0
