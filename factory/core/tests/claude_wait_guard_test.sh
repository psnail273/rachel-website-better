# The wait guard (hooks/claude-wait-guard.sh), fed the JSON Claude Code gives a
# PreToolUse hook, and its place in the generated hook config. The commands it
# refuses and those it lets by are in fixture/wait-guard/: refused and passed,
# each a `== <why>` line and the command's lines after it.

GUARD="$FACTORY_CORE/hooks/claude-wait-guard.sh"
GUARD_FIXTURES="$FACTORY_CORE/tests/fixture/wait-guard"
. "$FACTORY_CORE/lib/json.sh"

# guard_call <tool> <tool_input json> [agent_type]: run the guard on that call;
# an empty or missing agent_type is a call from the main session.
guard_call() {
	local agent=""
	[ -z "${3:-}" ] || agent="\"agent_id\": \"a1\", \"agent_type\": \"$3\", "
	printf '{"session_id": "s1", "cwd": %s, "hook_event_name": "PreToolUse", %s"tool_name": "%s", "tool_input": %s, "tool_use_id": "t1"}' \
		"$(factory_json_string "$PWD")" "$agent" "$1" "$2" > "$TEST_TMP/call.json"
	run_cmd bash "$GUARD" < "$TEST_TMP/call.json"
}

# guard_bash <command> [agent_type]: a Bash call of that command.
guard_bash() {
	guard_call Bash "{\"command\": $(factory_json_string "$1"), \"description\": \"a call\"}" "${2:-}"
}

# each_fixture <file> <function>: call <function> <why> <command> for each of
# the file's commands.
each_fixture() {
	local why="" command="" line started=""
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "${line#== }" != "$line" ]; then
			[ -z "$started" ] || "$2" "$why" "$command"
			why="${line#== }" command="" started=1
		else
			command="${command:+$command$'\n'}$line"
		fi
	done < "$1"
	[ -z "$started" ] || "$2" "$why" "$command"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
refused() {
	guard_bash "$2"
	[ "$status" -eq 2 ] || fail "not refused ($1), exit $status: $2"
	[ -z "$out" ] || fail "stdout isn't empty ($1): $out"
	grep -qF 'Refused (wait-guard)' "$TEST_TMP/stderr" || fail "no refusal on stderr ($1): $(cat "$TEST_TMP/stderr")"
	echo "$1" >> "$TEST_TMP/seen"
}

passed() {
	guard_bash "$2"
	[ "$status" -eq 0 ] || fail "refused ($1), exit $status: $2"$'\n'"$(cat "$TEST_TMP/stderr")"
	[ -z "$out" ] && [ ! -s "$TEST_TMP/stderr" ] || fail "output ($1): $out $(cat "$TEST_TMP/stderr")"
	echo "$1" >> "$TEST_TMP/seen"
}

test_refuses_each_call_whose_pattern_matches_its_own_command() {
	each_fixture "$GUARD_FIXTURES/refused" refused
	[ "$(wc -l < "$TEST_TMP/seen")" -ge 20 ] || fail "too few fixtures read: $(cat "$TEST_TMP/seen")"
}

test_lets_each_other_call_by() {
	each_fixture "$GUARD_FIXTURES/passed" passed
	[ "$(wc -l < "$TEST_TMP/seen")" -ge 20 ] || fail "too few fixtures read: $(cat "$TEST_TMP/seen")"
}

# The refusal names the rule and each fix: a PID, run_in_background, a bracket.
test_the_refusal_names_the_pattern_and_the_fixes() {
	guard_bash 'until ! pgrep -f "factory/core/test.sh nextjs/adopt"; do echo waiting; done'
	assert_status 2
	stderr_has "\`pgrep -f\` with the pattern 'factory/core/test.sh nextjs/adopt' matches this command's own text"
	stderr_has "pgrep matches that shell too, and a wait on it never ends"
	stderr_has 'while kill -0 "$pid"'
	stderr_has "run_in_background"
	stderr_has "[f]actory/core/test.sh"
	guard_bash 'pkill -f "some script"'
	assert_status 2
	stderr_has "pkill would kill that shell"
}

