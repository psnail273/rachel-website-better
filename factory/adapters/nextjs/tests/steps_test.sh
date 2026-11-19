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
# generated) with no finding, or fail: primed_project.
prepared_project() {
	needs_store
	primed_project
}

test_the_skeleton_passes_every_step_with_node() {
	# prepare's findings: primed_project fails on any.
	prepared_project
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
	[ ! -e node_modules/.factory-install ] || fail "a failed install left an install record"
	# The record is gone, so the next prepare installs (and fails) again.
	step prepare
	assert_status 1
	assert_line "pnpm-lock.yaml:1 install-failed pnpm install --offline --frozen-lockfile exited 1 (see stderr); run bash tools/verify/bootstrap, the step allowed the network, then prepare again"
}

# prepare_skipped <what>: the last prepare passed and skipped the install.
prepare_skipped() {
	[ "$status" -eq 0 ] && [ -z "$out" ] || fail "prepare after $1: status $status: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	stderr_has "prepare: skipped pnpm install --offline --frozen-lockfile: node_modules/.factory-install matches"
	[ "$(grep -c 'skipped pnpm install' "$TEST_TMP/stderr")" -eq 1 ] || fail "the skip didn't print one line"
}

# prepare_installed <what>: the last prepare passed, ran the install and recorded it.
prepare_installed() {
	[ "$status" -eq 0 ] && [ -z "$out" ] || fail "prepare after $1: status $status: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	! grep -qF 'skipped pnpm install' "$TEST_TMP/stderr" || fail "prepare skipped the install after $1"
	[ -s node_modules/.factory-install ] || fail "no install record after $1"
}

test_prepare_skips_the_install_only_while_nothing_it_depends_on_changed_with_node() {
	prepared_project
	[ -s node_modules/.factory-install ] || fail "the first install wrote no record"
	git check-ignore -q node_modules/.factory-install || fail "git doesn't ignore the install record"
	local record
	record="$(cat node_modules/.factory-install)"
	step prepare
	prepare_skipped "nothing changed"
	assert_eq "$record" "$(cat node_modules/.factory-install)" "the record after a skip"
	[ -f next-env.d.ts ] && [ -d .next/types ] || fail "a skipping prepare didn't run typegen"
	# The tools' caches in node_modules are not its state.
	mkdir -p node_modules/.vite/vitest && echo '{}' > node_modules/.vite/vitest/results.json
	step prepare
	prepare_skipped "a cache write"

	echo '# a comment' >> pnpm-lock.yaml
	step prepare
	prepare_installed "a lockfile change"
	step prepare
	prepare_skipped "the lockfile change, installed"

	printf '\n' >> package.json
	step prepare
	prepare_installed "a package.json change"

	sed -i 's/^axe .*/axe 4.14.1/' tools/verify/pins
	step prepare
	prepare_installed "a pin change"

	pnpm_config_child_concurrency=2 step prepare
	prepare_installed "a pnpm setting from the environment"

	rm -rf node_modules
	step prepare
	prepare_installed "node_modules removed"
	[ -x node_modules/.bin/next ] || fail "the reinstall didn't install next"

	rm node_modules/next
	step prepare
	prepare_installed "a package removed from node_modules"
	[ -e node_modules/next ] || fail "the reinstall didn't restore next"

	printf '\n' >> node_modules/.modules.yaml
	step prepare
	prepare_installed "node_modules' metadata altered"
	step prepare
	prepare_skipped "the reinstall"

	# The rest of prepare still runs on a skip: the cross-check.
	add_fixture scope/vendored.ts.txt vendor/vendored.ts
	echo '!vendor/' >> tools/verify/scope
	step prepare
	assert_status 1
	stderr_has "prepare: skipped pnpm install"
	assert_line "tsconfig.json:$(grep -n '"include"' tsconfig.json | cut -d: -f1) scope-unchecked tsc compiles vendor/vendored.ts, which is outside tools/verify/scope (tsconfig.json's include or an import reaches it); scope it, or keep it out of both"
}

