# The Godot adapter's format and lint steps (factory/adapters/godot/tools/verify),
# run on a scratch project built from tests/fixture. The fixtures end in .gd.txt
# so Godot never imports or checks them where they're stored.
#
# Every test starts GDQuest gdscript-formatter 0.27.0 (real_formatter, in
# tests/lib.sh), and skips without it, so each ends in _with_formatter
# (tests/names_test.sh holds it).

GODOT_ADAPTER="$FACTORY_CORE/../adapters/godot"
. "$GODOT_ADAPTER/tests/lib.sh"
GODOT_FIXTURES="$GODOT_ADAPTER/tests/fixture"

# godot_project: a git project in $TEST_TMP/project with the adapter's step
# scripts and an empty format-exclude list, and cd there; skip without the
# formatter.
godot_project() {
	real_formatter
	mkdir -p "$TEST_TMP/project/tools" || fail "could not make the project"
	cp -R "$GODOT_ADAPTER/tools/verify" "$TEST_TMP/project/tools/verify" || fail "could not copy the adapter"
	cd "$TEST_TMP/project" || fail "could not enter the project"
	git init -q . || fail "git init failed"
}

# add_gd <fixture> <path>: put tests/fixture/<fixture>.gd.txt at <path>.
add_gd() {
	mkdir -p "$(dirname "$2")"
	cp "$GODOT_FIXTURES/$1.gd.txt" "$2" || fail "no fixture $1"
}

