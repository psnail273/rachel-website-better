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

# page <html> [route]: the site's page at <route> (default `/`), a page axe
# finds nothing on but what <html> brings.
page() {
	mkdir -p "$TEST_TMP/site${2:-/}"
	printf '<!doctype html><html lang="en"><head><title>t</title></head><body><p>hi</p>%s</body></html>\n' "$1" > "$TEST_TMP/site${2:-/}/index.html"
}

# routes <line...>: ARCHITECTURE.md's Routes table holds these lines alone.
routes() {
	{
		printf '# Architecture\n\n## Routes\n\n```\n'
		printf '%s\n' "$@"
		printf '```\n\n## Modules\n'
	} > ARCHITECTURE.md
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

# Every page route in the table is loaded, in both schemes; the method line, the
# route handler and the dynamic route aren't (the last with a note).
test_every_page_route_in_the_table_is_loaded_with_node() {
	needs_browser
	site_project
	routes '/  app/page.tsx  Home' '/about  app/about/page.tsx  About' \
		'POST /api/x  app/api/x/route.ts  no page' '/api/health  app/api/health/route.ts  handler' \
		'/blog/[slug]  app/blog/[slug]/page.tsx  dynamic'
	page ''
	page '<script>console.error("boom")</script>' /about
	smoke_and_server_gone "two routes"
	assert_status 1
	assert_eq "package.json:1 smoke-console /about: console error: boom" "$out" "the second route's finding"
	stderr_has "routes: left out /blog/[slug]: a dynamic segment can't be loaded without a value"
}

# axe runs on each route in each scheme: a fault in both is a finding for each,
# one that shows in the dark scheme alone a finding for that one.
test_an_accessibility_fault_is_a_finding_in_its_scheme_with_node() {
	needs_browser
	site_project
	page '<input type="text">'
	smoke_and_server_gone "an unlabelled input"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / dark label input: Form elements must have labels
package.json:1 smoke-a11y / light label input: Form elements must have labels" "$out" "an unlabelled input"

	page '<style>@media (prefers-color-scheme: dark) { p { color: #777; background: #888 } }</style>'
	smoke_and_server_gone "a contrast fault in the dark"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / dark color-contrast p: Elements must meet minimum color contrast ratio thresholds" "$out" "a fault in the dark scheme alone"

	# A list's items are one finding, however many the page's data makes: the
	# selector names no position.
	local item='<li class="card"><input class="field" type="text" style="height:32px;margin:8px"></li>'
	page "<ul>$item$item$item</ul>"
	smoke_and_server_gone "three faulty items"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / dark label li.card > input.field: Form elements must have labels
package.json:1 smoke-a11y / light label li.card > input.field: Form elements must have labels" "$out" "three faulty items"
	page "<ul>$item</ul>"
	smoke_and_server_gone "one faulty item"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / dark label li.card > input.field: Form elements must have labels
package.json:1 smoke-a11y / light label li.card > input.field: Form elements must have labels" "$out" "one faulty item"
}

# Each same-origin link is requested once, without its hash: one that answers
# 4xx or 5xx is a finding, naming the route it was first found on; a redirect to
# a page passes; a route already loaded, an off-site link and a mailto: aren't
# requested. (Each link is 24px square, or axe's target-size rule finds it.)
test_a_link_to_a_missing_page_is_a_finding_with_node() {
	needs_browser
	site_project
	routes '/  app/page.tsx  Home' '/about  app/about/page.tsx  About'
	local big='<style>a { display: inline-block; min-width: 24px; min-height: 24px }</style>'
	page "$big"'<a href="/missing">a</a> <a href="/missing#top">b</a> <a href="/here#top">c</a> <a href="/moved">d</a> <a href="/about">e</a> <a href="#top">f</a> <a href="http://example.invalid/x">g</a> <a href="mailto:a@example.invalid">h</a>'
	page "$big"'<a href="/broken">i</a> <a href="/missing">j</a>' /about
	page '' /here
	echo moved > "$TEST_TMP/site/moved"
	echo 308 > "$TEST_TMP/site/moved.status"
	echo /here > "$TEST_TMP/site/moved.location"
	echo broken > "$TEST_TMP/site/broken"
	echo 500 > "$TEST_TMP/site/broken.status"
	smoke_and_server_gone "dead links"
	assert_status 1
	assert_eq "package.json:1 smoke-link / /missing 404
package.json:1 smoke-link /about /broken 500" "$out" "the dead links"
}

# No page route to load is a finding, before any build.
test_no_page_route_is_a_finding_before_the_build_with_node() {
	lock_project
	routes 'POST /api/x  app/api/x/route.ts  no page'
	step smoke
	assert_status 1
	assert_eq "ARCHITECTURE.md:3 smoke-routes the \`## Routes\` table lists no page route: a line whose first field is its path, \`/\` and on" "$out" "smoke's finding"
	[ ! -e "$TEST_TMP/builds" ] || fail "a build ran with no route to load"
	rm ARCHITECTURE.md
	step smoke
	assert_status 1
	assert_eq "ARCHITECTURE.md:1 smoke-routes can't read ARCHITECTURE.md (ENOENT), whose \`## Routes\` table lists the page routes" "$out" "smoke's finding with no ARCHITECTURE.md"
}

# routes_of <file>: run the route reader on <file>, with run_cmd.
routes_of() {
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_routes.mjs" "$1" smoke-routes
}

# The reader keeps a page line of the Routes table's fenced block (its path
# first), once, in order; drops a method line, a route handler, a dynamic route
# (with a note) and anything outside the block.
test_the_route_reader_keeps_the_page_lines_with_node() {
	needs_node
	routes_of "$NEXTJS_FIXTURES/smoke/routes.md.txt"
	assert_status 0
	assert_eq "/
/about
/contact" "$out" "the page routes"
	assert_eq "routes: left out /blog/[slug]: a dynamic segment can't be loaded without a value" "$(cat "$TEST_TMP/stderr")" "the note"
}

# No table, no fenced block under it, no page line or only dynamic ones: a
# finding at the heading's line, or the first.
test_the_route_reader_finds_no_table_with_node() {
	needs_node
	printf '# Architecture\n\n## Modules\n' > "$TEST_TMP/none.md"
	routes_of "$TEST_TMP/none.md"
	assert_status 1
	assert_eq "$TEST_TMP/none.md:1 smoke-routes no \`## Routes\` section: list the app's page routes there, in a fenced block, one \`<path> <file> <what>\` a line" "$out" "no section"

	printf '# Architecture\n\n## Routes\n\n/ app/page.tsx\n\n## Modules\n\n```\n/ app/page.tsx\n```\n' > "$TEST_TMP/bare.md"
	routes_of "$TEST_TMP/bare.md"
	assert_status 1
	assert_eq "$TEST_TMP/bare.md:3 smoke-routes the \`## Routes\` section has no fenced block: list the app's page routes in one, one \`<path> <file> <what>\` a line" "$out" "no fenced block"

	printf '## Routes\n\n```\n/blog/[slug]  app/blog/[slug]/page.tsx\n```\n' > "$TEST_TMP/dynamic.md"
	routes_of "$TEST_TMP/dynamic.md"
	assert_status 1
	assert_eq "$TEST_TMP/dynamic.md:1 smoke-routes the \`## Routes\` table lists no page route without a dynamic segment (/blog/[slug]), so none can be loaded" "$out" "only a dynamic route"
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

# lock_project [build]: skeleton_project (nothing installed) with a next whose
# build appends `begin` then `end` to $TEST_TMP/builds, and `overlap` when another
# build is running then ($TEST_TMP/building), running the bash <build> between
# (default: nothing); whose start exits 3.
lock_project() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin
	cat > node_modules/.bin/next << SH
#!/usr/bin/env bash
[ "\$1" = build ] || exit 3
[ ! -e $(printf '%q' "$TEST_TMP/building") ] || echo overlap >> $(printf '%q' "$TEST_TMP/builds")
: > $(printf '%q' "$TEST_TMP/building")
echo begin >> $(printf '%q' "$TEST_TMP/builds")
${1:-}
rm -f $(printf '%q' "$TEST_TMP/building")
echo end >> $(printf '%q' "$TEST_TMP/builds")
SH
	chmod 755 node_modules/.bin/next
}

# lock_gone: no build holds the build lock.
lock_gone() {
	[ ! -e "$FACTORY_BUILD_LOCK" ] || fail "the build lock is still there: $(ls -la "$FACTORY_BUILD_LOCK" 2>&1)"
}

# Two smoke runs at once (as in two worktrees): the second's build waits for the
# first's to end, then runs; the builds never overlap, and the lock is released.
test_two_builds_at_once_run_one_after_the_other_with_node() {
	blocking_stand_in "$TEST_TMP/build-1" "$TEST_TMP/release-1"
	blocking_stand_in "$TEST_TMP/build-2" "$TEST_TMP/release-2"
	lock_project "n=\$(grep -c begin $(printf '%q' "$TEST_TMP/builds")); $(printf '%q' "$TEST_TMP")/build-\$n"
	local a b
	trap ': > "$TEST_TMP/release-1"; : > "$TEST_TMP/release-2"; wait' EXIT
	bash tools/verify/smoke > "$TEST_TMP/a.out" 2> "$TEST_TMP/a.err" &
	a=$!
	wait_until "the first build to start" test -s "$TEST_TMP/build-1.pid"
	bash tools/verify/smoke > "$TEST_TMP/b.out" 2> "$TEST_TMP/b.err" &
	b=$!
	wait_until "the second run to wait for the build lock" grep -q "next build: waiting for the build lock $FACTORY_BUILD_LOCK, held by pid $a (up to 900s, FACTORY_BUILD_WAIT)" "$TEST_TMP/b.err"
	[ ! -e "$TEST_TMP/build-2.pid" ] || fail "the second build started while the first ran"
	: > "$TEST_TMP/release-1"
	wait "$a"
	assert_eq 1 "$?" "the first run's exit (its server exits 3)"
	wait_until "the second build to start" test -s "$TEST_TMP/build-2.pid"
	: > "$TEST_TMP/release-2"
	wait "$b"
	assert_eq 1 "$?" "the second run's exit (its server exits 3)"
	assert_eq "begin
end
begin
end" "$(cat "$TEST_TMP/builds")" "the builds, in order"
	assert_eq "package.json:1 smoke-start next start exited 3 before it answered (see stderr)" "$(cat "$TEST_TMP/b.out")" "the second run's finding"
	lock_gone
}

# Held by a running build past FACTORY_BUILD_WAIT, the lock is a transient
# finding (exit 75): no build runs, and the holder's lock stays.
test_a_build_lock_held_past_the_wait_is_a_transient_finding_with_node() {
	lock_project
	mkdir "$FACTORY_BUILD_LOCK" && echo "$BASHPID" > "$FACTORY_BUILD_LOCK/pid" || fail "could not hold the lock"
	FACTORY_BUILD_WAIT=0 step smoke
	assert_status 75
	assert_eq "package.json:1 smoke-build-lock another next build held the build lock $FACTORY_BUILD_LOCK (pid $BASHPID) past FACTORY_BUILD_WAIT (0s, tools/verify/local.env); run again once it ends, or remove the lock if no build is running" "$out" "smoke's finding"
	[ ! -e "$TEST_TMP/builds" ] || fail "a build ran under another's lock"
	assert_eq "$BASHPID" "$(cat "$FACTORY_BUILD_LOCK/pid")" "the holder's lock"

	# Named by no pid yet, a fresh lock is a build taking it: waited for too.
	rm -rf "$FACTORY_BUILD_LOCK" && mkdir "$FACTORY_BUILD_LOCK" || fail "could not make the lock"
	FACTORY_BUILD_WAIT=0 step smoke
	assert_status 75
	assert_eq "package.json:1 smoke-build-lock another next build held the build lock $FACTORY_BUILD_LOCK (pid unknown) past FACTORY_BUILD_WAIT (0s, tools/verify/local.env); run again once it ends, or remove the lock if no build is running" "$out" "smoke's finding for a lock naming no pid"
}

# A lock whose holder is gone, or that has named no holder for over a minute, is
# taken over: the build runs and releases it.
test_a_stale_build_lock_is_taken_over_with_node() {
	lock_project
	local dead
	dead="$(bash -c 'echo $$')"
	mkdir "$FACTORY_BUILD_LOCK" && echo "$dead" > "$FACTORY_BUILD_LOCK/pid" || fail "could not make the lock"
	FACTORY_BUILD_WAIT=0 step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-start next start exited 3 before it answered (see stderr)" "$out" "smoke's finding"
	stderr_has "next build: took over the stale build lock $FACTORY_BUILD_LOCK (its holder, pid $dead, is gone)"
	lock_gone

	mkdir "$FACTORY_BUILD_LOCK" && touch -t 200001010000 "$FACTORY_BUILD_LOCK" || fail "could not make an old lock"
	FACTORY_BUILD_WAIT=0 step smoke
	assert_status 1
	stderr_has "next build: took over the stale build lock $FACTORY_BUILD_LOCK (its holder is gone)"
	assert_eq "begin
end
begin
end" "$(cat "$TEST_TMP/builds")" "the builds"
	lock_gone
}

# Takeovers run one at a time, under <lock>.takeover: while another waiter's
# takeover holds it, a stale lock is left alone (waited for); a guard over a
# minute old, left by a takeover cut short, is removed and the lock taken over.
test_a_stale_build_lock_is_taken_over_one_waiter_at_a_time_with_node() {
	lock_project
	local dead
	dead="$(bash -c 'echo $$')"
	mkdir "$FACTORY_BUILD_LOCK" "$FACTORY_BUILD_LOCK.takeover" && echo "$dead" > "$FACTORY_BUILD_LOCK/pid" || fail "could not make the lock"
	FACTORY_BUILD_WAIT=0 step smoke
	assert_status 75
	assert_eq "package.json:1 smoke-build-lock another next build held the build lock $FACTORY_BUILD_LOCK (pid $dead) past FACTORY_BUILD_WAIT (0s, tools/verify/local.env); run again once it ends, or remove the lock if no build is running" "$out" "smoke's finding while another takeover runs"
	assert_eq "$dead" "$(cat "$FACTORY_BUILD_LOCK/pid")" "the stale lock, left to the other takeover"
	[ ! -e "$TEST_TMP/builds" ] || fail "a build ran during another's takeover"

	touch -t 200001010000 "$FACTORY_BUILD_LOCK.takeover" || fail "could not age the guard"
	FACTORY_BUILD_WAIT=0 step smoke
	assert_status 1
	stderr_has "next build: took over the stale build lock $FACTORY_BUILD_LOCK (its holder, pid $dead, is gone)"
	assert_eq "begin
end" "$(cat "$TEST_TMP/builds")" "the build"
	lock_gone
	[ ! -e "$FACTORY_BUILD_LOCK.takeover" ] || fail "the takeover left its guard behind"
}

# next build's own refusal, another build running in the checkout (as next
# prints it, colours and all), is a transient finding; the lock is released.
test_next_finding_another_build_running_is_a_transient_finding_with_node() {
	lock_project "cat $(printf '%q' "$NEXTJS_FIXTURES/smoke/another-build.txt") >&2; exit 1"
	step smoke
	assert_status 75
	assert_eq "package.json:1 smoke-build next build exited 1: another next build was running in this checkout (see stderr)" "$out" "smoke's finding"
	stderr_has "process is already running."
	lock_gone
}

# A failed build releases the lock too, and stays an ordinary failure.
test_a_failed_build_releases_the_lock_with_node() {
	lock_project 'exit 2'
	step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-build next build exited 2 (see stderr)" "$out" "smoke's finding"
	lock_gone
}

test_the_build_wait_must_be_seconds_and_the_lock_makeable_with_node() {
	lock_project
	local v
	for v in soon -1 1.5 1234567; do
		FACTORY_BUILD_WAIT="$v" step smoke
		assert_status 1
		assert_eq "tools/verify/local.env:1 smoke-setting FACTORY_BUILD_WAIT is '$v', not a number of seconds from 0 to 999999" "$out" "smoke's finding for '$v'"
	done
	FACTORY_BUILD_LOCK="$TEST_TMP/missing/next-build.lock" step smoke
	assert_status 1
	assert_eq "tools/verify/local.env:1 smoke-build-lock could not make the build lock $TEST_TMP/missing/next-build.lock; FACTORY_BUILD_LOCK in tools/verify/local.env names a folder to make, in a folder that exists" "$out" "smoke's finding for a lock it can't make"
	[ ! -e "$TEST_TMP/builds" ] || fail "a build ran without the lock"
}

# A lock released between a waiter's failed mkdir and its look at the lock (here
# a mkdir that fails once) is tried again, not reported as a folder it can't make.
test_a_lock_released_between_tries_is_tried_again() {
	skeleton_project
	(
		# shellcheck source=/dev/null
		. tools/verify/_nextjs.sh
		failed=""
		# shellcheck disable=SC2317 # called by nx_build_lock
		mkdir() {
			if [ -z "$failed" ] && [ "$1" = "$NX_BUILD_LOCK" ]; then
				failed=1
				return 1
			fi
			command mkdir "$@"
		}
		nx_build_lock 0 || echo "$NX_BUILD_MSG"
		[ -n "$failed" ] || echo "the first mkdir did not fail"
		[ "$(cat "$NX_BUILD_LOCK/pid" 2> /dev/null)" = "$$" ] || echo "the lock names no holder"
		nx_build_unlock
	) > "$TEST_TMP/lock.out" 2>&1
	assert_eq "" "$(cat "$TEST_TMP/lock.out")" "what went wrong taking the lock"
	lock_gone
}

# A TERM mid-build: once the build ends, the step exits and releases the lock.
test_a_signal_mid_build_releases_the_lock_with_node() {
	blocking_stand_in "$TEST_TMP/build-1" "$TEST_TMP/release-1"
	lock_project "$(printf '%q' "$TEST_TMP/build-1")"
	smoke_apart
	wait_until "the build to start" test -s "$TEST_TMP/build-1.pid"
	kill -TERM "$smoke"
	: > "$TEST_TMP/release-1"
	wait "$smoke"
	assert_eq 143 "$?" "the step's exit on TERM"
	smoke=""
	lock_gone
}

# A request refused a connection (the server gone, or not yet up) is a transient
# failure (exit 75); any other finding stays an ordinary one.
test_a_refused_connection_is_a_transient_failure_with_node() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin "$TEST_TMP/site"
	cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next || fail "could not stand in for next"
	cp "$NEXTJS_FIXTURES/smoke/page-findings.mjs.txt" tools/verify/_smoke_page.mjs || fail "could not stand in for the browser script"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_FINDINGS="$TEST_TMP/findings"
	local line
	while IFS= read -r line; do
		printf '%s\n' "$line" > "$TEST_TMP/findings"
		step smoke
		assert_status 75
		assert_eq "$line" "$out" "smoke's finding"
		stderr_has "smoke: a request was refused a connection"
	done < "$NEXTJS_FIXTURES/smoke/refused-findings.txt"
	echo "package.json:1 smoke-console /: console error: boom" > "$TEST_TMP/findings"
	step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-console /: console error: boom" "$out" "smoke's finding"
}
