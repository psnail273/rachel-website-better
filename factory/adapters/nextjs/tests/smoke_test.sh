# The Next.js smoke step (tools/verify/smoke, _smoke_page.mjs) and bootstrap's
# browser. The step's logic (the port, the wait and its limit, stopping the
# server, the findings) runs against stand-ins for next: a small server serving a
# folder of pages (tests/fixture/smoke/next.mjs), or a bash one around
# blocking_stand_in. The real next build and next start run in adopt_test.sh's
# end to end, on the skeleton.
#
# The tests that load a page need Node, pnpm, a primed pnpm store
# (FACTORY_PNPM_STORE) and Chromium (FACTORY_PLAYWRIGHT_BROWSERS), and skip
# without them; the rest need Node alone.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# site_project: skeleton_project with its packages installed (prepare), and
# next replaced by the stand-in serving $TEST_TMP/site; cd there. The stand-in
# writes its pid to $TEST_TMP/server.pid.
site_project() {
	skeleton_project
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed on the skeleton: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	rm -f node_modules/.bin/next && cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	mkdir -p "$TEST_TMP/site/api"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_PID="$TEST_TMP/server.pid"
}

# page <html>: the site's `/`.
page() {
	printf '<!doctype html><html><head><title>t</title></head><body><p>hi</p>%s</body></html>\n' "$1" > "$TEST_TMP/site/index.html"
}

# blocking_project [prefix]: skeleton_project (nothing installed) with a next
# whose build passes and whose start runs <prefix> (bash), then blocks: a
# blocking_stand_in at $TEST_TMP/server, its pid in $TEST_TMP/server.pid,
# released by $TEST_TMP/release.
blocking_project() {
	needs_node
	skeleton_project
	blocking_stand_in "$TEST_TMP/server" "$TEST_TMP/release"
	mkdir -p node_modules/.bin
	printf '#!/usr/bin/env bash\ncase "$1" in build) exit 0 ;; esac\n%s\nexec %q\n' "${1:-}" "$TEST_TMP/server" > node_modules/.bin/next
	chmod 755 node_modules/.bin/next
}

# server_gone: the stand-in server's pid is no process.
server_gone() {
	[ -s "$TEST_TMP/server.pid" ] && ! kill -0 "$(cat "$TEST_TMP/server.pid")" 2> /dev/null
}

# smoke_and_server_gone <what>: run the step, then wait for the server to be gone.
smoke_and_server_gone() {
	rm -f "$TEST_TMP/server.pid"
	step smoke
	wait_until "the server to stop after $1" server_gone
}

test_a_clean_page_passes_and_its_server_stops_with_node() {
	needs_browser
	site_project
	page ''
	smoke_and_server_gone "a clean page"
	assert_status 0
	assert_eq "" "$out" "smoke's findings"
	stderr_has "- Local:         http://127.0.0.1:"
}

test_each_fault_on_the_page_is_a_finding_and_the_server_stops_with_node() {
	needs_browser
	site_project
	page '<script>console.error("boom")</script>'
	smoke_and_server_gone "a console error"
	assert_status 1
	assert_eq "package.json:1 smoke-console /: console error: boom" "$out" "a console error"

	page '<script>throw new Error("kaput")</script>'
	smoke_and_server_gone "a page error"
	assert_status 1
	assert_eq "package.json:1 smoke-page-error /: uncaught Error: kaput" "$out" "an uncaught error"

	page '<script>fetch("/api/fail")</script>'
	echo failed > "$TEST_TMP/site/api/fail"
	echo 500 > "$TEST_TMP/site/api/fail.status"
	smoke_and_server_gone "a route answering 500"
	assert_status 1
	assert_eq "package.json:1 smoke-console /: console error: Failed to load resource: the server responded with a status of 500 (Internal Server Error)
package.json:1 smoke-response /: /api/fail answered 500" "$out" "a request answered 500"

	page ''
	echo 503 > "$TEST_TMP/site/index.html.status"
	smoke_and_server_gone "a page answering 503"
	assert_status 1
	assert_eq "package.json:1 smoke-console /: console error: Failed to load resource: the server responded with a status of 503 (Service Unavailable)
package.json:1 smoke-response /: / answered 503" "$out" "the page answered 503"
}

