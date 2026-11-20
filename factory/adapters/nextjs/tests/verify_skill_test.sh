# The Next.js adapter's verify-<project> generator (verify-skill.sh), through the
# Core's factory/core/verify-skill.sh, on small made-up projects, and the two
# helpers it copies into the skill (verify-skill-helpers/). The generator's tests
# need nothing. The contrast arithmetic's needs Node; the app helper's starts a
# real Chromium (and smoke's stand-in for next in the background) on the primed
# skeleton, and needs Node, pnpm, a primed pnpm store (FACTORY_PNPM_STORE) and
# the browsers (FACTORY_PLAYWRIGHT_BROWSERS); each skips without them.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
. "$FACTORY_CORE/../adapters/nextjs/tests/lib.sh"

generate() {
	run_cmd bash "$FACTORY_CORE/verify-skill.sh" --adapter nextjs "$@"
}

# small_app: $TEST_TMP/project (no git), a Next.js app named "small-shop" with a
# page, a route group, a dynamic segment, a parallel slot, a private folder, an
# API route with a test beside it, a tool script and a CONTEXT.md; cd there.
small_app() {
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "could not make the project"
	unset FACTORY_PROJECT
	mkdir -p "app/(shop)/cart" "app/items/[id]" app/@modal/login app/_parts app/api/health app/api/orders tools node_modules/x .next/server/app
	printf '{\n  "name": "small-shop",\n  "private": true\n}\n' > package.json
	echo "export default function P() { return null; }" | tee app/page.tsx "app/(shop)/cart/page.tsx" "app/items/[id]/page.tsx" app/@modal/login/page.tsx app/_parts/page.tsx node_modules/x/page.tsx .next/server/app/page.tsx > /dev/null
	echo "export function GET() { return Response.json({}); }" | tee app/api/health/route.ts app/api/orders/route.ts > /dev/null
	echo "test" | tee app/api/orders/route.test.ts app/api/orders/total.test.ts "app/(shop)/cart/cart.test.tsx" > /dev/null
	printf '#!/usr/bin/env bash\n# Seeds the dev database. Run from the root:\n#   bash tools/seed.sh\n' > tools/seed.sh
	echo "# Terms" > CONTEXT.md
}

test_the_small_app_skill_and_feature_map() {
	small_app
	generate --out "$TEST_TMP/skill"
	assert_status 0
	local skill="$TEST_TMP/skill/SKILL.md" map="$TEST_TMP/skill/feature-map.md"
	grep -qxF "name: verify-project" "$skill" || fail "the skill isn't named after the folder"
	grep -qF 'Launch, drive and inspect the running small-shop app (Next.js)' "$skill" || fail "no package name in the description"
	grep -qF '**Health**: `curl -fsS http://localhost:3100/api/health`' "$skill" || fail "no health check"
	grep -qxF -- '  - `bash tools/seed.sh`: Seeds the dev database.' "$skill" || fail "wrong tool line"
	grep -qF 'Names follow `CONTEXT.md`.' "$skill" || fail "no domain-doc pointer"
	grep -qF 'read `docs/agents/devices.md`' "$skill" && fail "a devices doc it doesn't have"
	assert_eq '| `/` | page | `app/page.tsx` | none |
| `/api/health` | API | `app/api/health/route.ts` | none |
| `/api/orders` | API | `app/api/orders/route.ts` | `route.test.ts`, `total.test.ts` |
| `/cart` | page | `app/(shop)/cart/page.tsx` | `cart.test.tsx` |
| `/items/[id]` | page | `app/items/[id]/page.tsx` | none |
| `/login` | page | `app/@modal/login/page.tsx` | none |' "$(grep '^| `' "$map")" "the feature map rows"
}

test_a_src_app_router_is_mapped() {
	mkdir -p "$TEST_TMP/project/src/app/about" && cd "$TEST_TMP/project" || fail "no project"
	echo "x" > src/app/about/page.mdx
	FACTORY_PROJECT=site generate --out "$TEST_TMP/skill"
	assert_status 0
	assert_eq '| `/about` | page | `src/app/about/page.mdx` | none |' "$(grep '^| `' "$TEST_TMP/skill/feature-map.md")" "the feature map rows"
	grep -qF '**Health**' "$TEST_TMP/skill/SKILL.md" && fail "a health check the app lacks"
	grep -qF 'running site app' "$TEST_TMP/skill/SKILL.md" || fail "no project name without a package.json"
}

test_a_bare_project_still_gets_every_section() {
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "no project"
	FACTORY_PROJECT=bare generate --out "$TEST_TMP/skill"
	assert_status 0
	grep -qF 'no App Router folder' "$TEST_TMP/skill/feature-map.md" || fail "no fallback in the feature map"
}

