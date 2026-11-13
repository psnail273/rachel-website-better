# The Next.js test step (tools/verify/test): Vitest on a project made from the
# skeleton, with the fixtures in tests/fixture/test, and its reader of Vitest's
# JSON report (_vitest_results.mjs).
#
# The step's tests need Node, pnpm and a primed pnpm store (FACTORY_PNPM_STORE)
# and skip without them; the reader's need only Node.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# prepared_project: skeleton_project, prepared, or fail.
prepared_project() {
	needs_store
	skeleton_project
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed on the skeleton: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
}

# run_test_step: the test step, as the runner runs it; its results in $TEST_TMP/results.
run_test_step() {
	FACTORY_RESULTS_FILE="$TEST_TMP/results" step test
}

TAB=$'\t'

test_the_skeletons_test_passes_with_node() {
	prepared_project
	run_test_step
	assert_status 0
	assert_eq "" "$out" "the step's findings"
	assert_eq "app/api/health/route.test.ts > GET /api/health > answers ok${TAB}PASS${TAB}app/api/health/route.test.ts:6" "$(cat "$TEST_TMP/results")" "the results"
}

# Each outcome, at its test's line: a failed expect is FAILURE, as are expect's
# own errors (expect.assertions, .rejects, expect.poll); a thrown error is ERROR;
# skip and todo are SKIP. A file that doesn't import, and one whose afterAll
# throws, is an ERROR line of its own. A tab or newline in a title is escaped.
test_each_outcome_is_reported_at_its_tests_line_with_node() {
	prepared_project
	add_fixture test/outcomes.test.ts.txt lib/cart/outcomes.test.ts
	add_fixture test/broken.test.ts.txt lib/cart/broken.test.ts
	add_fixture test/teardown.test.ts.txt lib/cart/teardown.test.ts
	run_test_step
	assert_status 1
	assert_eq "" "$out" "the step's findings"
	assert_eq "app/api/health/route.test.ts > GET /api/health > answers ok${TAB}PASS${TAB}app/api/health/route.test.ts:6
lib/cart/broken.test.ts${TAB}ERROR${TAB}lib/cart/broken.test.ts:1
lib/cart/outcomes.test.ts > cart > total > adds the prices${TAB}PASS${TAB}lib/cart/outcomes.test.ts:5
lib/cart/outcomes.test.ts > cart > total > applies the discount${TAB}FAILURE${TAB}lib/cart/outcomes.test.ts:9
lib/cart/outcomes.test.ts > cart > loads the prices${TAB}ERROR${TAB}lib/cart/outcomes.test.ts:14
lib/cart/outcomes.test.ts > cart > rounds the total${TAB}SKIP${TAB}lib/cart/outcomes.test.ts:18
lib/cart/outcomes.test.ts > cart > taxes the total${TAB}SKIP${TAB}lib/cart/outcomes.test.ts:22
lib/cart/outcomes.test.ts > cart > counts\\tits\\nchecks${TAB}FAILURE${TAB}lib/cart/outcomes.test.ts:24
lib/cart/outcomes.test.ts > cart > refuses an empty cart${TAB}FAILURE${TAB}lib/cart/outcomes.test.ts:29
lib/cart/outcomes.test.ts > cart > settles${TAB}FAILURE${TAB}lib/cart/outcomes.test.ts:33
lib/cart/outcomes.test.ts > cart > waits for a store that is never made${TAB}ERROR${TAB}lib/cart/outcomes.test.ts:37
lib/cart/outcomes.test.ts > cart > keeps item 1${TAB}FAILURE${TAB}lib/cart/outcomes.test.ts:42
lib/cart/outcomes.test.ts > cart > keeps item 2${TAB}PASS${TAB}lib/cart/outcomes.test.ts:42
lib/cart/teardown.test.ts${TAB}ERROR${TAB}lib/cart/teardown.test.ts:1
lib/cart/teardown.test.ts > session > opens${TAB}PASS${TAB}lib/cart/teardown.test.ts:8" "$(cat "$TEST_TMP/results")" "the results"
	# The Core reads every line.
	. "$FACTORY_CORE/lib/steps.sh"
	. "$FACTORY_CORE/lib/findings.sh"
	. "$FACTORY_CORE/lib/results.sh"
	factory_results_read "$TEST_TMP/results" > "$TEST_TMP/read" || fail "the Core can't read the results: $(cat "$TEST_TMP/read")"
	assert_eq 15 "${#RESULT_NAMES[@]}" "the tests the Core read"
}

