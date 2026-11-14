# The Editor's gate (hooks/editor-gate.sh) and the Sonnet Editor's SubagentStop
# hook (hooks/claude-subagent-stop.sh, also its SubagentHandback PreToolUse hook),
# on the git fixture project.

STOP_HOOK="$FACTORY_CORE/hooks/claude-subagent-stop.sh"
START_HOOK="$FACTORY_CORE/hooks/claude-subagent-start.sh"
EDITOR_GATE="$FACTORY_CORE/hooks/editor-gate.sh"
. "$FACTORY_CORE/lib/json.sh"

# transcript <worktree line>: a subagent transcript whose prompt holds the line.
transcript() {
	printf '{"type":"user","message":{"role":"user","content":"Build issue 7.\\n%s\\nThe brief is in the git dir."}}\n' "$1" > "$TEST_TMP/transcript.jsonl"
	printf '{"type":"assistant","message":{"content":"factory-worktree: /elsewhere"}}\n' >> "$TEST_TMP/transcript.jsonl"
}

# stop_input [agent_type] [message]: the hook's JSON input for subagent agent-1
# (or $STOP_AGENT),
# in $TEST_TMP/input, its last_assistant_message <message> (empty when given
# empty: a stop after a hand-back has none). Without one the
# message quotes the gate's result line for HEAD as run_stop_hook runs it
# (quoting), so a green gate lets it finish.
stop_input() {
	printf '{"session_id":"s1","hook_event_name":"SubagentStop","stop_hook_active":false,"agent_id":"%s","agent_type":"%s","agent_transcript_path":"%s","last_assistant_message":"%s"}\n' \
		"${STOP_AGENT:-agent-1}" "${1:-editor-sonnet}" "$TEST_TMP/transcript.jsonl" "${2-@QUOTE@}" > "$TEST_TMP/input"
}

# quoting: a final message quoting the green gate's result line for HEAD.
quoting() {
	echo "Done: verify: PASS at $(git rev-parse --short HEAD 2> /dev/null)."
}

# editor_project: the git fixture, with a transcript naming it and a stop input.
editor_project() {
	fixture_git_project
	transcript "factory-worktree: $PWD"
	stop_input
}

# hook_input: $TEST_TMP/input as the hook gets it now, in $TEST_TMP/input.now.
hook_input() {
	sed "s/@QUOTE@/$(quoting)/" "$TEST_TMP/input" > "$TEST_TMP/input.now"
}

# run_stop_hook [hook]: run the stop hook (the Core's, or <hook>) on the input.
run_stop_hook() {
	hook_input
	run_cmd bash "${1:-$STOP_HOOK}" < "$TEST_TMP/input.now"
}

# handback_input [message] [agent_type] [tool]: the PreToolUse input of agent-1's
# SubagentHandback call, in $TEST_TMP/input, its message <message> (by default
# quoting, as stop_input), the subagent's transcript where Claude Code keeps it,
# beside the session's.
handback_input() {
	mkdir -p "$TEST_TMP/session/subagents"
	cp "$TEST_TMP/transcript.jsonl" "$TEST_TMP/session/subagents/agent-agent-1.jsonl"
	printf '{"session_id":"s1","hook_event_name":"PreToolUse","agent_id":"agent-1","agent_type":"%s","transcript_path":"%s","tool_name":"%s","tool_input":{"message":"%s"},"tool_use_id":"t1"}\n' \
		"${2:-editor-sonnet}" "$TEST_TMP/session.jsonl" "${3:-SubagentHandback}" "${1:-@QUOTE@}" > "$TEST_TMP/input"
}

red_lint() {
	echo "src/a.txt:1 lint-bad a lint finding" > .fixture/fail-lint
}

counter() {
	cat "$(git rev-parse --git-dir)/factory/subagent-stop/agent-1" 2> /dev/null
}

# --- the SubagentStop hook ------------------------------------------------------

test_stop_hook_blocks_with_the_findings_while_the_gate_is_red() {
	editor_project
	red_lint
	run_stop_hook
	assert_status 2
	stderr_has "The gate is red (block 1 of 5)"
	stderr_has "src/a.txt:1 lint-bad a lint finding"
	stderr_has "verify: FAILED at step lint"
}

test_stop_hook_lets_the_subagent_finish_when_the_gate_is_green() {
	editor_project
	start_round
	run_stop_hook
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")"
	grep -qx smoke .fixture/ran || fail "the full verify did not run"
}

test_stop_hook_blocks_until_the_findings_are_fixed() {
	editor_project
	red_lint
	run_stop_hook
	assert_status 2
	run_stop_hook
	assert_status 2
	stderr_has "(block 2 of 5)"
	rm .fixture/fail-lint
	run_stop_hook
	assert_status 0
	assert_eq "" "$(counter)" "the loop count was kept after a green gate"
}

test_stop_hook_lets_the_subagent_stop_after_five_blocks() {
	editor_project
	red_lint
	# shellcheck disable=SC2034 # n counts the five blocks
	for n in 1 2 3 4 5; do
		run_stop_hook
		assert_status 2
	done
	run_stop_hook
	assert_status 0
	stderr_has "still red after 5 tries"
}

test_stop_hook_ignores_other_agents() {
	editor_project
	red_lint
	stop_input general-purpose
	run_stop_hook
	assert_status 0
	[ ! -f .fixture/ran ] || fail "the gate ran for another agent"
}