test_a_long_name_keeps_the_description_in_budget() {
	small_app
	sed -i "s/small-shop/$(printf 'a%.0s' $(seq 1 120))/" package.json
	generate --out "$TEST_TMP/skill"
	assert_status 0
	grep -qF "description: Launch, drive and inspect this project's running Next.js app" "$TEST_TMP/skill/SKILL.md" || fail "the long name stayed in the description"
}

# The skill's shell setup is the steps' own: local.env, then _nextjs.sh.
test_the_skill_sets_the_shell_up_as_the_steps_do() {
	small_app
	generate --out "$TEST_TMP/skill"
	assert_status 0
	grep -qF '`set -a; . tools/verify/local.env; set +a; . tools/verify/_nextjs.sh`' "$TEST_TMP/skill/SKILL.md" || fail "no shell setup"
}

# In a checkout: a route deleted but not yet staged is gone from the map, and a
# path git would quote (non-ASCII) is listed as it is.
test_in_a_checkout_the_map_follows_the_files_on_disk() {
	small_app
	isolate_git
	mkdir -p app/about "app/café"
	echo "x" | tee app/about/page.tsx "app/café/page.tsx" > /dev/null
	printf '/node_modules/\n/.next/\n' > .gitignore
	git init -q . && git add -A && git commit -q -m app || fail "could not commit the app"
	rm app/about/page.tsx
	generate --out "$TEST_TMP/skill"
	assert_status 0
	grep -qF '/about' "$TEST_TMP/skill/feature-map.md" && fail "a deleted route is mapped"
	grep -qxF '| `/café` | page | `app/café/page.tsx` | none |' "$TEST_TMP/skill/feature-map.md" ||
		fail "the non-ASCII route isn't mapped:"$'\n'"$(cat "$TEST_TMP/skill/feature-map.md")"
}

test_the_small_app_twice_is_identical() {
	small_app
	generate --out "$TEST_TMP/one"
	generate --out "$TEST_TMP/two"
	diff -r "$TEST_TMP/one" "$TEST_TMP/two" > /dev/null || fail "two runs differ"
}

# In a git checkout the files come from git: ignored ones (node_modules/, .next/)
# never reach the map.
test_in_a_checkout_ignored_files_are_left_out() {
	small_app
	isolate_git
	printf '/node_modules/\n/.next/\napp/_parts/\n' > .gitignore
	git init -q . || fail "git init failed"
	echo "export default function P() { return null; }" > app/_parts/page.tsx
	generate --out "$TEST_TMP/skill"
	assert_status 0
	assert_eq 6 "$(grep -c '^| `/' "$TEST_TMP/skill/feature-map.md")" "the feature map rows"
}

# --- the helpers: app.sh and contrast.mjs ----------------------------------------------

# The skill folder carries both helpers as the adapter holds them, and SKILL.md
# says how to start, read a contrast with and stop by them, and never to pkill.
test_the_skill_carries_the_app_and_contrast_helpers() {
	small_app
	generate --out "$TEST_TMP/skill"
	assert_status 0
	local skill="$TEST_TMP/skill/SKILL.md" helpers="$FACTORY_CORE/../adapters/nextjs/verify-skill-helpers" f
	for f in app.sh contrast.mjs; do
		cmp -s "$helpers/$f" "$TEST_TMP/skill/$f" || fail "the skill's $f isn't the adapter's"
	done
	grep -qF '`bash .claude/skills/verify-project/app.sh start` builds' "$skill" || fail "no start line in Launch"
	grep -qF '`bash .claude/skills/verify-project/app.sh contrast <route>' "$skill" || fail "no contrast line in Evidence"
	grep -qF '`bash .claude/skills/verify-project/app.sh stop` stops' "$skill" || fail "no stop line in Cleanup"
	grep -qF 'Never `pkill`' "$skill" || fail "no word against pkill"
	grep -qF '@SKILL@' "$skill" && fail "a placeholder left in SKILL.md"
	sed -n '/^## Evidence/,/^## Cleanup/p' "$skill" | grep -qF 'app.sh contrast' || fail "the contrast line isn't under Evidence"
}