exclude() {
	echo "$1" >> tools/verify/ratchet/format_exclude.txt
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_formatted_files_pass_format_with_formatter() {
	godot_project
	add_gd formatted src/formatted.gd
	run_cmd bash tools/verify/format
	assert_status 0
	assert_eq "" "$out"
}

test_unformatted_file_is_a_format_finding_and_write_mode_fixes_it_with_formatter() {
	godot_project
	add_gd formatted src/formatted.gd
	add_gd unformatted src/unformatted.gd
	run_cmd bash tools/verify/format
	assert_status 1
	assert_eq "src/unformatted.gd:2 format not formatted; run: bash tools/verify/format --write src/unformatted.gd" "$out"

	run_cmd bash tools/verify/format --write src/unformatted.gd
	assert_status 0
	assert_eq "" "$out"
	cmp -s src/unformatted.gd src/formatted.gd || fail "write mode did not format the file"

	run_cmd bash tools/verify/format
	assert_status 0
	assert_eq "" "$out" "the finding is still there after write mode"
}

test_write_mode_formats_only_the_named_files_with_formatter() {
	godot_project
	add_gd unformatted src/a.gd
	add_gd unformatted src/b.gd
	run_cmd bash tools/verify/format --write src/a.gd
	assert_status 0
	cmp -s src/b.gd "$GODOT_FIXTURES/unformatted.gd.txt" || fail "write mode touched a file it wasn't given"
	run_cmd bash tools/verify/format
	assert_eq "src/b.gd:2 format not formatted; run: bash tools/verify/format --write src/b.gd" "$out"
}

test_file_on_the_exclude_list_is_skipped_with_formatter() {
	godot_project
	add_gd unformatted src/kept.gd
	exclude src/kept.gd
	run_cmd bash tools/verify/format
	assert_status 0
	assert_eq "" "$out"

	run_cmd bash tools/verify/format --write
	assert_status 0
	cmp -s src/kept.gd "$GODOT_FIXTURES/unformatted.gd.txt" || fail "write mode formatted an excluded file"
}

test_exclude_entry_for_no_file_in_scope_is_a_finding_with_formatter() {
	godot_project
	add_gd formatted src/formatted.gd
	exclude src/gone.gd
	run_cmd bash tools/verify/format
	assert_status 1
	assert_eq "tools/verify/ratchet/format_exclude.txt:4 format-exclude-stale src/gone.gd is no GDScript file in scope; remove its entry" "$out"
}

test_addons_and_ignored_files_are_out_of_scope_with_formatter() {
	godot_project
	add_gd unformatted addons/thing/thing.gd
	add_gd unformatted build/ignored.gd
	echo "/build/" > .gitignore
	run_cmd bash tools/verify/format
	assert_status 0
	run_cmd bash tools/verify/lint
	assert_status 0
}

test_assertion_free_test_and_unseeded_fuzzer_are_findings_with_formatter() {
	godot_project
	add_gd checks_test tests/checks_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/checks_test.gd:25 unseeded-fuzzer test_unseeded uses a fuzzer without fuzzer_seed
tests/checks_test.gd:8 assertion-free test_no_assertion has no assertion (assert_*, verify)" "$out"
}

test_assertion_checks_apply_only_under_tests_with_formatter() {
	godot_project
	add_gd checks_test src/checks_test.gd
	run_cmd bash tools/verify/lint
	assert_no_line "src/checks_test.gd:8 assertion-free test_no_assertion has no assertion (assert_*, verify)"
	assert_no_line "src/checks_test.gd:25 unseeded-fuzzer test_unseeded uses a fuzzer without fuzzer_seed"
}

# Float comparisons in tests: an exact float inside an array or dictionary
# assertion, a tolerance written with numbers, and a float tolerance handed to
# assert_vector. Statements that span lines count from their first line.
test_float_comparisons_are_findings_with_formatter() {
	godot_project
	add_gd float_compare_test tests/float_compare_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/float_compare_test.gd:10 float-exact compares a float exactly inside an array or dictionary; compare each float with is_equal_approx and a named tolerance
tests/float_compare_test.gd:11 float-exact compares a float exactly inside an array or dictionary; compare each float with is_equal_approx and a named tolerance
tests/float_compare_test.gd:16 unnamed-tolerance the tolerance 0.001 is written with numbers; make it a named constant
tests/float_compare_test.gd:18 vector-tolerance assert_vector's is_equal_approx takes a vector tolerance, such as Vector2(TOLERANCE, TOLERANCE), not the float TOLERANCE
tests/float_compare_test.gd:19 unnamed-tolerance the tolerance 0.5 is written with numbers; make it a named constant
tests/float_compare_test.gd:19 vector-tolerance assert_vector's is_equal_approx takes a vector tolerance, such as Vector2(0.5, 0.5), not the float 0.5
tests/float_compare_test.gd:20 unnamed-tolerance the tolerance Vector2(0.1, 0.1) is written with numbers; make it a named constant
tests/float_compare_test.gd:24 unnamed-tolerance the tolerance 1e-3 is written with numbers; make it a named constant" "$out"
}

# A name is a float in its own func, or at the top; a string over many lines is
# not code; every exact comparison in a chain counts, and an exponent float too.
test_float_checks_read_scope_strings_and_chains_with_formatter() {
	godot_project
	add_gd float_scope_test tests/float_scope_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/float_scope_test.gd:14 vector-tolerance assert_vector's is_equal_approx takes a vector tolerance, such as Vector2(WIDE, WIDE), not the float WIDE
tests/float_scope_test.gd:22 unnamed-tolerance the tolerance 0.1 is written with numbers; make it a named constant
tests/float_scope_test.gd:28 float-exact compares a float exactly inside an array or dictionary; compare each float with is_equal_approx and a named tolerance
tests/float_scope_test.gd:29 float-exact compares a float exactly inside an array or dictionary; compare each float with is_equal_approx and a named tolerance
tests/float_scope_test.gd:30 float-exact compares a float exactly inside an array or dictionary; compare each float with is_equal_approx and a named tolerance" "$out"
}

test_private_access_is_a_finding_in_product_code_only_with_formatter() {
	godot_project
	add_gd private_access src/peek.gd
	add_gd private_access tests/peek_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "src/peek.gd:5 private-access Private variable '_secret' should not be accessed from outside its class" "$out"
}

# Which files are tests comes from tools/verify/test-paths, not a fixed tests/.
test_lint_takes_the_test_files_from_test_paths_with_formatter() {
	godot_project
	echo 'spec/**' > tools/verify/test-paths
	add_gd private_access spec/peek_spec.gd
	add_gd private_access tests/peek.gd
	add_gd checks_test spec/checks_spec.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_line "tests/peek.gd:5 private-access Private variable '_secret' should not be accessed from outside its class"
	assert_line "spec/checks_spec.gd:8 assertion-free test_no_assertion has no assertion (assert_*, verify)"
	assert_no_line "spec/peek_spec.gd:5 private-access Private variable '_secret' should not be accessed from outside its class"
}

# A max-line-length finding leaves out the line's length, so a long line edited
# but left long keeps its Baseline entry.
test_a_long_line_finding_leaves_out_its_length_with_formatter() {
	godot_project
	mkdir -p src
	printf 'extends Node\n\nvar a_long_name: String = "%s"\n' "$(printf 'x%.0s' $(seq 1 100))" > src/long.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "src/long.gd:3 max-line-length Line is too long: over the maximum of 100 characters" "$out"
}

test_two_lint_runs_are_byte_identical_with_formatter() {
	godot_project
	add_gd private_access src/peek.gd
	add_gd checks_test tests/checks_test.gd
	add_gd unformatted src/unformatted.gd
	bash tools/verify/lint > "$TEST_TMP/run1" 2> /dev/null
	bash tools/verify/lint > "$TEST_TMP/run2" 2> /dev/null
	[ -s "$TEST_TMP/run1" ] || fail "the lint run found nothing"
	cmp -s "$TEST_TMP/run1" "$TEST_TMP/run2" || fail "two lint runs differ:"$'\n'"$(diff "$TEST_TMP/run1" "$TEST_TMP/run2")"
}

test_steps_meet_the_runner_contract_with_formatter() {
	godot_project
	add_gd unformatted src/unformatted.gd
	add_gd checks_test tests/checks_test.gd
	exclude tests/checks_test.gd
	run_verify format lint
	assert_status 1
	assert_eq "== format FAIL
src/unformatted.gd:2 format not formatted; run: bash tools/verify/format --write src/unformatted.gd
verify: FAILED at step format" "$out"

	bash tools/verify/format --write > /dev/null 2>&1
	run_verify format lint
	assert_status 1
	assert_line "== format PASS"
	assert_line "== lint FAIL"
	assert_line "tests/checks_test.gd:8 assertion-free test_no_assertion has no assertion (assert_*, verify)"
	assert_last_line "verify: FAILED at step lint"
}

# fixed-wait: await_millis, an awaited create_timer and OS.delay_msec, unless a
# `# fixed-wait: <why>` comment gives the reason on the line or the one above. A
# timer kept as a guard, and a wait inside a string, are no findings.
FIXED_WAIT_MESSAGE="waits a fixed time; wait for the state each frame behind a guard timer, or give the reason on this line or the one above: # fixed-wait: <why>"

test_fixed_waits_are_findings_on_every_line_without_a_diff_base_with_formatter() {
	godot_project
	add_gd fixed_wait_test tests/fixed_wait_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/fixed_wait_test.gd:5 fixed-wait await_millis() $FIXED_WAIT_MESSAGE
tests/fixed_wait_test.gd:6 fixed-wait an awaited create_timer() $FIXED_WAIT_MESSAGE
tests/fixed_wait_test.gd:7 fixed-wait OS.delay_msec() or OS.delay_usec() $FIXED_WAIT_MESSAGE" "$out"
}

test_fixed_waits_apply_only_under_tests_with_formatter() {
	godot_project
	add_gd fixed_wait_test src/fixed_wait_test.gd
	run_cmd bash tools/verify/lint
	assert_status 0
}

# With a diff base, only the lines the branch adds count: committed, uncommitted,
# and every line of a new untracked file.
test_fixed_wait_judges_only_the_lines_a_branch_adds_with_formatter() {
	godot_project
	isolate_git
	add_gd fixed_wait_test tests/fixed_wait_test.gd
	git checkout -q -b dev && git add -A && git commit -q -m base || fail "no base commit"
	git checkout -q -b work || fail "no work branch"
	run_cmd bash tools/verify/lint
	assert_status 0
	printf '\tawait await_millis(50)\n' >> tests/fixed_wait_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/fixed_wait_test.gd:16 fixed-wait await_millis() $FIXED_WAIT_MESSAGE" "$out"
	git commit -q -am "a wait" || fail "commit failed"
	add_gd fixed_wait_test tests/new_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/fixed_wait_test.gd:16 fixed-wait await_millis() $FIXED_WAIT_MESSAGE
tests/new_test.gd:5 fixed-wait await_millis() $FIXED_WAIT_MESSAGE
tests/new_test.gd:6 fixed-wait an awaited create_timer() $FIXED_WAIT_MESSAGE
tests/new_test.gd:7 fixed-wait OS.delay_msec() or OS.delay_usec() $FIXED_WAIT_MESSAGE" "$out"
	FACTORY_BASE=HEAD run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/new_test.gd:5 fixed-wait await_millis() $FIXED_WAIT_MESSAGE
tests/new_test.gd:6 fixed-wait an awaited create_timer() $FIXED_WAIT_MESSAGE
tests/new_test.gd:7 fixed-wait OS.delay_msec() or OS.delay_usec() $FIXED_WAIT_MESSAGE" "$out"
}

# branched-assert: an assertion under an if, elif, else, for, while or match, on
# its line or below it, or after a return inside one. A loop that waits and the
# assertion after it, a lambda's own guard, a helper's sentinel and an assertion
# inside a string are no findings.
BRANCHED_MESSAGE="this assertion sits under an if, elif, else, for, while or match, or after a guard return, so what the test asserts depends on the run; assert straight-line, each recorded value by index"

test_branched_assertions_are_findings_on_every_line_without_a_diff_base_with_formatter() {
	godot_project
	add_gd branched_assert_test tests/branched_assert_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/branched_assert_test.gd:11 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:13 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:15 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:18 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:19 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:27 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:7 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:9 branched-assert $BRANCHED_MESSAGE" "$out"
}

# A lambda's body is a scope of its own, inside a call's brackets or an if's
# condition too, and with a signature over lines; an if whose condition holds a
# lambda is still an if, inside a lambda too, and a ternary's else or a
# dictionary key opens no block. A header continued with a backslash and a
# match arm's inline return count.
test_branched_assert_reads_lambdas_continuations_and_match_arms_with_formatter() {
	godot_project
	add_gd branched_assert_scopes_test tests/branched_assert_scopes_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/branched_assert_scopes_test.gd:25 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_scopes_test.gd:32 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_scopes_test.gd:57 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_scopes_test.gd:67 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_scopes_test.gd:8 branched-assert $BRANCHED_MESSAGE" "$out"
}

test_branched_assertions_apply_only_under_tests_with_formatter() {
	godot_project
	add_gd branched_assert_test src/branched_assert_test.gd
	run_cmd bash tools/verify/lint
	assert_status 0
}

# With a diff base, only the lines the branch adds count, an assertion added
# after a guard the base already has among them.
test_branched_assert_judges_only_the_lines_a_branch_adds_with_formatter() {
	godot_project
	isolate_git
	add_gd branched_assert_test tests/branched_assert_test.gd
	git checkout -q -b dev && git add -A && git commit -q -m base || fail "no base commit"
	git checkout -q -b work || fail "no work branch"
	run_cmd bash tools/verify/lint
	assert_status 0
	printf '\tif list.is_empty():\n\t\tassert_int(i).is_equal(0)\n' >> tests/branched_assert_test.gd
	sed -i '27a\	assert_str(node.name).is_not_empty()' tests/branched_assert_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/branched_assert_test.gd:28 branched-assert $BRANCHED_MESSAGE
tests/branched_assert_test.gd:57 branched-assert $BRANCHED_MESSAGE" "$out"
}

# unguarded-poll: a while loop that awaits, in its body or inline, with nothing
# in its condition to bound it, an inner loop under a bounded one too. A guard
# timer's time_left, is_stopped(), the clock and a counter compared with a bound
# bound it, on the while line or a line the condition runs on to. A loop that
# never awaits, a reason on the while line or alone above it, and a loop inside a
# string are no findings.
POLL_MESSAGE="this while loop awaits but nothing in its condition bounds it, so a broken build hangs instead of failing; put a guard timer's time_left (guard.time_left > 0.0) or a frame counter (frames < MAX_FRAMES) in its condition, or give the reason on this line or the one above: # unguarded-poll: <why>"

test_unguarded_polls_are_findings_on_every_line_without_a_diff_base_with_formatter() {
	godot_project
	add_gd unguarded_poll_test tests/unguarded_poll_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/unguarded_poll_test.gd:39 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_test.gd:41 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_test.gd:45 unguarded-poll $POLL_MESSAGE" "$out"
}

# A counter is a variable, indexed or not, counting up or down; state compared
# with a bound is none (a call, a member, a constant), nor is a counter the body
# sets back to 0 (#154). An await in a lambda in the body, a list the body drains
# and a name that says it guards make no finding.
test_unguarded_poll_reads_counters_lambdas_drains_and_guard_names_with_formatter() {
	godot_project
	add_gd unguarded_poll_forms_test tests/unguarded_poll_forms_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/unguarded_poll_forms_test.gd:32 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_forms_test.gd:39 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_forms_test.gd:42 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_forms_test.gd:44 unguarded-poll $POLL_MESSAGE" "$out"
}

# Brackets around an operand, != with a constant, and a name or member the body
# steps (by +=, or from itself over lines too, through an index, a key or a
# cast, with self. or without) make a counter. A drain inline or through an
# index, a group, a cast or a backslash, a lambda whose signature or body runs
# on past its line, a lambda in the condition, a lambda's own assignment and a
# property or node named await make no finding. A member the body never steps,
# or sets from state over lines, is state, and a counter set back to 0 on an
# if's line is no bound.
test_unguarded_poll_reads_groups_steps_and_lambdas_over_lines_with_formatter() {
	godot_project
	add_gd unguarded_poll_shapes_test tests/unguarded_poll_shapes_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/unguarded_poll_shapes_test.gd:155 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_shapes_test.gd:91 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_shapes_test.gd:93 unguarded-poll $POLL_MESSAGE
tests/unguarded_poll_shapes_test.gd:97 unguarded-poll $POLL_MESSAGE" "$out"
}

test_unguarded_polls_apply_only_under_tests_with_formatter() {
	godot_project
	add_gd unguarded_poll_test src/unguarded_poll_test.gd
	run_cmd bash tools/verify/lint
	assert_status 0
}

# With a diff base, only a while line the branch adds counts: an old loop is no
# finding, nor is an await added to its body.
test_unguarded_poll_judges_only_the_lines_a_branch_adds_with_formatter() {
	godot_project
	isolate_git
	add_gd unguarded_poll_test tests/unguarded_poll_test.gd
	git checkout -q -b dev && git add -A && git commit -q -m base || fail "no base commit"
	git checkout -q -b work || fail "no work branch"
	run_cmd bash tools/verify/lint
	assert_status 0
	sed -i '40a\		await get_tree().physics_frame' tests/unguarded_poll_test.gd
	printf '\twhile _flow() == 1:\n\t\tawait _tap()\n' >> tests/unguarded_poll_test.gd
	run_cmd bash tools/verify/lint
	assert_status 1
	assert_eq "tests/unguarded_poll_test.gd:78 unguarded-poll $POLL_MESSAGE" "$out"
}
