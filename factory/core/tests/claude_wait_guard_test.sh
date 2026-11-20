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

# advised <why> <command>: a Bash call of the command gets the foreground advice,
# and only that: exit 0, PreToolUse JSON with no permissionDecision.
advised() {
	guard_bash "$2"
	[ "$status" -eq 0 ] || fail "refused ($1), exit $status: $2"$'\n'"$(cat "$TEST_TMP/stderr")"
	[ ! -s "$TEST_TMP/stderr" ] || fail "stderr ($1): $(cat "$TEST_TMP/stderr")"
	assert_eq PreToolUse "$(printf '%s' "$out" | factory_json_get hookSpecificOutput.hookEventName)" "hookEventName ($1)"
	printf '%s' "$out" | grep -qF permissionDecision && fail "a permission decision ($1): $out"
	printf '%s' "$out" | factory_json_get hookSpecificOutput.additionalContext > "$TEST_TMP/context" || fail "no additionalContext ($1): $out"
	grep -qF 'Advice (wait-guard)' "$TEST_TMP/context" || fail "no advice ($1): $out"
	grep -qF 'run_in_background' "$TEST_TMP/context" || fail "no run_in_background ($1): $out"
	grep -qF 'tail --pid="$(cat <scratch>/run.pid)" -f /dev/null' "$TEST_TMP/context" || fail "no tail --pid ($1): $out"
	echo "$1" >> "$TEST_TMP/seen"
}

# guard_background <command> [true|false]: a Bash call of that command with
# run_in_background set.
guard_background() {
	guard_call Bash "{\"command\": $(factory_json_string "$1"), \"description\": \"a call\", \"run_in_background\": ${2:-true}}"
}

test_advises_each_foreground_verify_lock_record_or_land() {
	each_fixture "$GUARD_FIXTURES/advised" advised
	[ "$(wc -l < "$TEST_TMP/seen")" -ge 10 ] || fail "too few fixtures read: $(cat "$TEST_TMP/seen")"
}

# The advice names what runs long: each script once.
test_the_advice_names_the_scripts_the_call_runs() {
	guard_bash 'bash factory/core/lock.sh record && bash factory/core/land.sh 42; bash factory/core/land.sh 43'
	assert_status 0
	printf '%s' "$out" | factory_json_get hookSpecificOutput.additionalContext > "$TEST_TMP/context"
	grep -qF 'this call runs lock.sh record and land.sh in the foreground' "$TEST_TMP/context" || fail "names: $(cat "$TEST_TMP/context")"
}

# A call with run_in_background set gets nothing; one with it false is advised.
test_a_call_in_the_background_gets_no_advice() {
	local command
	for command in 'bash tools/verify.sh' 'bash factory/core/lock.sh record' 'bash factory/core/land.sh 42' \
		'echo $$ > run.pid; exec bash tools/verify.sh > run.log 2>&1'; do
		guard_background "$command"
		assert_status 0
		[ -z "$out" ] && [ ! -s "$TEST_TMP/stderr" ] || fail "output in the background ($command): $out $(cat "$TEST_TMP/stderr")"
	done
	guard_background 'bash tools/verify.sh' false
	assert_status 0
	printf '%s' "$out" | grep -qF 'Advice (wait-guard)' || fail "no advice with run_in_background false: $out"
}

# A refusal wins over the advice: a call that waits on its own pgrep is refused.
test_a_refusal_comes_before_the_advice() {
	guard_bash 'bash tools/verify.sh; until ! pgrep -f "verify.sh ok"; do echo x; done'
	assert_status 2
	[ -z "$out" ] || fail "stdout on a refusal: $out"
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
	stderr_has "\`pkill -f '[s]ome script'\`"
}

# The bracketed form is built from the caller's own pattern, when it no longer
# matches; otherwise the refusal gives the general rule.
test_the_refusal_brackets_the_callers_own_pattern() {
	guard_bash "until ! pgrep -f 'tools/verify.sh'; do echo waiting; done"
	assert_status 2
	stderr_has "\`pgrep -f '[t]ools/verify.sh'\`"
	guard_bash "pgrep -f '[0-9]* run me'"
	assert_status 2
	stderr_has "\`pgrep -f '[0-9]* [r]un me'\`"
	guard_bash 'bash tools/verify.sh & pgrep -f tools/verify.sh'
	assert_status 2
	stderr_has "(only when the command doesn't also name it plainly)"
	grep -qF "[t]ools/verify.sh" "$TEST_TMP/stderr" && fail "a bracketed form that still matches: $(cat "$TEST_TMP/stderr")"
	guard_bash 'pgrep -f "(foo|bar)"'
	assert_status 2
	stderr_has "(only when the command doesn't also name it plainly)"
	return 0
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
