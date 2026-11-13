# The Next.js adapter's step scripts (factory/adapters/nextjs/tools/verify) on a
# project made from its skeleton (new/), with the fixtures in tests/fixture
# (stored with .txt, so no tool reads them where they're stored).
#
# Most need Node, pnpm and a pnpm store primed with the skeleton's packages
# (FACTORY_PNPM_STORE; tests/prime-store.sh primes one), and skip without them;
# they install offline from that store. The rest run with no Node at all.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# prepared_project: skeleton_project, prepared (packages installed, route types
# generated), or fail.
prepared_project() {
	needs_store
	skeleton_project
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed on the skeleton: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
}

test_the_skeleton_passes_every_step_with_node() {
	prepared_project
	assert_eq "" "$out" "prepare's findings"
	[ -f next-env.d.ts ] && [ -d .next/types ] || fail "prepare didn't generate the route types"
	local s
	# smoke too runs on the skeleton, for real, in adopt_test.sh's end to end.
	for s in format typecheck lint test arch; do
		FACTORY_RESULTS_FILE="$TEST_TMP/results" step "$s"
		[ "$status" -eq 0 ] && [ -z "$out" ] || fail "$s on the skeleton: status $status: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	done
	assert_eq "" "$(git status --porcelain --ignored -- next-env.d.ts .next | grep -v '^!! ')" "generated files git would track"
}

test_versions_reads_back_every_pin_with_node() {
	prepared_project
	step versions
	assert_status 0
	assert_eq "$(grep -v '^#' tools/verify/pins | LC_ALL=C sort)" "$(printf '%s\n' "$out" | LC_ALL=C sort)" "versions against pins"
	run_cmd bash "$FACTORY_CORE/pins.sh"
	assert_status 0
}

test_prepare_reports_a_lockfile_out_of_step_with_package_json_with_node() {
	prepared_project
	sed -i 's/"next": "16.4.6"/"next": "16.4.5"/' package.json
	step prepare
	assert_status 1
	assert_eq "pnpm-lock.yaml:1 install-failed pnpm install --offline --frozen-lockfile exited 1 (see stderr); run bash tools/verify/bootstrap, the step allowed the network, then prepare again" "$out" "prepare's finding"
}