test_stop_hook_without_a_worktree_line_lets_the_subagent_stop() {
	editor_project
	red_lint
	transcript "no worktree here"
	run_stop_hook
	assert_status 0
	stderr_has "the prompt names no worktree"
	[ ! -f .fixture/ran ] || fail "a gate ran without a worktree"
}

test_stop_hook_reads_a_windows_worktree_path() {
	editor_project
	command -v cygpath > /dev/null || skip "no cygpath, so no Windows path to test"
	red_lint
	transcript "factory-worktree: $(cygpath -w "$PWD" | sed 's/\\/\\\\/g')"
	run_stop_hook
	assert_status 2
	stderr_has "src/a.txt:1 lint-bad a lint finding"
}

test_stop_hook_runs_the_gate_in_the_named_worktree_from_anywhere() {
	editor_project
	red_lint
	project="$PWD"
	mkdir "$TEST_TMP/elsewhere" && cd "$TEST_TMP/elsewhere" || fail "could not enter $TEST_TMP/elsewhere"
	run_stop_hook
	assert_status 2
	stderr_has "Fix these findings in $project"
}

test_stop_hook_lets_a_green_linked_worktree_finish_under_the_main_checkouts_core() {
	linked_worktree
	transcript "factory-worktree: $PWD"
	stop_input
	start_round
	run_stop_hook "$MAIN_CORE/hooks/claude-subagent-stop.sh"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")"
	grep -qx smoke .fixture/ran || fail "the full verify did not run in the worktree"
	assert_eq "" "$(counter)" "a block count was left after a green gate"
}

# --- the Editor's gate ------------------------------------------------------------

test_gate_runs_the_full_verify_without_a_phase() {
	fixture_git_project
	run_cmd bash "$EDITOR_GATE"
	assert_status 0
	assert_last_line "verify: PASS"
}

test_gate_runs_the_red_gate_in_the_red_phase() {
	fixture_git_project
	git config branch.work.factory-phase red
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_line "== test FAIL"
}

test_gate_runs_the_baseline_gate_in_the_partial_phase() {
	fixture_git_project
	mkdir -p tools/verify/ratchet && : > tools/verify/ratchet/baseline.txt
	git add -A && git commit -q -m "the Baseline"
	mkdir -p .git/factory && printf '%s\n' '```factory-brief' 'scope src/**' '```' > .git/factory/brief.md
	git config branch.work.factory-phase partial
	run_cmd bash "$EDITOR_GATE"
	assert_status 0
	assert_last_line "baseline: PASS"
}

# The brief is the Driver's: once sealed, a changed brief stops the round before
# any gate runs, whatever the phase.
# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_gate_fails_on_a_brief_changed_after_its_seal() {
	fixture_git_project
	mkdir -p .git/factory && printf '%s\n' '```factory-brief' 'scope src/**' '```' > .git/factory/brief.md
	git config branch.work.factory-phase green
	git config branch.work.factory-brief-sha "$(git hash-object --no-filters .git/factory/brief.md)"
	run_cmd bash "$EDITOR_GATE"
	assert_status 0
	assert_last_line "verify: PASS"
	printf '%s\n' '```factory-brief' 'scope **' '```' > .git/factory/brief.md
	rm -f .fixture/ran
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_eq "gate: the Build Brief's seal
.git/factory/brief.md:1 brief-changed the Build Brief changed after the Driver sealed it; only the Driver edits it, then seals it again with brief.sh seal (Editor: report this and stop)" "$out"
	[ ! -f .fixture/ran ] || fail "a gate step ran on a changed brief: $(ran_steps)"
}

test_gate_formats_the_changed_files_first() {
	fixture_git_project
	cat > tools/verify/format << 'SH'
[ "$#" -eq 0 ] || echo "$*" > .fixture/format-args
SH
	git add -A && git commit -q -m "format records its arguments"
	echo two > src/a.txt
	echo new > src/b.txt
	run_cmd bash "$EDITOR_GATE"
	assert_eq "--write src/a.txt src/b.txt tools/verify/format" "$(cat .fixture/format-args)"
}

# uncommitted <file>: the gate's finding for that file.
uncommitted() {
	printf '%s:1 editor-uncommitted uncommitted, and Land refuses a dirty tree; commit it' "$1"
}

# not_run: the gate's first line when the tree is uncommitted before it runs.
NOT_RUN="gate: not run: the tree has uncommitted changes, and the gate judges only a committed tree"

# no_gate_step_ran: fail when any step but format --write ran.
no_gate_step_ran() {
	[ "$(ran_steps)" = format ] || fail "a gate step ran on an uncommitted tree: $(ran_steps)"
}

test_gate_does_not_run_on_an_untracked_file() {
	fixture_git_project
	echo new > src/b.txt
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_eq "$NOT_RUN" "$(printf '%s\n' "$out" | head -n 1)" "wrong first line"
	assert_last_line "$(uncommitted src/b.txt)"
	assert_eq 1 "$(grep -c editor-uncommitted <<< "$out")" "wrong number of findings"
	no_gate_step_ran
}

test_gate_does_not_run_on_a_modified_file() {
	fixture_git_project
	echo two > src/a.txt
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_eq "$NOT_RUN" "$(printf '%s\n' "$out" | head -n 1)" "wrong first line"
	assert_last_line "$(uncommitted src/a.txt)"
	assert_eq 1 "$(grep -c editor-uncommitted <<< "$out")" "wrong number of findings"
	no_gate_step_ran
}

