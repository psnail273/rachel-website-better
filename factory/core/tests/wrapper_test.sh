# The .ps1 wrapper: passes its arguments through and returns the runner's exit code.
#
# It needs a PowerShell that can read this checkout's paths: pwsh, or Windows
# PowerShell under Git Bash (cygpath turns the paths into Windows ones). WSL can
# start Windows' powershell.exe too, but hands it Linux paths, whose fate depends
# on where the checkout sits, so there the tests skip.

# run_wrapper <args...>: run factory/core/verify.ps1 on the current project.
run_wrapper() {
	local ps script
	if command -v pwsh > /dev/null; then
		ps=pwsh
	elif command -v powershell.exe > /dev/null && command -v cygpath > /dev/null; then
		ps=powershell.exe
	else
		skip "no PowerShell that can read this checkout's paths (pwsh, or Windows PowerShell under Git Bash)"
	fi
	script="$FACTORY_CORE/verify.ps1"
	command -v cygpath > /dev/null && script="$(cygpath -w "$script")"
	run_cmd "$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script" "$@"
	out="$(printf '%s\n' "$out" | tr -d '\r')"
}

test_wrapper_passes_steps_through() {
	fixture_project
	run_wrapper test lint
	assert_status 0
	assert_eq "lint test" "$(ran_steps)"
	assert_last_line "verify: PASS"
}

test_wrapper_returns_a_failing_exit_code() {
	fixture_project
	: > .fixture/fail-lint
	run_wrapper lint
	assert_status 1
	assert_last_line "verify: FAILED at step lint"
}

test_wrapper_returns_the_usage_exit_code() {
	fixture_project
	run_wrapper nosuchstep
	assert_status 2
}

test_wrapper_passes_options_through() {
	fixture_project
	run_wrapper --twice lint
	assert_status 0
	assert_last_line "verify: two runs match"
}
