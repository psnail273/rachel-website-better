# The hook config generator and drift check (hooks.sh), and the pre-commit hook
# (hooks/pre-commit.sh), on the git fixture project.

GITHOOKS="$FACTORY_CORE/hooks/githooks"

SETTINGS='{
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-opus-5-5"
  },
  "permissions": {
    "deny": [
      "Read(**/.env*)"
    ]
  }
}'

# $SETTINGS with the keys the generator adds: the hooks (@HOOKS@: see
# assert_settings), the main session's model and effort, and the Lock lift's
# allow rule.
SETTINGS_GENERATED='{
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-opus-5-5"
  },
  "permissions": {
    "deny": [
      "Read(**/.env*)"
    ],
    "allow": [
      "Bash(bash factory/core/lock.sh lift:*)"
    ]
  },
  "hooks": @HOOKS@,
  "model": "claude-opus-5-5",
  "effortLevel": "medium",
  "maxEffortLevel": "xhigh"
}'

# The Cursor Editor's generated files, much as the last release that had them
# wrote them.
CURSOR_HOOKS='{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "bash factory/core/hooks/cursor-stop.sh",
        "loop_limit": 5
      }
    ]
  }
}'
CURSOR_CLI='{
  "permissions": {
    "allow": [
      "Shell(bash tools/verify.sh)",
      "Shell(cat)"
    ],
    "deny": []
  }
}'

# retired_cursor_files: the Cursor Editor's .cursor/hooks.json and .cursor/cli.json,
# as a project that synced from a release with them has them.
retired_cursor_files() {
	mkdir -p .cursor
	printf '%s\n' "$CURSOR_HOOKS" > .cursor/hooks.json
	printf '%s\n' "$CURSOR_CLI" > .cursor/cli.json
}

generate() {
	run_cmd bash "$FACTORY_CORE/hooks.sh" generate
	assert_status 0
}

check_hooks() {
	run_cmd bash "$FACTORY_CORE/hooks.sh" check
}

# adopted_project <mode>: the git fixture with generated hook config, the hook mode
# committed and core.hooksPath at the Core's githooks.
adopted_project() {
	fixture_git_project
	mkdir -p .claude
	printf '%s\n' "$SETTINGS" > .claude/settings.json
	generate
	echo "$1" > tools/verify/hook-mode
	git config core.hooksPath "$GITHOOKS"
	git add -A && git commit -q -m "adopt" || fail "could not commit the adoption"
}

# locked_project <mode>: adopted_project, then a red commit that adds a test line,
# locked.
locked_project() {
	adopted_project "$1"
	echo test_new >> tests/a_test.txt
	git add -A && git commit -q -m "red" || fail "could not commit the red phase"
	run_cmd bash "$FACTORY_CORE/lock.sh" record
	assert_status 0
}

# commit_staged: commit what is staged; $status is the commit's exit code and
# $TEST_TMP/stderr holds the hook's report.
commit_staged() {
	run_cmd git commit -q -m "next"
}

# assert_settings <expected> [message]: .claude/settings.json is <expected>, with
# @HOOKS@ standing for the hooks block, the source claude-hooks.json indented to
# sit at the top level, so these tests don't change when a hook is added.
assert_settings() {
	local block
	block="$(sed '2,$s/^/  /' "$FACTORY_CORE/hooks/claude-hooks.json")"
	assert_eq "${1//@HOOKS@/"$block"}" "$(cat .claude/settings.json)" "${2:-values differ}"
}

# --- generate and check -------------------------------------------------------

test_generate_writes_the_settings_hooks_model_and_effort_keys() {
	fixture_git_project
	mkdir -p .claude
	printf '%s\n' "$SETTINGS" > .claude/settings.json
	generate
	assert_settings "$SETTINGS_GENERATED" "the unrelated keys changed"
	[ ! -e .cursor ] || fail "generate wrote a .cursor folder"
}