# #15: a file format --write changed is caught before any gate step, named as
# the formatter's change.
test_gate_catches_what_formatting_changed_before_any_gate_step() {
	fixture_git_project
	cat > tools/verify/format << 'SH'
echo format >> .fixture/ran
[ "$#" -eq 0 ] || echo formatted >> src/a.txt
SH
	echo two > src/a.txt
	git add -A && git commit -q -m "format appends to src/a.txt"
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_eq "$NOT_RUN" "$(printf '%s\n' "$out" | head -n 1)" "wrong first line"
	assert_last_line "src/a.txt:1 editor-uncommitted format --write changed it, and Land refuses a dirty tree; commit it"
	no_gate_step_ran
}

test_gate_is_red_when_its_own_tools_leave_a_file() {
	fixture_git_project
	echo 'echo made > src/c.txt' > .fixture/run-smoke
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_line "verify: PASS"
	assert_last_line "$(uncommitted src/c.txt)"
}

test_gate_is_green_on_a_clean_tree() {
	fixture_git_project
	run_cmd bash "$EDITOR_GATE"
	assert_status 0
	assert_last_line "verify: PASS"
}

test_gate_reports_the_uncommitted_files_before_a_red_step() {
	fixture_git_project
	red_lint
	echo new > src/b.txt
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_last_line "$(uncommitted src/b.txt)"
	grep -q lint-bad <<< "$out" && fail "a gate step ran on an uncommitted tree:"$'\n'"$out"
	return 0
}

# #15: every static step's findings at once, and no long step after a red one.
test_gate_shows_every_static_steps_findings_at_once() {
	fixture_git_project
	echo "src/a.txt:1 type-bad a type finding" > .fixture/fail-typecheck
	red_lint
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_line "src/a.txt:1 type-bad a type finding"
	assert_line "src/a.txt:1 lint-bad a lint finding"
	assert_line "== deviation PASS"
	assert_last_line "verify: FAILED at step typecheck"
	assert_eq "prepare format typecheck lint deviation" "$(ran_steps)" "wrong steps ran"
}

test_stop_hook_blocks_an_uncommitted_file_until_it_is_committed() {
	editor_project
	echo new > src/b.txt
	run_stop_hook
	assert_status 2
	stderr_has "(block 1 of 5)"
	stderr_has "$(uncommitted src/b.txt)"
	git add -A && git commit -q -m "add b"
	run_stop_hook
	assert_status 0
	assert_eq "" "$(counter)" "the loop count was kept after a green gate"
}

# --- the small lane ---------------------------------------------------------------

# small_red [lane]: the red phase of a brief in the small lane (none when the
# argument is "none"), committed: test_new added to tests/a_test.txt and failing
# on an assertion, the old tests passing, the product untouched.
small_red() {
	if [ "${1:-small}" = small ]; then
		brief "lane small" "scope tests/a_test.txt" "scope src/a.txt" "test test_new"
		git config branch.work.factory-lane small
	else
		brief "scope tests/a_test.txt" "scope src/a.txt" "test test_new"
	fi
	git config branch.work.factory-phase red
	echo test_new >> tests/a_test.txt
	printf '%s\t%s\t%s\n' test_old_one PASS tests/a_test.txt:1 test_old_two PASS tests/a_test.txt:2 \
		test_new FAILURE tests/a_test.txt:3 > .fixture/results
	git add -A && git commit -q -m red || fail "commit failed"
}

# green_instruction: how the small lane's message ends, the green phase's
# instruction: the green round the Driver sends after any other Lock, from
# prompts/green.md, then the footer.
green_instruction() {
	cat "$FACTORY_CORE/../skills/factory-run/prompts/green.md"
	echo
	cat "$FACTORY_CORE/../skills/factory-run/prompts/footer.md"
}

test_gate_in_the_small_lane_locks_a_green_red_phase_and_goes_on_to_green() {
	fixture_git_project
	small_red
	FACTORY_NOW=4000 run_cmd bash "$EDITOR_GATE"
	assert_status 3
	assert_eq "gate: verify --red (the red phase: the brief's new tests must fail, everything else pass)
The red gate passed, so the factory recorded the Lock at $(git rev-parse --short HEAD) and moved this issue to the green phase, in this chat. The locked test files:
  tests/a_test.txt

$(green_instruction)" "$out"
	stderr_has "verify: PASS"
	assert_eq "$(git rev-parse HEAD)" "$(git config branch.work.factory-red-commit)"
	assert_eq green "$(git config branch.work.factory-phase)"
	assert_eq 4000 "$(git config branch.work.factory-began-green)" "the move to green was not timed for the stats line's minutes"
}

# copy_core: a copy of the Core and of factory-run's prompts, outside the project,
# so a test can change a template; $COPY_GATE is its editor-gate.sh.
copy_core() {
	mkdir -p "$TEST_TMP/copy/skills/factory-run"
	cp -R "$FACTORY_CORE" "$TEST_TMP/copy/core" || fail "could not copy the Core"
	cp -R "$FACTORY_CORE/../skills/factory-run/prompts" "$TEST_TMP/copy/skills/factory-run/" || fail "could not copy the prompts"
	COPY_GATE="$TEST_TMP/copy/core/hooks/editor-gate.sh"
}

# The hook spelled out its own green text: it sends prompts/green.md's, so the
# two can't drift.
test_gate_in_the_small_lane_sends_the_green_text_of_prompts_green_md() {
	fixture_git_project
	small_red
	copy_core
	echo "Phase: green. A line the template changed to." > "$TEST_TMP/copy/skills/factory-run/prompts/green.md"
	run_cmd bash "$COPY_GATE"
	assert_status 3
	assert_eq "Phase: green. A line the template changed to.

$(cat "$FACTORY_CORE/../skills/factory-run/prompts/footer.md")" "$(tail -n 3 <<< "$out")"
	assert_eq green "$(git config branch.work.factory-phase)"
}

