# The Next.js smoke step (tools/verify/smoke, _smoke_page.mjs) and bootstrap's
# browser. The step's logic (the port, the wait and its limit, stopping the
# server, the findings) runs against stand-ins for next: a small server serving a
# folder of pages (tests/fixture/smoke/next.mjs), or a bash one around
# blocking_stand_in. The real next build and next start run in adopt_test.sh's
# end to end, on the skeleton.
#
# The tests that load a page need Node, pnpm, a primed pnpm store
# (FACTORY_PNPM_STORE) and the three browsers, Chromium, Firefox and WebKit
# (FACTORY_PLAYWRIGHT_BROWSERS), and skip without them; the rest need Node alone.
# A page finding all three engines report names none; one only some report
# names them after the route (test_a_finding_some_engines_report_names_them);
# one found at only one of axe's widths names it after that
# (test_an_accessibility_fault_at_one_width_names_it). The layout check runs
# on the pages of tests/fixture/layout/, under the layout contract's styles.
#
# A project's smoke step loads each page in all three engines; here most tests
# load it in Chromium alone, a third of the browser work, as the Editor's loop
# does (site_project sets FACTORY_GATE_LOOP=editor, which in this step does
# nothing else: the step's header). A test whose assertion is about which
# engines report, start or stop (the engine tokens, forced colours in Chromium
# and Firefox alone, a missing engine, the Editor's loop itself) calls
# all_engines, saying why, and loads all three, as a project's gate does.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# site_project: skeleton_project with its packages installed (primed_project), and
# next replaced by the stand-in serving $TEST_TMP/site; cd there. The stand-in
# writes its pid to $TEST_TMP/server.pid. The step loads the pages in Chromium
# alone (the Editor's loop) until the test calls all_engines.
site_project() {
	primed_project
	rm -f node_modules/.bin/next && cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	mkdir -p "$TEST_TMP/site/api"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_PID="$TEST_TMP/server.pid"
	export FACTORY_GATE_LOOP=editor
}

# all_engines: from here on the step runs outside the Editor's loop and starts
# Chromium, Firefox and WebKit, as a project's gate does.
all_engines() {
	unset FACTORY_GATE_LOOP
}

