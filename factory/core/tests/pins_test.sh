# The pin check, run by prepare: tools/verify/pins against tools/verify/versions.

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_matching_pins_pass_prepare() {
	fixture_project
	run_verify prepare
	assert_status 0
	assert_eq "== prepare PASS
verify: PASS" "$out"
	assert_eq "prepare" "$(ran_steps)"
}

test_version_mismatch_fails_prepare_with_expected_and_found() {
	fixture_project
	echo "FAKETOOL_VERSION=1.2.4" > tools/verify/local.env
	run_verify
	assert_status 1
	assert_eq "== prepare FAIL
tools/verify/pins:2 pin-mismatch faketool: expected 1.2.3, found 1.2.4
verify: FAILED at step prepare" "$out"
	assert_eq "" "$(ran_steps)" "the project's prepare ran after a failed pin check"
}

test_tool_not_found_fails_prepare() {
	fixture_project
	: > tools/verify/local.env
	run_verify prepare
	assert_status 1
	assert_line "tools/verify/pins:2 pin-mismatch faketool: expected 1.2.3, found none"
}

test_every_pin_is_checked() {
	fixture_project
	echo "othertool 9.0" >> tools/verify/pins
	run_verify prepare
	assert_status 1
	assert_line "tools/verify/pins:3 pin-mismatch othertool: expected 9.0, found none"
	assert_no_line "tools/verify/pins:2 pin-mismatch faketool: expected 1.2.3, found 1.2.3"
}

test_missing_pin_file_fails_prepare() {
	fixture_project
	rm tools/verify/pins
	run_verify prepare
	assert_status 1
	printf '%s\n' "$out" | grep -q '^tools/verify/pins:1 pin-file-missing ' || fail "no pin-file-missing finding:"$'\n'"$out"
}

test_malformed_pin_line_fails_prepare() {
	fixture_project
	echo "brokenpin" >> tools/verify/pins
	run_verify prepare
	assert_status 1
	assert_line "tools/verify/pins:3 pin-format expected '<tool> <version>', got: brokenpin"
}

test_empty_pin_file_needs_no_probe() {
	fixture_project
	echo "# no tools" > tools/verify/pins
	rm tools/verify/versions
	run_verify prepare
	assert_status 0
}

test_failing_probe_fails_prepare() {
	fixture_project
	printf '#!/usr/bin/env bash\nexit 3\n' > tools/verify/versions
	run_verify prepare
	assert_status 1
	assert_line "tools/verify/versions:1 pin-probe-failed the version probe exited 3"
}

test_pin_check_runs_only_in_prepare() {
	fixture_project
	echo "FAKETOOL_VERSION=1.2.4" > tools/verify/local.env
	run_verify lint
	assert_status 0
}