# Without its green prompt the small lane moves nothing: no Lock, still red.
test_gate_in_the_small_lane_locks_nothing_without_the_green_prompt() {
	fixture_git_project
	small_red
	copy_core
	rm "$TEST_TMP/copy/skills/factory-run/prompts/green.md"
	run_cmd bash "$COPY_GATE"
	assert_status 1
	printf '%s\n' "$out" | grep -q "^the small lane could not record the Lock: prompt.sh green failed, so there is no green instruction to send: prompt: no template " ||
		fail "no reason in:"$'\n'"$out"
	assert_last_line "This is the Driver's to fix: stop and report it."
	assert_eq red "$(git config branch.work.factory-phase)"
	git config branch.work.factory-red-commit > /dev/null && fail "the gate recorded a Lock with no green prompt to send"
	return 0
}

test_gate_in_the_small_lane_stays_in_red_while_the_red_gate_is_red() {
	fixture_git_project
	small_red
	red_lint
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_line "src/a.txt:1 lint-bad a lint finding"
	assert_eq red "$(git config branch.work.factory-phase)"
	git config branch.work.factory-red-commit > /dev/null && fail "a red gate recorded the Lock"
	return 0
}

test_gate_in_the_small_lane_wants_the_red_phase_committed_first() {
	fixture_git_project
	small_red
	echo "# a note" >> tests/a_test.txt
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_last_line "$(uncommitted tests/a_test.txt)"
	assert_eq red "$(git config branch.work.factory-phase)"
	git config branch.work.factory-red-commit > /dev/null && fail "a dirty tree recorded the Lock"
	return 0
}

# A commit made while the gate ran was never judged by it: no Lock on it.
test_gate_in_the_small_lane_locks_nothing_when_head_moves_during_the_gate() {
	fixture_git_project
	small_red
	echo 'echo test_more > tests/b_test.txt && git add tests/b_test.txt && git commit -q -m sneak' > .fixture/run-smoke
	run_cmd bash "$EDITOR_GATE"
	assert_status 1
	assert_line "the small lane could not record the Lock: HEAD moved while the gate ran, so the gate did not judge it"
	assert_eq red "$(git config branch.work.factory-phase)"
	git config branch.work.factory-red-commit > /dev/null && fail "the gate locked a commit it never judged"
	return 0
}

test_gate_outside_the_small_lane_leaves_a_green_red_phase_to_the_driver() {
	fixture_git_project
	small_red none
	run_cmd bash "$EDITOR_GATE"
	assert_status 0
	assert_last_line "verify: PASS"
	assert_eq red "$(git config branch.work.factory-phase)"
	git config branch.work.factory-red-commit > /dev/null && fail "the gate recorded a Lock outside the small lane"
	return 0
}

test_stop_hook_blocks_with_the_green_instruction_in_the_small_lane() {
	editor_project
	small_red
	mkdir -p "$(dirname "$(git rev-parse --git-dir)/factory/subagent-stop/agent-1")"
	echo 3 > "$(git rev-parse --git-dir)/factory/subagent-stop/agent-1"
	run_stop_hook
	assert_status 2
	stderr_has "$(cat "$FACTORY_CORE/../skills/factory-run/prompts/green.md")"
	stderr_has "$(cat "$FACTORY_CORE/../skills/factory-run/prompts/footer.md")"
	grep -q "^gate: " "$TEST_TMP/stderr" && fail "the block carried the gate's name line:"$'\n'"$(cat "$TEST_TMP/stderr")"
	assert_eq "" "$(counter)" "the move to green kept the block count"
	assert_eq green "$(git config branch.work.factory-phase)"
}

# --- the hand-back (#21) ---------------------------------------------------------

# smoke_runs: how many times the gate's smoke step ran.
smoke_runs() {
	grep -cx smoke .fixture/ran 2> /dev/null
}

# A subagent in auto mode ends with its SubagentHandback call, which delivers its
# report: the hook decides at that call's PreToolUse, so the green instruction
# reaches the same chat.
test_handback_hook_blocks_with_the_green_instruction_in_the_small_lane() {
	editor_project
	small_red
	handback_input
	run_stop_hook
	assert_status 2
	stderr_has "The red gate passed, so the factory recorded the Lock at $(git rev-parse --short HEAD)"
	stderr_has "$(cat "$FACTORY_CORE/../skills/factory-run/prompts/green.md")"
	assert_eq green "$(git config branch.work.factory-phase)"
	assert_eq "" "$(counter)" "the move to green kept the block count"
}

test_handback_hook_ignores_other_agents_and_other_tools() {
	editor_project
	red_lint
	handback_input "" general-purpose
	run_stop_hook
	assert_status 0
	handback_input "" editor-sonnet Bash
	run_stop_hook
	assert_status 0
	[ ! -f .fixture/ran ] || fail "the gate ran for another agent or tool: $(ran_steps)"
}

test_handback_hook_blocks_with_the_findings_while_the_gate_is_red() {
	editor_project
	red_lint
	handback_input
	run_stop_hook
	assert_status 2
	stderr_has "The gate is red (block 1 of 5)"
	stderr_has "src/a.txt:1 lint-bad a lint finding"
}

