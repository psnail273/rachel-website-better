# The factory's machine tools (factory/tools/): install.sh copies them onto a
# folder for PATH, checks the copies, and removes the retired ones it shipped.

TOOLS="$FACTORY_CORE/../tools"

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_install_copies_the_tools_and_check_spots_a_stale_copy() {
	run_cmd bash "$TOOLS/install.sh" --check "$TEST_TMP/bin"
	assert_status 1
	stderr_has "install: $TEST_TMP/bin/claude-usage is missing"
	run_cmd bash "$TOOLS/install.sh" "$TEST_TMP/bin"
	assert_status 0
	assert_eq "install: $TEST_TMP/bin/claude-usage" "$out"
	cmp -s "$TOOLS/claude-usage" "$TEST_TMP/bin/claude-usage" || fail "claude-usage was not copied as is"
	[ -x "$TEST_TMP/bin/claude-usage" ] || fail "claude-usage was not made executable"
	run_cmd bash "$TOOLS/install.sh" --check "$TEST_TMP/bin"
	assert_status 0
	echo "# changed" >> "$TEST_TMP/bin/claude-usage"
	run_cmd bash "$TOOLS/install.sh" --check "$TEST_TMP/bin"
	assert_status 1
	stderr_has "install: $TEST_TMP/bin/claude-usage differs from factory/tools/claude-usage"
	run_cmd bash "$TOOLS/install.sh" a b
	assert_status 2
}

# The Cursor Editor's ai-pane and the Codex Verifier's codex-verify are gone from
# the factory: a machine that installed them has them removed, known by the second
# line the factory's copies had; a file of the same name that isn't one is kept.
test_install_removes_the_retired_tools_it_shipped() {
	mkdir -p "$TEST_TMP/bin"
	printf '%s\n' '#!/usr/bin/env bash' "# Run Cursor's CLI agent (\`agent\`) as named jobs, each in its own tmux window, its" > "$TEST_TMP/bin/ai-pane"
	printf '%s\n' '#!/usr/bin/env bash' '# codex-verify: one fresh Verifier check with Codex, start to finish.' > "$TEST_TMP/bin/codex-verify"
	run_cmd bash "$TOOLS/install.sh" --check "$TEST_TMP/bin"
	assert_status 1
	stderr_has "install: $TEST_TMP/bin/ai-pane is retired; run bash factory/tools/install.sh to remove it"
	stderr_has "install: $TEST_TMP/bin/codex-verify is retired; run bash factory/tools/install.sh to remove it"
	[ -f "$TEST_TMP/bin/ai-pane" ] || fail "--check removed a retired tool"
	run_cmd bash "$TOOLS/install.sh" "$TEST_TMP/bin"
	assert_status 0
	assert_eq "install: $TEST_TMP/bin/claude-usage
install: removed the retired $TEST_TMP/bin/ai-pane
install: removed the retired $TEST_TMP/bin/codex-verify" "$out"
	[ ! -e "$TEST_TMP/bin/ai-pane" ] || fail "ai-pane is still there"
	[ ! -e "$TEST_TMP/bin/codex-verify" ] || fail "codex-verify is still there"
	run_cmd bash "$TOOLS/install.sh" --check "$TEST_TMP/bin"
	assert_status 0
	printf '%s\n' '#!/bin/sh' '# the human'"'"'s own codex-verify' > "$TEST_TMP/bin/codex-verify"
	run_cmd bash "$TOOLS/install.sh" "$TEST_TMP/bin"
	assert_status 0
	assert_eq "install: $TEST_TMP/bin/claude-usage" "$out"
	[ -f "$TEST_TMP/bin/codex-verify" ] || fail "a file that isn't the factory's copy was removed"
	run_cmd bash "$TOOLS/install.sh" --check "$TEST_TMP/bin"
	assert_status 0
}