# A test file in scope that declares a test (a todo too), but which Vitest's
# config leaves out, is ERROR: the gate never passes a test that didn't run.
test_a_test_file_vitest_does_not_run_is_an_error_with_node() {
	prepared_project
	sed -i 's#"tools/\*\*",#"tools/**",\n      "lib/legacy/**",#' vitest.config.ts
	grep -qF '"lib/legacy/**"' vitest.config.ts || fail "could not change the Vitest config"
	add_fixture test/teardown.test.ts.txt lib/legacy/old.test.ts
	add_fixture test/deferred.test.ts.txt lib/legacy/deferred.test.ts
	# A helper under tests/ declares no test, so it is no ERROR: a method named
	# test is none.
	mkdir -p tests && printf 'export const fixtures = [1, 2];\n\nexport class Fixture {\n  test(): boolean {\n    return true;\n  }\n}\n' > tests/fixtures.ts
	run_test_step
	assert_status 0
	assert_eq "app/api/health/route.test.ts > GET /api/health > answers ok${TAB}PASS${TAB}app/api/health/route.test.ts:6
lib/legacy/deferred.test.ts${TAB}ERROR${TAB}lib/legacy/deferred.test.ts:1
lib/legacy/old.test.ts${TAB}ERROR${TAB}lib/legacy/old.test.ts:1" "$(cat "$TEST_TMP/results")" "the results"
	run_cmd bash "$FACTORY_CORE/verify.sh" test
	assert_status 1
	assert_line "lib/legacy/old.test.ts:1 green-not-pass lib/legacy/old.test.ts is ERROR; the green gate needs every test to PASS"
}

test_vitest_failing_without_a_report_is_a_finding_with_node() {
	prepared_project
	echo 'export default {;' > vitest.config.ts
	run_test_step
	assert_status 1
	assert_eq "tools/verify/test:1 test-error Vitest exited 1 without a report (see stderr)" "$out" "the step's finding"
	assert_eq "" "$(cat "$TEST_TMP/results")" "the results"
}

test_the_step_needs_the_runner_and_vitest_with_node() {
	needs_node
	skeleton_project
	run_cmd bash tools/verify/test
	assert_status 2
	stderr_has "FACTORY_RESULTS_FILE is not set"
	run_test_step
	assert_status 1
	assert_eq "package.json:1 tool-missing node_modules/.bin/vitest is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)" "$out" "without Vitest"
}

# The red gate reads the names: the brief names the new test as the results
# file does, and it fails on its assertion.
test_the_red_gate_takes_the_results_names_with_node() {
	prepared_project
	git add -A && git commit -q -m base || fail "commit failed"
	FACTORY_BASE="$(git rev-parse HEAD)"
	export FACTORY_BASE
	brief "scope lib/**" "test lib/price.test.ts > price > doubles a big order" "seam lib/price.ts price"
	mkdir -p lib
	printf 'export function price(n: number): number {\n  return n * 0;\n}\n' > lib/price.ts
	printf 'import { describe, expect, it } from "vitest";\n\nimport { price } from "@/lib/price";\n\ndescribe("price", () => {\n  it("doubles a big order", () => {\n    expect(price(20)).toBe(40);\n  });\n});\n' > lib/price.test.ts
	git add -A && git commit -q -m red || fail "commit failed"
	run_cmd bash "$FACTORY_CORE/verify.sh" --red test
	assert_status 0
	assert_last_line "verify: PASS"
}

