# The Next.js Scenario driver (tools/verify/scenarios, _scenarios.config.mjs,
# _scenario_results.mjs, and _server.sh, which it shares with smoke), and the
# Scenario folder kept out of the gate's steps and the build, on a project made
# from the skeleton (new/) with the fixtures in tests/fixture/scenarios.
#
# The tests that run Node need Node and pnpm; those that install the skeleton's
# packages a primed pnpm store (FACTORY_PNPM_STORE), and those that open a page
# Chromium (FACTORY_PLAYWRIGHT_BROWSERS); each skips without them. The rest run
# with no Node at all.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# scenario <fixture> <path in the folder>: a Scenario fixture
# (tests/fixture/scenarios/<fixture>.ts.txt) at scenarios/<path>.
scenario() {
	add_fixture "scenarios/$1.ts.txt" "scenarios/$2"
}

# app_project: the skeleton, prepared, with the fixture app as its page (a tap
# on Serve serves a ball, a second tap a second one); cd there.
app_project() {
	needs_browser
	skeleton_project
	add_fixture scenarios/page.tsx.txt app/page.tsx
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
}

# stand_in_next: next replaced by smoke's stand-in (tests/fixture/smoke), which
# builds nothing and serves $TEST_TMP/site, its pid in $TEST_TMP/server.pid.
stand_in_next() {
	rm -f node_modules/.bin/next && cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	mkdir -p "$TEST_TMP/site"
	echo '<!doctype html><html><head><title>t</title></head><body><p>hi</p></body></html>' > "$TEST_TMP/site/index.html"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_PID="$TEST_TMP/server.pid"
}

# stand_in <tool> <script>: node_modules/.bin/<tool> replaced by <script>
# (printf %b: \n is a newline).
stand_in() {
	mkdir -p node_modules/.bin && rm -f "node_modules/.bin/$1" &&
		printf '%b' "$2" > "node_modules/.bin/$1" && chmod 755 "node_modules/.bin/$1" || fail "could not stand in for $1"
}

# tree: the project's files, but node_modules/ and .next/.
tree() {
	find . \( -path ./node_modules -o -path ./.next -o -path ./.git \) -prune -o -print | LC_ALL=C sort
}

# drive: the driver, as factory/core/scenarios.sh runs it.
drive() {
	run_cmd bash tools/verify/scenarios
}

# descendants <pid>: the pids of the process's children, theirs, and on down.
descendants() {
	local p
	for p in $(pgrep -P "$1"); do
		echo "$p"
		descendants "$p"
	done
}

# gone <pid...>: none of these is a process any more.
gone() {
	local p
	for p in "$@"; do
		! kill -0 "$p" 2> /dev/null || return 1
	done
}

test_the_adapter_names_a_scenario_folder_no_step_lists() {
	skeleton_project
	run_cmd bash -c '. "$FACTORY_CORE/lib/steps.sh" && . "$FACTORY_CORE/lib/scenarios.sh" && factory_scenario_folder'
	assert_eq scenarios "$out"
	scenario serve serve/_serve.ts
	add_fixture scenarios/serve.ts.txt lib/serve.ts
	run_cmd bash -c '. tools/verify/_nextjs.sh && nx_all_files ts && echo -- && nx_files ts'
	assert_eq "lib/serve.ts
--
lib/serve.ts" "$(printf '%s\n' "$out" | grep -e '^--$' -e serve)" "the files the steps check"
}

test_the_driver_prints_nothing_without_a_scenario() {
	skeleton_project
	stand_in next "#!/usr/bin/env bash\ntouch $(printf '%q' "$TEST_TMP/next.ran")\n"
	drive
	assert_status 0
	assert_eq "" "$out" "no folder"
	scenario serve serve/_serve.ts
	echo "a note" > scenarios/README.md
	drive
	assert_status 0
	assert_eq "" "$out" "a helper and a note are no Scenario"
	rm tools/verify/scenario-folder
	scenario one_ball serve/one_ball.ts
	drive
	assert_status 0
	assert_eq "" "$out" "no folder named"
	[ ! -e "$TEST_TMP/next.ran" ] || fail "the driver ran next with no Scenario"
}

test_the_driver_cannot_run_with_a_bad_limit() {
	skeleton_project
	scenario one_ball serve/one_ball.ts
	FACTORY_SMOKE_TIMEOUT=soon drive
	assert_status 2
	assert_eq "" "$out"
	stderr_has "scenarios: FACTORY_SMOKE_TIMEOUT is 'soon', not a number of seconds from 1 to 999999 (tools/verify/local.env)"
}