# A redirect is followed and its target judged; a 3xx with no Location is no
# redirect.
test_a_redirect_passes_and_its_target_is_judged_with_node() {
	needs_browser
	site_project
	page '<script>fetch("/api/moved")</script>'
	echo moved > "$TEST_TMP/site/api/moved"
	echo 307 > "$TEST_TMP/site/api/moved.status"
	echo /api/here > "$TEST_TMP/site/api/moved.location"
	echo here > "$TEST_TMP/site/api/here"
	smoke_and_server_gone "a redirect"
	assert_status 0
	assert_eq "" "$out" "a redirect to a 200"

	echo 404 > "$TEST_TMP/site/api/here.status"
	smoke_and_server_gone "a redirect to a 404"
	assert_status 1
	assert_line "package.json:1 smoke-response /: /api/here answered 404"
	assert_no_line "package.json:1 smoke-response /: /api/moved answered 307"

	rm "$TEST_TMP/site/api/moved.location"
	smoke_and_server_gone "a 3xx with no Location"
	assert_status 1
	assert_line "package.json:1 smoke-response /: /api/moved answered 307"
}

test_a_missing_browser_is_a_finding_and_the_server_stops_with_node() {
	needs_store
	site_project
	page ''
	smoke_and_server_gone "a missing browser"
	assert_status 1
	[[ $out == "tools/verify/local.env:1 browser-missing Chromium didn't start ("*"); run bash tools/verify/bootstrap, which installs it into PLAYWRIGHT_BROWSERS_PATH (tools/verify/local.env), and if it names missing system libraries: pnpm exec playwright install-deps chromium" ]] ||
		fail "smoke's finding: $out"
}

test_a_failed_build_is_a_finding_with_node() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin
	printf '#!/usr/bin/env bash\necho "build broke" >&2\nexit 2\n' > node_modules/.bin/next
	chmod 755 node_modules/.bin/next
	step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-build next build exited 2 (see stderr)" "$out" "smoke's finding"
	stderr_has "build broke"
}

test_a_server_that_exits_before_it_answers_is_a_finding_with_node() {
	blocking_project 'echo "port taken" >&2; exit 3'
	step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-start next start exited 3 before it answered (see stderr)" "$out" "smoke's finding"
	stderr_has "port taken"
}

# The server's leader exits, the server it started runs on, in its group: the
# step stops that too.
test_a_server_that_exits_leaving_a_child_is_stopped_too_with_node() {
	blocking_project "$(printf '%q' "$TEST_TMP/server") & echo \$! > $(printf '%q' "$TEST_TMP/server.pid"); exit 3"
	step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-start next start exited 3 before it answered (see stderr)" "$out" "smoke's finding"
	wait_until "the server's child to stop" server_gone
}

test_a_server_that_never_answers_is_stopped_at_the_limit_with_node() {
	blocking_project
	FACTORY_SMOKE_TIMEOUT=1 step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-start next start didn't answer within 1s (FACTORY_SMOKE_TIMEOUT in tools/verify/local.env)" "$out" "smoke's finding"
	wait_until "the server to stop" server_gone
}

test_a_server_that_ignores_term_is_killed_at_the_limit_with_node() {
	blocking_project "trap '' TERM"
	FACTORY_SMOKE_TIMEOUT=1 step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-start next start didn't answer within 1s (FACTORY_SMOKE_TIMEOUT in tools/verify/local.env)" "$out" "smoke's finding"
	wait_until "the server to be killed" server_gone
}

# A TERM while the step stops its server (one that ignores TERM, so the stop
# waits out the limit) doesn't cut the stop short: the server is killed and
# reaped before the step exits.
test_a_signal_while_the_step_stops_its_server_waits_for_the_stop_with_node() {
	blocking_project "trap '' TERM"
	local pid code=0
	FACTORY_SMOKE_TIMEOUT=3 bash tools/verify/smoke > "$TEST_TMP/smoke.out" 2> "$TEST_TMP/smoke.err" &
	pid=$!
	# The finding is printed as the step goes on to stop the server.
	wait_until "the step to give up on the server" grep -q "didn't answer" "$TEST_TMP/smoke.out"
	kill -TERM "$pid"
	kill -TERM "$pid"
	wait "$pid" || code=$?
	server_gone || fail "the server outlived the step (it exited $code)"
}