# The main session runs Opus 5.5 at medium effort (#16, #17): a model or an effort
# already in the file is replaced where it stands, and the human's other keys stay
# as they were, byte for byte.
test_generate_replaces_the_model_and_effort_in_place_and_keeps_the_rest() {
	fixture_git_project
	mkdir -p .claude
	printf '{\n  "model": "claude-fable-5-2",\n  "env": {"A": "1"},\n  "effortLevel": "max",\n  "maxEffortLevel": "max",\n  "permissions": {"allow": ["Bash(ls)"]}\n}\n' > .claude/settings.json
	generate
	assert_settings '{
  "model": "claude-opus-5-5",
  "env": {"A": "1"},
  "effortLevel": "medium",
  "maxEffortLevel": "xhigh",
  "permissions": {"allow": ["Bash(ls)", "Bash(bash factory/core/lock.sh lift:*)"]},
  "hooks": @HOOKS@
}'
	cp .claude/settings.json "$TEST_TMP/claude1"
	generate
	cmp -s "$TEST_TMP/claude1" .claude/settings.json || fail ".claude/settings.json changed on the second run"
}

# A project that synced past the Cursor Editor loses its generated files: generate
# removes them, and their folder once it is empty.
test_generate_removes_the_retired_cursor_files() {
	fixture_git_project
	retired_cursor_files
	generate
	[ ! -e .cursor ] || fail "the retired Cursor files are still there: $(ls -A .cursor)"
}

# A .cursor/ file the human wrote is theirs: generate keeps it, and the folder.
test_generate_keeps_a_cursor_file_that_is_not_the_factorys() {
	fixture_git_project
	retired_cursor_files
	echo '{"hooks": {"stop": [{"command": "my-hook.sh"}]}}' > .cursor/hooks.json
	echo '{"rules": []}' > .cursor/other.json
	generate
	[ -f .cursor/hooks.json ] || fail "the human's .cursor/hooks.json was removed"
	[ -f .cursor/other.json ] || fail "the human's .cursor/other.json was removed"
	[ ! -e .cursor/cli.json ] || fail "the retired .cursor/cli.json is still there"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_a_retired_cursor_file_fails_the_check() {
	adopted_project report
	retired_cursor_files
	check_hooks
	assert_status 1
	assert_eq ".cursor/cli.json:1 hook-drift the retired Cursor Editor's; run bash factory/core/hooks.sh generate
.cursor/hooks.json:1 hook-drift the retired Cursor Editor's; run bash factory/core/hooks.sh generate" "$out"
	generate
	check_hooks
	assert_status 0
}

# A model of the human's own goes in the untracked settings.local.json: one in
# settings.json is drift, as is another effort.
test_a_hand_edit_to_the_model_fails_the_check() {
	adopted_project report
	sed -i 's/"model": "claude-opus-5-5"/"model": "claude-fable-5-2"/' .claude/settings.json
	check_hooks
	assert_status 1
	assert_eq '.claude/settings.json:1 hook-drift its "hooks", "model", "effortLevel" or "maxEffortLevel" key differs from what the factory writes (factory/core/hooks/claude-hooks.json, lib/hooks.sh); set your own model in .claude/settings.local.json, then run bash factory/core/hooks.sh generate' "$out"
}

test_a_hand_edit_to_the_effort_fails_the_check() {
	adopted_project report
	sed -i 's/"effortLevel": "medium"/"effortLevel": "high"/' .claude/settings.json
	check_hooks
	assert_status 1
	assert_eq '.claude/settings.json:1 hook-drift its "hooks", "model", "effortLevel" or "maxEffortLevel" key differs from what the factory writes (factory/core/hooks/claude-hooks.json, lib/hooks.sh); set your own model in .claude/settings.local.json, then run bash factory/core/hooks.sh generate' "$out"
}

# The cap is xhigh: a settings file that lifts it to max is drift.
test_a_hand_edit_to_the_effort_cap_fails_the_check() {
	adopted_project report
	sed -i 's/"maxEffortLevel": "xhigh"/"maxEffortLevel": "max"/' .claude/settings.json
	grep -qF '"maxEffortLevel": "max"' .claude/settings.json || fail "the cap wasn't in the generated settings: $(cat .claude/settings.json)"
	check_hooks
	assert_status 1
	assert_eq '.claude/settings.json:1 hook-drift its "hooks", "model", "effortLevel" or "maxEffortLevel" key differs from what the factory writes (factory/core/hooks/claude-hooks.json, lib/hooks.sh); set your own model in .claude/settings.local.json, then run bash factory/core/hooks.sh generate' "$out"
}

test_generating_twice_gives_identical_files() {
	fixture_git_project
	mkdir -p .claude
	printf '%s\n' "$SETTINGS" > .claude/settings.json
	generate
	cp .claude/settings.json "$TEST_TMP/claude1"
	generate
	cmp -s "$TEST_TMP/claude1" .claude/settings.json || fail ".claude/settings.json changed on the second run"
}

test_generate_replaces_an_existing_hooks_key_in_place() {
	fixture_git_project
	mkdir -p .claude
	printf '{\n  "hooks": {\n    "Stop": []\n  },\n  "env": {}\n}\n' > .claude/settings.json
	generate
	assert_settings '{
  "permissions": {
    "allow": [
      "Bash(bash factory/core/lock.sh lift:*)"
    ]
  },
  "hooks": @HOOKS@,
  "env": {},
  "model": "claude-opus-5-5",
  "effortLevel": "medium",
  "maxEffortLevel": "xhigh"
}'
}

