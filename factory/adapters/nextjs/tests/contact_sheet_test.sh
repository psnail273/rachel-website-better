# The Next.js contact sheet (tools/verify/contact-sheet, _contact_sheet.mjs):
# not a gate step, but smoke's build and server (_server.sh) and route reader
# (_routes.mjs), and a screenshot of each page route at each width and scheme.
# It runs against smoke's stand-in for next (tests/fixture/smoke/next.mjs),
# serving a folder of pages.
#
# The test that takes the sheet starts a real Chromium (and the stand-in server
# in the background) and needs Node, pnpm, a primed pnpm store
# (FACTORY_PNPM_STORE) and Chromium (FACTORY_PLAYWRIGHT_BROWSERS); it skips
# without them. The routes' test needs Node alone, the setting's nothing.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# routes <line...>: ARCHITECTURE.md's Routes table holds these lines alone.
routes() {
	{
		printf '# Architecture\n\n## Routes\n\n```\n'
		printf '%s\n' "$@"
		printf '```\n\n## Modules\n'
	} > ARCHITECTURE.md
}

# page <html> <route>: the stand-in's page at <route>.
page() {
	mkdir -p "$TEST_TMP/site$2"
	printf '<!doctype html><html lang="en"><head><title>t</title></head><body><p>hi</p>%s</body></html>\n' "$1" > "$TEST_TMP/site$2/index.html"
}

# files_in <dir>: the names of the folder's files, one a line, sorted.
files_in() {
	local f
	for f in "$1"/*; do
		[ ! -e "$f" ] || basename "$f"
	done | LC_ALL=C sort
}

# png_width <file>: the PNG's width in pixels, from its header.
png_width() {
	od -An -tu1 -j16 -N4 "$1" | awk '{ print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }'
}

# Two page routes give twelve screenshots, each route at 390, 768 and 1280 px,
# light and dark, named as the Board names its files, and an index naming the
# commit; the route handler and the method line get none. The index lists what
# axe couldn't decide at 390 and 1280 px (the contrast of text over a gradient),
# naming the screenshots, and no finding. stdout is the folder alone, and the
# server is gone after; on a page axe decides everything on, the list is none.
test_the_sheet_holds_each_page_route_at_each_width_and_scheme_with_node() {
	needs_browser
	skeleton_project
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed on the skeleton: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	rm -f node_modules/.bin/next && cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_PID="$TEST_TMP/server.pid"
	routes '/  app/page.tsx  Home' '/therapy/about  app/therapy/about/page.tsx  About' \
		'POST /api/x  app/api/x/route.ts  no page' '/api/health  app/api/health/route.ts  handler'
	page '<style>@media (prefers-color-scheme: dark) { body { background: #000; color: #fff } }</style>' /
	page '<p class="over" style="background-image: linear-gradient(#000, #fff); color: #777">over</p>' /therapy/about
	git add -A && git commit -qm init || fail "could not commit the project"
	local head folder
	head="$(git rev-parse --short HEAD)"
	folder="$(git rev-parse --absolute-git-dir)/factory/contact-sheet"
	mkdir -p "$folder" && : > "$folder/stale.png"

	step contact-sheet
	assert_status 0
	assert_eq "$folder" "$out" "contact-sheet's stdout"
	assert_eq "home-1280-dark.png
home-1280-light.png
home-390-dark.png
home-390-light.png
home-768-dark.png
home-768-light.png
index.md
therapy-about-1280-dark.png
therapy-about-1280-light.png
therapy-about-390-dark.png
therapy-about-390-light.png
therapy-about-768-dark.png
therapy-about-768-light.png" "$(files_in "$folder")" "the sheet's files"
	assert_eq "# Contact sheet

Taken from $head: each page route at 390, 768, 1280 px wide (the window 900 tall, the whole page captured), light and dark, with reduced motion. Each file is \`<route-slug>-<width>-<scheme>.png\`, named as the Board's are (\`docs/design/board/\`).

- \`/\`: home-390-light.png, home-390-dark.png, home-768-light.png, home-768-dark.png, home-1280-light.png, home-1280-dark.png
- \`/therapy/about\`: therapy-about-390-light.png, therapy-about-390-dark.png, therapy-about-768-light.png, therapy-about-768-dark.png, therapy-about-1280-light.png, therapy-about-1280-dark.png

## Axe couldn't decide

What axe checked at 390 and 1280 px and couldn't decide (its incomplete results; smoke's rules), such as the contrast of text over an image: judge each by eye in the screenshots it names. None gates. One line per route, rule and selector:

- \`/therapy/about\` color-contrast \`p.over\`: Element's background color could not be determined due to a background gradient (therapy-about-390-light.png, therapy-about-390-dark.png, therapy-about-1280-light.png, therapy-about-1280-dark.png)" "$(cat "$folder/index.md")" "the index"
	assert_eq "390 768 1280" "$(png_width "$folder/home-390-light.png") $(png_width "$folder/home-768-dark.png") $(png_width "$folder/therapy-about-1280-light.png")" "the screenshots' widths"
	! cmp -s "$folder/home-390-light.png" "$folder/home-390-dark.png" || fail "the dark scheme's screenshot is the light one's"
	wait_until "the server to stop" eval '! kill -0 "$(cat "$TEST_TMP/server.pid")" 2> /dev/null'

	echo changed >> ARCHITECTURE.md
	page '' /therapy/about
	step contact-sheet
	assert_status 0
	assert_eq "Taken from $head, with changes not committed:" "$(sed -n 3p "$folder/index.md" | sed 's/: each page route.*/:/')" "the index of a changed tree"
	assert_eq "- none" "$(tail -n 1 "$folder/index.md")" "the list of a sheet axe decided everything on"
}

