# The Sonnet Editor's deny (hooks/claude-deny.sh) on the git
# fixture project, fed the JSON Claude Code gives a PreToolUse hook. Inside a
# subagent the input carries agent_id and agent_type; in the main session (the
# Driver) it carries neither.

DENY_HOOK="$FACTORY_CORE/hooks/claude-deny.sh"
. "$FACTORY_CORE/lib/json.sh"

# claude_call <agent_type> <tool> <tool_input json>: run the deny on that call,
# its cwd the current folder; an empty agent_type is a call from the main session.
claude_call() {
	local agent=""
	[ -z "$1" ] || agent="\"agent_id\": \"a1\", \"agent_type\": \"$1\", "
	printf '{"session_id": "s1", "cwd": %s, "hook_event_name": "PreToolUse", %s"tool_name": "%s", "tool_input": %s}' \
		"$(factory_json_string "$PWD")" "$agent" "$2" "$3" > "$TEST_TMP/call.json"
	run_cmd bash "$DENY_HOOK" < "$TEST_TMP/call.json"
}

# sonnet_write <path> [agent_type]: a Write to the path from that agent (default
# editor-sonnet; "" for the Driver).
sonnet_write() {
	claude_call "${2-editor-sonnet}" Write "{\"file_path\": $(factory_json_string "$1"), \"content\": \"x\"}"
}

sonnet_bash() {
	claude_call editor-sonnet Bash "{\"command\": $(factory_json_string "$1")}"
}