# A green gate lets the hand-back through only when its message quotes the gate's
# result line; the gate runs once for both, and the stop that follows the
# hand-back runs none.
test_handback_hook_refuses_a_message_that_does_not_quote_the_gate_result() {
	editor_project
	start_round
	handback_input "Done, the gate is green."
	run_stop_hook
	assert_status 2
	stderr_has "The gate is green, but your final message doesn't quote its result (block 1 of 5)"
	assert_last_line_of_stderr "verify: PASS at $(git rev-parse --short HEAD)"
	assert_eq 1 "$(counter)"
	handback_input
	run_stop_hook
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")"
	assert_eq "" "$(counter)" "the block count was kept after a quoted result"
	assert_eq 1 "$(smoke_runs)" "the gate ran again for the same commit"
	stop_input editor-sonnet ""
	run_stop_hook
	assert_status 0
	assert_eq 1 "$(smoke_runs)" "the stop after the hand-back ran the gate"
	[ ! -e "$(git rev-parse --git-dir)/factory/subagent-stop/agent-1.handback" ] || fail "the hand-back's mark outlived its stop"
}

# assert_last_line_of_stderr <line>
assert_last_line_of_stderr() {
	assert_eq "$1" "$(tail -n 1 "$TEST_TMP/stderr")" "the last line of stderr"
}

test_stop_hook_refuses_a_last_message_that_does_not_quote_the_gate_result() {
	editor_project
	stop_input editor-sonnet "All done."
	run_stop_hook
	assert_status 2
	assert_last_line_of_stderr "verify: PASS at $(git rev-parse --short HEAD)"
	stop_input
	run_stop_hook
	assert_status 0
}

# A result line of another commit is no quote of this one's.
test_stop_hook_refuses_the_result_line_of_an_older_commit() {
	editor_project
	stop_input editor-sonnet "$(quoting)"
	echo two > src/a.txt
	git commit -q -am "product change"
	run_stop_hook
	assert_status 2
	assert_last_line_of_stderr "verify: PASS at $(git rev-parse --short HEAD)"
}

test_stop_hook_quotes_the_baseline_gate_in_the_partial_phase() {
	editor_project
	mkdir -p tools/verify/ratchet && : > tools/verify/ratchet/baseline.txt
	git add -A && git commit -q -m "the Baseline"
	mkdir -p .git/factory && printf '%s\n' '```factory-brief' 'scope src/**' '```' > .git/factory/brief.md
	git config branch.work.factory-phase partial
	stop_input editor-sonnet "Done."
	run_stop_hook
	assert_status 2
	assert_last_line_of_stderr "baseline: PASS at $(git rev-parse --short HEAD)"
	stop_input editor-sonnet "Done: baseline: PASS at $(git rev-parse --short HEAD)."
	run_stop_hook
	assert_status 0
}

test_stop_hook_lets_the_subagent_stop_after_five_unquoted_messages() {
	editor_project
	stop_input editor-sonnet "All done."
	# shellcheck disable=SC2034 # n counts the five blocks
	for n in 1 2 3 4 5; do
		run_stop_hook
		assert_status 2
	done
	run_stop_hook
	assert_status 0
	stderr_has "the final message still doesn't quote the gate's result after 5 tries"
}

# sealed_green: the green phase, its brief sealed as the Driver seals it.
sealed_green() {
	mkdir -p .git/factory && printf '%s\n' '```factory-brief' 'scope src/**' '```' > .git/factory/brief.md
	git config branch.work.factory-phase green
	git config branch.work.factory-brief-sha "$(git hash-object --no-filters .git/factory/brief.md)"
}

# A green result serves only the stop, then the hand-back, of the subagent that
# ran it: the next round's subagent runs the gate again, and so sees a brief
# changed after its seal (review of #21's amend).
test_stop_hook_runs_the_gate_again_for_the_next_rounds_subagent() {
	editor_project
	sealed_green
	run_stop_hook
	assert_status 0
	printf '%s\n' '```factory-brief' 'scope **' '```' > .git/factory/brief.md
	STOP_AGENT=agent-2 stop_input
	run_stop_hook
	assert_status 2
	stderr_has "brief-changed the Build Brief changed after the Driver sealed it"
}

# Between a subagent's stop and the hand-back it asks for, a changed brief is no
# green result's: the round's compare blocks it.
test_stop_hook_takes_no_green_result_over_a_changed_brief() {
	editor_project
	sealed_green
	stop_input editor-sonnet "Done."
	run_stop_hook
	assert_status 2
	stderr_has "doesn't quote its result"
	printf '%s\n' '```factory-brief' 'scope **' '```' > .git/factory/brief.md
	stop_input
	run_stop_hook
	assert_status 2
	stderr_has "brief.md:1 round-changed"
}

# hold_the_gate: the gate's smoke step blocks until $TEST_TMP/release exists.
hold_the_gate() {
	blocking_stand_in "$TEST_TMP/hang" "$TEST_TMP/release"
	printf '%q\n' "$TEST_TMP/hang" > .fixture/run-smoke
}

# start_held_hook: the hook run on the input in the background, its pid in
# $held, its stderr in $TEST_TMP/held.stderr; returns once its gate holds.
start_held_hook() {
	hook_input
	bash "$STOP_HOOK" < "$TEST_TMP/input.now" > /dev/null 2> "$TEST_TMP/held.stderr" &
	held=$!
	wait_until "the gate to reach its smoke step" test -s "$TEST_TMP/hang.pid"
}

gate_free() {
	[ ! -e "$(git rev-parse --git-dir)/factory/editor-gate/running" ]
}

