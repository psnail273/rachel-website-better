# The Next.js tests' names: a test that starts a real tool ends in _with_node, so
# factory/core/test.sh starts it first (it starts each test ending in
# _with_<tool>, one word after the last _with_, first), and no other test ends in
# _with_<tool>. A test starts a real tool when its body calls one of the helpers
# below (tests/lib.sh), directly or through a function of tests/lib.sh or of its
# own file that does. A test that only skips without Node still counts: it starts
# Node when Node is there. The check is misnamed_tests
# (factory/core/tests/lib.sh); it needs only bash and awk.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# The helpers that start Node, pnpm or a browser, as misnamed_tests reads marks (a
# call of one, a word of a body, starts node), kept out of every function body
# here so the check doesn't read this file's own tests as starting them.
NEXTJS_TOOL_MARKS='node (^|[^A-Za-z0-9_])(needs_node|needs_store|needs_browser)([^A-Za-z0-9_]|$)'

test_each_test_that_runs_a_real_tool_ends_in_with_a_tool_and_no_other() {
	local files=("$NEXTJS_ADAPTER"/tests/*_test.sh)
	[ "${#files[@]}" -gt 1 ] || fail "no Next.js test files"
	run_cmd misnamed_tests "$NEXTJS_TOOL_MARKS" "$NEXTJS_ADAPTER/tests/lib.sh" "${files[@]}"
	assert_eq "" "$out" "the misnamed tests"
}

# tests/fixture/names/misnamed_test.sh.txt: a test of each kind, named right and
# wrong, two tests and a helper written so the check can't read them (the
# function after those is read again), and code on a test's opening line.
test_the_check_names_each_misnamed_and_unread_test() {
	add_fixture names/misnamed_test.sh.txt "$TEST_TMP/misnamed_test.sh"
	run_cmd misnamed_tests "$NEXTJS_TOOL_MARKS" "$NEXTJS_ADAPTER/tests/lib.sh" "$TEST_TMP/misnamed_test.sh"
	assert_eq "misnamed_test.sh: unread_helper: can't read its body (from \`unread_helper() {\` to a \`}\` at column 0)
misnamed_test.sh: test_a_keyword_definition: can't read its body (from \`test_a_keyword_definition() {\` to a \`}\` at column 0)
misnamed_test.sh: test_an_indented_closing_brace: can't read its body (from \`test_an_indented_closing_brace() {\` to a \`}\` at column 0)
misnamed_test.sh: test_calls_a_lib_helper_unnamed: starts the real node, so ends in _with_node
misnamed_test.sh: test_calls_a_lib_helper_with_browser: starts the real node, so ends in _with_node
misnamed_test.sh: test_calls_a_local_helper_unnamed: starts the real node, so ends in _with_node
misnamed_test.sh: test_calls_it_directly_unnamed: starts the real node, so ends in _with_node
misnamed_test.sh: test_calls_nothing_but_named_with_node: starts no real tool, so doesn't end in _with_<tool>
misnamed_test.sh: test_code_on_the_opening_line_unnamed: starts the real node, so ends in _with_node
misnamed_test.sh: test_one_line_unnamed: starts the real node, so ends in _with_node" "$out" "the misnamed tests"
}

# The Node pin check needs_node ends with (node_is_pinned), on stand-in Nodes. All
# but the last call the check alone, so they start no real tool and run on a
# machine with no Node; the last calls needs_node, so its name says it runs one.
# Each sets NODE_BIN and PNPM_BIN itself: the run's own would pick another Node.

# stand_in <dir> <name> <output>: <dir>/<name>, a program that prints <output>
# whatever its arguments.
stand_in() {
	mkdir -p "$1" || fail "could not make $1"
	printf '%s' "$3" > "$1/$2.out"
	printf '#!/usr/bin/env bash\ncat %q\n' "$1/$2.out" > "$1/$2" && chmod +x "$1/$2" || fail "could not write $1/$2"
}

# the_pin: the node line of the adapter's tools/verify/pins, as the check reads it.
the_pin() {
	tr -d '\r' < "$NEXTJS_ADAPTER/tools/verify/pins" | sed -n 's/^node //p'
}

test_a_node_other_than_the_pinned_one_fails_naming_both_and_the_fix() {
	local pin
	pin="$(the_pin)"
	[ -n "$pin" ] && [ "$pin" != 24.5.0 ] || fail "the pins name node '$pin'"
	stand_in "$TEST_TMP/path" node $'v24.5.0\n'
	PNPM_BIN='' NODE_BIN='' PATH="$TEST_TMP/path:$PATH" run_cmd node_is_pinned "$NEXTJS_ADAPTER/tools/verify/pins"
	assert_status 1
	assert_eq "    Node 24.5.0 runs here (the node on PATH), but the Next.js adapter's tools/verify/pins names $pin: put Node $pin first on PATH, or name it in NODE_BIN" "$(cat "$TEST_TMP/stderr")" "the failure, Node on PATH"
	PNPM_BIN='' NODE_BIN="$TEST_TMP/path/node" run_cmd node_is_pinned "$NEXTJS_ADAPTER/tools/verify/pins"
	assert_status 1
	assert_eq "    Node 24.5.0 runs here (NODE_BIN=$TEST_TMP/path/node), but the Next.js adapter's tools/verify/pins names $pin: put Node $pin first on PATH, or name it in NODE_BIN" "$(cat "$TEST_TMP/stderr")" "the failure, NODE_BIN"
	stand_in "$TEST_TMP/silent" node ''
	PNPM_BIN='' NODE_BIN="$TEST_TMP/silent/node" run_cmd node_is_pinned "$NEXTJS_ADAPTER/tools/verify/pins"
	assert_status 1
	stderr_has "Node (no version printed) runs here (NODE_BIN=$TEST_TMP/silent/node)"
	printf '# node %s\npnpm 1.0.0\n' "$pin" > "$TEST_TMP/pins"
	PNPM_BIN='' NODE_BIN="$TEST_TMP/path/node" run_cmd node_is_pinned "$TEST_TMP/pins"
	assert_status 1
	stderr_has "no node line in $TEST_TMP/pins"
}

# The steps put PNPM_BIN's folder first on PATH (tools/verify/_nextjs.sh), so with
# no NODE_BIN a Node beside PNPM_BIN is the one they run, ahead of the pinned one.
test_a_wrong_node_beside_pnpm_bin_fails_and_node_bin_overrides_it() {
	local pin
	pin="$(the_pin)"
	stand_in "$TEST_TMP/pinned" node "v$pin"$'\n'
	stand_in "$TEST_TMP/old" node $'v24.5.0\n'
	stand_in "$TEST_TMP/old" pnpm $'1.0.0\n'
	NODE_BIN='' PNPM_BIN="$TEST_TMP/old/pnpm" PATH="$TEST_TMP/pinned:$PATH" run_cmd node_is_pinned "$NEXTJS_ADAPTER/tools/verify/pins"
	assert_status 1
	stderr_has "Node 24.5.0 runs here (the node on PATH, PNPM_BIN's folder first), but"
	NODE_BIN="$TEST_TMP/pinned/node" PNPM_BIN="$TEST_TMP/old/pnpm" run_cmd node_is_pinned "$NEXTJS_ADAPTER/tools/verify/pins"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "stderr, NODE_BIN ahead of PNPM_BIN's folder"
}

# The pinned Node passes, on PATH or named by NODE_BIN ahead of another on PATH;
# a CRLF version line and pins file read the same.
test_the_pinned_node_passes_on_path_or_in_node_bin() {
	local pin
	pin="$(the_pin)"
	stand_in "$TEST_TMP/pinned" node "v$pin"$'\n'
	stand_in "$TEST_TMP/other" node $'v24.5.0\n'
	PNPM_BIN='' NODE_BIN='' PATH="$TEST_TMP/pinned:$TEST_TMP/other:$PATH" run_cmd node_is_pinned "$NEXTJS_ADAPTER/tools/verify/pins"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "stderr, the pinned Node on PATH"
	stand_in "$TEST_TMP/crlf" node "v$pin"$'\r\n'
	sed 's/$/\r/' "$NEXTJS_ADAPTER/tools/verify/pins" > "$TEST_TMP/pins"
	PNPM_BIN='' NODE_BIN="$TEST_TMP/crlf/node" PATH="$TEST_TMP/other:$PATH" run_cmd node_is_pinned "$TEST_TMP/pins"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "stderr, the pinned Node in NODE_BIN, CRLF"
	# A tab, or more than one space, around the version, as factory/core/pins.sh reads it.
	printf '# Node\n  node\t %s\npnpm 1.0.0\n' "$pin" > "$TEST_TMP/pins"
	PNPM_BIN='' NODE_BIN='' PATH="$TEST_TMP/pinned:$PATH" run_cmd node_is_pinned "$TEST_TMP/pins"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "stderr, a pins line spaced with a tab"
}

# needs_node ends with the pin check: Node and pnpm here, but the wrong Node, fail.
# It calls needs_node, so it ends in _with_node, though its Node is a stand-in.
test_needs_node_fails_on_a_node_other_than_the_pinned_one_with_node() {
	stand_in "$TEST_TMP/bin" node $'v24.5.0\n'
	stand_in "$TEST_TMP/bin" pnpm $'1.0.0\n'
	NODE_BIN="$TEST_TMP/bin/node" PNPM_BIN="$TEST_TMP/bin/pnpm" run_cmd needs_node
	assert_status 1
	stderr_has "Node 24.5.0 runs here (NODE_BIN=$TEST_TMP/bin/node)"
}
