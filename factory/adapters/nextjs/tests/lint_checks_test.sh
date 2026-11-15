# The Next.js lint step's own checks (_lint_checks.awk: assertion-free and
# fixed-wait) on the test files in tests/fixture/lint, and its reader of ESLint's
# report (_eslint_findings.mjs). The checks need only awk; the reader needs Node.

NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# checks <fixture...>: the adapter's own checks on these fixtures, copied into
# $TEST_TMP under their names less .txt; cd there.
checks() {
	local f
	cd "$TEST_TMP" || fail "no temp folder"
	for f in "$@"; do
		add_fixture "lint/$f" "${f%.txt}"
	done
	run_cmd awk -f "$NEXTJS_ADAPTER/tools/verify/_lint_checks.awk" "${@%.txt}"
}

# rules: run_cmd's findings as `<file>:<line> <rule>`, one a line.
# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
rules() {
	printf '%s\n' "$out" | cut -d' ' -f1-2
}

test_assertion_free_finds_each_test_that_asserts_nothing() {
	checks assertions.test.ts.txt
	assert_status 0
	assert_eq "assertions.test.ts:8 assertion-free
assertions.test.ts:19 assertion-free
assertions.test.ts:23 assertion-free
assertions.test.ts:44 assertion-free
assertions.test.ts:51 assertion-free
assertions.test.ts:59 assertion-free" "$(rules)" "the assertion-free findings"
	assert_line 'assertions.test.ts:8 assertion-free "has no assertion" has no assertion; call expect or assert, or a helper whose name starts with expect or assert'
	assert_line 'assertions.test.ts:51 assertion-free `a template name` has no assertion; call expect or assert, or a helper whose name starts with expect or assert'
}

test_fixed_wait_finds_each_sleep_and_passes_a_reasoned_one() {
	checks waits.test.ts.txt
	assert_status 0
	assert_eq "waits.test.ts:7 fixed-wait
waits.test.ts:18 fixed-wait
waits.test.ts:19 fixed-wait
waits.test.ts:24 fixed-wait
waits.test.ts:25 fixed-wait
waits.test.ts:30 fixed-wait
waits.test.ts:31 fixed-wait
waits.test.ts:32 fixed-wait" "$(rules)" "the fixed-wait findings"
	assert_line "waits.test.ts:7 fixed-wait setTimeout() in a new Promise waits a fixed time; wait for the state (vi.waitFor, expect.poll, an event) or use fake timers, or give the reason on this line or the one above: // fixed-wait: <why>"
	assert_eq "an awaited setTimeout()|an awaited setTimeout()|an awaited sleep()|an awaited delay()|waitForTimeout()|Atomics.wait()|scheduler.wait()" \
		"$(printf '%s\n' "$out" | sed -n '2,$s/^[^ ]* fixed-wait \(.*\) waits a fixed time;.*/\1/p' | paste -sd'|' -)" "what each wait is"
}

test_fixed_wait_under_fake_timers_passes_the_timer_forms() {
	checks fake_timers.test.ts.txt
	assert_status 0
	assert_eq "fake_timers.test.ts:19 fixed-wait" "$(rules)" "the fixed-wait findings"
}

# In a .tsx file JSX's tags and text are no code, its {...} are; a type's or a
# generic arrow's <T> is no JSX; an assertion may go through members.
test_jsx_text_is_no_code_and_its_braces_are() {
	checks jsx.test.tsx.txt
	assert_status 0
	assert_eq "jsx.test.tsx:29 assertion-free
jsx.test.tsx:34 fixed-wait" "$(rules)" "the findings"
}

test_the_checks_read_several_files_in_one_run() {
	checks assertions.test.ts.txt fake_timers.test.ts.txt
	assert_eq 7 "$(printf '%s\n' "$out" | grep -c .)" "the findings of both files"
	assert_line "fake_timers.test.ts:19 fixed-wait waitForTimeout() waits a fixed time; wait for the state (vi.waitFor, expect.poll, an event) or use fake timers, or give the reason on this line or the one above: // fixed-wait: <why>"
}

test_a_crlf_file_reports_the_same_lines() {
	cd "$TEST_TMP" || fail "no temp folder"
	sed 's/$/\r/' "$NEXTJS_FIXTURES/lint/waits.test.ts.txt" > waits.test.ts
	run_cmd awk -f "$NEXTJS_ADAPTER/tools/verify/_lint_checks.awk" waits.test.ts
	assert_eq 8 "$(printf '%s\n' "$out" | grep -c ' fixed-wait ')" "fixed-wait findings with CRLF"
	assert_line "waits.test.ts:7 fixed-wait setTimeout() in a new Promise waits a fixed time; wait for the state (vi.waitFor, expect.poll, an event) or use fake timers, or give the reason on this line or the one above: // fixed-wait: <why>"
}

test_the_eslint_report_becomes_findings_with_node() {
	needs_node
	cd "$TEST_TMP" || fail "no temp folder"
	cat > report.json << JSON
[
  {"filePath": "$TEST_TMP/app/page.tsx", "messages": [
    {"ruleId": "@typescript-eslint/no-floating-promises", "line": 7, "message": "Promises must be\n  awaited."},
    {"ruleId": null, "fatal": true, "line": 2, "message": "Parsing error: ';' expected."}
  ]},
  {"filePath": "$TEST_TMP/legacy/old.ts", "messages": [
    {"ruleId": null, "severity": 1, "message": "File ignored because of a matching ignore pattern. Use \"--no-ignore\" to override."}
  ]},
  {"filePath": "$TEST_TMP/app/clean.ts", "messages": []},
  {"filePath": "$TEST_TMP/app/other.ts", "messages": [{"ruleId": null, "line": 0, "message": ""}]}
]
JSON
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_eslint_findings.mjs" report.json
	assert_status 0
	assert_eq "app/page.tsx:7 @typescript-eslint/no-floating-promises Promises must be awaited.
app/page.tsx:2 lint-parse Parsing error: ';' expected.
legacy/old.ts:1 lint-ignored the ESLint config ignores this file, which tools/verify/scope checks; lint it, or take it out of the scope
app/other.ts:1 lint-other (no message)" "$out" "the findings"
	echo '{"not": "a report"}' > bad.json
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_eslint_findings.mjs" bad.json
	assert_status 2
}

# list=1: the checks' names, which the arch step's lint-tags check takes as
# rules the lint step runs; each is the rule its findings carry.
test_list_prints_each_checks_name_and_reads_nothing() {
	cd "$TEST_TMP" || fail "no temp folder"
	run_cmd awk -v list=1 -f "$NEXTJS_ADAPTER/tools/verify/_lint_checks.awk" < /dev/null
	assert_status 0
	assert_eq "assertion-free
fixed-wait" "$out" "the checks' names"
	add_fixture lint/assertions.test.ts.txt assertions.test.ts
	add_fixture lint/waits.test.ts.txt waits.test.ts
	run_cmd awk -f "$NEXTJS_ADAPTER/tools/verify/_lint_checks.awk" assertions.test.ts waits.test.ts
	assert_eq "assertion-free
fixed-wait" "$(rules | cut -d' ' -f2 | LC_ALL=C sort -u)" "the rules the checks' findings carry"
}