test_generate_creates_a_missing_settings_file() {
	fixture_git_project
	generate
	assert_settings '{
  "permissions": {
    "allow": [
      "Bash(bash factory/core/lock.sh lift:*)"
    ]
  },
  "hooks": @HOOKS@,
  "model": "claude-opus-5-5",
  "effortLevel": "medium",
  "maxEffortLevel": "xhigh"
}'
}

test_generate_fills_an_empty_object() {
	fixture_git_project
	mkdir -p .claude
	echo '{}' > .claude/settings.json
	generate
	assert_settings '{
  "permissions": {
    "allow": [
      "Bash(bash factory/core/lock.sh lift:*)"
    ]
  },
  "hooks": @HOOKS@,
  "model": "claude-opus-5-5",
  "effortLevel": "medium",
  "maxEffortLevel": "xhigh"
}'
}

test_generate_refuses_a_settings_file_that_is_not_an_object() {
	fixture_git_project
	mkdir -p .claude
	echo '["hooks"]' > .claude/settings.json
	run_cmd bash "$FACTORY_CORE/hooks.sh" generate
	assert_status 1
	assert_eq '["hooks"]' "$(cat .claude/settings.json)" "the settings file was rewritten"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_check_passes_on_an_adopted_project() {
	adopted_project report
	check_hooks
	assert_status 0
	assert_eq "" "$out"
}

test_check_passes_on_a_project_without_a_hook_mode() {
	fixture_git_project
	check_hooks
	assert_status 0
	assert_eq "" "$out"
}

test_a_hand_edit_to_the_settings_hooks_fails_the_check() {
	adopted_project report
	sed -i 's/"hooks": {/"hooks": {"Stop": [], /' .claude/settings.json
	check_hooks
	assert_status 1
	assert_eq '.claude/settings.json:1 hook-drift its "hooks", "model", "effortLevel" or "maxEffortLevel" key differs from what the factory writes (factory/core/hooks/claude-hooks.json, lib/hooks.sh); set your own model in .claude/settings.local.json, then run bash factory/core/hooks.sh generate' "$out"
}

test_an_edit_to_another_settings_key_is_not_drift() {
	adopted_project report
	sed -i 's/"CLAUDE_CODE_SUBAGENT_MODEL": "claude-opus-5-5"/"CLAUDE_CODE_SUBAGENT_MODEL": "claude-sonnet-5-5"/' .claude/settings.json
	check_hooks
	assert_status 0
	assert_eq "" "$out"
}

test_an_unset_hooks_path_fails_the_check() {
	adopted_project report
	git config --unset core.hooksPath
	check_hooks
	assert_status 1
	assert_eq "tools/verify/hook-mode:1 hooks-path core.hooksPath is unset, so no git hook runs; run git config core.hooksPath factory/core/hooks/githooks" "$out"
}

test_a_hooks_path_elsewhere_fails_the_check() {
	adopted_project report
	mkdir -p other-hooks
	git config core.hooksPath other-hooks
	check_hooks
	assert_status 1
	assert_eq "tools/verify/hook-mode:1 hooks-path core.hooksPath is other-hooks, not the Core's githooks; run git config core.hooksPath factory/core/hooks/githooks" "$out"
}

test_a_hooks_path_that_does_not_resolve_fails_the_check() {
	adopted_project report
	git config core.hooksPath no-such-hooks
	check_hooks
	assert_status 1
	assert_eq "tools/verify/hook-mode:1 hooks-path core.hooksPath is no-such-hooks, not the Core's githooks; run git config core.hooksPath factory/core/hooks/githooks" "$out"
}

test_check_passes_in_a_linked_worktree_under_the_main_checkouts_core() {
	linked_worktree
	run_cmd bash "$MAIN_CORE/hooks.sh" check
	assert_status 0
	assert_eq "" "$out"
}

test_check_passes_in_a_linked_worktree_under_its_own_core() {
	linked_worktree
	run_cmd bash factory/core/hooks.sh check
	assert_status 0
	assert_eq "" "$out"
}

test_a_hooks_path_elsewhere_fails_in_a_linked_worktree_under_the_main_checkouts_core() {
	linked_worktree
	mkdir -p other-hooks
	git config core.hooksPath other-hooks
	run_cmd bash "$MAIN_CORE/hooks.sh" check
	assert_status 1
	assert_eq "tools/verify/hook-mode:1 hooks-path core.hooksPath is other-hooks, not the Core's githooks; run git config core.hooksPath factory/core/hooks/githooks" "$out"
}

test_a_bad_hook_mode_fails_the_check() {
	adopted_project report
	echo armed > tools/verify/hook-mode
	check_hooks
	assert_status 1
	assert_eq "tools/verify/hook-mode:1 hook-mode expected 'report' (Adopted) or 'enforce' (Armed)" "$out"
}

test_prepare_fails_on_hook_drift() {
	adopted_project report
	retired_cursor_files
	rm .cursor/cli.json
	run_verify prepare
	assert_status 1
	assert_eq "== prepare FAIL
.cursor/hooks.json:1 hook-drift the retired Cursor Editor's; run bash factory/core/hooks.sh generate
verify: FAILED at step prepare" "$out"
}

# --- pre-commit -----------------------------------------------------------------

test_armed_pre_commit_refuses_an_edit_to_a_locked_test() {
	locked_project enforce
	red="$(git rev-parse --short HEAD)"
	echo test_changed >> tests/a_test.txt
	git add tests/a_test.txt
	commit_staged
	assert_status 1
	stderr_has "pre-commit: tests/a_test.txt:1 locked-test changed after the Lock (red commit $red)"
	stderr_has "pre-commit: refused (the project is Armed)"
	assert_eq "$red" "$(git rev-parse --short HEAD)" "the commit went in"
}

test_adopted_pre_commit_reports_an_edit_to_a_locked_test() {
	locked_project report
	red="$(git rev-parse --short HEAD)"
	echo test_changed >> tests/a_test.txt
	git add tests/a_test.txt
	commit_staged
	assert_status 0
	stderr_has "pre-commit: tests/a_test.txt:1 locked-test changed after the Lock (red commit $red)"
	stderr_has "pre-commit: reported only (the project is Adopted)"
	[ "$red" != "$(git rev-parse --short HEAD)" ] || fail "the commit did not go in"
}

test_armed_pre_commit_lets_other_files_through() {
	locked_project enforce
	echo real > src/a.txt
	echo test_more > tests/b_test.txt
	git add -A
	commit_staged
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")"
}

test_pre_commit_checks_the_index_not_the_working_tree() {
	locked_project enforce
	echo test_changed >> tests/a_test.txt
	echo real > src/a.txt
	git add src/a.txt
	commit_staged
	assert_status 0
	git checkout -q -- tests/a_test.txt
	cp tests/a_test.txt "$TEST_TMP/locked"
	echo test_changed >> tests/a_test.txt
	git add tests/a_test.txt
	cp "$TEST_TMP/locked" tests/a_test.txt
	commit_staged
	assert_status 1
}

test_pre_commit_without_a_lock_passes() {
	adopted_project enforce
	echo test_new >> tests/a_test.txt
	git add -A
	commit_staged
	assert_status 0
}

# arch_step: an arch step with one static check (a staged file holding BAD) and
# one runtime check (always a finding), both cited by ARCHITECTURE.md.
arch_step() {
	cat > tools/verify/arch << 'SH'
. "$FACTORY_CORE/lib/steps.sh"
. "$FACTORY_CORE/lib/findings.sh"
. "$FACTORY_CORE/lib/architecture.sh"
check_bad() { grep -rn BAD src | awk -F: '{ print $1 ":" $2 " holds BAD" }'; }
check_runtime() { echo "src/a.txt:1 the runtime check ran"; }
factory_arch_check no-bad check_bad
factory_arch_check runtime-walk check_runtime runtime
factory_arch_main ARCHITECTURE.md
SH
	printf '**R1.** No BAD.\nEnforced by: `arch:no-bad`\n\n**R2.** Runtime.\nEnforced by: `arch:runtime-walk`\n' > ARCHITECTURE.md
	git add -A && git commit -q -m "arch" || fail "could not commit the arch step"
}

test_armed_pre_commit_runs_the_static_arch_checks_on_the_index() {
	adopted_project enforce
	arch_step
	echo BAD > src/a.txt
	git add src/a.txt
	echo fine > src/a.txt
	commit_staged
	assert_status 1
	stderr_has "pre-commit: src/a.txt:1 R1 holds BAD"
	grep -q "runtime check ran" "$TEST_TMP/stderr" && fail "the runtime check ran in pre-commit"
	return 0
}

test_adopted_pre_commit_reports_arch_findings() {
	adopted_project report
	arch_step
	echo BAD > src/a.txt
	git add src/a.txt
	commit_staged
	assert_status 0
	stderr_has "pre-commit: src/a.txt:1 R1 holds BAD"
}

test_pre_commit_passes_a_clean_arch_step() {
	adopted_project enforce
	arch_step
	echo fine > src/a.txt
	git add src/a.txt
	commit_staged
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")"
}

# --- scalar values beside "hooks" ---------------------------------------------

# scalar_settings: a settings file with top-level scalars before and after the
# hooks key; the generator must keep each one.
scalar_settings() {
	mkdir -p .claude
	printf '{\n  "a": true,\n  "b": false,\n  "c": null,\n  "d": 30,\n  "e": -1,\n  "hooks": {"Stop": []},\n  "f": true,\n  "g": false,\n  "h": null,\n  "i": 12,\n  "j": -1\n}\n' > .claude/settings.json
}

SCALARS_GENERATED='{
  "permissions": {
    "allow": [
      "Bash(bash factory/core/lock.sh lift:*)"
    ]
  },
  "a": true,
  "b": false,
  "c": null,
  "d": 30,
  "e": -1,
  "hooks": @HOOKS@,
  "f": true,
  "g": false,
  "h": null,
  "i": 12,
  "j": -1,
  "model": "claude-opus-5-5",
  "effortLevel": "medium",
  "maxEffortLevel": "xhigh"
}'

