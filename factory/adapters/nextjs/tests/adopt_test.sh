# The Next.js adapter's part of adoption (adopt.sh, ARCHITECTURE.md), and the
# whole of it end to end: `install.sh <project> nextjs --new` from a clone of the
# factory makes a project whose full gate passes and which arms at once, and
# `adopt.sh nextjs` on a project from before the factory records its Baseline.
#
# Those two need Node, pnpm, a primed pnpm store (FACTORY_PNPM_STORE) and
# the three browsers, Chromium, Firefox and WebKit (FACTORY_PLAYWRIGHT_BROWSERS),
# and skip without them; they install offline from the store and run the full
# verify, the real smoke step's next build, next start and browsers too, so they
# take a while. The rest need
# nothing.

NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# bootstrap_stand_in <status>: $TEST_TMP/project with a tools/verify/bootstrap
# that logs the MARK it sees to $TEST_TMP/bootstrap.log and exits <status>; cd there.
bootstrap_stand_in() {
	mkdir -p "$TEST_TMP/project/tools/verify" && cd "$TEST_TMP/project" || fail "no project"
	printf 'echo "bootstrap ${MARK:-}" >> "%s/bootstrap.log"\nexit %s\n' "$TEST_TMP" "$1" > tools/verify/bootstrap
}

test_adopt_runs_bootstrap_with_the_machines_local_env() {
	bootstrap_stand_in 0
	echo MARK=from-local-env > tools/verify/local.env
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh" --new
	assert_status 0
	assert_eq "bootstrap from-local-env" "$(cat "$TEST_TMP/bootstrap.log")" "the bootstrap run"
}

test_adopt_seeds_the_test_configs_from_the_skeleton() {
	bootstrap_stand_in 0
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh"
	assert_status 0
	cmp -s "$NEXTJS_ADAPTER/new/vitest.config.ts.txt" vitest.config.ts || fail "vitest.config.ts isn't the skeleton's"
	cmp -s "$NEXTJS_ADAPTER/new/stryker.config.json.txt" stryker.config.json || fail "stryker.config.json isn't the skeleton's"
}

test_adopt_keeps_the_projects_own_test_configs() {
	bootstrap_stand_in 0
	echo "// the project's vitest" > vitest.config.ts
	echo '{"the": "project'"'"'s"}' > stryker.config.json
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh"
	assert_status 0
	assert_eq "// the project's vitest" "$(cat vitest.config.ts)" "vitest.config.ts was overwritten"
	assert_eq '{"the": "project'"'"'s"}' "$(cat stryker.config.json)" "stryker.config.json was overwritten"
	stderr_has "kept vitest.config.ts"
	stderr_has "kept stryker.config.json"
}

# A config under another name Vitest or Stryker reads keeps ours out: Vitest
# would read a vitest.config.ts before the project's vite.config.mts.
test_adopt_keeps_test_configs_under_other_names() {
	bootstrap_stand_in 0
	echo "// the project's vite" > vite.config.mts
	echo "// the project's stryker" > stryker.conf.mjs
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh"
	assert_status 0
	[ ! -e vitest.config.ts ] || fail "vitest.config.ts was seeded beside vite.config.mts"
	[ ! -e stryker.config.json ] || fail "stryker.config.json was seeded beside stryker.conf.mjs"
	stderr_has "kept vite.config.mts"
	stderr_has "kept stryker.conf.mjs"
}

# A seeded Stryker config points Vitest at the project's own config.
test_a_seeded_stryker_config_names_the_projects_vitest_config() {
	bootstrap_stand_in 0
	echo "// the project's vitest" > vitest.config.mts
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh"
	assert_status 0
	[ ! -e vitest.config.ts ] || fail "vitest.config.ts was seeded beside vitest.config.mts"
	assert_eq '  "vitest": { "configFile": "vitest.config.mts" }' "$(grep configFile stryker.config.json)" "the seeded Stryker config's Vitest config"
}

