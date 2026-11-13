# The Next.js adapter's verify-<project> generator (verify-skill.sh), through the
# Core's factory/core/verify-skill.sh, on small made-up projects. None needs Node.

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