test_generate_keeps_top_level_scalars_on_both_sides_of_hooks() {
	fixture_git_project
	scalar_settings
	generate
	assert_settings "$SCALARS_GENERATED"
}

test_generate_adds_hooks_after_a_trailing_scalar() {
	fixture_git_project
	mkdir -p .claude
	printf '{\n  "includeCoAuthoredBy": false,\n  "cleanupPeriodDays": 30\n}\n' > .claude/settings.json
	generate
	assert_settings '{
  "permissions": {
    "allow": [
      "Bash(bash factory/core/lock.sh lift:*)"
    ]
  },
  "includeCoAuthoredBy": false,
  "cleanupPeriodDays": 30,
  "hooks": @HOOKS@,
  "model": "claude-opus-5-5",
  "effortLevel": "medium",
  "maxEffortLevel": "xhigh"
}'
}

test_check_passes_with_top_level_scalars_on_both_sides_of_hooks() {
	adopted_project report
	scalar_settings
	generate
	check_hooks
	assert_status 0
	assert_eq "" "$out"
	sed -i 's/"hooks": {/"hooks": {"Stop": [], /' .claude/settings.json
	check_hooks
	assert_status 1
	assert_eq '.claude/settings.json:1 hook-drift its "hooks", "model", "effortLevel" or "maxEffortLevel" key differs from what the factory writes (factory/core/hooks/claude-hooks.json, lib/hooks.sh); set your own model in .claude/settings.local.json, then run bash factory/core/hooks.sh generate' "$out"
}