test_adopt_goes_on_when_bootstrap_fails_and_says_how_to_resume() {
	bootstrap_stand_in 1
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh"
	assert_status 0
	assert_eq "bootstrap " "$(cat "$TEST_TMP/bootstrap.log")" "the bootstrap run"
	stderr_has "run bash tools/verify/bootstrap, then bash factory/core/adopt.sh nextjs again"
}

test_adopt_needs_the_seeded_bootstrap() {
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "no project"
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh"
	assert_status 1
	stderr_has "no tools/verify/bootstrap"
}

test_the_adapter_adopt_sh_usage() {
	bootstrap_stand_in 0
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh" --old
	assert_status 2
	run_cmd bash "$NEXTJS_ADAPTER/adopt.sh" --new extra
	assert_status 2
	[ ! -e "$TEST_TMP/bootstrap.log" ] || fail "bootstrap ran on a usage error"
}

# The default rules cite exactly the checks the arch step registers, and each
# other rule is enforced by typecheck, a lint rule, deviation or review.
test_the_default_architecture_md_cites_each_arch_check() {
	. "$FACTORY_CORE/lib/architecture.sh"
	local doc="$NEXTJS_ADAPTER/ARCHITECTURE.md"
	assert_eq "$(sed -n 's/^factory_arch_check \([^ ]*\) .*/\1/p' "$NEXTJS_ADAPTER/tools/verify/arch" | LC_ALL=C sort)" \
		"$(factory_arch_parse "$doc" | awk '$1 == "tag" { print $4 }' | LC_ALL=C sort)" "the arch:<id> tags against the arch step's checks"
	[ "$(factory_arch_parse "$doc" | grep -c '^rule ')" -ge 1 ] || fail "no rules"
	assert_eq "" "$(grep '^Enforced by:' "$doc" | sed 's/^Enforced by: *//; s/`\(typecheck\|deviation\|review\|lint:[^`]*\|arch:[^`]*\)`//g; s/[ ,]//g' | grep .)" "an Enforced by: naming something else"
	[ "$(wc -l < "$doc")" -le 150 ] || fail "the default ARCHITECTURE.md is over 150 lines"
}

# factory_clone: $TEST_TMP/clone, a clone (at tag v0.1.0) of a repo holding this
# factory at its root, as install.sh wants one.
factory_clone() {
	local src="$TEST_TMP/src"
	copy_factory "$src" || fail "could not copy the factory"
	git -C "$src" init -q -b main && git -C "$src" add -A && git -C "$src" commit -q -m "factory 0.1.0" &&
		git -C "$src" tag -a v0.1.0 -m "factory 0.1.0" || fail "could not commit the factory"
	git clone -q -b v0.1.0 "$src" "$TEST_TMP/clone" 2> /dev/null || fail "could not clone the factory"
}