test_prepare_cross_checks_the_scope_against_tsc_with_node() {
	prepared_project
	add_fixture scope/legacy.cts.txt lib/legacy.cts
	add_fixture scope/vendored.ts.txt vendor/vendored.ts
	echo '!vendor/' >> tools/verify/scope
	step prepare
	assert_status 1
	local line
	line="$(grep -n '"include"' tsconfig.json | cut -d: -f1)"
	assert_eq "tsconfig.json:$line scope-not-typechecked lib/legacy.cts is in tools/verify/scope, but tsc doesn't compile it; add it to tsconfig.json's include
tsconfig.json:$line scope-unchecked tsc compiles vendor/vendored.ts, which is outside tools/verify/scope (tsconfig.json's include or an import reaches it); scope it, or keep it out of both" "$out" "the cross-check's findings"
}

test_prepare_names_a_missing_node_or_pnpm_with_node() {
	skeleton_project
	NODE_BIN="$TEST_TMP/no-node" step prepare
	assert_status 1
	assert_eq "tools/verify/local.env:1 node-missing NODE_BIN '$TEST_TMP/no-node' is not a program; fix it in tools/verify/local.env" "$out" "without Node"
	needs_node
	PNPM_BIN="$TEST_TMP/no-pnpm" step prepare
	assert_status 1
	assert_eq "tools/verify/local.env:1 pnpm-missing PNPM_BIN '$TEST_TMP/no-pnpm' is not a program; fix it in tools/verify/local.env" "$out" "without pnpm"
}

test_the_steps_name_a_tool_not_installed_with_node() {
	needs_node
	skeleton_project
	local s tool
	for s in format:prettier typecheck:tsc lint:eslint; do
		tool="${s#*:}"
		step "${s%%:*}"
		assert_status 1
		assert_eq "package.json:1 tool-missing node_modules/.bin/$tool is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)" "$out" "${s%%:*} with nothing installed"
	done
}

test_format_finds_unformatted_and_unparsable_files_with_node() {
	prepared_project
	add_fixture format/unformatted.ts.txt lib/total.ts
	add_fixture format/broken.ts.txt lib/broken.ts
	add_fixture format/unformatted.json.txt lib/cart.json
	step format
	assert_status 1
	assert_eq "lib/broken.ts:5 format-error SyntaxError: Variable declaration expected.
lib/cart.json:1 format not formatted; run: bash tools/verify/format --write lib/cart.json
lib/total.ts:3 format not formatted; run: bash tools/verify/format --write lib/total.ts" "$(printf '%s\n' "$out" | LC_ALL=C sort)" "format's findings"
}

test_format_reads_no_prettier_ignore_file_with_node() {
	prepared_project
	add_fixture format/unformatted.ts.txt lib/total.ts
	printf 'lib/\n' > .prettierignore
	step format
	assert_status 1
	assert_eq "lib/total.ts:3 format not formatted; run: bash tools/verify/format --write lib/total.ts" "$out" "format's findings"
}

test_format_write_formats_only_the_named_files_with_node() {
	prepared_project
	add_fixture format/unformatted.ts.txt lib/total.ts
	add_fixture format/unformatted.ts.txt lib/other.ts
	step format --write lib/total.ts
	assert_status 0
	cmp -s "$NEXTJS_FIXTURES/format/unformatted.ts.txt" lib/total.ts && fail "lib/total.ts wasn't formatted"
	cmp -s "$NEXTJS_FIXTURES/format/unformatted.ts.txt" lib/other.ts || fail "lib/other.ts, not named, was formatted"
	step format
	assert_eq "lib/other.ts:3 format not formatted; run: bash tools/verify/format --write lib/other.ts" "$out" "format after --write"
}

test_format_skips_excluded_files_and_reports_stale_entries_with_node() {
	prepared_project
	add_fixture format/unformatted.ts.txt lib/total.ts
	printf 'lib/total.ts\nlib/gone.ts\n' >> tools/verify/ratchet/format_exclude.txt
	local n
	n="$(wc -l < tools/verify/ratchet/format_exclude.txt | tr -d ' ')"
	step format
	assert_status 1
	assert_eq "tools/verify/ratchet/format_exclude.txt:$n format-exclude-stale lib/gone.ts is no file the format step checks; remove its entry" "$out" "format's findings"
}

test_format_usage_with_node() {
	needs_node
	skeleton_project
	step format lib/total.ts
	assert_status 2
	step format --check
	assert_status 2
}

test_typecheck_reports_tsc_errors_at_their_line_with_node() {
	prepared_project
	add_fixture typecheck/total.ts.txt "app/(shop)/cart/total.ts"
	step typecheck
	assert_status 1
	assert_eq "app/(shop)/cart/total.ts:2 TS2322 Type 'string' is not assignable to type 'number'." "$out" "typecheck's findings"
}

test_typecheck_needs_strict_and_every_check_it_brings_on_with_node() {
	prepared_project
	cp tsconfig.json "$TEST_TMP/tsconfig.json"
	sed -i 's/"strict": true,/"strict": true,\n    "noImplicitAny": false,/' tsconfig.json
	step typecheck
	assert_status 1
	assert_eq "tsconfig.json:$(grep -n '"noImplicitAny"' tsconfig.json | cut -d: -f1) typecheck-strict noImplicitAny is off, which strict turns on; remove it" "$out" "with a strict check off"
	cp "$TEST_TMP/tsconfig.json" tsconfig.json
	sed -i 's/"strict": true,/"strict": false,/' tsconfig.json
	step typecheck
	assert_status 1
	assert_eq "tsconfig.json:$(grep -n '"strict"' tsconfig.json | cut -d: -f1) typecheck-strict strict is not on; the gate needs \"strict\": true" "$out" "with strict off"
}

test_typecheck_without_a_tsconfig_with_node() {
	needs_node
	skeleton_project
	rm tsconfig.json
	step typecheck
	assert_status 1
	assert_eq "tsconfig.json:1 typecheck-config no tsconfig.json; tsc checks the project through it" "$out" "typecheck's finding"
}

test_lint_ignores_disable_comments_and_reports_type_aware_rules_with_node() {
	prepared_project
	add_fixture lint/floating.ts.txt lib/submit.ts
	step lint
	assert_status 1
	assert_eq "lib/submit.ts:7 @typescript-eslint/no-floating-promises" "$(printf '%s\n' "$out" | cut -d' ' -f1-2)" "lint's findings"
}

test_lint_reports_a_scoped_file_its_config_ignores_with_node() {
	prepared_project
	add_fixture format/unformatted.ts.txt legacy/total.ts
	sed -i 's#ignores: \[#ignores: ["legacy/", #' eslint.config.mjs
	grep -qF '"legacy/"' eslint.config.mjs || fail "could not change the ESLint config"
	step lint
	assert_status 1
	assert_eq "legacy/total.ts:1 lint-ignored the ESLint config ignores this file, which tools/verify/scope checks; lint it, or take it out of the scope" "$out" "lint's findings"
}

test_lint_runs_its_own_checks_on_test_files_only_with_node() {
	prepared_project
	add_fixture lint/waits.test.ts.txt lib/waits.test.ts
	cp lib/waits.test.ts lib/waits.ts
	step lint
	assert_status 1
	assert_eq 8 "$(printf '%s\n' "$out" | grep -c '^lib/waits\.test\.ts:[0-9]* fixed-wait ')" "fixed-wait findings in the test file"
	assert_eq "" "$(printf '%s\n' "$out" | grep '^lib/waits\.ts:[0-9]* fixed-wait ')" "fixed-wait findings outside the tests"
}

test_lint_reports_eslint_failing_without_a_report_with_node() {
	prepared_project
	echo 'export default [;' > eslint.config.mjs
	step lint
	assert_status 1
	assert_eq "tools/verify/lint:1 lint-error ESLint exited 2 without a report (see stderr)" "$out" "lint's finding"
}

test_bootstrap_installs_what_the_lockfile_locks_with_node() {
	needs_browser
	skeleton_project
	step bootstrap
	assert_status 0
	assert_eq "" "$out" "bootstrap's stdout"
	[ -x node_modules/.bin/next ] || fail "next isn't installed"
	rm pnpm-lock.yaml
	step bootstrap
	assert_status 1
	stderr_has "bootstrap: no pnpm-lock.yaml"
}

# Node and pnpm on PATH, named by no NODE_BIN or PNPM_BIN (the test's own, from the
# environment, go first on PATH instead): the bare start command.
test_playtest_builds_and_prints_how_to_start_with_node() {
	prepared_project
	local node pnpm
	node="$(command -v "${NODE_BIN:-node}")" && pnpm="$(command -v "${PNPM_BIN:-pnpm}")" || fail "no node or pnpm"
	PATH="$(dirname "$node"):$(dirname "$pnpm"):$PATH" NODE_BIN='' PNPM_BIN='' FACTORY_PLAYTEST_PORT=4100 step playtest
	assert_status 0
	assert_eq "pnpm exec next start --port 4100   then open http://localhost:4100" "$out" "playtest's stdout"
	[ -f .next/BUILD_ID ] || fail "nothing was built"
	FACTORY_PLAYTEST_PORT=web step playtest
	assert_status 1
	stderr_has "FACTORY_PLAYTEST_PORT is 'web', not a port number"
}

# Node and pnpm named by a path, and on no PATH: the playtest's start command and
# the verify skill's shell setup (local.env, then _nextjs.sh) still find them.
test_node_and_pnpm_off_path_are_found_through_local_env_with_node() {
	prepared_project
	local node pnpm
	node="$(command -v "${NODE_BIN:-node}")" && pnpm="$(command -v "${PNPM_BIN:-pnpm}")" || fail "no node or pnpm"
	printf 'NODE_BIN=%s\nPNPM_BIN=%s\n' "$node" "$pnpm" > tools/verify/local.env
	run_cmd env -u NODE_BIN -u PNPM_BIN PATH=/usr/bin:/bin bash -c 'set -a; . tools/verify/local.env; set +a; . tools/verify/_nextjs.sh; pnpm exec next --version'
	assert_status 0
	PATH=/usr/bin:/bin NODE_BIN="$node" PNPM_BIN="$pnpm" step playtest
	assert_status 0
	assert_eq "PATH=$(printf '%q' "$(dirname "$node")"):$(printf '%q' "$(dirname "$pnpm")"):\"\$PATH\" pnpm exec next start --port 3000   then open http://localhost:3000" "$out" "playtest's stdout"
}