# -u, -U and -G let a call by only when they name none of the agent's own user
# and group, which the guard shares: by name or ID, alone or in a list.
test_refuses_a_user_or_group_that_takes_in_the_agents_own() {
	local command
	for command in "pgrep -u $(id -un) -f foo" "pgrep -U$(id -u) -f foo" \
		"pgrep --euid=factory-other,$(id -un) -f foo" "pgrep --uid $(id -u) -f foo" \
		"pgrep -G $(id -gn) -f foo" "pkill --group=$(id -g) -f foo"; do
		refused "own user or group" "$command"
	done
	passed "another group" "pgrep -G factory-no-such-group,factory-other -f foo"
}

# Every agent: the main session, and any subagent, the Verifier and the amend
# builder among them.
test_refuses_the_main_session_and_every_subagent() {
	local agent
	for agent in "" verifier amend-builder editor-sonnet driver; do
		guard_bash 'until ! pgrep -f stress.sh; do echo waiting; done' "$agent"
		[ "$status" -eq 2 ] || fail "not refused for agent '$agent', exit $status"
	done
}

# Only a Bash call's command counts: another tool's input that holds the same
# text, PowerShell's included, and input that is no Bash call pass.
test_lets_other_tools_and_other_input_by() {
	guard_call Write "{\"file_path\": \"$PWD/wait.sh\", \"content\": \"until ! pgrep -f wait.sh; do echo x; done\"}"
	assert_status 0
	guard_call PowerShell '{"command": "pgrep -f foo"}'
	assert_status 0
	guard_call Bash '{"description": "pgrep -f foo"}'
	assert_status 0
	run_cmd bash "$GUARD" <<< 'not json, pgrep -f foo'
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "stderr on input that is no call"
}

# The command is read from the JSON as Claude Code escapes it: quotes,
# backslashes, newlines and \u escapes.
test_reads_the_command_through_json_escapes() {
	guard_call Bash '{"command": "echo \"a\\\\b\"\npgrep -f \u0022some thing\u0022"}'
	assert_status 2
	stderr_has "the pattern 'some thing'"
}

test_generated_settings_run_the_wait_guard_on_every_bash_call() {
	fixture_git_project
	run_cmd bash "$FACTORY_CORE/hooks.sh" generate
	assert_status 0
	local matcher tool index="" i
	for i in 0 1 2 3; do
		if [ "$(factory_json_get "hooks.PreToolUse.$i.hooks.0.command" < .claude/settings.json)" = "bash \"\$CLAUDE_PROJECT_DIR/factory/core/hooks/claude-wait-guard.sh\"" ]; then
			index="$i"
		fi
	done
	[ -n "$index" ] || fail "no PreToolUse hook runs the wait guard: $(cat .claude/settings.json)"
	matcher="$(factory_json_get "hooks.PreToolUse.$index.matcher" < .claude/settings.json)" || fail "no matcher"
	[[ Bash =~ $matcher ]] || fail "the matcher '$matcher' misses Bash"
	for tool in Write Edit Read PowerShell Agent BashOutput; do
		[[ $tool =~ $matcher ]] && fail "the matcher '$matcher' takes in $tool"
	done
	return 0
}

# The factory repo's workspace runs the same guard, as claude-hooks.json has it,
# and nothing else.
test_the_workspace_hooks_hold_the_guard_alone_as_projects_have_it() {
	local key ws project
	ws="$FACTORY_CORE/hooks/claude-workspace-hooks.json"
	project="$FACTORY_CORE/hooks/claude-hooks.json"
	for key in matcher hooks.0.type hooks.0.command hooks.0.timeout; do
		assert_eq "$(factory_json_get "PreToolUse.1.$key" < "$project")" "$(factory_json_get "PreToolUse.0.$key" < "$ws")" "the workspace's $key"
	done
	assert_eq "PreToolUse.0.hooks.0.command" "$(_factory_json_scan flatten < "$ws" | cut -f 1 | grep 'command$')" "the workspace's hooks"
}
