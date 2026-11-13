# The Scenario run (scenarios.sh) over a stand-in driver, and the Scenario
# folder's reader (lib/scenarios.sh).

# scenario_project: a git project in $TEST_TMP/project naming scenarios/ its
# Scenario folder, and cd there. driver <body> writes its
# driver.
scenario_project() {
	isolate_git
	mkdir -p "$TEST_TMP/project/tools/verify" && cd "$TEST_TMP/project" || fail "could not make the project"
	git init -q . || fail "git init failed"
	printf '# the Scenario folder\n\n%s\n' scenarios/ > tools/verify/scenario-folder
}

driver() {
	printf '%s\n' "$1" > tools/verify/scenarios
}

run_scenarios() {
	run_cmd bash "$FACTORY_CORE/scenarios.sh" "$@"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_every_scenario_passing_passes() {
	scenario_project
	driver 'printf "serve/after_a_miss\tPASS\tscenarios/serve/after_a_miss.gd:6\nclear\tPASS\tscenarios/clear.gd:4\n"'
	run_scenarios
	assert_status 0
	assert_eq "serve/after_a_miss	PASS	scenarios/serve/after_a_miss.gd:6
clear	PASS	scenarios/clear.gd:4
scenarios: PASS: 2 passed" "$out"
}

test_a_scenario_that_doesnt_pass_fails_the_run() {
	scenario_project
	driver 'printf "a\tPASS\tscenarios/a.gd:1\nb\tFAILURE\tscenarios/b.gd:9\nc\tSKIP\tscenarios/c.gd:2\n"; exit 1'
	run_scenarios
	assert_status 1
	assert_eq "a	PASS	scenarios/a.gd:1
b	FAILURE	scenarios/b.gd:9
c	SKIP	scenarios/c.gd:2
scenarios: FAIL: 2 of 3 did not pass" "$out"
}

test_a_wrong_line_or_exit_from_the_driver_is_a_finding() {
	scenario_project
	driver 'printf "a\tPASS\tscenarios/a.gd:1\nnot a result\na\tPASS\tscenarios/a.gd:1\n"'
	run_scenarios
	assert_status 1
	assert_eq "a	PASS	scenarios/a.gd:1
scenarios/a.gd:1 results-duplicate a is listed twice in the results
tools/verify/scenarios:1 results-format results line 2: expected '<name><TAB><PASS|FAILURE|ERROR|SKIP><TAB><file:line>', got: not a result
scenarios: FAIL: 0 of 1 did not pass" "$out"
	driver 'printf "a\tPASS\tscenarios/a.gd:1\n"; exit 1'
	run_scenarios
	assert_status 1
	assert_eq "a	PASS	scenarios/a.gd:1
tools/verify/scenarios:1 scenarios-exit the driver exited 1, yet no Scenario it printed failed
scenarios: FAIL: 0 of 1 did not pass" "$out"
}

test_a_project_without_scenarios_has_them_not_run() {
	scenario_project
	run_scenarios
	assert_status 3
	assert_eq "scenarios: not run: the project has no Scenario driver (tools/verify/scenarios)" "$out" "no driver"
	echo "# factory: no-op" > tools/verify/scenarios
	run_scenarios
	assert_status 3
	assert_eq "scenarios: not run: the project has no Scenario driver (tools/verify/scenarios)" "$out" "a no-op driver"
	driver 'exit 0'
	run_scenarios
	assert_status 3
	assert_eq "scenarios: not run: no Scenario in scenarios/" "$out" "an empty folder"
	driver 'echo "no Godot" >&2; exit 2'
	run_scenarios
	assert_status 3
	assert_eq "scenarios: not run: the driver could not run them (it exited 2; its stderr says why)" "$out" "the driver couldn't run"
	stderr_has "no Godot"
	rm tools/verify/scenario-folder
	run_scenarios
	assert_status 3
	assert_eq "scenarios: not run: the project names no Scenario folder (tools/verify/scenario-folder)" "$out" "no folder"
}

test_the_driver_runs_from_the_root_with_local_env_and_the_core() {
	scenario_project
	printf 'GREETING=hello\n' > tools/verify/local.env
	driver 'printf "%s %s %s\tPASS\tscenarios/a.gd:1\n" "$GREETING" "$(basename "$PWD")" "$(basename "$(dirname "$FACTORY_CORE")")"'
	mkdir -p src && cd src || fail "no src"
	run_scenarios
	assert_status 0
	assert_line "hello project factory	PASS	scenarios/a.gd:1"
	run_scenarios extra
	assert_status 2
}

test_the_folder_line_is_checked() {
	local line want
	scenario_project
	while read -r line want; do
		printf '%s\n' "$line" > tools/verify/scenario-folder
		run_cmd bash -c '. "$FACTORY_CORE/lib/steps.sh" && . "$FACTORY_CORE/lib/scenarios.sh" && factory_scenario_folder'
		assert_status 0
		assert_eq "$want" "$out" "$line"
	done << 'LINES'
scenarios scenarios
scenarios/ scenarios
./scenarios// scenarios
checks/play.through_1/ checks/play.through_1
LINES
	for line in "" / /abs ../up a/../b . ./ 'a*b' '$HOME'; do
		printf '%s\n' "$line" > tools/verify/scenario-folder
		run_cmd bash -c '. "$FACTORY_CORE/lib/steps.sh" && . "$FACTORY_CORE/lib/scenarios.sh" && factory_scenario_folder'
		assert_status 1
	done
}