# pnpm that fails, then one that installs nothing: the driver could not run them.
test_the_driver_cannot_run_without_its_packages_with_node() {
	needs_node
	skeleton_project
	scenario one_ball serve/one_ball.ts
	mkdir -p "$TEST_TMP/bin"
	printf '#!/usr/bin/env bash\necho "store lacks next" >&2\nexit 1\n' > "$TEST_TMP/bin/pnpm"
	chmod 755 "$TEST_TMP/bin/pnpm"
	PNPM_BIN="$TEST_TMP/bin/pnpm" drive
	assert_status 2
	assert_eq "" "$out"
	stderr_has "store lacks next"
	stderr_has "scenarios: pnpm install --offline --frozen-lockfile exited 1 (above); run bash tools/verify/bootstrap, the step allowed the network, then the Scenarios again"
	printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMP/bin/pnpm"
	PNPM_BIN="$TEST_TMP/bin/pnpm" drive
	assert_status 2
	stderr_has "scenarios: node_modules/.bin/next is not installed"
	stand_in next '#!/usr/bin/env bash\nexit 0\n'
	PNPM_BIN="$TEST_TMP/bin/pnpm" drive
	assert_status 2
	stderr_has "scenarios: node_modules/.bin/playwright is not installed"
}

test_a_missing_browser_cannot_run_the_scenarios_with_node() {
	needs_store
	skeleton_project
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed: $out"
	stand_in_next
	scenario one_ball serve/one_ball.ts
	drive
	assert_status 2
	assert_eq "" "$out"
	stderr_has "scenarios: Chromium didn't start (above); run bash tools/verify/bootstrap"
	[ ! -e "$TEST_TMP/server.pid" ] || fail "the server started with no browser"
}

# A build that fails, a server that won't start: the driver could not run them,
# and the Core reports them not run.
test_a_failed_build_or_start_cannot_run_the_scenarios_with_node() {
	app_project
	scenario one_ball serve/one_ball.ts
	scenario serve serve/_serve.ts
	stand_in next '#!/usr/bin/env bash\necho "build broke" >&2\nexit 2\n'
	drive
	assert_status 2
	assert_eq "" "$out"
	stderr_has "build broke"
	stderr_has "scenarios: next build exited 2 (above)"
	run_cmd bash "$FACTORY_CORE/scenarios.sh"
	assert_status 3
	assert_eq "scenarios: not run: the driver could not run them (it exited 2; its stderr says why)" "$out"

	stand_in next '#!/usr/bin/env bash\ncase "$1" in build) exit 0 ;; esac\necho "port taken" >&2\nexit 3\n'
	drive
	assert_status 2
	stderr_has "port taken"
	stderr_has "scenarios: next start exited 3 before it answered (above)"
}

# Playwright that writes no report: each Scenario is an ERROR, at its line 1.
test_a_run_with_no_report_is_an_error_with_node() {
	app_project
	stand_in_next
	scenario one_ball serve/one_ball.ts
	scenario serve serve/_serve.ts
	scenario crash crash.ts
	stand_in playwright '#!/usr/bin/env bash\necho "no report" >&2\nexit 1\n'
	drive
	assert_status 1
	assert_eq "crash	ERROR	scenarios/crash.ts:1
serve/one_ball	ERROR	scenarios/serve/one_ball.ts:1" "$out"
	stderr_has "scenarios: scenarios/crash.ts: Playwright exited 1 without a report it could read (above)"
	wait_until "the server to stop" eval '! kill -0 "$(cat "$TEST_TMP/server.pid")" 2> /dev/null'
}

# The real app, built and started, and real Scenarios in Chromium: one that
# holds, one the app breaks, one that throws, one that doesn't load (it fails
# alone), one skipped; then the Core's run of them. It starts with no packages
# installed, as the Scenario run's own worktree does.
test_scenarios_pass_and_fail_on_the_app_with_node() {
	app_project
	scenario serve serve/_serve.ts
	scenario one_ball serve/one_ball.ts
	scenario second_tap serve/second_tap.ts
	scenario crash crash.ts
	scenario unloadable unloadable.ts
	scenario skipped skipped.ts
	rm -rf node_modules
	tree > "$TEST_TMP/tree.before"
	drive
	assert_status 1
	assert_eq "crash	ERROR	scenarios/crash.ts:3
serve/one_ball	PASS	scenarios/serve/one_ball.ts:4
serve/second_tap	FAILURE	scenarios/serve/second_tap.ts:10
skipped	SKIP	scenarios/skipped.ts:3
unloadable	ERROR	scenarios/unloadable.ts:7" "$out"
	stderr_has "Received: \"Balls in play: 2\""
	stderr_has "- Local:         http://127.0.0.1:"
	assert_eq "$(cat "$TEST_TMP/tree.before")" "$(tree)" "the tree after the driver, but node_modules/ and .next/"
	[ -x node_modules/.bin/next ] || fail "the driver didn't install the packages"

	run_cmd bash "$FACTORY_CORE/scenarios.sh"
	assert_status 1
	assert_eq "crash	ERROR	scenarios/crash.ts:3
serve/one_ball	PASS	scenarios/serve/one_ball.ts:4
serve/second_tap	FAILURE	scenarios/serve/second_tap.ts:10
skipped	SKIP	scenarios/skipped.ts:3
unloadable	ERROR	scenarios/unloadable.ts:7
scenarios: FAIL: 4 of 5 did not pass" "$out" "the Core's run"

	rm scenarios/serve/second_tap.ts scenarios/crash.ts scenarios/unloadable.ts scenarios/skipped.ts
	run_cmd bash "$FACTORY_CORE/scenarios.sh"
	assert_status 0
	assert_eq "serve/one_ball	PASS	scenarios/serve/one_ball.ts:4
scenarios: PASS: 1 passed" "$out" "the Core's run, every Scenario holding"
}