# second_hook_waits_or_ends: the second hook said it waits for the gate in
# flight, or it ended.
second_hook_waits_or_ends() {
	grep -qF "a gate is already running in $PWD; waiting for it" "$TEST_TMP/stderr" || ! kill -0 "$second" 2> /dev/null
}

# Claude Code stops a hook while its gate runs (#21): the gate runs on, and the
# next stop waits for it and passes on its green instruction, with no second run.
# It waits before it compares the round: the gate in flight writes the small
# lane's run state (here, before its held smoke step), the gate's and not the
# round's.
test_stop_hook_waits_for_a_gate_in_flight_and_passes_on_its_green_instruction() {
	editor_project
	small_red
	hold_the_gate
	printf '%s\n' 'git config branch.work.factory-red-commit early' "$(cat .fixture/run-smoke)" > .fixture/run-smoke
	start_held_hook
	kill "$held"
	wait "$held"
	[ -d "$(git rev-parse --git-dir)/factory/editor-gate/running" ] || fail "the gate stopped with its hook"
	hook_input
	bash "$STOP_HOOK" < "$TEST_TMP/input.now" > /dev/null 2> "$TEST_TMP/stderr" &
	second=$!
	wait_until "the second hook to wait for the gate, or end" second_hook_waits_or_ends
	touch "$TEST_TMP/release"
	wait "$second"
	status=$?
	assert_status 2
	stderr_has "$(cat "$FACTORY_CORE/../skills/factory-run/prompts/green.md")"
	assert_eq green "$(git config branch.work.factory-phase)"
	assert_eq 1 "$(smoke_runs)" "the gate ran twice"
	wait_until "the gate to free" gate_free
}

# A gate whose hook was stopped, done before the next stop: its green instruction
# is passed on once.
test_stop_hook_passes_on_a_stopped_hooks_green_instruction_once() {
	editor_project
	small_red
	hold_the_gate
	start_held_hook
	kill "$held"
	wait "$held"
	touch "$TEST_TMP/release"
	wait_until "the gate to free" gate_free
	run_stop_hook
	assert_status 2
	stderr_has "$(cat "$FACTORY_CORE/../skills/factory-run/prompts/green.md")"
	assert_eq 1 "$(smoke_runs)" "the gate ran twice"
	run_stop_hook
	assert_status 2
	stderr_has "The gate is red (block 1 of 5)"
}

# The wait is bounded by FACTORY_EDITOR_GATE_WAIT: past it the stop goes through,
# saying so, and the gate in flight still ends with its own hook's answer.
test_stop_hook_stops_waiting_after_the_gate_wait() {
	editor_project
	small_red
	hold_the_gate
	start_held_hook
	FACTORY_EDITOR_GATE_WAIT=1 run_stop_hook
	assert_status 0
	stderr_has "a gate already running in $PWD ran past FACTORY_EDITOR_GATE_WAIT (1s)"
	touch "$TEST_TMP/release"
	wait "$held"
	# shellcheck disable=SC2034 # read by assert_status
	status=$?
	assert_status 2
	grep -qF "$(head -n 1 "$FACTORY_CORE/../skills/factory-run/prompts/green.md")" "$TEST_TMP/held.stderr" ||
		fail "the held hook did not pass on the green instruction:"$'\n'"$(cat "$TEST_TMP/held.stderr")"
	assert_eq 1 "$(smoke_runs)" "the gate ran twice"
}

# --- the round's snapshot and its compare (lib/round.sh) ------------------------------

# start_round [agent_type]: run the SubagentStart hook for subagent agent-1, its cwd
# the current folder, as Claude Code runs it in the main checkout.
start_round() {
	printf '{"session_id":"s1","hook_event_name":"SubagentStart","agent_id":"agent-1","agent_type":"%s","cwd":"%s"}\n' \
		"${1:-editor-sonnet}" "$PWD" > "$TEST_TMP/start-input"
	run_cmd bash "$START_HOOK" < "$TEST_TMP/start-input"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "the start hook printed something"
}

snapshot() {
	printf '%s/factory/round/agent-1' "$(git rev-parse --path-format=absolute --git-common-dir)"
}

# with_remote: a bare origin holding dev, as the fixture's remote.
with_remote() {
	git init -q --bare -b dev "$TEST_TMP/origin.git" || fail "could not make the remote"
	git remote add origin "$TEST_TMP/origin.git"
	git push -q origin dev 2> /dev/null || fail "could not push dev"
}

# assert_round_blocked <finding>: the stop hook blocked on what the round changed,
# that finding among them, and ran no gate step.
assert_round_blocked() {
	assert_status 2
	stderr_has "This round changed what the factory protects (block 1 of 5), so the gate did not run."
	stderr_has "$1"
	[ ! -f .fixture/ran ] || fail "the gate ran on a round that changed what the factory protects: $(ran_steps)"
}

test_start_hook_takes_no_snapshot_for_another_agent() {
	editor_project
	start_round general-purpose
	[ ! -e "$(snapshot)" ] || fail "a snapshot for another agent"
}

test_start_hook_snapshots_the_checkouts_the_config_and_the_refs() {
	editor_project
	start_round
	grep -qx "head	$PWD	$(git rev-parse HEAD)" "$(snapshot)" || fail "no HEAD line in:"$'\n'"$(cat "$(snapshot)")"
	grep -qx "ref	local	refs/heads/dev	$(git rev-parse dev)" "$(snapshot)" || fail "no dev line in:"$'\n'"$(cat "$(snapshot)")"
	grep -qx "remote	unreachable" "$(snapshot)" || fail "a fixture with no remote was reached:"$'\n'"$(cat "$(snapshot)")"
}

