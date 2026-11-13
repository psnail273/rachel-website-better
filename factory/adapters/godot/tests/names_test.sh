# The Godot tests' names: a test that starts a real tool, Godot, gdscript-formatter
# or gdmutant, ends in _with_<a tool it starts>: _with_godot, _with_formatter or
# _with_gdmutant; and no other test ends in _with_<tool>. So
# factory/core/test.sh starts it first and amend.sh land can leave it out when
# its diff doesn't touch the adapter (both read a test ending in _with_<tool>,
# one word after the last _with_, as a real-tool test). gdmutant runs Godot, so a
# test that starts gdmutant starts Godot too: it may end in _with_godot.
#
# A test starts a tool when its body skips without it, directly or through a
# function of tests/lib.sh or of its own file that does, each tool by its own
# skip: Godot's `skip "GODOT_BIN is not set"` (either quote), as needs_godot
# (arch_test.sh), real_godot (steps_test.sh) and the tests that check GODOT_BIN
# themselves do; the formatter's and gdmutant's a skip whose message starts
# `no gdscript-formatter` or `no gdmutant`, as real_formatter and real_gdmutant
# (tests/lib.sh) do. A test that sets GODOT_BIN or GDMUTANT_BIN to a fake, or
# empty, starts no real tool, so it doesn't skip that way. The check is
# misnamed_tests (factory/core/tests/lib.sh); it needs only bash and awk.

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
GODOT_ADAPTER="$FACTORY_CORE/../adapters/godot"

# The skips that mark a function as starting a real tool, as misnamed_tests reads
# marks, kept out of every function body here so the check doesn't read this
# file's own tests as starting one.
GODOT_TOOL_MARKS='godot skip[[:space:]]+["'\'']GODOT_BIN is not set["'\'']
formatter skip[[:space:]]+["'\'']no gdscript-formatter[ "'\'']
gdmutant,godot skip[[:space:]]+["'\'']no gdmutant[ "'\'']'

test_each_test_that_starts_a_real_tool_ends_in_with_a_tool_it_starts_and_no_other() {
	local files=("$GODOT_ADAPTER"/tests/*_test.sh)
	[ "${#files[@]}" -gt 1 ] || fail "no Godot test files"
	run_cmd misnamed_tests "$GODOT_TOOL_MARKS" "$GODOT_ADAPTER/tests/lib.sh" "${files[@]}"
	assert_eq "" "$out" "the misnamed tests"
}

# tests/fixture/names/misnamed_test.sh.txt, with tests/fixture/names/lib.sh.txt as
# its lib: a test of each kind, for each tool, named right and wrong, two tests
# and a helper of each file written so the check can't read them (the function
# after those is read again), and code and a comment on a test's opening line.
test_the_check_names_each_misnamed_and_unread_test() {
	mkdir -p "$TEST_TMP/names" &&
		cp "$GODOT_ADAPTER/tests/fixture/names/lib.sh.txt" "$TEST_TMP/names/lib.sh" &&
		cp "$GODOT_ADAPTER/tests/fixture/names/misnamed_test.sh.txt" "$TEST_TMP/names/misnamed_test.sh" ||
		fail "could not copy the fixtures"
	run_cmd misnamed_tests "$GODOT_TOOL_MARKS" "$TEST_TMP/names/lib.sh" "$TEST_TMP/names/misnamed_test.sh"
	assert_eq "lib.sh: lib_unread: can't read its body (from \`lib_unread() {\` to a \`}\` at column 0)
misnamed_test.sh: unread_helper: can't read its body (from \`unread_helper() {\` to a \`}\` at column 0)
misnamed_test.sh: test_a_keyword_definition: can't read its body (from \`test_a_keyword_definition() {\` to a \`}\` at column 0)
misnamed_test.sh: test_an_indented_closing_brace: can't read its body (from \`test_an_indented_closing_brace() {\` to a \`}\` at column 0)
misnamed_test.sh: test_calls_a_lib_helper_unnamed: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_calls_a_local_helper_but_named_with_gdmutant: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_calls_a_local_helper_unnamed: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_checks_godot_bin_itself_unnamed: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_checks_godot_bin_itself_with_node: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_code_on_the_opening_line_unnamed: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_empty_godot_bin_but_named_with_godot: starts no real tool, so doesn't end in _with_<tool>
misnamed_test.sh: test_godot_and_the_formatter_but_named_with_gdmutant: starts the real godot and formatter, so ends in _with_godot or _with_formatter
misnamed_test.sh: test_one_line_unnamed: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_single_quoted_skip_unnamed: starts the real godot, so ends in _with_godot
misnamed_test.sh: test_starts_gdmutant_alone_unnamed: starts the real godot and gdmutant, so ends in _with_godot or _with_gdmutant
misnamed_test.sh: test_starts_the_formatter_but_named_with_godot: starts the real formatter, so ends in _with_formatter
misnamed_test.sh: test_starts_the_formatter_unnamed: starts the real formatter, so ends in _with_formatter
misnamed_test.sh: test_starts_the_formatter_with_a_local_helper_unnamed: starts the real formatter, so ends in _with_formatter
misnamed_test.sh: test_three_tools_unnamed: starts the real godot, formatter and gdmutant, so ends in _with_godot, _with_formatter or _with_gdmutant" "$out" "the misnamed tests"
}