# contrast.mjs's arithmetic, on known colours and pixels: WCAG's ratio cut (not
# rounded) to two decimals; the text colour is the glyphs' core, not their
# anti-aliased edge; the background is the commonest colour behind; worst is
# against the darkest pixel right under the text. And the PNG reader, on a PNG
# whose rows use each of the five filters.
test_the_contrast_arithmetic_with_node() {
	needs_node
	local helper="$FACTORY_CORE/../adapters/nextjs/verify-skill-helpers/contrast.mjs"
	run_cmd env CONTRAST_HELPER="$helper" node --input-type=module -e '
		import { deflateSync } from "node:zlib";
		const m = await import(process.env.CONTRAST_HELPER);
		const px = (...cs) => Uint8Array.from(cs.flatMap((c) => [...c, 255]));
		const W = [255, 255, 255], G = [0x77, 0x77, 0x77], E = [0xbb, 0xbb, 0xbb], D = [0xee, 0xee, 0xee];
		console.log(m.cut(m.ratio(G, W)), m.cut(m.ratio(W, G)), m.cut(m.ratio([0, 0, 0], W)), m.cut(4.499));
		// 20 pixels: 12 white behind, 8 light grey; text: 10 core grey, 2 edge.
		const bg = [...Array(12).fill(W), ...Array(8).fill(D)];
		const text = bg.map((c, i) => (i < 10 ? G : i < 12 ? E : c));
		text[12] = G;
		const r = m.measure(px(...text), px(...bg));
		console.log(m.cut(r.contrast), m.hex(r.text), m.hex(r.background), r.share, m.cut(r.worst), m.hex(r.worstBackground));
		console.log(m.measure(px(W, W), px(W, W)));
		// A 3x5 PNG, colour type 2, row y filtered with filter y.
		const w = 3, h = 5, raw = [];
		for (let y = 0; y < h; y++) for (let x = 0; x < w * 3; x++) raw.push((x * 37 + y * 91 + 11) & 255);
		const at = (x, y) => (x < 0 || y < 0 ? 0 : raw[y * w * 3 + x]);
		const rows = [];
		for (let y = 0; y < h; y++) {
			rows.push(y);
			for (let x = 0; x < w * 3; x++) {
				const a = at(x - 3, y), b = at(x, y - 1), c = at(x - 3, y - 1);
				const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
				const pred = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][y];
				rows.push((at(x, y) - pred) & 255);
			}
		}
		const chunk = (name, body) => {
			const b = Buffer.alloc(12 + body.length);
			b.writeUInt32BE(body.length, 0); b.write(name, 4, "ascii"); body.copy(b, 8);
			return b;
		};
		const ihdr = Buffer.alloc(13);
		ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
		const png = Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(Buffer.from(rows))), chunk("IEND", Buffer.alloc(0))]);
		const d = m.decodePng(png);
		const rgb = [...d.data].filter((_, i) => i % 4 !== 3);
		console.log(d.width, d.height, rgb.every((v, i) => v === raw[i]), [...d.data].filter((_, i) => i % 4 === 3).every((v) => v === 255));
	'
	assert_status 0
	assert_eq "4.47 4.47 21.00 4.49
4.47 #777777 #ffffff 60 3.85 #eeeeee
null
3 5 true true" "$out" "the readings"
}