test_prepare_installs_every_time_without_a_hasher_with_node() {
	prepared_project
	path_without sha256sum
	path_without shasum
	step prepare
	[ "$status" -eq 0 ] && [ -z "$out" ] || fail "prepare with no hasher: status $status: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	! grep -qF 'skipped pnpm install' "$TEST_TMP/stderr" || fail "prepare skipped with no hasher"
	[ ! -e node_modules/.factory-install ] || fail "prepare with no hasher left an install record"
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
	local s tool want
	# lint names each of its three tools, and runs none.
	for s in format:prettier typecheck:tsc "lint:eslint knip secretlint"; do
		want=""
		for tool in ${s#*:}; do
			want+="${want:+$'\n'}package.json:1 tool-missing node_modules/.bin/$tool is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)"
		done
		step "${s%%:*}"
		assert_status 1
		assert_eq "$want" "$out" "${s%%:*} with nothing installed"
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

# Each check strict leaves off that the gate needs: off is a finding at its line,
# left out one at compilerOptions; on, an unchecked index read is a tsc error.
test_typecheck_needs_the_checks_strict_leaves_off_with_node() {
	prepared_project
	cp tsconfig.json "$TEST_TMP/tsconfig.json"
	local flag
	for flag in noUncheckedIndexedAccess noImplicitOverride noFallthroughCasesInSwitch; do
		cp "$TEST_TMP/tsconfig.json" tsconfig.json
		sed -i "s/\"$flag\": true/\"$flag\": false/" tsconfig.json
		grep -qF "\"$flag\": false" tsconfig.json || fail "could not turn $flag off"
		step typecheck
		assert_status 1
		assert_eq "tsconfig.json:$(grep -n "\"$flag\"" tsconfig.json | cut -d: -f1) typecheck-flags $flag is not on; the gate needs \"$flag\": true" "$out" "with $flag off"
	done
	cp "$TEST_TMP/tsconfig.json" tsconfig.json
	sed -i '/"noImplicitOverride": true,/d' tsconfig.json
	step typecheck
	assert_status 1
	assert_eq "tsconfig.json:$(grep -n '"compilerOptions"' tsconfig.json | cut -d: -f1) typecheck-flags noImplicitOverride is not on; the gate needs \"noImplicitOverride\": true" "$out" "with noImplicitOverride left out"
	cp "$TEST_TMP/tsconfig.json" tsconfig.json
	add_fixture typecheck/first.ts.txt lib/first.ts
	step typecheck
	assert_status 1
	assert_eq "lib/first.ts:3 TS18048 'head' is possibly 'undefined'." "$out" "an unchecked index read"
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
	assert_eq "lib/submit.ts:7 @typescript-eslint/no-floating-promises" "$(printf '%s\n' "$out" | grep -v ' knip-files ' | cut -d' ' -f1-2)" "ESLint's findings"
}

test_lint_reports_a_scoped_file_its_config_ignores_with_node() {
	prepared_project
	add_fixture format/unformatted.ts.txt legacy/total.ts
	sed -i 's#ignores: \[#ignores: ["legacy/", #' eslint.config.mjs
	grep -qF '"legacy/"' eslint.config.mjs || fail "could not change the ESLint config"
	step lint
	assert_status 1
	assert_eq "legacy/total.ts:1 lint-ignored the ESLint config ignores this file, which tools/verify/scope checks; lint it, or take it out of the scope" "$(printf '%s\n' "$out" | grep -v ' knip-files ')" "ESLint's findings"
}

# has_line_starting <prefix>: stdout has a line starting with this text.
has_line_starting() {
	printf '%s\n' "$out" | grep -qF -- "$1" && printf '%s\n' "$out" | cut -c1-"${#1}" | grep -qxF -- "$1" ||
		fail "no line starting '$1' in stdout:"$'\n'"$out"
}

test_lint_reports_hooks_misuse_and_nextjs_rules_with_node() {
	prepared_project
	add_fixture lint/hooks.tsx.txt app/counter.tsx
	add_fixture lint/img.tsx.txt app/logo.tsx
	step lint
	assert_status 1
	has_line_starting "app/counter.tsx:5 react-hooks/rules-of-hooks "
	has_line_starting "app/logo.tsx:2 @next/next/no-img-element "
}

# knip's issues in files in scope, one finding each; none out of scope.
# server-only, which R6 names and Next.js bundles, needs no package.json line.
test_lint_reports_knips_unused_files_exports_and_dependencies_with_node() {
	prepared_project
	add_fixture lint/key.ts.txt lib/key.ts
	add_fixture lint/key-route.ts.txt app/api/key/route.ts
	add_fixture lint/util.ts.txt lib/util.ts
	add_fixture lint/uses.tsx.txt app/uses/page.tsx
	add_fixture lint/orphan.ts.txt lib/orphan.ts
	add_fixture lint/orphan.ts.txt vendor/orphan.ts
	printf '**\n!.claude/\n!.cursor/\n!factory/\n!tools/\n!vendor/\n' > tools/verify/scope
	sed -i 's/"zod": "4.6.7"/"zod": "4.6.7",\n    "is-odd": "3.0.1"/' package.json
	grep -qF '"is-odd"' package.json || fail "could not add a dependency"
	step lint
	assert_status 1
	assert_eq "app/uses/page.tsx:1 knip-unlisted left-pad is imported but package.json doesn't list it
lib/orphan.ts:1 knip-files nothing imports this file; use it or delete it
lib/util.ts:5 knip-exports spare is exported but nothing imports it
package.json:$(grep -n '"is-odd"' package.json | cut -d: -f1) knip-dependencies is-odd is a dependency nothing imports" "$(printf '%s\n' "$out" | grep ' knip-')" "knip's findings"
}

test_lint_reports_knip_failing_without_a_report_with_node() {
	prepared_project
	echo '{ "ignore": [' > knip.json
	step lint
	assert_status 1
	assert_eq "tools/verify/lint:1 lint-error knip exited 2 without a report (see stderr)" "$out" "lint's finding"
}

# A secret in any file in scope, its value masked in the finding; with no
# .secretlintrc.json, the recommended preset still finds it.
test_lint_reports_a_committed_secret_masked_with_node() {
	prepared_project
	add_fixture lint/aws.md.txt docs/deploy.md
	step lint
	assert_status 1
	assert_eq "docs/deploy.md:5 secret-aws found AWS Secret Access Key: ****************************************" "$out" "lint's finding"
	rm .secretlintrc.json
	step lint
	assert_status 1
	assert_eq "docs/deploy.md:5 secret-aws found AWS Secret Access Key: ****************************************" "$out" "with no secretlint config"
	case "$out" in *wJalrXUtnFEMI*) fail "the finding carries the secret" ;; esac
}