test_stop_hook_lets_a_round_that_changed_nothing_protected_run_the_gate() {
	editor_project
	start_round
	echo two > src/a.txt
	git commit -q -am "product change"
	run_stop_hook
	assert_status 0
	grep -qx smoke .fixture/ran || fail "the full verify did not run"
	[ ! -e "$(snapshot)" ] || fail "the snapshot outlived a green stop"
}

test_stop_hook_blocks_a_protected_file_written_by_python() {
	editor_project
	start_round
	python3 -c 'open("tools/verify/lint", "a").write("exit 0\n")'
	run_stop_hook
	assert_round_blocked "$PWD/tools/verify/lint:1 round-changed changed this round, on disk and not committed: the factory protects it; put it back as it was"
}

test_stop_hook_blocks_a_protected_file_changed_by_git_apply() {
	editor_project
	start_round
	echo "exit 0" >> tools/verify/lint
	git diff > "$TEST_TMP/patch"
	git checkout -q -- tools/verify/lint
	git apply "$TEST_TMP/patch" || fail "git apply failed"
	run_stop_hook
	assert_round_blocked "$PWD/tools/verify/lint:1 round-changed"
}

test_stop_hook_blocks_a_protected_file_the_round_committed() {
	editor_project
	start_round
	echo "exit 0" >> tools/verify/lint
	git commit -q -am "loosen lint"
	run_stop_hook
	assert_round_blocked "$PWD/tools/verify/lint:1 round-changed a commit this round changed it: the factory protects it; revert that change in a new commit"
}

test_stop_hook_blocks_the_run_state_the_round_set() {
	editor_project
	start_round
	git config branch.work.factory-phase green
	run_stop_hook
	assert_round_blocked "the run state branch.work.factory-phase changed this round"
}

test_stop_hook_blocks_a_dev_moved_here() {
	editor_project
	start_round
	echo two > src/a.txt
	git commit -q -am "product change"
	git update-ref refs/heads/dev HEAD
	run_stop_hook
	assert_round_blocked "refs/heads/dev:1 round-changed moved this round here, from "
	stderr_has "round compare: origin could not be reached, so only the local dev and main were compared"
}

test_stop_hook_blocks_a_dev_pushed_to_the_remote() {
	editor_project
	with_remote
	start_round
	echo two > src/a.txt
	git commit -q -am "product change"
	git push -q origin HEAD:refs/heads/dev 2> /dev/null || fail "could not push"
	run_stop_hook
	assert_round_blocked "refs/heads/dev:1 round-changed moved this round on origin, from $(git rev-parse dev) to $(git rev-parse HEAD)"
	grep -q "could not be reached" "$TEST_TMP/stderr" && fail "the remote was reachable"
	return 0
}

# A remote that never answers: the start hook gives up on it after
# FACTORY_ROUND_REMOTE_TIMEOUT seconds and still snapshots the rest, so the stop
# compares all but the remote.
test_start_hook_snapshots_all_but_a_remote_that_never_answers() {
	editor_project
	assert_round_gives_up_on_a_remote_that_never_answers
}

# The same on a machine with no timeout (stock macOS): lib/bounded.sh's watchdog
# bounds the wait.
test_start_hook_snapshots_all_but_a_remote_that_never_answers_where_timeout_is_missing() {
	editor_project
	path_without timeout
	assert_round_gives_up_on_a_remote_that_never_answers
}

# assert_round_gives_up_on_a_remote_that_never_answers: on the editor project, a
# remote whose ssh blocks until released: the start hook gives up on it, the
# stop compares the rest, and the ssh stand-ins end once released.
assert_round_gives_up_on_a_remote_that_never_answers() {
	git remote add origin ssh://example.invalid/factory.git
	blocking_stand_in "$TEST_TMP/hang" "$TEST_TMP/release"
	# The ssh git starts: it runs the stand-in, notes its pid (each run overwrites
	# hang.pid), and notes how it ended, unless it is killed first.
	cat > "$TEST_TMP/ssh" << SH
#!/usr/bin/env bash
$(printf '%q' "$TEST_TMP/hang") &
echo "\$!" >> $(printf '%q' "$TEST_TMP/ssh.pids")
wait "\$!"
echo "\$?" >> $(printf '%q' "$TEST_TMP/ssh.ends")
SH
	chmod 755 "$TEST_TMP/ssh"
	export GIT_SSH_COMMAND="$TEST_TMP/ssh" FACTORY_ROUND_REMOTE_TIMEOUT=1
	start_round
	# The hook stopped waiting for the stand-in, which never ended on its own.
	[ ! -s "$TEST_TMP/ssh.ends" ] || fail "the start hook waited until the remote gave up"
	grep -qx "remote	unreachable" "$(snapshot)" || fail "no unreachable remote in:"$'\n'"$(cat "$(snapshot)")"
	grep -qx "ref	local	refs/heads/dev	$(git rev-parse dev)" "$(snapshot)" || fail "no dev line in:"$'\n'"$(cat "$(snapshot)")"
	python3 -c 'open("tools/verify/lint", "a").write("exit 0\n")'
	run_stop_hook
	assert_round_blocked "$PWD/tools/verify/lint:1 round-changed changed this round"
	stderr_has "round compare: origin could not be reached, so only the local dev and main were compared"
	touch "$TEST_TMP/release"
	wait_until "the ssh stand-ins to end" ssh_stand_ins_ended
}