# driver_apart: the driver in the background, with a Scenario's started and
# release files, its pid in $driver (a global, which the traps below read after
# the test returns; a test clears it once it has reaped the driver), in a process
# group of its own (job control, so it isn't started with INT ignored). test.sh's
# TERM to the test's group misses that group, so the test passes it on, and on
# any exit releases the Scenario, stops the driver and waits for it.
driver_apart() {
	driver=""
	trap '[ -z "$driver" ] || { kill -TERM "$driver" 2> /dev/null; wait "$driver"; }; exit 143' TERM
	trap ': > "$TEST_TMP/release"; [ -z "$driver" ] || { kill -TERM "$driver" 2> /dev/null; wait "$driver"; }' EXIT
	rm -f "$TEST_TMP/started" "$TEST_TMP/release" "$TEST_TMP/child.pid"
	set -m
	SCENARIO_STARTED="$TEST_TMP/started" SCENARIO_RELEASE="$TEST_TMP/release" SCENARIO_CHILD="$TEST_TMP/child.pid" \
		bash tools/verify/scenarios > "$TEST_TMP/driver.out" 2> "$TEST_TMP/driver.err" &
	driver=$!
	set +m
}

# While a Scenario runs, the driver has the server, Playwright, its worker and
# Chromium under it; none outlives a run, or a TERM to the driver. Nor does a
# process a Scenario started and left running.
test_no_process_outlives_a_run_or_a_signal_with_node() {
	app_project
	scenario leaves leaves.ts
	scenario waits waits.ts
	local pids code

	driver_apart
	wait_until "the Scenario to start" test -e "$TEST_TMP/started"
	[ -s "$TEST_TMP/child.pid" ] || fail "the first Scenario left no process"
	wait_until "the process a Scenario left to stop" gone "$(cat "$TEST_TMP/child.pid")"
	pids="$(descendants "$driver")"
	[ "$(printf '%s\n' "$pids" | grep -c .)" -ge 4 ] || fail "too few processes under the driver (the server, Playwright, its worker, Chromium): $pids"
	: > "$TEST_TMP/release"
	wait "$driver"
	code=$?
	driver=""
	assert_eq 0 "$code" "the driver's exit after the release"$'\n'"$(tail -n 20 "$TEST_TMP/driver.err")"
	assert_eq "leaves	PASS	scenarios/leaves.ts:7
waits	PASS	scenarios/waits.ts:6" "$(cat "$TEST_TMP/driver.out")" "the driver's lines"
	# shellcheck disable=SC2086 # one pid a word
	wait_until "every process of the run to stop" gone $pids

	driver_apart
	wait_until "the Scenario to start again" test -e "$TEST_TMP/started"
	pids="$(descendants "$driver")"
	kill -TERM "$driver"
	wait_until "the driver to exit on TERM" eval '! kill -0 "$driver" 2> /dev/null'
	wait "$driver"
	code=$?
	driver=""
	assert_eq 143 "$code" "the driver's exit on TERM"
	assert_eq "" "$(cat "$TEST_TMP/driver.out")" "the driver's lines on TERM"
	# shellcheck disable=SC2086 # one pid a word
	wait_until "every process of the run to stop on TERM" gone $pids
}