# --- the session-start update check -------------------------------------------

test_generate_wires_the_update_check_to_session_start() {
	fixture_git_project
	generate
	. "$FACTORY_CORE/lib/json.sh"
	assert_eq 'bash "$CLAUDE_PROJECT_DIR/factory/core/hooks/claude-update-check.sh"' \
		"$(factory_json_get hooks.SessionStart.0.hooks.0.command < .claude/settings.json)" "the SessionStart command"
	assert_eq 20 "$(factory_json_get hooks.SessionStart.0.hooks.0.timeout < .claude/settings.json)" "the SessionStart timeout"
	! factory_json_get hooks.SessionStart.0.matcher < .claude/settings.json > /dev/null || fail "the SessionStart hook has a matcher"
}

test_a_missing_session_start_hook_fails_the_check() {
	adopted_project report
	cp .claude/settings.json "$TEST_TMP/settings"
	sed -i '/^    "SessionStart": \[$/,/^    \],$/d' .claude/settings.json
	! cmp -s "$TEST_TMP/settings" .claude/settings.json || fail "no SessionStart hook to remove"
	grep -q '"SubagentStop"' .claude/settings.json || fail "the removal took more than the SessionStart hook"
	check_hooks
	assert_status 1
	assert_eq '.claude/settings.json:1 hook-drift its "hooks", "model", "effortLevel" or "maxEffortLevel" key differs from what the factory writes (factory/core/hooks/claude-hooks.json, lib/hooks.sh); set your own model in .claude/settings.local.json, then run bash factory/core/hooks.sh generate' "$out"
}

