# The Next.js assertion-count probe (tools/verify/assert-counts, _lint_checks.awk
# with counts=1) and the Core's deviation step reading it for its assert-drop
# check, on the test files in tests/fixture/counts. They need only awk and git.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# counts <fixture> <path>: the probe on the fixture's text, as <path>.
counts() {
	run_cmd bash "$NEXTJS_ADAPTER/tools/verify/assert-counts" "$2" < "$NEXTJS_FIXTURES/counts/$1"
}

# Each test, named by its describe blocks and its title (a string's text, a
# template's code, each run of other ASCII characters one _), at its line, with
# its assertion calls: expect and its asserting members, an assert or expect
# helper, a nested function's calls; not expect.any, a declaration, a comment or
# a string. it.todo declares no test.
test_assert_counts_prints_each_tests_assertion_calls() {
	counts orders.test.ts.txt lib/orders.test.ts
	assert_status 0
	assert_eq "7 orders.GET_api_orders.lists_the_orders 2
13 orders.GET_api_orders.refuses_a_stranger 3
21 orders.totals_i_items 1
25 orders.keeps_the_receipt 3
34 reads_no_code_in_strings 1" "$out" "the counts"
}

test_assert_counts_reads_jsx_text_as_no_code() {
	run_cmd bash "$NEXTJS_ADAPTER/tools/verify/assert-counts" lib/jsx.test.tsx < "$NEXTJS_FIXTURES/lint/jsx.test.tsx.txt"
	assert_status 0
	assert_eq "7 renders_the_sleep_example 1
12 renders_a_fragment_and_attributes 1
22 asserts_through_a_member_chain 1
29 renders_without_asserting 0
33 sleeps_in_a_JSX_handler 1
38 compares 1
44 renders_a_regex_source 1
50 formats_generic_functions 1" "$out" "the counts"
}

# A method named like an assertion, declared in an object or a class, is no
# call: the test that rewrites it as a property keeps its count.
test_assert_counts_leaves_out_a_method_being_declared() {
	counts methods.test.ts.txt lib/methods.test.ts
	assert_status 0
	assert_eq "3 reads_the_method 1
8 reads_the_typed_method 1
17 reads_the_property 1" "$out" "the counts"
}

# A call ending a case label is a call, though a colon follows it.
test_assert_counts_reads_a_call_before_a_case_labels_colon() {
	counts case_label.test.ts.txt lib/case_label.test.ts
	assert_status 0
	assert_eq "5 suite.works 1" "$out" "the counts"
}

test_assert_counts_counts_no_other_file_and_needs_a_path() {
	counts orders.test.ts.txt lib/orders.test.md
	assert_status 0
	assert_eq "" "$out" "the counts of a Markdown file"
	run_cmd bash "$NEXTJS_ADAPTER/tools/verify/assert-counts" < /dev/null
	assert_status 2
}

# assert_drop_project <rewrite> <brief line...>: the skeleton with the orders
# tests in the base, and a branch that rewrites them as the counts fixture
# <rewrite>. The brief scopes app/** and lib/** plus the given lines.
assert_drop_project() {
	local rewrite="$1"
	shift
	skeleton_project
	add_fixture counts/orders.test.ts.txt lib/orders.test.ts
	git add -A && git commit -q -m base || fail "commit failed"
	FACTORY_BASE="$(git rev-parse HEAD)"
	export FACTORY_BASE
	brief "scope app/**" "scope lib/**" "$@"
	add_fixture "counts/$rewrite" lib/orders.test.ts
	git add -A && git commit -q -m "rewrite the orders tests" || fail "commit failed"
}

ASSERT_DROP_HINT="keep every check, or the Driver declares the drop in the brief"

# Reformatted, moved, quoted otherwise, an asymmetric matcher made a literal, the
# todo gone and a check added: no count falls.
test_deviation_passes_a_rewrite_that_keeps_every_assertion() {
	assert_drop_project orders_reformatted.test.ts.txt
	step deviation
	assert_status 0
	assert_eq "" "$out" "deviation's findings"
}

test_deviation_fails_a_rewrite_that_drops_an_expect() {
	assert_drop_project orders_dropped.test.ts.txt
	step deviation
	assert_status 1
	assert_eq "lib/orders.test.ts:1 assert-drop reads_no_code_in_strings drops from 1 assertion call at the base to 0 at HEAD, where it is gone: $ASSERT_DROP_HINT: asserts lib/orders.test.ts reads_no_code_in_strings 1 0
lib/orders.test.ts:7 assert-drop orders.GET_api_orders.lists_the_orders drops from 2 assertion calls at the base to 1 at HEAD: $ASSERT_DROP_HINT: asserts lib/orders.test.ts orders.GET_api_orders.lists_the_orders 2 1" "$out" "deviation's findings"
}

test_deviation_passes_the_drops_the_brief_declares() {
	assert_drop_project orders_dropped.test.ts.txt "asserts lib/orders.test.ts orders.GET_api_orders.lists_the_orders 2 1" \
		"asserts lib/orders.test.ts reads_no_code_in_strings 1 0"
	step deviation
	assert_status 0
	assert_eq "lib/orders.test.ts:1 assert-declared reads_no_code_in_strings drops from 1 assertion call at the base to 0 at HEAD, where it is gone; the brief declares it (asserts)
lib/orders.test.ts:7 assert-declared orders.GET_api_orders.lists_the_orders drops from 2 assertion calls at the base to 1 at HEAD; the brief declares it (asserts)" "$out" "deviation's findings"
}