# No page route to take is a finding, before any build; so is no ARCHITECTURE.md.
test_no_page_route_is_a_finding_before_the_build_with_node() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin
	printf '#!/usr/bin/env bash\necho "$1" >> %q\nexit 3\n' "$TEST_TMP/next.log" > node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	routes 'POST /api/x  app/api/x/route.ts  no page' '/api/health  app/api/health/route.ts  handler'
	step contact-sheet
	assert_status 1
	assert_eq "ARCHITECTURE.md:3 contact-sheet-routes the \`## Routes\` table lists no page route: a line whose first field is its path, \`/\` and on" "$out" "contact-sheet's finding"
	rm ARCHITECTURE.md
	step contact-sheet
	assert_status 1
	assert_eq "ARCHITECTURE.md:1 contact-sheet-routes can't read ARCHITECTURE.md (ENOENT), whose \`## Routes\` table lists the page routes" "$out" "contact-sheet's finding with no ARCHITECTURE.md"
	[ ! -e "$TEST_TMP/next.log" ] || fail "next ran with no route to take: $(cat "$TEST_TMP/next.log")"
}

# Its limit is smoke's setting, and a bad one is a finding before anything runs.
test_a_bad_limit_is_a_setting_finding() {
	skeleton_project
	FACTORY_SMOKE_TIMEOUT=soon step contact-sheet
	assert_status 1
	assert_eq "tools/verify/local.env:1 contact-sheet-setting FACTORY_SMOKE_TIMEOUT is 'soon', not a number of seconds from 1 to 999999" "$out" "contact-sheet's finding"
	[ ! -e "$(git rev-parse --absolute-git-dir)/factory/contact-sheet" ] || fail "contact-sheet made its folder on a bad setting"
}

# It reads smoke's tools/verify/smoke-env: a bad line is a finding of its own,
# before the build.
test_a_bad_smoke_env_is_a_finding_before_the_build_with_node() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin
	printf '#!/usr/bin/env bash\necho "$1" >> %q\nexit 3\n' "$TEST_TMP/next.log" > node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	routes '/  app/page.tsx  Home'
	printf 'feed_url=x\n' > tools/verify/smoke-env
	step contact-sheet
	assert_status 1
	assert_eq "tools/verify/smoke-env:1 contact-sheet-env 'feed_url=x' is not NAME=value, NAME in capitals, digits and _, and none of the steps' own (NX_*, FACTORY_*)" "$out" "contact-sheet's finding"
	printf 'FEED_URL={fixtures}/feed.ics\n' > tools/verify/smoke-env
	step contact-sheet
	assert_status 1
	assert_eq "tools/verify/smoke-env:1 contact-sheet-env {fixtures}/feed.ics names no fixture: tools/verify/smoke-fixtures/feed.ics is no file" "$out" "contact-sheet's finding"
	[ ! -e "$TEST_TMP/next.log" ] || fail "next ran on a bad smoke-env: $(cat "$TEST_TMP/next.log")"
}