# smoke_apart: the step in the background with FACTORY_SMOKE_TIMEOUT=600, its
# pid in $smoke (a global, which the traps below read after the test returns;
# a test clears it once it has reaped the step), in a process group of its own (job control, so it isn't started
# with INT ignored, as a background command otherwise is). test.sh's TERM to the
# test's group misses that group, so the test passes it on, and on any exit
# stops the step and waits for it.
smoke_apart() {
	smoke=""
	trap '[ -z "$smoke" ] || { kill -TERM "$smoke" 2> /dev/null; wait "$smoke"; }; exit 143' TERM
	trap '[ -z "$smoke" ] || { kill -TERM "$smoke" 2> /dev/null; wait "$smoke"; }' EXIT
	set -m
	FACTORY_SMOKE_TIMEOUT=600 bash tools/verify/smoke > "$TEST_TMP/smoke.out" 2> "$TEST_TMP/smoke.err" &
	smoke=$!
	set +m
}

# Stopped while it waits for the server, by TERM or INT, the step stops it too.
test_a_signal_to_the_step_stops_its_server_with_node() {
	blocking_project
	local sig code
	for sig in TERM INT; do
		rm -f "$TEST_TMP/server.pid"
		smoke_apart
		wait_until "the server to start" test -s "$TEST_TMP/server.pid"
		kill -"$sig" "$smoke"
		wait_until "the step to exit on $sig" eval '! kill -0 "$smoke" 2> /dev/null'
		wait "$smoke"
		code=$?
		smoke=""
		[ "$sig" = TERM ] && assert_eq 143 "$code" "the step's exit on TERM"
		[ "$sig" = INT ] && assert_eq 130 "$code" "the step's exit on INT"
		wait_until "the server to stop on $sig" server_gone
	done
}

# descendants <pid>: the pids of the process's children, theirs, and on down.
descendants() {
	local p
	for p in $(pgrep -P "$1"); do
		echo "$p"
		descendants "$p"
	done
}

# Stopped while the browser waits on the page, the step stops the browser and
# the server: nothing it started outlives it.
test_a_signal_while_the_page_loads_leaves_no_process_with_node() {
	needs_browser
	site_project
	page ''
	: > "$TEST_TMP/site/index.html.hang"
	local pids p
	smoke_apart
	wait_until "the page's request" test -e "$TEST_TMP/site/index.html.hit"
	pids="$(descendants "$smoke")"
	[ "$(printf '%s\n' "$pids" | grep -c .)" -ge 3 ] || fail "too few processes under the step (the server, node and Chromium): $pids"
	kill -TERM "$smoke"
	wait_until "the step to exit" eval '! kill -0 "$smoke" 2> /dev/null'
	wait "$smoke"
	assert_eq 143 "$?" "the step's exit on TERM"
	smoke=""
	for p in $pids; do
		wait_until "process $p ($(ps -o comm= -p "$p" 2> /dev/null)) to stop" eval '! kill -0 "$p" 2> /dev/null'
	done
	server_gone || fail "the server outlived the step"
}

# The limit is whole seconds, read as decimal: a leading 0 is no octal.
test_the_limit_must_be_seconds_with_node() {
	blocking_project 'exit 3'
	local v
	for v in soon 0 000 -1 1.5 1234567; do
		FACTORY_SMOKE_TIMEOUT="$v" step smoke
		assert_status 1
		assert_eq "tools/verify/local.env:1 smoke-setting FACTORY_SMOKE_TIMEOUT is '$v', not a number of seconds from 1 to 999999" "$out" "smoke's finding for '$v'"
	done
	FACTORY_SMOKE_TIMEOUT=08 step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-start next start exited 3 before it answered (see stderr)" "$out" "smoke's finding with a limit of 08"
}

# bootstrap installs the pinned Playwright's Chromium where local.env says, and
# fetches nothing when it is there (the download host is a dead port).
test_bootstrap_installs_the_browser_where_local_env_says_with_node() {
	needs_browser
	skeleton_project
	echo "PLAYWRIGHT_BROWSERS_PATH=$FACTORY_PLAYWRIGHT_BROWSERS" > tools/verify/local.env
	run_cmd env -u PLAYWRIGHT_BROWSERS_PATH bash -c 'set -a; . tools/verify/local.env; set +a; bash tools/verify/bootstrap'
	[ "$status" -eq 0 ] || fail "bootstrap exited $status:"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	assert_eq "" "$out" "bootstrap's stdout"
	[ -x node_modules/.bin/next ] || fail "next isn't installed"

	: > tools/verify/local.env
	PLAYWRIGHT_BROWSERS_PATH="$TEST_TMP/empty" step bootstrap
	assert_status 1
	stderr_has "bootstrap: playwright install --only-shell chromium exited 1 (into $TEST_TMP/empty)"
}