# An unhandled error, which Vitest's JSON report leaves out, is an ERROR line
# for the file that was running: the red gate doesn't take a test that failed
# on its assertion while it came.
test_an_unhandled_error_is_an_error_line_for_its_file_with_node() {
	prepared_project
	git add -A && git commit -q -m base || fail "commit failed"
	FACTORY_BASE="$(git rev-parse HEAD)"
	export FACTORY_BASE
	brief "scope lib/**" "test lib/unhandled.test.ts > fails on its assertion"
	add_fixture test/unhandled.test.ts.txt lib/unhandled.test.ts
	git add -A && git commit -q -m red || fail "commit failed"
	run_test_step
	assert_status 1
	assert_eq "" "$out" "the step's findings"
	assert_eq "app/api/health/route.test.ts > GET /api/health > answers ok${TAB}PASS${TAB}app/api/health/route.test.ts:6
lib/unhandled.test.ts${TAB}ERROR${TAB}lib/unhandled.test.ts:1
lib/unhandled.test.ts > fails on its assertion${TAB}FAILURE${TAB}lib/unhandled.test.ts:3" "$(cat "$TEST_TMP/results")" "the results"
	stderr_has "background crashed"
	run_cmd bash "$FACTORY_CORE/verify.sh" --red test
	assert_status 1
	assert_line "lib/unhandled.test.ts:1 red-unnamed lib/unhandled.test.ts is ERROR but the brief doesn't name it; only the brief's tests may fail"
}

# --- the reader, on a report of Vitest's JSON shape ---

# reader <report> [declared]: _vitest_results.mjs on it, from $TEST_TMP.
reader() {
	needs_node
	cd "$TEST_TMP" || fail "no temp folder"
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_vitest_results.mjs" "$@"
}

# A name given twice is one line, its worst status at its first line; a test
# with no location is at line 1; one that never finished is ERROR; a control
# character in a title is escaped; a declared test file the report lacks is
# ERROR, as is the file an unhandled error came in, or the run for one in none.
test_the_reader_merges_names_and_fills_gaps_with_node() {
	cat > "$TEST_TMP/report.json" << JSON
{"testResults": [
  {"name": "$TEST_TMP/lib/a.test.ts", "status": "failed", "message": "", "assertionResults": [
    {"ancestorTitles": ["a"], "title": "twice", "status": "passed", "failureMessages": [], "location": {"line": 9, "column": 3}},
    {"ancestorTitles": ["a"], "title": "twice", "status": "failed", "failureMessages": ["AssertionError: expected 1 to be 2\\n    at x"], "location": {"line": 4, "column": 3}},
    {"ancestorTitles": [], "title": "nowhere", "status": "skipped", "failureMessages": []},
    {"ancestorTitles": [], "title": "hung", "status": "pending", "failureMessages": []},
    {"ancestorTitles": ["bell\\u0007"], "title": "ok", "status": "passed", "failureMessages": [], "location": {"line": 12, "column": 3}}
  ]}
]}
JSON
	printf 'lib/a.test.ts\nlib/b.test.ts\n' > "$TEST_TMP/declared"
	printf '%s\tUnhandled Rejection: late\n\tUncaught Exception: nowhere\n' "$TEST_TMP/lib/c.test.ts" > "$TEST_TMP/errors"
	reader report.json declared errors
	assert_status 0
	assert_eq "lib/a.test.ts${TAB}1${TAB}lib/a.test.ts > hung${TAB}ERROR
lib/a.test.ts${TAB}1${TAB}lib/a.test.ts > nowhere${TAB}SKIP
lib/a.test.ts${TAB}4${TAB}lib/a.test.ts > a > twice${TAB}FAILURE
lib/a.test.ts${TAB}12${TAB}lib/a.test.ts > bell\\x07 > ok${TAB}PASS
lib/b.test.ts${TAB}1${TAB}lib/b.test.ts${TAB}ERROR
lib/c.test.ts${TAB}1${TAB}lib/c.test.ts${TAB}ERROR
tools/verify/test${TAB}1${TAB}unhandled error${TAB}ERROR" "$(printf '%s\n' "$out" | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n -k3,3)" "the reader's lines"
}

test_the_reader_refuses_what_isnt_vitests_report_with_node() {
	echo '{"not": "a report"}' > "$TEST_TMP/bad.json"
	reader bad.json
	assert_status 2
	stderr_has "no testResults"
}