# page <html> [route]: the site's page at <route> (default `/`), a page smoke
# finds nothing on but what <html> brings, which goes in its <main>, after a
# heading and a paragraph (axe's best-practice rules want a main landmark
# holding the content, and a heading one).
page() {
	mkdir -p "$TEST_TMP/site${2:-/}"
	printf '<!doctype html><html lang="en"><head><title>t</title></head><body><main><h1>t</h1><p>hi</p>%s</main></body></html>\n' "$1" > "$TEST_TMP/site${2:-/}/index.html"
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

# pid_gone <file>: the pid in <file> is no process. Called once the step has
# stopped the server's group: a pid file still empty or missing then is a
# server killed before it wrote its pid, gone too (waiting on it would only run
# out the hang guard).
pid_gone() {
	local pid
	pid="$(cat "$1" 2> /dev/null)"
	[ -z "$pid" ] || ! kill -0 "$pid" 2> /dev/null
}

# server_gone: the stand-in server's pid, in $TEST_TMP/server.pid, is no process.
server_gone() {
	pid_gone "$TEST_TMP/server.pid"
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

	all_engines # an uncaught error reads as one line from all three, and Firefox logs no console error for a 500 or a 503
	page '<script>throw new Error("kaput")</script>'
	smoke_and_server_gone "a page error"
	assert_status 1
	assert_eq "package.json:1 smoke-page-error /: uncaught Error: kaput" "$out" "an uncaught error"

	page '<script>fetch("/api/fail")</script>'
	echo failed > "$TEST_TMP/site/api/fail"
	echo 500 > "$TEST_TMP/site/api/fail.status"
	smoke_and_server_gone "a route answering 500"
	assert_status 1
	assert_eq "package.json:1 smoke-console / chromium,webkit: console error: Failed to load resource: the server responded with a status of 500 (Internal Server Error)
package.json:1 smoke-response /: /api/fail answered 500" "$out" "a request answered 500 (Firefox logs no console error for it)"

	page ''
	echo 503 > "$TEST_TMP/site/index.html.status"
	smoke_and_server_gone "a page answering 503"
	assert_status 1
	assert_eq "package.json:1 smoke-console / chromium,webkit: console error: Failed to load resource: the server responded with a status of 503 (Service Unavailable)
package.json:1 smoke-response /: / answered 503" "$out" "the page answered 503 (Firefox logs no console error for it)"
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
	assert_eq "package.json:1 smoke-a11y / dark label main > input: Form elements must have labels
package.json:1 smoke-a11y / light label main > input: Form elements must have labels" "$out" "an unlabelled input"

	page '<style>@media (prefers-color-scheme: dark) { p { color: #777; background: #888 } }</style>'
	smoke_and_server_gone "a contrast fault in the dark"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / dark color-contrast main > p: Elements must meet minimum color contrast ratio thresholds" "$out" "a fault in the dark scheme alone"

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

# A fault all three engines report names none, as when smoke ran Chromium
# alone; one only some report names them after the route, chromium, firefox and
# webkit in that order: here an unlabelled input only Firefox gets, and a
# console error all but Chromium log.
test_a_finding_some_engines_report_names_them_with_node() {
	needs_browser
	site_project
	all_engines # the engine tokens, and the pages loaded in Firefox and WebKit
	page '<script>console.error("everywhere")</script><script>if (!/Chrome\//.test(navigator.userAgent)) console.error("not in chromium")</script><script>if (/Firefox\//.test(navigator.userAgent)) document.querySelector("main").insertAdjacentHTML("beforeend", "<input type=text>")</script>'
	smoke_and_server_gone "faults in some engines"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / firefox dark label main > input: Form elements must have labels
package.json:1 smoke-a11y / firefox light label main > input: Form elements must have labels
package.json:1 smoke-console / firefox,webkit: console error: not in chromium
package.json:1 smoke-console /: console error: everywhere" "$out" "the findings of some engines and of all"
}

# axe runs at 390 and 1280 px: a fault at both names no width, as before; one
# at 390 alone (a contrast fault under a phone-width media query) names it,
# after the route.
test_an_accessibility_fault_at_one_width_names_it_with_node() {
	needs_browser
	site_project
	page '<style>@media (max-width: 500px) { p { color: #777; background: #888 } }</style><input type="text">'
	smoke_and_server_gone "a fault at 390 px and one at both widths"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / 390px dark color-contrast main > p: Elements must meet minimum color contrast ratio thresholds
package.json:1 smoke-a11y / 390px light color-contrast main > p: Elements must meet minimum color contrast ratio thresholds
package.json:1 smoke-a11y / dark label main > input: Form elements must have labels
package.json:1 smoke-a11y / light label main > input: Form elements must have labels" "$out" "the faults at one width and at both"
}

# axe's WCAG 2.1 rules and its best practices run too: an autocomplete token
# that doesn't exist (autocomplete-valid, wcag21aa) and a heading that skips a
# level (heading-order, best-practice).
test_wcag_2_1_and_best_practice_rules_run_with_node() {
	needs_browser
	site_project
	page '<input aria-label="name" autocomplete="nonsense"><h3>skipped</h3>'
	smoke_and_server_gone "a WCAG 2.1 fault and a best-practice one"
	assert_status 1
	assert_eq "package.json:1 smoke-a11y / dark autocomplete-valid main > input: autocomplete attribute must be used correctly
package.json:1 smoke-a11y / dark heading-order main > h3: Heading levels should only increase by one
package.json:1 smoke-a11y / light autocomplete-valid main > input: autocomplete attribute must be used correctly
package.json:1 smoke-a11y / light heading-order main > h3: Heading levels should only increase by one" "$out" "the WCAG 2.1 and best-practice faults"
}

# In forced colours, a link whose focus style is outline: none and nothing
# else shows no indicator: a finding, naming no engine (Chromium and Firefox
# force the colours; WebKit's Playwright doesn't, so the check doesn't run
# there). The browser's own ring, a transparent outline (which forced colours
# paint), a ring on the label beside a hidden checkbox or on the box in it
# (after a select of 250 options), an underline that doubles or thickens, a
# button that opts out of forced colours and flips its colours, and a ring on a
# card's child pass, the last on each of 60 cards.
test_a_focus_indicator_forced_colours_hide_is_a_finding_with_node() {
	needs_browser
	site_project
	local cards="" options="" i
	for i in $(seq 250); do
		options+="<option>c$i</option>"
	done
	for i in $(seq 60); do
		cards+="<a class=\"card\" href=\"#c$i\"><span class=\"x\">x</span><span class=\"y\">y</span><span class=\"t\">Card $i</span></a>"
	done
	all_engines # forced colours run in Chromium and Firefox, not WebKit: the finding names none
	page '<style>a { display: inline-block; min-width: 24px; min-height: 24px } .bare:focus { outline: none; box-shadow: 0 0 0 3px blue } .clear:focus-visible { outline: 2px solid transparent } .box { position: absolute; opacity: 0 } .box:focus { outline: none } .box:focus-visible + span { outline: 2px solid } .deco, .thick { outline: none; text-decoration: underline } .deco:focus { text-decoration-style: double } .thick:focus { text-decoration-thickness: 5px } .flip { outline: none; forced-color-adjust: none; background: white; color: black } .flip:focus { background: black; color: white } .card { outline: none } .card:focus .t { outline: 3px solid } .vh { position: absolute; opacity: 0 } .vh:focus { outline: none } .vh:focus-visible + label .tick { outline: 2px solid } .tick { display: inline-block; width: 16px; height: 16px; border: 1px solid }</style><a class="bare" href="#a">bare</a> <a href="#b">plain</a> <a class="clear" href="#c">clear</a> <label class="check"><input class="box" type="checkbox"><span>agree</span></label> <a class="deco" href="#d">deco</a> <a class="thick" href="#e">thick</a> <button class="flip">flip</button><div class="field"><label for="s">Country</label><select id="s">'"$options"'</select><input id="v" class="vh" type="checkbox"><label for="v"><span class="tick"></span> Agree</label></div><div class="grid">'"$cards"'</div>'
	smoke_and_server_gone "a focus style forced colours hide"
	assert_status 1
	assert_eq "package.json:1 smoke-forced-colors / main > a.bare: no visible focus indicator in forced colours" "$out" "the focus style forced colours hide"
}

# At 320 px wide a page that scrolls sideways is a finding naming its width and
# the element reaching furthest right; content that scrolls inside a box of its
# own, or that the page clips (overflow-x: hidden on the body), is none.
test_a_page_wider_than_320px_is_a_finding_with_node() {
	needs_browser
	site_project
	page '<div class="hero"><img alt="" class="art" style="display: block; width: 500px; height: 10px"></div>'
	smoke_and_server_gone "a page wider than 320 px"
	assert_status 1
	assert_eq "package.json:1 smoke-reflow /: scrolls horizontally at 320px (508px wide, widest div.hero > img.art)" "$out" "the page wider than 320 px"

	page '<style>ul:focus-visible { outline: 2px solid }</style><ul tabindex="0" aria-label="strip" style="display: flex; overflow-x: auto; padding: 0"><li style="flex: 0 0 240px">a</li><li style="flex: 0 0 240px">b</li></ul>'
	smoke_and_server_gone "a strip that scrolls in its own box"
	assert_status 0
	assert_eq "" "$out" "a strip that scrolls in its own box"

	page '<style>body { overflow-x: hidden }</style><div style="width: 500px">clipped</div>'
	smoke_and_server_gone "a page that clips its overflow"
	assert_status 0
	assert_eq "" "$out" "a page that clips its overflow"
}

# layout_page <fixture> [route] [css]: the site's page at <route> (default
# `/`): tests/fixture/layout/<fixture>.html.txt as its body, under the layout
# contract's styles (contract.css.txt) and <css>.
layout_page() {
	mkdir -p "$TEST_TMP/site${2:-/}"
	printf '<!doctype html><html lang="en"><head><title>t</title><style>%s%s</style></head><body>%s</body></html>\n' \
		"$(cat "$NEXTJS_FIXTURES/layout/contract.css.txt")" "${3:-}" "$(cat "$NEXTJS_FIXTURES/layout/$1.html.txt")" > "$TEST_TMP/site${2:-/}/index.html" ||
		fail "could not write the page $1"
}

# The layout check, on each route whose page carries [data-shell], at 390, 768,
# 1280 and 1920 px (in Chromium here, in each engine in a project): the page
# that keeps the whole contract (a bleeding hero, a Sidebar, a Switcher, a
# Center with a quote, a form, a strip of events that scrolls in its own box) is
# no finding, and a page without
# [data-shell] is skipped; on /faults each departure is one finding, naming no
# width when it shows at all four (the header's edge, a box outside the column
# beside a hero data-bleed lets out, a section and a heading gap, narrow prose
# alone) and the width when it shows at one (a block off-centre at 1920 px
# alone); /narrow's column, on a page of its own whose shells agree, is off /'s
# at the two widths where it's narrower than the window.
test_the_layout_check_finds_each_departure_from_the_contract_with_node() {
	needs_browser
	site_project
	routes '/  app/page.tsx  Home' '/faults  app/faults/page.tsx  Faults' \
		'/narrow  app/narrow/page.tsx  Narrow' '/plain  app/plain/page.tsx  Plain'
	layout_page pass
	layout_page faults /faults
	layout_page pass /narrow '[data-shell] { max-inline-size: 900px }'
	page '' /plain
	smoke_and_server_gone "the layout faults"
	assert_status 1
	assert_eq "package.json:1 smoke-layout /faults 1920px lone section > div.late: 560px wide in a 1160px cell, 0px | 600px either side (want 0.9 of it, or centred, ±2px)
package.json:1 smoke-layout /faults edges header > div.off: content box left +40px, right 0px from main's (want main's, ±1px)
package.json:1 smoke-layout /faults headings section.pushed > h2#h-pushed.spaced: gap below is --space-heading +12px (want --space-heading, ±1px)
package.json:1 smoke-layout /faults outside section > div.wide: reaches 10px past the column's right edge (want inside the column, or in [data-bleed])
package.json:1 smoke-layout /faults prose section.pushed > div.narrow: 150px wide, nothing beside it (want 0.6 of the column or more, or something beside it)
package.json:1 smoke-layout /faults sections div > section.pushed: gap above is --space-section +10px (want --space-section, ±1px)
package.json:1 smoke-layout /narrow 1280px,1920px edges main#main > div: content box left +150px, right -150px from /'s (want /'s, ±1px)" "$out" "the layout findings"
}

# A project without the contract is unaffected: no page carries [data-shell],
# so nothing is measured and nothing is loaded at the layout check's own
# widths, 768 and 1920 px (a load there would request a file that isn't
# there: a finding).
test_a_page_without_a_shell_loads_at_no_layout_width_with_node() {
	needs_browser
	site_project
	page '<script>if ([768, 1920].includes(innerWidth)) fetch("/api/missing")</script>'
	smoke_and_server_gone "a page with no shell"
	assert_status 0
	assert_eq "" "$out" "smoke's findings on a page with no shell"
}

# server_started: the stand-in server printed its URL; its port in $port.
server_started() {
	[[ "$(cat "$TEST_TMP/server.out" 2> /dev/null)" =~ http://127\.0\.0\.1:([0-9]+) ]] && port="${BASH_REMATCH[1]}"
}

# The browser script runs on its own against any server, with a cookie set in
# every browser context (here the page shows an unlabelled input only when the
# cookie is set); arguments it can't read are its usage and exit 2.
test_the_page_checks_run_on_their_own_with_a_cookie_with_node() {
	needs_browser
	site_project
	page '<script>if (document.cookie.split("; ").includes("direction=b")) document.querySelector("main").insertAdjacentHTML("beforeend", "<input type=text>")</script>'
	port=""
	# server: no local, so the EXIT trap, which runs after the function returns,
	# still sees it.
	node node_modules/.bin/next start --hostname 127.0.0.1 --port 0 > "$TEST_TMP/server.out" 2>&1 &
	server=$!
	trap 'kill "$server" 2> /dev/null; wait "$server"' EXIT
	tether "$server"
	wait_until "the stand-in server to listen" server_started
	run_cmd node tools/verify/_smoke_page.mjs "http://127.0.0.1:$port" 60 --engines chromium --cookie direction=b /
	assert_status 0
	assert_eq "package.json:1 smoke-a11y / dark label main > input: Form elements must have labels
package.json:1 smoke-a11y / light label main > input: Form elements must have labels" "$out" "the findings with the cookie"
	run_cmd node tools/verify/_smoke_page.mjs "http://127.0.0.1:$port/" 60 --engines chromium /
	assert_status 0
	assert_eq "" "$out" "the findings without it"

	run_cmd node tools/verify/_smoke_page.mjs "http://127.0.0.1:$port" 60 --cookie novalue /
	assert_status 2
	assert_eq "" "$out" "stdout on a cookie with no value"
	stderr_has "--cookie takes <name>=<value>, not 'novalue'"
	run_cmd node tools/verify/_smoke_page.mjs "http://127.0.0.1:$port" 60
	assert_status 2
	stderr_has "usage: node tools/verify/_smoke_page.mjs <origin> <seconds> [--cookie <name>=<value>] <route>..."
	stderr_has "  --engines <engine>,... (before the routes) runs only those browsers: chromium, firefox, webkit"
	run_cmd node tools/verify/_smoke_page.mjs "http://127.0.0.1:$port" 60 --engines chromium,blink /
	assert_status 2
	stderr_has "--engines takes chromium, firefox or webkit, each once, joined by commas, not 'chromium,blink'"
	kill "$server"
	wait_until "the stand-in server to stop" server_gone
}

# The layout check runs on its own too, against any server, with a cookie set
# in every browser context (here the photo reaches past the column only when
# the cookie is set): its findings as smoke prints them, then what it reports
# for the eye, Chromium's, one line per route, width, check and selector
# (/reported: a heading of four words with one on its last line, a ragged
# paragraph, a short statement), and on stderr the routes it checked and those
# it skipped for want of [data-shell]. Arguments it can't read are its usage
# and exit 2.
test_the_layout_check_runs_on_its_own_with_a_cookie_with_node() {
	needs_browser
	site_project
	layout_page pass / '.b .photo { margin-inline-end: -30px }'
	sed -i 's|</body>|<script>if (document.cookie.split("; ").includes("direction=b")) document.body.classList.add("b")</script></body>|' "$TEST_TMP/site/index.html"
	layout_page reported /reported
	layout_page pass /far '.photo { position: relative; left: 2500px }'
	layout_page pass /parked 'body { overflow-x: hidden } .photo { position: relative; left: 2500px }'
	# /busy never goes quiet: it holds a request open that the stand-in never
	# answers. (A page polling every 100 ms went quiet now and then on a loaded
	# machine, its timers held back past networkidle's 500 ms, in any engine.)
	page '<script>fetch("/busy/held")</script>' /busy
	: > "$TEST_TMP/site/busy/held" && : > "$TEST_TMP/site/busy/held.hang" || fail "could not hold /busy's request"
	page '' /plain
	port=""
	# server: no local, so the EXIT trap, which runs after the function returns,
	# still sees it.
	node node_modules/.bin/next start --hostname 127.0.0.1 --port 0 > "$TEST_TMP/server.out" 2>&1 &
	server=$!
	trap 'kill "$server" 2> /dev/null; wait "$server"' EXIT
	tether "$server"
	wait_until "the stand-in server to listen" server_started
	# All three engines (it takes no --engines): the reported lines are Chromium's alone of the three.
	run_cmd node tools/verify/_layout.mjs "http://127.0.0.1:$port" 60 --cookie direction=b / /plain /reported
	assert_status 0
	assert_eq "package.json:1 smoke-layout / outside div > div.photo: reaches 30px past the column's right edge (want inside the column, or in [data-bleed])" "$(grep '^package' <<< "$out")" "the findings with the cookie"
	# The reported lines' lengths are the fonts'; their format is fixed.
	assert_eq "reported: /reported 390px one-word section > p.tag
reported: /reported 390px one-word section > h2#h-word
reported: /reported 390px one-word section > p.cta
reported: /reported 390px ragged div.ragged > p
reported: /reported 390px short section > p
reported: /reported 768px one-word section > p.tag
reported: /reported 768px one-word section > h2#h-word
reported: /reported 768px one-word section > p.cta
reported: /reported 768px ragged div.ragged > p
reported: /reported 768px short section > p
reported: /reported 1280px one-word section > p.tag
reported: /reported 1280px one-word section > h2#h-word
reported: /reported 1280px one-word section > p.cta
reported: /reported 1280px ragged div.ragged > p
reported: /reported 1280px short section > p
reported: /reported 1920px one-word section > p.tag
reported: /reported 1920px one-word section > h2#h-word
reported: /reported 1920px one-word section > p.cta
reported: /reported 1920px ragged div.ragged > p
reported: /reported 1920px short section > p" "$(grep -v '^package' <<< "$out" | sed 's/: ".*//')" "the reported lines"
	[[ "$out" =~ reported:\ /reported\ 390px\ one-word\ section\ \>\ h2#h-word:\ \"One\ two\ three\ four\"\ breaks\ 3/1\ words\ a\ line\ \(want\ no\ line\ of\ one\ word\) ]] ||
		fail "the one-word line isn't as the header has it: $out"
	[[ "$out" =~ reported:\ /reported\ 390px\ short\ section\ \>\ p:\ \"A\ short\ statement.\"\ 1\ line,\ the\ longest\ [0-9]+px\ of\ [0-9]+px\ \(want\ [0-9]+px\ \(0.75\ of\ its\ box\)\) ]] ||
		fail "the short line isn't as the header has it: $out"
	[[ "$out" =~ reported:\ /reported\ 390px\ one-word\ section\ \>\ p\.tag:\ \"Licensed\ psychotherapist,\ clarinetist,\ r…\"\ breaks\ 1/2/2\ words\ a\ line ]] ||
		fail "the hero tagline isn't a label: $out"
	stderr_has "layout: 1 finding(s), 20 reported; checked / /reported; skipped (no [data-shell]) /plain"

	run_cmd node tools/verify/_layout.mjs "http://127.0.0.1:$port/" 60 /
	assert_status 0
	assert_eq "" "$out" "the findings without the cookie"
	stderr_has "layout: 0 finding(s), 0 reported; checked /; skipped (no [data-shell]) none"

	# A box past the window's right edge, which the page scrolls to, is outside;
	# one where body's overflow-x hides it, or the skip link above the window
	# (on every page here), is not; a page that
	# never goes quiet is a smoke-load finding as smoke prints it, its width
	# unnamed, though the shell pages were loaded at 768 and 1920 px too.
	run_cmd node tools/verify/_layout.mjs "http://127.0.0.1:$port" 15 / /far /parked /busy
	assert_status 0
	assert_eq "package.json:1 smoke-layout /far outside div > div.photo: reaches 2500px past the column's right edge (want inside the column, or in [data-bleed])
package.json:1 smoke-load /busy: the page didn't load and go quiet within 15s: page.goto: Timeout 15000ms exceeded." "$out" "the findings past the window and on a busy page"
	[ -e "$TEST_TMP/site/busy/held.hit" ] || fail "/busy's request never reached the stand-in"

	run_cmd node tools/verify/_layout.mjs "http://127.0.0.1:$port" 60 --cookie novalue /
	assert_status 2
	stderr_has "--cookie takes <name>=<value>, not 'novalue'"
	run_cmd node tools/verify/_layout.mjs "http://127.0.0.1:$port" 60
	assert_status 2
	stderr_has "usage: node tools/verify/_layout.mjs <origin> <seconds> [--cookie <name>=<value>] <route>..."
	kill "$server"
	wait_until "the stand-in server to stop" server_gone
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

# missing_line <Engine> <engine>: the glob browser-missing's line for the engine
# matches.
missing_line() {
	printf '%s' "tools/verify/local.env:1 browser-missing $1 didn't start (*); run bash tools/verify/bootstrap, which installs it into PLAYWRIGHT_BROWSERS_PATH (tools/verify/local.env), and if it names missing system libraries: pnpm exec playwright install-deps $2"
}

# No browser installed: a browser-missing line for each engine, in order, and no
# page loaded.
test_a_missing_browser_is_a_finding_and_the_server_stops_with_node() {
	needs_store
	site_project
	all_engines # a browser-missing line for each engine
	page ''
	smoke_and_server_gone "a missing browser"
	assert_status 1
	local lines
	mapfile -t lines <<< "$out"
	[ "${#lines[@]}" -eq 3 ] || fail "smoke's findings, not one for each engine: $out"
	# shellcheck disable=SC2053 # the right side is a glob
	[[ ${lines[0]} == $(missing_line Chromium chromium) ]] || fail "Chromium's finding: ${lines[0]}"
	# shellcheck disable=SC2053
	[[ ${lines[1]} == $(missing_line Firefox firefox) ]] || fail "Firefox's finding: ${lines[1]}"
	# shellcheck disable=SC2053
	[[ ${lines[2]} == $(missing_line WebKit webkit) ]] || fail "WebKit's finding: ${lines[2]}"
}

# One engine that won't start (here Firefox, not installed: the browsers folder
# holds Chromium and WebKit alone) is a finding naming it, and no page is loaded
# in the others (the page's console error would be a finding).
test_an_engine_that_doesnt_start_is_a_finding_naming_it_with_node() {
	needs_browser
	site_project
	all_engines # Firefox, which won't start, is the one finding
	page '<script>console.error("boom")</script>'
	local d
	mkdir -p "$TEST_TMP/two-browsers"
	for d in "$FACTORY_PLAYWRIGHT_BROWSERS"/chromium_headless_shell-* "$FACTORY_PLAYWRIGHT_BROWSERS"/webkit-*; do
		[ -d "$d" ] || fail "no $d in FACTORY_PLAYWRIGHT_BROWSERS (prime it: bash factory/adapters/nextjs/tests/prime-store.sh <store> <browsers>)"
		ln -s "$d" "$TEST_TMP/two-browsers/" || fail "could not link $d"
	done
	export PLAYWRIGHT_BROWSERS_PATH="$TEST_TMP/two-browsers"
	smoke_and_server_gone "a missing Firefox"
	assert_status 1
	# shellcheck disable=SC2053 # the right side is a glob
	[[ $out == $(missing_line Firefox firefox) ]] || fail "smoke's finding: $out"
}

# The Editor's loop (FACTORY_GATE_LOOP=editor) starts Chromium alone: with no
# browser installed, Chromium's is the one browser-missing line.
test_the_editors_loop_misses_chromium_alone_with_node() {
	needs_store
	site_project
	all_engines # the loop alone narrows the engines
	page ''
	export FACTORY_GATE_LOOP=editor
	smoke_and_server_gone "a missing browser in the Editor's loop"
	assert_status 1
	# shellcheck disable=SC2053 # the right side is a glob
	[[ $out == $(missing_line Chromium chromium) ]] || fail "smoke's findings in the Editor's loop: $out"
}

# The Editor's loop loads the pages in Chromium alone (here the only browser
# installed), and a finding Chromium reports names no engine, as one every engine
# reports does; outside the loop the same folder misses Firefox and WebKit.
test_the_editors_loop_loads_the_pages_in_chromium_alone_with_node() {
	needs_browser
	site_project
	all_engines # the loop alone narrows the engines; outside it, all three start
	page '<script>console.error("boom")</script>'
	local d
	mkdir -p "$TEST_TMP/chromium-only"
	for d in "$FACTORY_PLAYWRIGHT_BROWSERS"/chromium_headless_shell-*; do
		[ -d "$d" ] || fail "no $d in FACTORY_PLAYWRIGHT_BROWSERS (prime it: bash factory/adapters/nextjs/tests/prime-store.sh <store> <browsers>)"
		ln -s "$d" "$TEST_TMP/chromium-only/" || fail "could not link $d"
	done
	export PLAYWRIGHT_BROWSERS_PATH="$TEST_TMP/chromium-only"
	FACTORY_GATE_LOOP=editor smoke_and_server_gone "the Editor's loop"
	assert_status 1
	assert_eq "package.json:1 smoke-console /: console error: boom" "$out" "smoke's findings in the Editor's loop"
	smoke_and_server_gone "a run outside the loop"
	assert_status 1
	local lines
	mapfile -t lines <<< "$out"
	[ "${#lines[@]}" -eq 2 ] || fail "smoke's findings outside the loop, not one for Firefox and one for WebKit: $out"
	# shellcheck disable=SC2053 # the right side is a glob
	[[ ${lines[0]} == $(missing_line Firefox firefox) ]] || fail "Firefox's finding: ${lines[0]}"
	# shellcheck disable=SC2053
	[[ ${lines[1]} == $(missing_line WebKit webkit) ]] || fail "WebKit's finding: ${lines[1]}"
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
# step stops that too. The leader writes the child's pid to a file of its own
# before it exits, so the step's stop can't leave it unwritten (the child's own
# server.pid can be: the stop may come between its truncate and its write).
test_a_server_that_exits_leaving_a_child_is_stopped_too_with_node() {
	blocking_project "$(printf '%q' "$TEST_TMP/server") & echo \$! > $(printf '%q' "$TEST_TMP/child.pid"); exit 3"
	step smoke
	assert_status 1
	assert_eq "package.json:1 smoke-start next start exited 3 before it answered (see stderr)" "$out" "smoke's finding"
	[ -s "$TEST_TMP/child.pid" ] || fail "the leader didn't write its child's pid"
	wait_until "the server's child to stop" pid_gone "$TEST_TMP/child.pid"
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

# The browser script exits non-zero having written no finding (a stand-in for
# it, which writes to stderr alone and exits 3): the step's own finding names
# the script and its status, stderr keeps what the script wrote, and the server
# stops. No browser is started.
test_a_browser_script_that_fails_with_no_finding_is_a_finding_with_node() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin "$TEST_TMP/site"
	cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next || fail "could not stand in for next"
	printf 'process.stderr.write("the browser script broke\\n");\nprocess.exit(3);\n' > tools/verify/_smoke_page.mjs ||
		fail "could not stand in for the browser script"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_PID="$TEST_TMP/server.pid"
	smoke_and_server_gone "a browser script that failed"
	assert_status 1
	assert_eq "package.json:1 smoke-load the browser script (tools/verify/_smoke_page.mjs) exited 3 (see stderr)" "$out" "smoke's finding"
	stderr_has "the browser script broke"
}

# A TERM while the step stops its server (one that ignores TERM, so the stop
# waits out the limit) doesn't cut the stop short: the server is killed and
# reaped before the step exits.
test_a_signal_while_the_step_stops_its_server_waits_for_the_stop_with_node() {
	blocking_project "trap '' TERM"
	local pid code=0
	FACTORY_SMOKE_TIMEOUT=3 bash tools/verify/smoke > "$TEST_TMP/smoke.out" 2> "$TEST_TMP/smoke.err" &
	pid=$!
	tether "$pid"
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
	tether "$smoke"
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
	all_engines # each engine's browser processes stop with the step
	page ''
	: > "$TEST_TMP/site/index.html.hang"
	local pids p
	smoke_apart
	wait_until "the page's request" test -e "$TEST_TMP/site/index.html.hit"
	pids="$(descendants "$smoke")"
	[ "$(printf '%s\n' "$pids" | grep -c .)" -ge 5 ] || fail "too few processes under the step (the server, node and the three browsers): $pids"
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

# bootstrap installs the pinned Playwright's Chromium, Firefox and WebKit where
# local.env says, and fetches nothing when they are there (the download host is
# a dead port).
test_bootstrap_installs_the_browsers_where_local_env_says_with_node() {
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
	stderr_has "bootstrap: playwright install --only-shell chromium firefox webkit exited 1 (into $TEST_TMP/empty)"
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
	tether "$a"
	wait_until "the first build to start" test -s "$TEST_TMP/build-1.pid"
	bash tools/verify/smoke > "$TEST_TMP/b.out" 2> "$TEST_TMP/b.err" &
	b=$!
	tether "$b"
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

# env_project: skeleton_project with stand-ins for next (env-next.sh: it logs
# `<command>|FEED_URL|CACHE_PATH|<what FEED_URL answers>` to $TEST_TMP/next.log,
# then serves $TEST_TMP/site) and for the browser script (no findings), so the
# step runs with Node alone; cd there.
env_project() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin "$TEST_TMP/site"
	cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" "$TEST_TMP/next.mjs" &&
		cp "$NEXTJS_FIXTURES/smoke/env-next.sh.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	cp "$NEXTJS_FIXTURES/smoke/page-findings.mjs.txt" tools/verify/_smoke_page.mjs || fail "could not stand in for the browser script"
	: > "$TEST_TMP/findings"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_FINDINGS="$TEST_TMP/findings" \
		STAND_IN_NEXT="$TEST_TMP/next.mjs" STAND_IN_LOG="$TEST_TMP/next.log"
}

# port_free <port>: nothing listens on it.
port_free() {
	node -e 'require("node:net").createServer().on("error", () => process.exit(1)).listen(Number(process.argv[1]), "127.0.0.1", function () { this.close(); });' "$1"
}

# smoke-env's lines are the env of next build and next start; {fixtures} is the
# fixture server on a free port, the same for both, serving the committed files
# of tools/verify/smoke-fixtures/ at any depth, and {state} a folder of the
# step's own. Both are gone when the step ends.
test_smoke_env_serves_the_committed_fixtures_to_the_build_and_the_server_with_node() {
	env_project
	mkdir -p tools/verify/smoke-fixtures/feeds
	printf 'BEGIN:VCALENDAR\nEND:VCALENDAR\n' > tools/verify/smoke-fixtures/feeds/cal.ics
	printf '%s\n' '' 'FEED_URL={fixtures}/feeds/cal.ics' 'CACHE_PATH={state}/events.sqlite' >> tools/verify/smoke-env
	step smoke
	assert_status 0
	assert_eq "" "$out" "smoke's findings"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	local feed cache state port
	feed="$(head -n 1 "$TEST_TMP/next.log" | cut -d'|' -f2)"
	cache="$(head -n 1 "$TEST_TMP/next.log" | cut -d'|' -f3)"
	[[ $feed =~ ^http://127\.0\.0\.1:([0-9]+)/feeds/cal\.ics$ ]] || fail "FEED_URL is not {fixtures}/feeds/cal.ics: $feed"
	port="${BASH_REMATCH[1]}"
	state="${cache%/events.sqlite}"
	[ "$state" != "$cache" ] && [ -n "$state" ] || fail "CACHE_PATH is not {state}/events.sqlite: $cache"
	assert_eq "build|$feed|$cache|200 text/calendar \"BEGIN:VCALENDAR\\nEND:VCALENDAR\\n\"
start|$feed|$cache|200 text/calendar \"BEGIN:VCALENDAR\\nEND:VCALENDAR\\n\"" "$(cat "$TEST_TMP/next.log")" "the env of next build and next start, and what the feed answered"
	[ ! -e "$state" ] || fail "the state folder outlived the step: $state"
	port_free "$port" || fail "the fixture server outlived the step, on port $port"
}

# The adapter's smoke-env names nothing: the app gets no env of the step's, and
# no fixture server starts (a seed it couldn't read would stop it).
test_an_empty_smoke_env_starts_no_fixture_server_with_node() {
	env_project
	mkdir -p tools/verify/smoke-fixtures && ln -s nowhere tools/verify/smoke-fixtures/broken.ics || fail "could not make the seed"
	step smoke
	assert_status 0
	assert_eq "" "$out" "smoke's findings"
	assert_eq "build|||
start|||" "$(cat "$TEST_TMP/next.log")" "the env of next build and next start"
}

# A line that isn't NAME=value or names the steps' own, a {fixtures} target with
# no file, and a seed the fixture server can't read: each is a finding at its
# line, before the build.
test_a_bad_smoke_env_is_a_finding_before_the_build_with_node() {
	env_project
	local base n line
	base="$(cat tools/verify/smoke-env)"
	n="$(($(wc -l < tools/verify/smoke-env) + 2))"
	for line in 'feed_url=x' 'FEED_URL' ' FEED_URL=x' '1FEED=x' 'FACTORY_X=x' 'NX_LIMIT=9'; do
		printf '%s\n\n%s\n' "$base" "$line" > tools/verify/smoke-env
		step smoke
		assert_status 1
		assert_eq "tools/verify/smoke-env:$n smoke-env '$line' is not NAME=value, NAME in capitals, digits and _, and none of the steps' own (NX_*, FACTORY_*)" "$out" "the line '$line'"
	done
	mkdir -p tools/verify/smoke-fixtures
	echo here > tools/verify/smoke-fixtures/here.json
	printf '%s\n' 'BASE={fixtures}' 'FEED_URL={fixtures}/feed.ics {fixtures}/here.json' 'MORE={fixtures}/a/b.ics#top' \
		'QUERY={fixtures}/here.json?x=1' 'TOP={fixtures}/here.json#top' > tools/verify/smoke-env
	step smoke
	assert_status 1
	assert_eq "tools/verify/smoke-env:2 smoke-env {fixtures}/feed.ics names no fixture: tools/verify/smoke-fixtures/feed.ics is no file
tools/verify/smoke-env:3 smoke-env {fixtures}/a/b.ics names no fixture: tools/verify/smoke-fixtures/a/b.ics is no file
tools/verify/smoke-env:4 smoke-env {fixtures}/here.json carries a query, but a smoke fixture answers its path alone" "$out" "the missing fixtures and the query"
	printf '%s\n' '# the feed' 'FEED_URL={fixtures}/here.json' > tools/verify/smoke-env
	ln -s nowhere tools/verify/smoke-fixtures/broken.ics || fail "could not make the broken seed"
	step smoke
	assert_status 1
	assert_eq "tools/verify/smoke-env:2 smoke-env the fixture server (tools/verify/_scenario_fixtures.mjs) exited 1 before it listened (see stderr)" "$out" "a seed the server can't read"
	stderr_has "fixtures: seed: ENOENT"
	[ ! -e "$TEST_TMP/next.log" ] || fail "next ran on a bad smoke-env: $(cat "$TEST_TMP/next.log")"
}