# app_page: the stand-in's page at /, with a text box read mid-transition and
# one read mid-animation: each would read near white before they settle, #777777
# on white after.
app_page() {
	mkdir -p "$TEST_TMP/site"
	cat > "$TEST_TMP/site/index.html" << 'HTML'
<!doctype html><html lang="en"><head><title>t</title><style>
body { background: #fff; margin: 0; }
p { font: 32px/1.2 sans-serif; margin: 20px; }
#fade { color: #fff; transition: color 600s linear; }
#fade.in { color: #777; }
@keyframes rise { from { color: #fff; } }
#rise { color: #777; animation: rise 600s linear; }
</style></head><body>
<p id="fade">Fading in slowly</p><p id="rise">Rising in slowly</p>
<script>requestAnimationFrame(() => requestAnimationFrame(() => document.getElementById("fade").classList.add("in")));</script>
</body></html>
HTML
}

# The app helper on the primed skeleton, against smoke's stand-in for next:
# start builds, starts on a free port and prints the url, pid, env and log; the
# env holds the URL and the browsers folder from local.env's
# FACTORY_PLAYWRIGHT_BROWSERS (its PLAYWRIGHT_BROWSERS_PATH empty); a second
# start is refused while it runs; contrast reads each box after it settles;
# stop ends the server and nothing else (a process of the test's own lives on);
# a second stop has nothing to stop.
test_the_app_helper_starts_reads_and_stops_only_its_own_with_node() {
	needs_browser
	primed_project
	rm -f node_modules/.bin/next && cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	export STAND_IN_SITE="$TEST_TMP/site" STAND_IN_PID="$TEST_TMP/server.pid"
	app_page
	printf 'PLAYWRIGHT_BROWSERS_PATH=\nFACTORY_PLAYWRIGHT_BROWSERS=%s\n' "$FACTORY_PLAYWRIGHT_BROWSERS" > tools/verify/local.env
	unset PLAYWRIGHT_BROWSERS_PATH
	git add -A && git commit -qm init || fail "could not commit the project"
	generate --out .claude/skills/verify-project
	assert_status 0
	local app=.claude/skills/verify-project/app.sh state url pid
	state="$(git rev-parse --absolute-git-dir)/factory/app"
	trap 'bash .claude/skills/verify-project/app.sh stop > /dev/null 2>&1' EXIT

	run_cmd bash "$app" start
	assert_status 0
	url="$(printf '%s\n' "$out" | sed -n 's/^url //p')"
	pid="$(printf '%s\n' "$out" | sed -n 's/^pid //p')"
	[[ $url =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || fail "no url line: $out"
	[ -n "$pid" ] && kill -0 "$pid" 2> /dev/null || fail "no live pid line: $out"
	tether "$pid"
	assert_eq "url $url
pid $pid
env $state/env
log $state/server.log" "$out" "start's stdout"
	assert_eq "APP_URL=$url
PLAYWRIGHT_BROWSERS_PATH=$FACTORY_PLAYWRIGHT_BROWSERS" "$(cat "$state/env")" "the env file"

	run_cmd bash "$app" start
	assert_status 1
	grep -qF "still runs (pid $pid, $url)" "$TEST_TMP/stderr" || fail "a second start wasn't refused: $(cat "$TEST_TMP/stderr")"

	run_cmd bash "$app" contrast / '#fade'
	assert_status 0
	assert_eq "contrast 4.47:1
text #777777
background #ffffff" "$(printf '%s\n' "$out" | sed -n '1,3p' | sed 's/ [0-9]*%$//')" "the transition's box"
	run_cmd bash "$app" contrast / '#rise'
	assert_status 0
	assert_eq "contrast 4.47:1" "$(printf '%s\n' "$out" | sed -n 1p)" "the animation's box"
	run_cmd bash "$app" run sh -c 'printf "%s\n" "$APP_URL"'
	assert_status 0
	assert_eq "$url" "$out" "run's APP_URL"

	blocking_stand_in "$TEST_TMP/bystander" "$TEST_TMP/release"
	"$TEST_TMP/bystander" > /dev/null 2>&1 &
	local bystander=$!
	wait_until "the bystander to start" test -s "$TEST_TMP/bystander.pid"
	run_cmd bash "$app" stop
	assert_status 0
	assert_eq "stopped $pid" "$out" "stop's stdout"
	wait_until "the server to stop" eval '! kill -0 "$(cat "$TEST_TMP/server.pid")" 2> /dev/null'
	kill -0 "$bystander" 2> /dev/null || fail "stop ended a process it didn't start"
	: > "$TEST_TMP/release"
	wait "$bystander"
	run_cmd bash "$app" stop
	assert_eq "nothing to stop" "$out" "a second stop"
}

# With a smoke-env that names {fixtures}, start starts the fixture server too and
# keeps its pid. When the server dies without a stop (killed by hand here), the
# next start stops that fixture server before it starts afresh, so stop still
# reaches everything start started.
test_a_restart_after_the_server_died_stops_the_old_fixture_server_with_node() {
	needs_node
	primed_project
	rm -f node_modules/.bin/next && cp "$NEXTJS_FIXTURES/smoke/next.mjs.txt" node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	export STAND_IN_SITE="$TEST_TMP/site"
	app_page
	echo 'FEED_URL={fixtures}/feed.txt' > tools/verify/smoke-env
	mkdir -p tools/verify/smoke-fixtures && echo feed > tools/verify/smoke-fixtures/feed.txt
	git add -A && git commit -qm init || fail "could not commit the project"
	generate --out .claude/skills/verify-project
	assert_status 0
	local app=.claude/skills/verify-project/app.sh state server fixtures
	state="$(git rev-parse --absolute-git-dir)/factory/app"
	trap 'bash .claude/skills/verify-project/app.sh stop > /dev/null 2>&1' EXIT

	run_cmd bash "$app" start
	assert_status 0
	server="$(printf '%s\n' "$out" | sed -n 's/^pid //p')"
	fixtures="$(cat "$state/fixtures.pid")"
	tether "$server"
	tether "$fixtures"
	kill -0 "$fixtures" 2> /dev/null || fail "no fixture server running"
	kill -TERM -- "-$server"
	wait_until "the server to die" eval '! kill -0 "$server" 2> /dev/null'

	run_cmd bash "$app" start
	assert_status 0
	grep -qxF "stopped $fixtures" "$TEST_TMP/stderr" || fail "the old fixture server wasn't stopped: $(cat "$TEST_TMP/stderr")"
	wait_until "the old fixture server to stop" eval '! kill -0 "$fixtures" 2> /dev/null'
	[ "$(cat "$state/fixtures.pid")" != "$fixtures" ] || fail "the old fixture server's pid is still kept"
	run_cmd bash "$app" stop
	assert_status 0
	assert_eq 2 "$(printf '%s\n' "$out" | grep -c '^stopped ')" "stop's lines"
}