test_lint_reports_secretlint_failing_without_a_report_with_node() {
	prepared_project
	echo '{ "rules": [{ "id": "no-such-rule" }] }' > .secretlintrc.json
	step lint
	assert_status 1
	has_line_starting "tools/verify/lint:1 lint-error secretlint exited "
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
	# knip, which can't load the config either, finds ESLint's packages unused.
	assert_eq "tools/verify/lint:1 lint-error ESLint exited 2 without a report (see stderr)" "$(printf '%s\n' "$out" | grep -v ' knip-dev-dependencies ')" "lint's finding"
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

# playtest builds under the machine-wide build lock (_nextjs.sh): held past
# FACTORY_BUILD_WAIT, it builds nothing and says why; free, it builds and releases
# it. next is a stand-in that records its build.
test_playtest_waits_for_the_build_lock_with_node() {
	needs_node
	skeleton_project
	mkdir -p node_modules/.bin
	printf '#!/usr/bin/env bash\necho "$1" >> %q\n' "$TEST_TMP/built" > node_modules/.bin/next && chmod 755 node_modules/.bin/next ||
		fail "could not stand in for next"
	mkdir "$FACTORY_BUILD_LOCK" && echo "$BASHPID" > "$FACTORY_BUILD_LOCK/pid" || fail "could not hold the lock"
	FACTORY_BUILD_WAIT=0 step playtest
	assert_status 1
	assert_eq "" "$out" "playtest's stdout"
	stderr_has "playtest: another next build held the build lock $FACTORY_BUILD_LOCK (pid $BASHPID) past FACTORY_BUILD_WAIT (0s, tools/verify/local.env)"
	[ ! -e "$TEST_TMP/built" ] || fail "playtest built under another's lock"

	rm -rf "$FACTORY_BUILD_LOCK"
	FACTORY_BUILD_WAIT=0 step playtest
	assert_status 0
	assert_eq "build" "$(cat "$TEST_TMP/built")" "what next ran"
	[ ! -e "$FACTORY_BUILD_LOCK" ] || fail "playtest left the build lock behind"

	# Run bare, it reads the lock's settings from local.env, as the gate's steps
	# get them from verify.sh: the same lock as theirs.
	mkdir "$TEST_TMP/other.lock" && echo "$BASHPID" > "$TEST_TMP/other.lock/pid" || fail "could not hold the other lock"
	printf 'FACTORY_BUILD_WAIT=0\nFACTORY_BUILD_LOCK=%s\n' "$TEST_TMP/other.lock" > tools/verify/local.env
	step playtest
	assert_status 1
	stderr_has "playtest: another next build held the build lock $TEST_TMP/other.lock (pid $BASHPID) past FACTORY_BUILD_WAIT (0s, tools/verify/local.env)"
	assert_eq "build" "$(cat "$TEST_TMP/built")" "what next ran"
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

# The adapter's no-overlap file: its steps share nothing (each one's writes are in
# the file's comments), so the gate runs typecheck, lint, arch, deviation and test
# at once.
test_the_parallel_steps_may_all_overlap() {
	mkdir -p "$TEST_TMP/project/tools" && cd "$TEST_TMP/project" || fail "could not make the project"
	cp -R "$NEXTJS_ADAPTER/tools/verify" tools/verify || fail "could not copy the adapter"
	. "$FACTORY_CORE/lib/steps.sh"
	factory_no_overlap_check || fail "the no-overlap file names a step outside the parallel set"
	local a b
	for a in $FACTORY_PARALLEL_STEPS; do
		for b in $FACTORY_PARALLEL_STEPS; do
			[ "$a" = "$b" ] || factory_steps_may_overlap "$a" "$b" || fail "$a and $b may not overlap"
		done
	done
}

# The four tool steps of the parallel set at once on the skeleton, with the real
# tools: the same report as one by one (deviation, the Core's, reads git only).
test_the_tool_steps_at_once_report_as_one_by_one_with_node() {
	prepared_project
	FACTORY_SERIAL_STEPS=1 run_cmd bash "$FACTORY_CORE/verify.sh" typecheck lint arch test
	local serial_out="$out" serial_status="$status"
	run_cmd bash "$FACTORY_CORE/verify.sh" typecheck lint arch test
	assert_eq "$serial_out" "$out" "the report at once against one by one"
	assert_eq "$serial_status" "$status" "the exit code at once against one by one"
	assert_eq "== typecheck PASS
== lint PASS
== arch PASS
== test PASS
verify: PASS" "$out" "the report at once"
}