# adopted_project: the git fixture with hook mode report, as adopt.sh leaves it.
adopted_project() {
	fixture_git_project
	echo report > tools/verify/hook-mode
	git add -A && git commit -q -m adopted || fail "commit failed"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
assert_refused() {
	assert_status 2
	assert_eq "" "$out" "stdout isn't empty"
	stderr_has "($1)"
}

assert_passed() {
	assert_status 0
	assert_eq "" "$out" "stdout isn't empty"
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "stderr isn't empty"
}

PROTECTED="factory/core/verify.sh factory
tools/verify/ratchet/baseline.txt baseline
tools/verify/ratchet/format_exclude.txt ratchet
tools/verify/pins pins
tools/verify/lint gate-script
tools/verify.sh gate-script
.claude/settings.json hook-config"

test_sonnet_is_refused_each_protected_path_class_while_adopted() {
	adopted_project
	local path class
	while read -r path class; do
		sonnet_write "$PWD/$path"
		assert_refused "$class"
	done <<< "$PROTECTED"
	brief "scope src/**"
	sonnet_write "$PWD/.git/factory/brief.md"
	assert_refused brief
	claude_call editor-sonnet Edit "{\"file_path\": \"$PWD/tools/verify/pins\", \"old_string\": \"a\", \"new_string\": \"b\"}"
	assert_refused pins
	claude_call editor-sonnet NotebookEdit "{\"notebook_path\": \"$PWD/factory/n.ipynb\", \"new_source\": \"x\"}"
	assert_refused factory
}

# A lib that doesn't load leaves the checks undefined, or ends the hook early
# (an unset variable under set -u): the hook refuses all.
test_sonnet_is_refused_every_call_when_a_lib_fails_to_load() {
	adopted_project
	unset FACTORY_TEST_UNSET
	local line
	for line in 'broken() { (' ': "$FACTORY_TEST_UNSET"'; do
		rm -rf "$TEST_TMP/broken" && mkdir -p "$TEST_TMP/broken" && cp -R "$FACTORY_CORE" "$TEST_TMP/broken/" || fail "could not copy the Core"
		LINE="$line" awk '/^factory_shell_targets\(\) \{/ { print ENVIRON["LINE"] } { print }' "$FACTORY_CORE/lib/protect.sh" > "$TEST_TMP/broken/core/lib/protect.sh"
		grep -qxF "$line" "$TEST_TMP/broken/core/lib/protect.sh" || fail "could not break protect.sh"
		DENY_HOOK="$TEST_TMP/broken/core/hooks/claude-deny.sh"
		sonnet_bash "touch factory/VERSION"
		assert_status 2
		stderr_has "could not load $TEST_TMP/broken/core/lib/protect.sh"
	done
}

test_the_driver_is_never_refused() {
	adopted_project
	local path class
	while read -r path class; do
		sonnet_write "$PWD/$path" ""
		assert_passed
	done <<< "$PROTECTED"
	claude_call "" Bash '{"command": "echo x > tools/verify/pins"}'
	assert_passed
}

test_the_asset_fetcher_is_refused_a_protected_path_but_not_an_asset() {
	adopted_project
	sonnet_write "$PWD/tools/verify/pins" asset-fetcher
	assert_refused pins
	sonnet_write "$PWD/docs/assets.md" asset-fetcher
	assert_passed
}

test_another_subagent_is_not_refused() {
	adopted_project
	sonnet_write "$PWD/tools/verify/pins" Explore
	assert_passed
}

test_sonnet_may_write_a_product_file_and_read_anything() {
	adopted_project
	brief "scope src/**"
	sonnet_write "$PWD/src/a.txt"
	assert_passed
	local tool
	for tool in Read NotebookRead LS; do
		claude_call editor-sonnet "$tool" "{\"file_path\": \"$PWD/factory/core/verify.sh\", \"notebook_path\": \"$PWD/factory/n.ipynb\", \"path\": \"$PWD/tools/verify\"}"
		assert_passed
	done
}

test_sonnet_is_refused_a_shell_command_writing_a_protected_path() {
	adopted_project
	sonnet_bash 'echo gdtoolkit 4.3.1 > tools/verify/pins'
	assert_refused pins
	sonnet_bash 'git config branch.work.factory-phase green'
	assert_refused run-state
	claude_call editor-sonnet PowerShell '{"command": "Set-Content -Path factory/core/verify.sh -Value x"}'
	assert_refused factory
	sonnet_bash 'bash factory/core/verify.sh > verify.log 2>&1'
	assert_passed
}

# verify.sh counts each gate run in the run state itself (the Core's write, which
# the deny never sees); an Editor's own count is refused like any run-state write.
test_sonnet_runs_the_gate_that_counts_but_cannot_count_itself() {
	adopted_project
	sonnet_bash 'bash tools/verify.sh'
	assert_passed
	sonnet_bash 'bash factory/core/state.sh incr caught-lint'
	assert_refused run-state
	sonnet_bash 'git config branch.issue/7.factory-seconds-lint 0'
	assert_refused run-state
}

# Relative paths in a command are taken from the call's cwd.
test_a_relative_shell_path_is_taken_from_the_call_cwd() {
	adopted_project
	cd src || fail "no src"
	sonnet_bash 'cp a.txt ../tools/verify/pins'
	assert_refused pins
}

# The subagent works in an issue's worktree, by absolute path, while Claude Code
# runs the hook from the main checkout: that worktree's paths count, its Lock
# among them.
test_sonnet_is_refused_in_its_worktree_while_the_hook_runs_in_the_main_checkout() {
	adopted_project
	local main="$PWD" wt="$PWD/.claude/worktrees/issue-1"
	git worktree add -q -b issue/1 "$wt" || fail "no worktree"
	(
		cd "$wt" || exit 1
		echo stub > src/a.txt
		echo test_new >> tests/a_test.txt
		# The Lock as lock.sh records it; this tests the deny hook, not the gate.
		git add -A && git commit -q -m red && git config branch.issue/1.factory-red-commit "$(git rev-parse HEAD)"
	) || fail "could not lock the worktree's red commit"
	cd "$main" || fail "no main checkout"
	sonnet_write "$wt/tests/a_test.txt"
	assert_refused locked-test
	sonnet_write "$wt/tools/verify/pins"
	assert_refused pins
	sonnet_write "$(git -C "$wt" rev-parse --absolute-git-dir)/factory/brief.md"
	assert_refused brief
	sonnet_write "$wt/src/a.txt"
	assert_passed
	sonnet_write "$main/tests/a_test.txt"
	assert_passed
}

# The Core's writing subcommands (and land.sh, whose every run writes), each with
# the class of what it rewrites, and the ways to run one: @ stands for
# `<script> <subcommand> <arguments>`.
CORE_WRITES="baseline.sh shrink|baseline
baseline.sh record|baseline
baseline.sh add R15|baseline
brief.sh seal|run-state
hooks.sh generate|hook-config
land.sh 5|run-state
lock.sh record|run-state
lock.sh lift|run-state
state.sh set phase green|run-state
state.sh unset red-commit|run-state
state.sh incr rounds-red|run-state"

# core_runs: each way to run @: alone, by relative and absolute path, after a cd,
# through bash and sh, and inside bash -c and sh -c.
core_runs() {
	printf '%s\n' "bash factory/core/@" "sh factory/core/@" "factory/core/@" "./factory/core/@" \
		"'$PWD/factory/core/'@" "bash '$PWD/factory/core/'@" "cd factory/core && ./@" \
		"cd factory/core; bash @" "cd '$PWD' && sh factory/core/@" \
		"bash -c 'bash factory/core/@'" "sh -c 'factory/core/@'"
}

# #159's Editor ran baseline.sh shrink, which rewrote the Baseline: the Sonnet
# Editor and the asset-fetcher are refused the Core's writing subcommands, the
# Driver (the main session and its driver subagents) never.
test_sonnet_is_refused_the_core_scripts_writing_subcommands_and_the_driver_is_not() {
	adopted_project
	local write class run command sub
	while IFS='|' read -r write class; do
		sub="${write#* }"
		sub="factory/core/${write%% *} ${sub%% *}"
		[ "${write%% *}" != land.sh ] || sub=factory/core/land.sh
		while IFS= read -r run; do
			command="$(factory_json_string "${run//@/$write}")"
			sonnet_bash "${run//@/$write}"
			assert_refused "$class"
			stderr_has "$sub ($class): it rewrites"
			claude_call "" Bash "{\"command\": $command}"
			assert_passed
			claude_call driver Bash "{\"command\": $command}"
			assert_passed
		done < <(core_runs)
		claude_call asset-fetcher Bash "{\"command\": $(factory_json_string "bash factory/core/$write")}"
		assert_refused "$class"
	done <<< "$CORE_WRITES"
}

test_sonnet_may_run_the_core_scripts_read_only_subcommands() {
	adopted_project
	local command
	for command in 'bash factory/core/state.sh get phase' 'bash factory/core/lock.sh check' \
		'bash factory/core/baseline.sh gate' 'bash factory/core/state.sh --issue 5 get phase' \
		'bash factory/core/brief.sh check' 'bash factory/core/hooks.sh check'; do
		sonnet_bash "$command"
		assert_passed
	done
}

test_generated_settings_run_the_deny_before_the_editor_tools() {
	fixture_git_project
	run_cmd bash "$FACTORY_CORE/hooks.sh" generate
	assert_status 0
	. "$FACTORY_CORE/lib/json.sh"
	assert_eq "bash \"\$CLAUDE_PROJECT_DIR/factory/core/hooks/claude-deny.sh\"" \
		"$(factory_json_get hooks.PreToolUse.0.hooks.0.command < .claude/settings.json)" "the PreToolUse command"
	local matcher tool
	matcher="$(factory_json_get hooks.PreToolUse.0.matcher < .claude/settings.json)" || fail "no matcher"
	# The writing tools, and the reading ones for the Scenario folder.
	for tool in Write Edit MultiEdit NotebookEdit Bash PowerShell Read Grep Glob NotebookRead LS; do
		[[ $tool =~ $matcher ]] || fail "the matcher '$matcher' misses $tool"
	done
	for tool in Agent WebFetch TodoWrite ReadMcpResource; do
		[[ $tool =~ $matcher ]] && fail "the matcher '$matcher' takes in $tool"
	done
	return 0
}

# --- the Scenario folder: the one read deny ---

# scenario_project: the adopted fixture naming scenarios/ its Scenario folder,
# with a Scenario committed, and an issue's worktree at $wt that leaves it out,
# as start.sh makes one. The hook runs from the main checkout, as Claude Code
# runs it.
scenario_project() {
	adopted_project
	printf 'scenarios/\n' > tools/verify/scenario-folder
	mkdir -p scenarios && echo 'serve once' > scenarios/serve.gd
	git add -A && git commit -q -m scenarios || fail "commit failed"
	wt="$PWD/.claude/worktrees/issue-1"
	git worktree add -q --no-checkout -b issue/1 "$wt" || fail "no worktree"
	git -C "$wt" sparse-checkout set --no-cone '/*' '!/scenarios/' || fail "no sparse checkout"
	git -C "$wt" checkout -q || fail "no checkout"
}

# sonnet_read <tool> <tool_input json> [agent_type]
sonnet_read() {
	claude_call "${3-editor-sonnet}" "$1" "$2"
}

test_sonnet_is_refused_every_read_and_write_of_the_scenario_folder() {
	scenario_project
	local tool input
	while IFS='|' read -r tool input; do
		sonnet_read "$tool" "$input"
		assert_refused scenarios
		sonnet_read "$tool" "$input" asset-fetcher
		assert_refused scenarios
	done <<- CALLS
		Read|{"file_path": "$PWD/scenarios/serve.gd"}
		Read|{"file_path": "$wt/scenarios/serve.gd"}
		NotebookRead|{"notebook_path": "$PWD/scenarios/n.ipynb"}
		LS|{"path": "$PWD/scenarios"}
		Grep|{"pattern": "serve", "path": "$PWD"}
		Grep|{"pattern": "serve"}
		Grep|{"pattern": "serve", "glob": "*.gd", "path": "$PWD/scenarios"}
		Glob|{"pattern": "scenarios/**/*.gd"}
		Glob|{"pattern": "**/*.gd", "path": "$PWD"}
		Write|{"file_path": "$PWD/scenarios/new.gd", "content": "x"}
		Edit|{"file_path": "$wt/scenarios/serve.gd", "old_string": "a", "new_string": "b"}
		Bash|{"command": "cat scenarios/serve.gd"}
		Bash|{"command": "grep -rn serve ."}
		Bash|{"command": "rg serve"}
		Bash|{"command": "git -C $wt show HEAD:scenarios/serve.gd"}
		Bash|{"command": "git -C $wt log -p -- scenarios"}
		Bash|{"command": "git -C $wt sparse-checkout disable"}
		Bash|{"command": "cd $wt && git grep serve HEAD -- scenarios"}
		PowerShell|{"command": "Get-Content scenarios/serve.gd"}
	CALLS
}

# The Scenarios' screenshot baselines (Next.js: <folder>/looks/) are in the
# Scenario folder, so the Editor can't record or rewrite one: only the Driver's
# record after an approved Playtest does.
test_sonnet_is_refused_every_write_of_a_screenshot_baseline() {
	scenario_project
	local tool input
	while IFS='|' read -r tool input; do
		sonnet_read "$tool" "$input"
		assert_refused scenarios
	done <<- CALLS
		Write|{"file_path": "$PWD/scenarios/looks/home-390-light.png", "content": "x"}
		Write|{"file_path": "$wt/scenarios/looks/home-390-light.png", "content": "x"}
		Bash|{"command": "cp shot.png scenarios/looks/home-390-light.png"}
		Bash|{"command": "rm -rf $wt/scenarios/looks"}
		Bash|{"command": "git -C $wt add --sparse scenarios/looks/home-390-light.png"}
	CALLS
}

test_sonnet_may_read_and_search_its_worktree_beside_the_scenario_folder() {
	scenario_project
	local tool input
	while IFS='|' read -r tool input; do
		sonnet_read "$tool" "$input"
		assert_passed
	done <<- CALLS
		Read|{"file_path": "$wt/src/a.txt"}
		Grep|{"pattern": "serve", "path": "$wt"}
		Glob|{"pattern": "**/*.txt", "path": "$wt"}
		Glob|{"pattern": "src/**"}
		Bash|{"command": "cd $wt && grep -rn one . && git grep one && git status"}
		Bash|{"command": "git -C $wt sparse-checkout list"}
	CALLS
}

test_the_driver_and_other_subagents_read_the_scenario_folder() {
	scenario_project
	local agent
	for agent in "" Explore general-purpose driver; do
		sonnet_read Read "{\"file_path\": \"$PWD/scenarios/serve.gd\"}" "$agent"
		assert_passed
		sonnet_read Grep '{"pattern": "serve"}' "$agent"
		assert_passed
		sonnet_read Bash '{"command": "cat scenarios/serve.gd"}' "$agent"
		assert_passed
	done
}

test_sonnet_reads_anything_in_a_project_without_a_scenario_folder() {
	scenario_project
	rm tools/verify/scenario-folder
	sonnet_read Read "{\"file_path\": \"$PWD/scenarios/serve.gd\"}"
	assert_passed
	sonnet_read Bash '{"command": "grep -rn serve ."}'
	assert_passed
}

# --- git commands that move dev, main or the remote, or skip the hooks (#13) -------

test_sonnet_is_refused_a_push_a_ref_update_a_forced_branch_on_dev_or_main_and_no_verify() {
	adopted_project
	local cmd
	for cmd in "git push" "git push origin HEAD:dev" "git -C src push --force" "cd src && git send-pack ../x dev" \
		"git update-ref refs/heads/dev HEAD" "git update-ref -d refs/heads/feature" \
		"git branch -f dev HEAD" "git branch -D main" "git branch -M feature dev" "git branch --delete --force refs/heads/dev" \
		"git --git-dir .git push" "git --work-tree . push origin HEAD:dev"; do
		sonnet_bash "$cmd"
		assert_refused branches
		stderr_has "dev, main and the remote move only through the gate, the Verifier and Land"
	done
	for cmd in "git commit --no-verify -m wip" "git commit -n -m wip" "git commit -anm wip" "git -c user.name=x commit -m wip --no-verify" \
		"git commit --no-veri -m wip" "git -c core.hooksPath=/dev/null commit -m wip" "git -c core.hookspath commit -m wip" \
		"git --config-env core.hooksPath=X commit -m wip" "git --config-env=core.hooksPath=X commit -m wip"; do
		sonnet_bash "$cmd"
		assert_refused hooks
		stderr_has "the pre-commit hook runs on every commit"
	done
}

test_sonnet_may_commit_and_branch_off_dev_and_main() {
	adopted_project
	local cmd
	for cmd in "git commit -m wip" "git commit -am fix" 'git commit -m "-n"' 'git commit -m "no verify"' \
		"git commit -uno -m wip" "git commit -Skey-n -m wip" "git -c core.editor=nano commit" "git --git-dir .git log dev" \
		"git branch -f feature main" "git branch -d feature" "git branch feature dev" "git branch" \
		"git log main" "git status" "git rev-parse dev"; do
		sonnet_bash "$cmd"
		assert_passed
	done
}

test_the_driver_may_push_and_move_dev() {
	adopted_project
	local cmd
	for cmd in "git push origin HEAD:dev" "git update-ref refs/heads/dev HEAD" "git branch -f dev HEAD" "git commit --no-verify -m x"; do
		claude_call "" Bash "{\"command\": $(factory_json_string "$cmd")}"
		assert_passed
	done
}