# The Scenario folder holds a file each gate step would fail; no step reaches it,
# nor does next build. prepare finds a tsconfig.json or Vitest config that would.
test_no_gate_step_or_the_build_reaches_the_scenario_folder_with_node() {
	needs_store
	skeleton_project
	scenario stray.test reach/stray.test.ts
	step prepare
	assert_status 0
	assert_eq "" "$out" "prepare's findings"
	local s
	for s in format typecheck lint test arch; do
		FACTORY_RESULTS_FILE="$TEST_TMP/results" step "$s"
		[ "$status" -eq 0 ] && [ -z "$out" ] || fail "$s reached the Scenario folder: status $status: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	done
	! grep -q scenarios "$TEST_TMP/results" || fail "the test step ran a Scenario: $(cat "$TEST_TMP/results")"
	run_cmd node_modules/.bin/next build
	[ "$status" -eq 0 ] || fail "next build reached the Scenario folder: $(tail -n 20 "$TEST_TMP/stderr")"

	sed -i 's/, "scenarios"\]/]/' tsconfig.json
	sed -i '\#"scenarios/\*\*",#d' vitest.config.ts
	step prepare
	assert_status 1
	assert_eq "tsconfig.json:$(grep -n '"exclude"' tsconfig.json | cut -d: -f1) scenario-not-ignored tsc compiles scenarios/reach/stray.test.ts, in the Scenario folder, so typecheck and next build would read it; add \"scenarios\" to tsconfig.json's exclude
vitest.config.ts:$(grep -n 'exclude' vitest.config.ts | head -n 1 | cut -d: -f1) scenario-not-ignored Vitest would run scenarios/reach/stray.test.ts, in the Scenario folder, as a test; add \"scenarios/**\" to its test.exclude" "$out" "prepare's findings without the exclusions"

	# An issue's worktree leaves the folder out: nothing on disk, nothing found.
	rm -r scenarios
	step prepare
	assert_status 0
	assert_eq "" "$out" "prepare with the folder left out"
}

# The report reader, on reports Playwright writes: a load error at its line in
# the Scenario, one in a helper (line 1), none located, nothing reported, and a
# file that is no report.
test_the_reader_places_errors_outside_every_test_with_node() {
	needs_node
	local reader="$NEXTJS_ADAPTER/tools/verify/_scenario_results.mjs" f=/p/scenarios/a.ts
	printf '{"suites":[],"errors":[{"message":"Error: x","location":{"file":"%s","line":7}},{"message":"Error: No tests found"}]}' "$f" > "$TEST_TMP/r.json"
	run_cmd node "$reader" "$TEST_TMP/r.json" "$f"
	assert_eq "ERROR	7" "$out" "a load error in the Scenario"
	printf '{"suites":[],"errors":[{"message":"Error: x","location":{"file":"/p/scenarios/_h.ts","line":4}},{"message":"Error: No tests found"}]}' > "$TEST_TMP/r.json"
	run_cmd node "$reader" "$TEST_TMP/r.json" "$f"
	assert_eq "ERROR	1" "$out" "a load error in a helper"
	# expect's failures, as Playwright writes them: alone, after the message a
	# script gave, and a thrown error that only names expect.
	local plain='Error: expect(received).toBe(expected) // Object.is equality\n\nExpected: 2'
	local given='Error: two balls\n\nexpect(received).toBe(expected) // Object.is equality\n'
	local thrown='Error: expect(this) is no assertion\n\n  6 | test()'
	local m
	for m in "$plain:FAILURE" "$given:FAILURE" "$thrown:ERROR"; do
		printf '{"suites":[{"specs":[{"line":4,"tests":[{"status":"unexpected","results":[{"status":"failed","errors":[{"message":"%s"}]}]}]}]}],"errors":[]}' "${m%:*}" > "$TEST_TMP/r.json"
		run_cmd node "$reader" "$TEST_TMP/r.json" "$f"
		assert_eq "${m##*:}	4" "$out" "the failure: ${m%:*}"
	done
	echo '{"suites":[],"errors":[]}' > "$TEST_TMP/r.json"
	run_cmd node "$reader" "$TEST_TMP/r.json" "$f"
	assert_eq "ERROR	1" "$out" "nothing reported"
	printf '{"suites":[{"specs":[{"line":3,"tests":[{"status":"expected","results":[{"status":"passed"}]}]},{"line":9,"tests":[{"status":"unexpected","results":[{"status":"failed","errors":[{"message":"\\u001b[31mError: expect(locator).toHaveText(expected) failed"}]}]}]}],"suites":[{"specs":[{"line":12,"tests":[{"status":"unexpected","results":[{"status":"timedOut","errors":[{"message":"Test timeout of 30000ms exceeded."}]}]}]},{"line":15,"tests":[{"status":"skipped","results":[{"status":"skipped"}]}]}]}]}],"errors":[]}' > "$TEST_TMP/r.json"
	run_cmd node "$reader" "$TEST_TMP/r.json" "$f"
	assert_eq "ERROR	12" "$out" "a timeout is worse than a failed check"
	echo 'not json' > "$TEST_TMP/r.json"
	run_cmd node "$reader" "$TEST_TMP/r.json" "$f"
	assert_status 2
}