# The brief's proof: install.sh --new in a fresh repo, then the full gate passes,
# and arm.sh (two more full verifies, which must match) arms it.
# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_install_new_makes_a_project_that_verifies_green_and_arms_with_node() {
	needs_browser
	isolate_git
	unset FACTORY_PROJECT FACTORY_LABEL_CMD FACTORY_BASE FACTORY_UPSTREAM FACTORY_INSTALL FACTORY_INSTALL_TAG FACTORY_INSTALL_UPSTREAM
	factory_clone
	mkdir -p "$TEST_TMP/web-shop" && cd "$TEST_TMP/web-shop" || fail "no project"
	echo "# Web shop" > README.md
	git init -q -b dev . && git add -A && git commit -q -m "the project" || fail "could not commit the project"

	run_cmd bash "$TEST_TMP/clone/core/install.sh" "$PWD" nextjs --new
	assert_status 0
	assert_last_line "baseline: RECORDED 0 entries in tools/verify/ratchet/baseline.txt"
	grep -qxF "  verify: verify: PASS" "$TEST_TMP/stderr" || fail "the Baseline's verify didn't pass:"$'\n'"$(grep 'verify:' "$TEST_TMP/stderr")"
	assert_eq '  "name": "web-shop",' "$(grep '"name"' package.json)" "the project's name"
	cmp -s "$NEXTJS_ADAPTER/ARCHITECTURE.md" ARCHITECTURE.md || fail "ARCHITECTURE.md isn't the adapter's default rules"
	local f
	for f in package.json pnpm-lock.yaml tsconfig.json eslint.config.mjs vitest.config.ts stryker.config.json app/page.tsx app/api/health/route.ts app/api/health/route.test.ts .gitignore \
		.claude/skills/write-tests-nextjs/SKILL.md .claude/skills/verify-web-shop/SKILL.md .claude/skills/verify-web-shop/feature-map.md; do
		[ -n "$(git ls-files -- "$f")" ] || fail "$f isn't staged"
	done
	grep -qxF '| `/api/health` | API | `app/api/health/route.ts` | `route.test.ts` |' .claude/skills/verify-web-shop/feature-map.md ||
		fail "the feature map lacks the health route:"$'\n'"$(cat .claude/skills/verify-web-shop/feature-map.md)"
	assert_eq "" "$(git status --porcelain | grep -v '^A ')" "adoption left files unstaged"
	assert_eq "" "$(git ls-files -- node_modules .next next-env.d.ts tools/verify/local.env)" "installed or generated files were staged"
	git commit -q -m "adopt the factory" || fail "could not commit the adoption"

	run_cmd bash tools/verify.sh
	assert_status 0
	assert_last_line "verify: PASS"
	# Every step is real: none is a no-op (mutate, the Core's optional step,
	# skips a tree with no change since its base).
	local s
	for s in prepare format typecheck lint arch deviation test smoke; do
		assert_line "== $s PASS"
	done

	run_cmd bash factory/core/arm.sh
	assert_status 0
	grep -qxF "  verify: verify: two runs match" "$TEST_TMP/stderr" || fail "arm.sh's verify:"$'\n'"$(cat "$TEST_TMP/stderr")"
	assert_eq enforce "$(git show :tools/verify/hook-mode | grep -v '^#')" "arm.sh didn't stage enforce"
	assert_eq "M  tools/verify/hook-mode" "$(git status --porcelain)" "arm.sh left more than the staged hook mode"
}

# adopt.sh nextjs on a project from before the factory (the skeleton, with a file
# Prettier would change and a floating promise): the Baseline holds both.
test_adopting_an_existing_project_records_its_baseline_with_node() {
	needs_browser
	isolate_git
	unset FACTORY_PROJECT FACTORY_LABEL_CMD FACTORY_BASE
	lay_skeleton "$TEST_TMP/existing" existing
	cd "$TEST_TMP/existing" || fail "no project"
	add_fixture format/unformatted.ts.txt lib/total.ts
	add_fixture lint/floating.ts.txt lib/submit.ts
	cp -R "$FACTORY_CORE/.." factory || fail "could not vendor the factory"
	git init -q -b dev . && git add -A && git commit -q -m "the existing project" || fail "could not commit the project"

	run_cmd bash factory/core/adopt.sh nextjs
	assert_status 0
	assert_last_line "baseline: RECORDED $(wc -l < tools/verify/ratchet/baseline.txt | tr -d ' ') entries in tools/verify/ratchet/baseline.txt"
	grep -q '^lib/total\.ts format ' tools/verify/ratchet/baseline.txt ||
		fail "the unformatted file isn't in the Baseline:"$'\n'"$(cat tools/verify/ratchet/baseline.txt)"
	grep -q '^lib/submit\.ts @typescript-eslint/no-floating-promises ' tools/verify/ratchet/baseline.txt ||
		fail "the floating promise isn't in the Baseline:"$'\n'"$(cat tools/verify/ratchet/baseline.txt)"
	assert_eq "" "$(git status --porcelain | grep -v '^[AM] ')" "adoption left files unstaged"
}
