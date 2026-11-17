# A Run's relay (relay.sh): it turns a driver's report into the exact Agent call
# or the main session's own outcome, and a report it can't read into a reply
# asking the driver to report again.

# report <outcome>: a driver's report with that outcome line, in ./report.
report() {
	printf '%s\n' "outcome: $1" "issue: #12" "stats: none" "question: none" \
		"summary: round 2 of green, its prompt written." > report
}

# a_prompt [file] [worktree]: a prompt file as a driver writes one.
a_prompt() {
	printf '%s\n' "factory-effort: high" "Build the slice." "factory-worktree: ${2:-/work/issue-12}" > "${1:-prompt.md}"
}

# a_worktree: a git repo at ./work with one commit, an issue's worktree.
a_worktree() {
	isolate_git
	git init -q work && echo one > work/a.txt && git -C work add a.txt &&
		git -C work commit -qm one || fail "no fixture worktree"
}

relay() {
	run_cmd bash "$FACTORY_CORE/relay.sh" "$@"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_needs_editor_sonnet_prints_the_agent_call_and_the_prompt() {
	a_prompt
	report "needs editor-sonnet prompt.md high"
	relay report
	assert_status 0
	assert_eq "relay: agent
subagent_type: editor-sonnet
effort: high
reply: factory-result: editor-sonnet
prompt: $PWD/prompt.md
factory-effort: high
Build the slice.
factory-worktree: /work/issue-12" "$out"
}

test_needs_verifier_and_amend_builder_name_their_own_type_and_result() {
	a_worktree
	mkdir -p rounds
	a_prompt rounds/check.md "$PWD/work"
	report "needs verifier rounds/check.md medium"
	relay report
	assert_status 0
	assert_line "subagent_type: verifier"
	assert_line "effort: medium"
	assert_line "reply: factory-result: verifier"
	assert_line "prompt: $PWD/rounds/check.md"

	report "needs amend-builder $PWD/rounds/check.md xhigh"
	relay report
	assert_status 0
	assert_line "subagent_type: amend-builder"
	assert_line "effort: xhigh"
	assert_line "reply: factory-result: amend-builder"
	assert_line "prompt: $PWD/rounds/check.md"
	assert_no_line "after: bash $FACTORY_CORE/relay.sh after $PWD/work"
}

test_the_report_comes_on_stdin_too_with_crlf_and_indentation() {
	a_worktree
	a_prompt prompt.md "$PWD/work"
	run_cmd bash -c "printf 'summary: x\r\n  outcome: needs verifier prompt.md low  \r\n' | bash '$FACTORY_CORE/relay.sh'"
	assert_status 0
	assert_line "subagent_type: verifier"
	assert_line "effort: low"
}

test_an_effort_of_max_runs_at_xhigh_and_says_so() {
	a_prompt
	report "needs editor-sonnet prompt.md max"
	relay report
	assert_status 0
	assert_line "effort: xhigh"
	assert_no_line "effort: max"
	assert_line "reply: factory-result: editor-sonnet"
	assert_line "reply: factory-relay: the report named effort max, which a driver never asks for: ran at xhigh"
}

test_a_missing_effort_runs_at_medium_and_says_so() {
	a_worktree
	a_prompt prompt.md "$PWD/work"
	report "needs verifier prompt.md"
	relay report
	assert_status 0
	assert_line "effort: medium"
	assert_line "reply: factory-relay: the report named no effort: ran at medium"
}

test_other_outcomes_are_the_main_sessions() {
	report "landed"
	relay report
	assert_status 0
	assert_eq "relay: main-session landed" "$out"

	report "waits-on issue-7-intro"
	relay report
	assert_eq "relay: main-session waits-on issue-7-intro" "$out"

	report "escalated"
	relay report
	assert_eq "relay: main-session escalated" "$out"

	report "needs asset-fetcher"
	relay report
	assert_status 0
	assert_eq "relay: main-session needs asset-fetcher" "$out"
}

test_a_malformed_report_asks_the_driver_to_report_again() {
	a_worktree
	a_prompt prompt.md "$PWD/work"
	printf 'summary: no outcome here\n' > report
	relay report
	assert_status 1
	assert_eq "relay: malformed
reply: factory-relay: the report has no outcome: line; report again" "$out"

	printf '%s\n' "outcome: landed" "outcome: needs verifier prompt.md medium" > report
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the report has 2 outcome: lines, not one; report again"

	report ""
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the report's outcome: line is empty; report again"

	report "needs verifier"
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the needs line names no prompt file: needs verifier; report again"

	report "needs verifier prompt.md ultra"
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the needs line's effort ultra is none of low, medium, high, xhigh; report again"

	report "needs verifier prompt.md medium now"
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the needs line has words past its effort: needs verifier prompt.md medium now; report again"

	report "needs verifier gone.md medium"
	relay report
	assert_status 1
	assert_line "reply: factory-relay: no prompt file gone.md; report again"

	: > empty.md
	report "needs verifier empty.md medium"
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the prompt file empty.md is empty; report again"
	assert_no_line "relay: agent"
}

test_a_report_file_that_isnt_there_is_usage() {
	relay missing-report
	assert_status 2
	stderr_has "relay: no report file missing-report"
}

# A Verifier check that leaves the workspace as it was keeps its verdict.
test_a_verifier_check_that_changes_nothing_is_unchanged() {
	a_worktree
	a_prompt check.md "$PWD/work"
	report "needs verifier check.md medium"
	relay report
	assert_status 0
	assert_line "after: bash $FACTORY_CORE/relay.sh after $PWD/work"
	assert_eq "prompt: $PWD/check.md" "$(printf '%s\n' "$out" | sed -n '6p')" "the after line isn't just above the prompt"
	[ -s work/.git/factory/relay-before ] || fail "no fingerprint kept in the worktree's git dir"
	relay after "$PWD/work"
	assert_status 0
	assert_eq "relay: unchanged" "$out"
	[ ! -e work/.git/factory/relay-before ] || fail "the fingerprint outlived its after"
}

test_a_verifier_check_that_changes_the_workspace_is_void() {
	a_worktree
	a_prompt check.md "$PWD/work"
	report "needs verifier check.md medium"
	void_line="reply: factory-relay: the check changed the workspace of $PWD/work (HEAD, git status or the diff): the check's verdict is void (editor.md, Subagents); restore the worktree and run a fresh check, with no round counted"

	relay report
	echo two > work/a.txt
	relay after "$PWD/work"
	assert_status 0
	assert_eq "relay: void
$void_line" "$out"

	git -C work checkout -q -- a.txt
	relay report
	echo new > work/b.txt
	relay after "$PWD/work"
	assert_line "$void_line"

	rm work/b.txt
	relay report
	git -C work commit -q --allow-empty -m two
	relay after "$PWD/work"
	assert_line "$void_line"
}

test_an_after_with_no_fingerprint_is_void() {
	a_worktree
	relay after "$PWD/work"
	assert_status 0
	assert_line "relay: void"
	assert_line "reply: factory-relay: no fingerprint of $PWD/work from before the check: the check's verdict is void (editor.md, Subagents); restore the worktree and run a fresh check, with no round counted"

	relay after "$PWD/gone"
	assert_line "relay: void"
	relay after
	assert_status 2
}

test_a_verifier_prompt_without_a_worktree_is_malformed() {
	printf '%s\n' "factory-effort: medium" "Check it." > check.md
	report "needs verifier check.md medium"
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the prompt file check.md has no factory-worktree: line; report again"

	a_prompt check.md "$PWD/nowhere"
	relay report
	assert_status 1
	assert_line "reply: factory-relay: the prompt file's worktree $PWD/nowhere is no folder; report again"
}

# The after line runs as printed, whatever the worktree's path holds.
test_the_after_line_quotes_a_worktree_path_with_a_space() {
	a_worktree
	mv work "my work"
	a_prompt check.md "$PWD/my work"
	report "needs verifier check.md high"
	relay report
	assert_status 0
	after="$(printf '%s\n' "$out" | sed -n 's/^after: //p')"
	[ -n "$after" ] || fail "no after line in:"$'\n'"$out"
	run_cmd bash -c "$after"
	assert_status 0
	assert_eq "relay: unchanged" "$out"

	relay report
	echo two > "my work/a.txt"
	run_cmd bash -c "$after"
	assert_line "relay: void"
}