# --- the Lock lift's allow rule (#17.17) ---------------------------------------

LIFT_RULE='Bash(bash factory/core/lock.sh lift:*)'

# A Driver's one Lock lift runs without a permission prompt: generate adds the
# allow rule beside the human's own rules, once, and keeps theirs.
test_generate_adds_the_lock_lift_rule_beside_the_humans_allow_rules() {
	fixture_git_project
	mkdir -p .claude
	printf '{\n  "permissions": {\n    "allow": [\n      "Bash(ls)"\n    ],\n    "deny": []\n  }\n}\n' > .claude/settings.json
	generate
	. "$FACTORY_CORE/lib/json.sh"
	assert_eq 'Bash(ls)' "$(factory_json_get permissions.allow.0 < .claude/settings.json)" "the human's rule"
	assert_eq "$LIFT_RULE" "$(factory_json_get permissions.allow.1 < .claude/settings.json)" "the lift rule"
	grep -qF '"deny": []' .claude/settings.json || fail "the deny list changed: $(cat .claude/settings.json)"
	cp .claude/settings.json "$TEST_TMP/claude1"
	generate
	cmp -s "$TEST_TMP/claude1" .claude/settings.json || fail ".claude/settings.json changed on the second run"
	assert_eq 1 "$(grep -cF "$LIFT_RULE" .claude/settings.json)" "the lift rule's count"
}

# A settings file whose "permissions" or "allow" is of another type is the human's
# to fix: generate refuses it and leaves it as it was.
test_generate_refuses_permissions_or_allow_of_another_type() {
	fixture_git_project
	mkdir -p .claude
	for bad in '{"permissions": "all"}' '{"permissions": {"allow": "Bash(ls)"}}'; do
		echo "$bad" > .claude/settings.json
		run_cmd bash "$FACTORY_CORE/hooks.sh" generate
		assert_status 1
		assert_eq "$bad" "$(cat .claude/settings.json)" "the settings file was rewritten"
	done
}

# A removed lift rule is its own finding, and generate puts it back.
test_a_missing_lock_lift_rule_fails_the_check() {
	adopted_project report
	grep -qF "\"$LIFT_RULE\"" .claude/settings.json || fail "the lift rule wasn't in the generated settings: $(cat .claude/settings.json)"
	sed -i 's|"Bash(bash factory/core/lock.sh lift:\*)"|"Bash(ls)"|' .claude/settings.json
	check_hooks
	assert_status 1
	assert_eq ".claude/settings.json:1 lift-rule its \"permissions\" \"allow\" list lacks the factory's rule for the Lock lift, $LIFT_RULE (lib/hooks.sh); run bash factory/core/hooks.sh generate" "$out"
	generate
	check_hooks
	assert_status 0
	grep -qF '"Bash(ls)"' .claude/settings.json || fail "generate dropped the human's rule"
}

# A settings file whose "permissions" is of another type is a JSON object still:
# check names the type, as generate does, not "not a JSON object" alone.
test_check_names_permissions_of_another_type() {
	adopted_project report
	echo '{"permissions": "all"}' > .claude/settings.json
	check_hooks
	assert_status 1
	assert_eq '.claude/settings.json:1 hook-drift not a JSON object, or its "permissions" or their "allow" is of another type, so its hooks can'"'"'t be generated' "$out"
}