ssh_stand_ins_ended() {
	local pid
	[ -s "$TEST_TMP/ssh.pids" ] || return 0
	while IFS= read -r pid; do
		! kill -0 "$pid" 2> /dev/null || return 1
	done < "$TEST_TMP/ssh.pids"
}

# A start hook stopped while it waited for the remote leaves a snapshot with no
# remote refs: the stop says the remote was not compared, even on a green gate.
test_stop_hook_says_so_when_the_snapshot_has_no_remote_refs() {
	editor_project
	with_remote
	start_round
	sed -i '/^ref	remote	/d' "$(snapshot)"
	echo two > src/a.txt
	git commit -q -am "product change"
	git push -q origin HEAD:refs/heads/dev 2> /dev/null || fail "could not push"
	run_stop_hook
	assert_status 0
	stderr_has "the snapshot of the round's start has no refs from origin"
}

# A parallel issue's Land moves dev during the round: a commit a land log names,
# its gate green, is no change of the round's.
test_stop_hook_lets_dev_move_to_a_commit_land_landed() {
	editor_project
	with_remote
	start_round
	git checkout -q -b other dev
	echo landed > src/other.txt
	git add src/other.txt && git commit -q -m "another issue"
	printf 'land.sh 9: verify, on other at %s\nland.sh: the gate exited 0; its verdict:\nverify: PASS\n' "$(git rev-parse HEAD)" \
		> "$(git rev-parse --git-common-dir)/factory/land-9.log"
	git push -q origin HEAD:refs/heads/dev 2> /dev/null || fail "could not push"
	git update-ref refs/heads/dev HEAD
	git checkout -q work
	run_stop_hook
	assert_status 0
}

test_stop_hook_lets_the_subagent_stop_after_five_round_blocks_and_tells_the_driver() {
	editor_project
	start_round
	echo "exit 0" >> tools/verify/lint
	# shellcheck disable=SC2034 # n counts the five blocks
	for n in 1 2 3 4 5; do
		run_stop_hook
		assert_status 2
	done
	run_stop_hook
	assert_status 0
	stderr_has "the round still changes what the factory protects after 5 tries"
	grep -q "tools/verify/lint:1 round-changed" "$(git rev-parse --git-dir)/factory/round-changed" ||
		fail "no round-changed file for the Driver"
}

test_stop_hook_without_a_snapshot_says_so_and_takes_one() {
	editor_project
	red_lint
	run_stop_hook
	assert_status 2
	stderr_has "no snapshot of this round's start"
	[ -f "$(snapshot)" ] || fail "no snapshot taken for the next stop"
	rm "$(snapshot)" .fixture/fail-lint
	run_stop_hook
	assert_status 0
	stderr_has "no snapshot of this round's start"
}

# The small lane's Lock and phase are the gate's: the next stop doesn't count them
# as the round's.
test_stop_hook_snapshots_again_after_the_small_lane_moves_on() {
	editor_project
	small_red
	start_round
	run_stop_hook
	assert_status 2
	assert_eq green "$(git config branch.work.factory-phase)"
	run_stop_hook
	assert_status 2
	stderr_has "The gate is red (block 1 of 5)"
	grep -q round-changed "$TEST_TMP/stderr" && fail "the small lane's own move counted as the round's:"$'\n'"$(cat "$TEST_TMP/stderr")"
	return 0
}

# --- the generated hook -------------------------------------------------------------

test_generated_settings_wire_the_start_hook_to_editor_sonnet() {
	fixture_git_project
	run_cmd bash "$FACTORY_CORE/hooks.sh" generate
	assert_status 0
	tr -d ' \n' < .claude/settings.json | grep -qF '"SubagentStart":[{"matcher":"editor-sonnet","hooks":[{"type":"command","command":"bash\"$CLAUDE_PROJECT_DIR/factory/core/hooks/claude-subagent-start.sh\""' ||
		fail "no SubagentStart hook for editor-sonnet in:"$'\n'"$(cat .claude/settings.json)"
}

test_generated_settings_wire_the_stop_hook_to_editor_sonnet() {
	fixture_git_project
	run_cmd bash "$FACTORY_CORE/hooks.sh" generate
	assert_status 0
	tr -d ' \n' < .claude/settings.json | grep -qF '"SubagentStop":[{"matcher":"editor-sonnet","hooks":[{"type":"command","command":"bash\"$CLAUDE_PROJECT_DIR/factory/core/hooks/claude-subagent-stop.sh\""' ||
		fail "no SubagentStop hook for editor-sonnet in:"$'\n'"$(cat .claude/settings.json)"
}

test_generated_settings_wire_the_stop_hook_to_every_subagent_handback() {
	local i index=""
	fixture_git_project
	run_cmd bash "$FACTORY_CORE/hooks.sh" generate
	assert_status 0
	for i in 0 1 2 3 4 5; do
		if [ "$(factory_json_get "hooks.PreToolUse.$i.matcher" < .claude/settings.json)" = '^SubagentHandback$' ]; then
			index="$i"
			break
		fi
	done
	[ -n "$index" ] || fail "no PreToolUse hook on SubagentHandback in:"$'\n'"$(cat .claude/settings.json)"
	assert_eq 'bash "$CLAUDE_PROJECT_DIR/factory/core/hooks/claude-subagent-stop.sh"' \
		"$(factory_json_get "hooks.PreToolUse.$index.hooks.0.command" < .claude/settings.json)" "its command"
	assert_eq 1800 "$(factory_json_get "hooks.PreToolUse.$index.hooks.0.timeout" < .claude/settings.json)" "its limit"
}
