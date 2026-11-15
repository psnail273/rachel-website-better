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

# routes <line...>: ARCHITECTURE.md's Routes table holds these lines alone.
routes() {
	{
		printf '# Architecture\n\n## Routes\n\n```\n'
		printf '%s\n' "$@"
		printf '```\n\n## Modules\n'
	} > ARCHITECTURE.md
}

# app_project: the skeleton, prepared, with the fixture app as its page (a tap
# on Serve serves a ball, a second tap a second one), and no page route in
# ARCHITECTURE.md, so the run has no looks; cd there.
app_project() {
	needs_browser
	skeleton_project
	routes '/api/health  app/api/health/route.ts  route handler (GET)'
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

# free_port: a port no process listens on now, on 127.0.0.1.
free_port() {
	node -e 'const s = require("node:net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); });'
}

# feed_project: the skeleton, with stand-ins for pnpm, next (smoke's, which
# appends `<command>|FEED_URL|CACHE_PATH|FLAG` to $TEST_TMP/next.log),
# Playwright (tests/fixture/scenarios/playwright.mjs.txt, which logs to
# $TEST_TMP/playwright.log) and @playwright/test, so the driver runs with Node
# alone; the fixture server's port, free, in $port and
# FACTORY_SCENARIO_FIXTURE_PORT; no page route in ARCHITECTURE.md, so the run
# has no looks; cd there.
feed_project() {
	needs_node
	skeleton_project
	routes '/api/health  app/api/health/route.ts  route handler (GET)'
	mkdir -p "$TEST_TMP/bin" node_modules/.bin node_modules/@playwright/test
	printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMP/bin/pnpm" && chmod 755 "$TEST_TMP/bin/pnpm" || fail "could not stand in for pnpm"
	stand_in_next
	mv node_modules/.bin/next "$TEST_TMP/next.mjs" || fail "could not move next's stand-in"
	stand_in next "#!/usr/bin/env bash\nprintf '%s|%s|%s|%s\\\\n' \"\$1\" \"\$FEED_URL\" \"\$CACHE_PATH\" \"\$FLAG\" >> $(printf '%q' "$TEST_TMP/next.log")\nexec node $(printf '%q' "$TEST_TMP/next.mjs") \"\$@\"\n"
	add_fixture scenarios/playwright.mjs.txt node_modules/.bin/playwright
	chmod 755 node_modules/.bin/playwright
	add_fixture scenarios/playwright-test.mjs.txt node_modules/@playwright/test/index.js
	echo '{"name":"@playwright/test","type":"module","exports":"./index.js"}' > node_modules/@playwright/test/package.json
	port="$(free_port)"
	[ -n "$port" ] || fail "no free port"
	export PNPM_BIN="$TEST_TMP/bin/pnpm" STAND_IN_LOG="$TEST_TMP/playwright.log" FACTORY_SCENARIO_FIXTURE_PORT="$port"
}

# port_free <port>: nothing listens on it.
port_free() {
	node -e 'require("node:net").createServer().on("error", () => process.exit(1)).listen(Number(process.argv[1]), "127.0.0.1", function () { this.close(); });' "$1"
}

# scenario-env's lines are the app's env for next build, next start and each
# Playwright run, {fixtures} the fixture server and {state} the run's own
# folder. A Scenario puts and deletes what the server serves; before each file
# the driver empties both, and when it exits the server and the folder are gone.
test_scenario_env_gives_the_app_a_fixture_feed_and_state_with_node() {
	feed_project
	scenario feed_first feed/first.ts
	scenario feed_second feed/second.ts
	printf '%s\n' '' '# the feed and the cache' 'FEED_URL={fixtures}/calendar.ics' 'CACHE_PATH={state}/events.sqlite' \
		'FLAG=a b=c & \1 {state}' >> tools/verify/scenario-env
	drive
	assert_status 0
	assert_eq "feed/first	PASS	scenarios/feed/first.ts:16
feed/second	PASS	scenarios/feed/second.ts:6" "$out" "the driver's lines"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	local feed="http://127.0.0.1:$port/calendar.ics" cache state
	cache="$(head -n 1 "$TEST_TMP/playwright.log" | cut -d'|' -f2)"
	state="${cache%/events.sqlite}"
	[ "$state" != "$cache" ] && [ -n "$state" ] || fail "CACHE_PATH is not {state}/events.sqlite: $cache"
	assert_eq "$feed|$cache|a b=c & \\1 $state|http://127.0.0.1:$port
$feed|$cache|a b=c & \\1 $state|http://127.0.0.1:$port" "$(cat "$TEST_TMP/playwright.log")" "the env of each Playwright run"
	assert_eq "build|$feed|$cache|a b=c & \\1 $state
start|$feed|$cache|a b=c & \\1 $state" "$(cat "$TEST_TMP/next.log")" "the env of next build and next start"
	[ ! -e "$state" ] || fail "the state folder outlived the run: $state"
	port_free "$port" || fail "the fixture server outlived the run, on port $port"
}

# With no scenario-env line naming {fixtures}, no fixture server starts, and the
# app gets no env of the driver's.
test_no_fixture_server_without_fixtures_in_scenario_env_with_node() {
	feed_project
	scenario feed_second feed/second.ts
	FACTORY_SCENARIO_FIXTURE_PORT=bad drive
	assert_status 1
	assert_eq "feed/second	FAILURE	scenarios/feed/second.ts:6" "$out" "a Scenario with no feed to ask"
	assert_eq "build|||
start|||" "$(cat "$TEST_TMP/next.log")" "the env of next build and next start"
	assert_eq "|||" "$(cat "$TEST_TMP/playwright.log")" "the env of the Playwright run"
}

# A port another Scenario run's fixture server holds: the driver can't run them,
# and says so before it builds.
test_a_taken_fixture_port_cannot_run_the_scenarios_with_node() {
	feed_project
	scenario feed_second feed/second.ts
	echo 'FEED_URL={fixtures}/calendar.ics' >> tools/verify/scenario-env
	local holder
	node tools/verify/_scenario_fixtures.mjs "$port" "$TEST_TMP/held" > "$TEST_TMP/held.log" 2>&1 < /dev/null &
	holder=$!
	trap 'kill "$holder" 2> /dev/null; wait "$holder"' EXIT
	wait_until "the other run's fixture server to listen" grep -qx "listening on http://127.0.0.1:$port" "$TEST_TMP/held.log"
	drive
	assert_status 2
	assert_eq "" "$out"
	stderr_has "fixtures: listen EADDRINUSE"
	stderr_has "scenarios: the fixture server exited 1 before it listened on 127.0.0.1:$port (above): another Scenario run may hold the port; FACTORY_SCENARIO_FIXTURE_PORT in tools/verify/local.env names another"
	[ ! -e "$TEST_TMP/next.log" ] || fail "the driver built with no fixture server: $(cat "$TEST_TMP/next.log")"
}

# Each target is a fixture of its own, whatever its name: putting one leaves
# another alone, also one named like a PUT's staged file (/feed.ics.new).
test_each_fixture_target_stands_alone_with_node() {
	needs_node
	local port server
	port="$(free_port)"
	node "$NEXTJS_ADAPTER/tools/verify/_scenario_fixtures.mjs" "$port" "$TEST_TMP/fixtures" > "$TEST_TMP/fixtures.log" 2>&1 < /dev/null &
	server=$!
	trap 'kill "$server" 2> /dev/null; wait "$server"' EXIT
	wait_until "the fixture server to listen" grep -qx "listening on http://127.0.0.1:$port" "$TEST_TMP/fixtures.log"
	cp "$NEXTJS_FIXTURES/scenarios/fixture-requests.mjs.txt" "$TEST_TMP/requests.mjs" || fail "could not copy the requests"
	run_cmd node "$TEST_TMP/requests.mjs" "http://127.0.0.1:$port"
	assert_status 0
	assert_eq "PUT /feed.ics.new 204 
PUT /feed.ics 204 
GET /feed.ics.new 200 X
GET /feed.ics 200 Y
DELETE /feed.ics 204 
GET /feed.ics.new 200 X
GET /feed.ics 404 " "$out" "each target's answers"
}

# A scenario-env line that isn't NAME=value, or names one of the driver's own;
# a fixture port that isn't a port, when a line names {fixtures}.
test_a_bad_scenario_env_cannot_run_the_scenarios() {
	skeleton_project
	scenario one_ball serve/one_ball.ts
	local base line n p
	base="$(cat tools/verify/scenario-env)"
	n="$(($(wc -l < tools/verify/scenario-env) + 2))"
	for line in 'feed_url=x' 'FEED_URL' ' FEED_URL=x' '1FEED=x' 'FACTORY_SCENARIO_FIXTURES=x' 'NX_LIMIT=9'; do
		printf '%s\n\n%s\n' "$base" "$line" > tools/verify/scenario-env
		drive
		assert_status 2
		assert_eq "" "$out"
		assert_eq "scenarios: tools/verify/scenario-env:$n: '$line' is not NAME=value, NAME in capitals, digits and _, and none of the driver's own (NX_*, FACTORY_*)" "$(cat "$TEST_TMP/stderr")" "the line '$line'"
	done
	echo 'FEED_URL={fixtures}/feed.ics' > tools/verify/scenario-env
	for p in 0 65536 0080 8o 1234567 ' 80'; do
		FACTORY_SCENARIO_FIXTURE_PORT="$p" drive
		assert_status 2
		assert_eq "scenarios: FACTORY_SCENARIO_FIXTURE_PORT is '$p', not a port from 1 to 65535 (tools/verify/local.env)" "$(cat "$TEST_TMP/stderr")" "the port '$p'"
	done
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

# The driver takes one argument, record, or none; record needs the Scenario
# folder named and in the checkout, which an issue's worktree leaves out.
test_the_driver_refuses_an_unknown_argument_and_a_record_without_the_folder() {
	skeleton_project
	run_cmd bash tools/verify/scenarios update
	assert_status 2
	assert_eq "" "$out"
	stderr_has "usage: bash tools/verify/scenarios [record]"
	run_cmd bash tools/verify/scenarios record
	assert_status 2
	stderr_has "scenarios: record: this checkout has no scenarios/ (an issue's worktree leaves it out): record from a checkout of dev (factory-run's playtest.md)"
	[ ! -e scenarios ] || fail "record made the Scenario folder"
	rm tools/verify/scenario-folder
	run_cmd bash tools/verify/scenarios record
	assert_status 2
	stderr_has "scenarios: record: the project names no Scenario folder (tools/verify/scenario-folder), where the looks' baselines go"
}

# looks_project: app_project's packages, next standing in to serve $TEST_TMP/site
# with a page at / and at /about, both page routes of ARCHITECTURE.md, a
# Scenario that holds, and the real Playwright behind a stand-in that appends
# its arguments to $TEST_TMP/playwright.log; cd there.
looks_project() {
	app_project
	stand_in_next
	routes '/  app/page.tsx  Home' '/about  app/about/page.tsx  About' '/api/health  app/api/health/route.ts  route handler (GET)'
	mkdir -p "$TEST_TMP/site/about" scenarios
	echo '<!doctype html><html><head><title>t</title></head><body><h1>About</h1></body></html>' > "$TEST_TMP/site/about/index.html"
	printf '%s\n' 'import { expect, test } from "@playwright/test";' \
		'test("holds", async ({ page }) => { await page.goto("/"); await expect(page.locator("p")).toHaveText("hi"); });' > scenarios/holds.ts
	cp node_modules/.bin/playwright node_modules/.bin/playwright.real || fail "could not keep Playwright"
	stand_in playwright "#!/usr/bin/env bash\necho \"\$*\" >> $(printf '%q' "$TEST_TMP/playwright.log")\nexec \"\$(dirname \"\$0\")/playwright.real\" \"\$@\"\n"
}

# files_in <dir>: the names of the folder's files, one a line, sorted.
files_in() {
	local f
	for f in "$1"/*; do
		[ ! -e "$f" ] || basename "$f"
	done | LC_ALL=C sort
}

# looks_lines <verdict> <name...>: the looks' results lines for these names, each
# with <verdict>.
looks_lines() {
	local verdict="$1" name
	shift
	for name in "$@"; do
		printf 'looks/%s\t%s\tscenarios/looks/%s.png:1\n' "$name" "$verdict" "$name"
	done
}

# Each page route's look, at 390 and 1280 px, light and dark, against its
# baseline in scenarios/looks/: a normal run never records one (no
# --update-snapshots), so a missing one fails the run, saying the next approved
# Playtest records it; record mode writes them, and a later run passes; a page
# that changes fails its looks, with the images in the git dir; a route gone
# takes its baselines with it at the next record.
test_each_page_route_looks_as_its_baseline_with_node() {
	looks_project
	local all=(about-1280-dark about-1280-light about-390-dark about-390-light home-1280-dark home-1280-light home-390-dark home-390-light)
	local about=(about-1280-dark about-1280-light about-390-dark about-390-light)
	local home=(home-1280-dark home-1280-light home-390-dark home-390-light)
	local holds=$'holds\tPASS\tscenarios/holds.ts:2'
	tree > "$TEST_TMP/tree.before"

	drive
	assert_status 1
	assert_eq "$(looks_lines SKIP "${all[@]}")"$'\n'"$holds" "$out" "a run with no baselines"
	local shots
	shots="$(git rev-parse --absolute-git-dir)/factory/looks"
	stderr_has "scenarios: looks/home-390-light: no baseline at scenarios/looks/home-390-light.png: the next Playtest the human approves records it (bash tools/verify/scenarios record); the page now: $shots/home-390-light-actual.png"
	assert_eq "$(printf '%s-actual.png\n' "${all[@]}")" "$(files_in "$shots")" "the pages now, for the human"
	assert_eq "390" "$(od -An -tu1 -j16 -N4 "$shots/home-390-light-actual.png" | awk '{ print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }')" "the page now's width"
	assert_eq "$(cat "$TEST_TMP/tree.before")" "$(tree)" "the tree after a run with no baselines"
	! grep -q -- --update-snapshots "$TEST_TMP/playwright.log" || fail "a normal run passed --update-snapshots: $(cat "$TEST_TMP/playwright.log")"

	run_cmd bash "$FACTORY_CORE/scenarios.sh"
	assert_status 1
	assert_eq "$(looks_lines SKIP "${all[@]}")"$'\n'"$holds"$'\n'"scenarios: FAIL: 8 of 9 did not pass" "$out" "the Core's run with no baselines"

	: > "$TEST_TMP/playwright.log"
	run_cmd bash tools/verify/scenarios record
	assert_status 0
	assert_eq "$(looks_lines PASS "${all[@]}")" "$out" "record mode"
	assert_eq "$(printf '%s.png\n' "${all[@]}")" "$(files_in scenarios/looks)" "the baselines recorded"
	grep -q -- "--update-snapshots=changed" "$TEST_TMP/playwright.log" || fail "record mode didn't pass --update-snapshots=changed: $(cat "$TEST_TMP/playwright.log")"

	: > "$TEST_TMP/playwright.log"
	drive
	assert_status 0
	assert_eq "$(looks_lines PASS "${all[@]}")"$'\n'"$holds" "$out" "a run with every baseline"
	! grep -q -- --update-snapshots "$TEST_TMP/playwright.log" || fail "a normal run passed --update-snapshots: $(cat "$TEST_TMP/playwright.log")"

	echo '<!doctype html><html><head><title>t</title></head><body><h1 style="font-size:80px">Changed</h1></body></html>' > "$TEST_TMP/site/about/index.html"
	cp -R scenarios/looks "$TEST_TMP/looks.before"
	drive
	assert_status 1
	assert_eq "$(looks_lines FAILURE "${about[@]}")"$'\n'"$(looks_lines PASS "${home[@]}")"$'\n'"$holds" "$out" "a run with a changed page"
	assert_eq "about-390-light-actual.png
about-390-light-diff.png
about-390-light-expected.png" "$(files_in "$shots" | grep '^about-390-light-')" "the changed look's images"
	stderr_has "scenarios: looks/about-390-light: the page doesn't look as its baseline scenarios/looks/about-390-light.png does: see $shots/about-390-light-expected.png, -actual.png and -diff.png"
	diff -r "$TEST_TMP/looks.before" scenarios/looks > /dev/null || fail "a failing run changed the baselines"

	routes '/  app/page.tsx  Home'
	run_cmd bash tools/verify/scenarios record
	assert_status 0
	assert_eq "$(looks_lines PASS "${home[@]}")" "$out" "record mode with /about gone"
	assert_eq "$(printf '%s.png\n' "${home[@]}")" "$(files_in scenarios/looks)" "the baselines after /about went"
	stderr_has "scenarios: record: removed scenarios/looks/about-390-light.png: no route has that look now"
}
