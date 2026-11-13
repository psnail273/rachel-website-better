# The Godot adapter's prepare, typecheck, test, smoke and playtest steps, its
# Scenario driver and its version probe (factory/adapters/godot/tools/verify), on a scratch project built
# from tests/fixture/project. Fixture files end in .txt so Godot never imports or
# checks them where they're stored.
#
# Tests named *_with_godot need Godot 4.7.1 in GODOT_BIN and the pinned gdUnit4
# (gdunit4_source in lib.sh), and *_with_gdmutant gdmutant 0.1.4 as well
# (real_gdmutant in lib.sh); without them they skip. The rest run Godot (and
# gdmutant) as a fake.

GODOT_ADAPTER="$FACTORY_CORE/../adapters/godot"
. "$GODOT_ADAPTER/tests/lib.sh"
GODOT_FIXTURES="$GODOT_ADAPTER/tests/fixture"
GODOT_PROJECT_SRC="$GODOT_FIXTURES/project"

# steps_project: a git project in $TEST_TMP/project, from the fixture project
# plus the adapter's step templates, and cd there. Godot is a fake (fake_godot)
# unless real_godot runs first.
steps_project() {
	local f
	mkdir -p "$TEST_TMP/project/tools" || fail "could not make the project"
	cp -R "$GODOT_PROJECT_SRC/." "$TEST_TMP/project/" || fail "could not copy the fixture"
	cp -R "$GODOT_ADAPTER/tools/verify" "$TEST_TMP/project/tools/verify" || fail "could not copy the adapter"
	cd "$TEST_TMP/project" || fail "could not enter the project"
	while IFS= read -r f; do
		mv "$f" "${f%.txt}"
	done < <(find . -name '*.txt' -not -path './tools/*')
	[ -n "${REAL_GODOT:-}" ] || fake_godot
	# format, lint and mutate aren't under test here, so their tools aren't pinned.
	sed -i '/^gdscript-formatter /d; /^gdmutant /d' tools/verify/pins
	printf 'GODOT_BIN=%s\n' "$GODOT_BIN" > tools/verify/local.env
	printf '.godot/\n/tools/verify/local.env\n' > .gitignore
	isolate_git
	git init -q . || fail "git init failed"
}

# real_godot: skip unless Godot 4.7.1 and the pinned gdUnit4 are here; then
# steps_project uses them.
real_godot() {
	[ -n "${GODOT_BIN:-}" ] || skip "GODOT_BIN is not set"
	command -v "$GODOT_BIN" > /dev/null 2>&1 || skip "GODOT_BIN '$GODOT_BIN' is not a program"
	"$GODOT_BIN" --headless --version 2> /dev/null | grep -q '^4\.7\.1\.stable' || skip "GODOT_BIN is not Godot 4.7.1"
	GDUNIT4_SRC="$(gdunit4_source)" || skip "no gdUnit4 at the pinned version (set FACTORY_GDUNIT4)"
	REAL_GODOT=1
}

# with_gdunit: copy the pinned gdUnit4 (real_godot found it) into the project.
with_gdunit() {
	mkdir -p addons && cp -R "$GDUNIT4_SRC" addons/gdUnit4 || fail "could not copy gdUnit4"
}

# fake_godot: GODOT_BIN becomes a script that logs its arguments to
# $TEST_TMP/godot.log, prints .fixture-version for --version, writes the report
# in $TEST_TMP/report.xml where -rd says, writes the --export-debug file, prints
# $TEST_TMP/godot.stderr to stderr, and exits with $TEST_TMP/godot.exit (default 0);
# an --import exits with $TEST_TMP/import.exit (default 0).
fake_godot() {
	export GODOT_BIN="$TEST_TMP/fake_godot"
	cat > "$GODOT_BIN" << 'SH'
#!/usr/bin/env bash
dir="$(dirname "$0")"
echo "$*" >> "$dir/godot.log"
args=("$@")
for i in "${!args[@]}"; do
	case "${args[i]}" in
		--version) echo "4.7.1.stable.official.a13da4feb" ;;
		--import) exit "$(cat "$dir/import.exit" 2> /dev/null || echo 0)" ;;
		-rd) [ -f "$dir/report.xml" ] && mkdir -p "${args[i+1]#res://}/report_1" && cp "$dir/report.xml" "${args[i+1]#res://}/report_1/results.xml" ;;
		--export-debug) [ "$(cat "$dir/godot.exit" 2> /dev/null || echo 0)" = 0 ] && echo apk > "${args[i+2]}" ;;
	esac
done
[ -f "$dir/godot.stderr" ] && cat "$dir/godot.stderr" >&2
exit "$(cat "$dir/godot.exit" 2> /dev/null || echo 0)"
SH
	chmod +x "$GODOT_BIN"
}

add_gd() {
	mkdir -p "$(dirname "$2")"
	cp "$GODOT_FIXTURES/$1.gd.txt" "$2" || fail "no fixture $1"
}

# run_step <step>: run one step script by hand, as the runner would.
run_step() {
	export FACTORY_RESULTS_FILE="$TEST_TMP/results"
	run_cmd bash "tools/verify/$1"
}

results() {
	cat "$TEST_TMP/results"
}

# --- the deviation step ---

# deviation_project: steps_project, committed, with a brief scoping src/** and the
# diff base at that commit. Then off_scope adds a .uid at the root, one in a folder,
# and any other files named, and commits them.
deviation_project() {
	steps_project
	git add -A && git commit -q -m base || fail "commit failed"
	FACTORY_BASE="$(git rev-parse HEAD)"
	export FACTORY_BASE
	brief "scope src/**"
}

off_scope() {
	mkdir -p levels
	echo 'uid://root' > root.gd.uid
	echo 'uid://marker' > levels/marker.gd.uid
	for f in "$@"; do
		echo extends Node > "$f"
	done
	git add -A && git commit -q -m "off scope" || fail "commit failed"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_deviation_lets_an_off_scope_uid_through() {
	deviation_project
	off_scope
	run_step deviation
	assert_status 0
	assert_eq "" "$out"
}

test_deviation_still_fails_an_off_scope_script() {
	deviation_project
	off_scope root.gd levels/marker.gd
	run_step deviation
	assert_status 1
	assert_eq "levels/marker.gd:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: levels/marker.gd: <reason>' trailer
root.gd:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: root.gd: <reason>' trailer" "$out"
}

# --- the assertion-count probe and the deviation step's assert-drop ---

# Each func's assertion calls by the lint's branched-assert pattern, every call
# on a line: an inner class's funcs under its name, a lambda's calls as its
# func's, and none in a comment or a string. A line at column 0 inside brackets
# or a string ends no func. A func after an annotation on its line counts, a Unicode
# name stays whole, a header joined with a backslash keeps its name, and an
# assert_* helper's own declaration is no call. A path that isn't GDScript gets
# nothing.
test_assert_counts_prints_each_funcs_assertion_calls() {
	steps_project
	add_gd assert_counts_test tests/counts_test.gd
	# shellcheck disable=SC2094 # the step reads the file; nothing writes it
	run_cmd bash tools/verify/assert-counts tests/counts_test.gd < tests/counts_test.gd
	assert_status 0
	assert_eq "11 Recorder.call_at 0
15 Recorder.Inner.check 1
19 _check_each 1
24 _helper 0
28 test_counts_every_call_on_a_line 6
41 test_skips_comments_and_strings 1
50 test_counts_its_lambdas 2
64 test_after_a_member 1
68 check_events 2
73 assert_valid 0
77 test_café 2
81 test_cafè 1
85 test_joined_header 1" "$out"
	run_cmd bash tools/verify/assert-counts tests/counts_test.gd.uid < tests/counts_test.gd
	assert_status 0
	assert_eq "" "$out"
}

# assert_drop_project <brief line...>: the cue tests in the base, and a branch
# that rewrites them: a sentinel helper takes over test_sound_cues_go_up's
# checks and drops two (#171), and test_break_cue_comes_last folds into
# test_serve_cue_comes_first, which keeps the file's other count. The brief
# scopes src/** and tests/** plus the given lines.
assert_drop_project() {
	steps_project
	add_gd assert_drop_base_test tests/cues_test.gd
	git add -A && git commit -q -m base || fail "commit failed"
	FACTORY_BASE="$(git rev-parse HEAD)"
	export FACTORY_BASE
	brief "scope src/**" "scope tests/**" "$@"
	add_gd assert_drop_rewrite_test tests/cues_test.gd
	git add -A && git commit -q -m "straight-line cues" || fail "commit failed"
}

ASSERT_DROP_HINT="keep every check, or the Driver declares the drop in the brief"

test_deviation_fails_a_rewrite_that_drops_assertions() {
	assert_drop_project
	run_step deviation
	assert_status 1
	assert_eq "tests/cues_test.gd:1 assert-drop test_break_cue_comes_last drops from 2 assertion calls at the base to 0 at HEAD, where it is gone: $ASSERT_DROP_HINT: asserts tests/cues_test.gd test_break_cue_comes_last 2 0
tests/cues_test.gd:15 assert-drop test_sound_cues_go_up drops from 5 assertion calls at the base to 3 at HEAD: $ASSERT_DROP_HINT: asserts tests/cues_test.gd test_sound_cues_go_up 5 3" "$out"
}

test_deviation_passes_the_drops_the_brief_declares_exactly() {
	assert_drop_project "asserts tests/cues_test.gd test_sound_cues_go_up 5 3" \
		"asserts tests/cues_test.gd test_break_cue_comes_last 2 0"
	run_step deviation
	assert_status 0
	assert_eq "tests/cues_test.gd:1 assert-declared test_break_cue_comes_last drops from 2 assertion calls at the base to 0 at HEAD, where it is gone; the brief declares it (asserts)
tests/cues_test.gd:15 assert-declared test_sound_cues_go_up drops from 5 assertion calls at the base to 3 at HEAD; the brief declares it (asserts)" "$out"
}

test_deviation_fails_a_declaration_the_counts_dont_match() {
	assert_drop_project "asserts tests/cues_test.gd test_sound_cues_go_up 5 4" \
		"asserts tests/cues_test.gd test_break_cue_comes_last 2 0"
	run_step deviation
	assert_status 1
	assert_eq "tests/cues_test.gd:1 assert-declared test_break_cue_comes_last drops from 2 assertion calls at the base to 0 at HEAD, where it is gone; the brief declares it (asserts)
tests/cues_test.gd:15 assert-drop the brief declares asserts tests/cues_test.gd test_sound_cues_go_up 5 4, but test_sound_cues_go_up has 5 assertion calls at the base and 3 at HEAD" "$out"
}

# --- the red judgement ---

# What gdUnit4 reports in the red phase below: the project's test passes, the new
# one fails.
red_report() {
	cat > "$TEST_TMP/report.xml" << 'XML'
<testsuites>
	<testsuite id="0" name="main_test" package="tests">
		<testcase name="test_main_script_loads" classname="main_test" time="0.000">
		</testcase>
	</testsuite>
	<testsuite id="1" name="stub_test" package="tests/levels">
		<testcase name="test_stub_answers" classname="stub_test" time="0.000">
			<failure message="FAILED: res://tests/levels/stub_test.gd:5" type="FAILURE">
<![CDATA[
]]>
			</failure>
		</testcase>
	</testsuite>
</testsuites>
XML
	echo 100 > "$TEST_TMP/godot.exit"
}

# The .uid Godot writes beside a new stub isn't the seam's file, and it arrives
# untracked, when the tests run. The runner judges it, so the runner runs here.
test_red_judgement_passes_a_new_stubs_uid() {
	steps_project
	git add -A && git commit -q -m base || fail "commit failed"
	FACTORY_BASE="$(git rev-parse HEAD)"
	export FACTORY_BASE
	brief "scope tests/**" "scope levels/stub.gd" "test test_stub_answers" "seam levels/stub.gd Stub.answer"
	mkdir -p levels tests/levels
	printf 'class_name Stub\n' > levels/stub.gd
	printf 'extends GdUnitTestSuite\n\n\nfunc test_stub_answers() -> void:\n\tpass\n' > tests/levels/stub_test.gd
	git add -A && git commit -q -m red || fail "commit failed"
	echo 'uid://stub' > levels/stub.gd.uid
	red_report
	run_cmd bash "$FACTORY_CORE/verify.sh" --red test
	assert_status 0
	assert_last_line "verify: PASS"
}

# --- the scope ---

test_scope_narrows_the_gdscript_files_the_gates_check() {
	steps_project
	add_gd parse_error src/kept.gd
	add_gd parse_error src/generated/dropped.gd
	add_gd parse_error addons/thing/thing.gd
	printf '**\n!addons/\n!tools/\n!src/generated/\n' > tools/verify/scope
	run_cmd bash -c '. tools/verify/_gdscript.sh && gd_files'
	assert_eq "main.gd"$'\n'"src/kept.gd"$'\n'"tests/main_test.gd" "$out"
}

test_scope_agreeing_with_the_exclude_filter_passes_prepare() {
	steps_project
	add_gd parse_error addons/thing/thing.gd
	run_step prepare
	assert_status 0
	assert_eq "" "$out"
}

test_scope_disagreeing_with_the_exclude_filter_is_a_finding() {
	steps_project
	add_gd parse_error src/unchecked.gd
	add_gd parse_error src/left_out.gd
	printf '**\n!addons/\n!tools/\n!src/unchecked.gd\n' > tools/verify/scope
	sed -i 's#^exclude_filter=.*#exclude_filter="addons/gdUnit4/*, src/left_*, tools/*"#' export_presets.cfg
	run_step prepare
	assert_status 1
	assert_eq 'export_presets.cfg:8 scope-not-shipped preset "Android" leaves out src/left_out.gd, which the scope checks as shipped code
export_presets.cfg:8 scope-test-shipped preset "Android" ships the test tests/main_test.gd; add it to exclude_filter
export_presets.cfg:8 scope-unchecked preset "Android" ships src/unchecked.gd, which is outside tools/verify/scope' "$(printf '%s\n' "$out" | LC_ALL=C sort)"
}

test_exclude_filter_patterns_match_like_godot() {
	steps_project
	add_gd parse_error src/deep/generated.gd
	printf '**\n!addons/\n!tools/\n!src/deep/\n' > tools/verify/scope
	sed -i 's#^exclude_filter=.*#exclude_filter="TESTS/*,GENERATED.GD,TOOLS/*"#' export_presets.cfg
	run_step prepare
	assert_status 0
	assert_eq "" "$out"
}

test_a_gdignored_folder_ships_in_no_preset() {
	steps_project
	add_gd parse_error vendored/thing.gd
	add_gd parse_error src/hidden/kept.gd
	: > vendored/.gdignore
	: > src/hidden/.gdignore
	printf '**\n!addons/\n!tools/\n!vendored/\n' > tools/verify/scope
	run_step prepare
	assert_status 1
	assert_eq 'export_presets.cfg:8 scope-not-shipped preset "Android" leaves out src/hidden/kept.gd, which the scope checks as shipped code' "$out"
}

test_an_export_filter_other_than_all_resources_is_a_finding() {
	steps_project
	sed -i 's#^export_filter=.*#export_filter="resources"#' export_presets.cfg
	run_step prepare
	assert_status 1
	assert_eq "export_presets.cfg:8 scope-export-filter preset \"Android\" exports 'resources'; the scope cross-check needs all_resources" "$out"
}

test_a_missing_scope_is_a_finding() {
	steps_project
	rm tools/verify/scope
	run_step prepare
	assert_status 1
	assert_eq "tools/verify/scope:1 scope-missing no scope file; it lists the globs of what the gates check (what ships plus the tests)" "$out"
}

# --- tools ---

test_each_godot_step_without_godot_bin_is_a_finding() {
	local step
	steps_project
	for step in prepare typecheck test smoke; do
		GODOT_BIN="" run_step "$step"
		assert_status 1
		assert_eq "tools/verify/local.env:1 godot-missing GODOT_BIN is not set; set it in tools/verify/local.env (see local.env.example)" "$out" "$step"
	done
	GODOT_BIN="" run_cmd bash tools/verify/playtest
	assert_status 1
	assert_eq "" "$out" "playtest prints only the build's path"
}

test_version_probe_reports_godot_and_gdunit4() {
	steps_project
	mkdir -p addons/gdUnit4
	printf '[plugin]\n\nname="gdUnit4"\nversion="6.2.2"\n' > addons/gdUnit4/plugin.cfg
	GDSCRIPT_FORMATTER=no-such-formatter GDMUTANT_BIN=no-such-gdmutant run_cmd bash tools/verify/versions
	assert_status 0
	assert_eq "godot 4.7.1.stable"$'\n'"gdunit4 6.2.2" "$out"
}

test_pins_name_godot_gdunit4_the_formatter_and_gdmutant() {
	assert_eq "godot 4.7.1.stable"$'\n'"gdunit4 6.2.2"$'\n'"gdscript-formatter 0.27.0"$'\n'"gdmutant 0.1.4" \
		"$(grep -v '^#' "$GODOT_ADAPTER/tools/verify/pins")"
}

test_bootstrap_does_nothing() {
	steps_project
	run_cmd bash tools/verify/bootstrap
	assert_status 0
	assert_eq "" "$out"
	[ ! -f "$TEST_TMP/godot.log" ] || fail "bootstrap ran Godot"
}

# --- test: the results file from gdUnit4's report ---

# A report as gdUnit4 6.2.2 writes it for tests/fixture/mixed_test.gd.txt.
mixed_report() {
	cat > "$TEST_TMP/report.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8" ?>
<testsuites id="2026-10-28" name="report_1" tests="5" failures="2" skipped="0" flaky="0" time="0.000">
	<testsuite id="0" name="mixed_test" package="tests/a" timestamp="2026-10-28T17:48:34" hostname="localhost" tests="5" failures="2" errors="1" skipped="0" flaky="0" time="0.124">
		<testcase name="test_passes" classname="mixed_test" time="0.009">
		</testcase>
		<testcase name="test_fails" classname="mixed_test" time="0.007">
			<failure message="FAILED: res://tests/a/mixed_test.gd:9" type="FAILURE">
<![CDATA[
Expecting:
 <testcase name="not_a_test">
]]>
			</failure>
		</testcase>
		<testcase name="test_errors" classname="mixed_test" time="0.009">
			<error message="ERROR: res://tests/a/mixed_test.gd:14" type="ABORT">
<![CDATA[
Godot Runtime Error !
]]>
			</error>
		</testcase>
		<testcase name="test_params:0 (1)" classname="mixed_test" time="0.008">
		</testcase>
		<testcase name="test_params:1 (2)" classname="mixed_test" time="0.007">
			<failure message="FAILED: res://tests/a/mixed_test.gd:23" type="FAILURE">
<![CDATA[
]]>
			</failure>
		</testcase>
	</testsuite>
</testsuites>
XML
}

test_results_have_a_line_per_test_with_its_status() {
	steps_project
	add_gd mixed_test tests/a/mixed_test.gd
	mixed_report
	echo 100 > "$TEST_TMP/godot.exit"
	run_step test
	assert_status 1
	assert_eq "" "$out"
	assert_eq "test_passes	PASS	tests/a/mixed_test.gd:4
test_fails	FAILURE	tests/a/mixed_test.gd:8
test_errors	ERROR	tests/a/mixed_test.gd:12
test_params	FAILURE	tests/a/mixed_test.gd:18
test_main_script_loads	ERROR	tests/main_test.gd:4" "$(results)" "an unreported test is ERROR"
}

test_a_skipped_test_is_skip() {
	steps_project
	cat > "$TEST_TMP/report.xml" << 'XML'
<testsuites>
	<testsuite id="0" name="main_test" package="tests">
		<testcase name="test_main_script_loads" classname="main_test" time="0.000">
			<skipped message="SKIPPED: res://tests/main_test.gd:4">
<![CDATA[
This test is skipped!
]]>
			</skipped>
		</testcase>
	</testsuite>
</testsuites>
XML
	run_step test
	assert_status 0
	assert_eq "test_main_script_loads	SKIP	tests/main_test.gd:4" "$(results)"
}

test_no_report_makes_every_test_error() {
	steps_project
	add_gd mixed_test tests/a/mixed_test.gd
	echo 105 > "$TEST_TMP/godot.exit"
	run_step test
	assert_status 1
	assert_eq "test_passes	ERROR	tests/a/mixed_test.gd:4
test_fails	ERROR	tests/a/mixed_test.gd:8
test_errors	ERROR	tests/a/mixed_test.gd:12
test_params	ERROR	tests/a/mixed_test.gd:18
test_main_script_loads	ERROR	tests/main_test.gd:4" "$(results)"
}

test_old_reports_are_cleared_before_a_run() {
	steps_project
	mkdir -p .godot/factory/gdunit/report_7
	mixed_report
	sed 's/test_passes/test_stale/' "$TEST_TMP/report.xml" > .godot/factory/gdunit/report_7/results.xml
	echo 105 > "$TEST_TMP/godot.exit"
	rm "$TEST_TMP/report.xml"
	run_step test
	assert_eq "test_main_script_loads	ERROR	tests/main_test.gd:4" "$(results)"
}

# --- playtest ---

test_playtest_exports_the_first_android_preset_and_prints_its_path() {
	steps_project
	run_cmd bash tools/verify/playtest
	assert_status 0
	assert_eq ".godot/factory/playtest/Android.apk" "$out"
	[ -f .godot/factory/playtest/Android.apk ] || fail "no APK at the printed path"
	grep -q -- '--export-debug Android .godot/factory/playtest/Android.apk' "$TEST_TMP/godot.log" ||
		fail "Godot wasn't asked for a debug export:"$'\n'"$(cat "$TEST_TMP/godot.log")"
}

test_playtest_fails_when_the_export_fails() {
	steps_project
	echo 1 > "$TEST_TMP/godot.exit"
	run_cmd bash tools/verify/playtest
	assert_status 1
	assert_eq "" "$out"
}

# --- the Scenario driver ---

# scenario_game: the fixture's serve scene under src/, and the Scenario folder
# with each Scenario fixture named (scenario_<name>.gd.txt as scenarios/<name>.gd)
# and its .gdignore.
scenario_game() {
	local name
	add_gd serve src/serve.gd
	cp "$GODOT_FIXTURES/serve.tscn.txt" src/serve.tscn || fail "no serve scene"
	mkdir -p scenarios && : > scenarios/.gdignore
	for name in "$@"; do
		add_gd "scenario_$name" "scenarios/$name.gd"
	done
}

# A report as gdUnit4 writes it for the two Scenario fixtures.
scenarios_report() {
	cat > "$TEST_TMP/report.xml" << 'XML'
<testsuites>
	<testsuite id="0" name="breaks" package="scenarios">
		<testcase name="test_the_level_starts_with_no_ball" classname="breaks" time="0.001">
		</testcase>
		<testcase name="test_the_tap_after_a_clear_serves_a_ball" classname="breaks" time="0.001">
			<failure message="FAILED: res://scenarios/breaks.gd:16" type="FAILURE">
<![CDATA[
]]>
			</failure>
		</testcase>
	</testsuite>
	<testsuite id="1" name="holds" package="scenarios">
		<testcase name="test_a_tap_serves_one_ball" classname="holds" time="0.001">
		</testcase>
	</testsuite>
</testsuites>
XML
}

test_the_adapter_names_a_scenario_folder_outside_the_tests() {
	steps_project
	run_cmd bash -c '. "$FACTORY_CORE/lib/steps.sh" && . "$FACTORY_CORE/lib/scenarios.sh" && factory_scenario_folder'
	assert_eq scenarios "$out"
	run_cmd bash -c '. tools/verify/_gdscript.sh && gd_tests_regex'
	! printf 'scenarios/a.gd\n' | grep -Eq "$out" || fail "the Scenario folder is under the test paths"
}

test_scenarios_prints_nothing_without_a_scenario() {
	steps_project
	run_cmd bash tools/verify/scenarios
	assert_status 0
	assert_eq "" "$out" "no folder"
	mkdir scenarios && : > scenarios/.gdignore && add_gd parse_error scenarios/helper.gd
	run_cmd bash tools/verify/scenarios
	assert_status 0
	assert_eq "" "$out" "a script with no test function is a helper"
	[ ! -f "$TEST_TMP/godot.log" ] || fail "Godot ran with no Scenario"
}

test_scenarios_prints_a_line_per_scenario_with_its_worst_status() {
	steps_project
	scenario_game holds breaks
	scenarios_report
	echo 100 > "$TEST_TMP/godot.exit"
	run_cmd bash tools/verify/scenarios
	assert_status 1
	assert_eq "breaks	FAILURE	scenarios/breaks.gd:11
holds	PASS	scenarios/holds.gd:6" "$out"
	grep -qF -- '-a res://scenarios/breaks.gd -a res://scenarios/holds.gd --ignoreHeadlessMode' "$TEST_TMP/godot.log" ||
		fail "gdUnit4 wasn't run on each Scenario:"$'\n'"$(cat "$TEST_TMP/godot.log")"
	! grep -q 'res://tests' "$TEST_TMP/godot.log" || fail "the driver ran the tests"
}

test_scenarios_passes_when_every_scenario_holds() {
	steps_project
	scenario_game holds
	scenarios_report
	sed -i '/name="breaks"/,/<\/testsuite>/d' "$TEST_TMP/report.xml"
	run_cmd bash tools/verify/scenarios
	assert_status 0
	assert_eq "holds	PASS	scenarios/holds.gd:6" "$out"
}

test_scenarios_without_a_report_are_each_error() {
	steps_project
	scenario_game holds breaks
	echo 105 > "$TEST_TMP/godot.exit"
	run_cmd bash tools/verify/scenarios
	assert_status 1
	assert_eq "breaks	ERROR	scenarios/breaks.gd:6
holds	ERROR	scenarios/holds.gd:6" "$out"
}

test_scenarios_cannot_run_without_a_gdignore_or_godot() {
	steps_project
	scenario_game holds
	GODOT_BIN="" run_cmd bash tools/verify/scenarios
	assert_status 2
	assert_eq "" "$out"
	stderr_has "scenarios: GODOT_BIN is not set"
	rm scenarios/.gdignore
	run_cmd bash tools/verify/scenarios
	assert_status 2
	stderr_has "scenarios/ has no .gdignore"
}

test_no_gate_step_reads_the_scenario_folder() {
	steps_project
	scenario_game holds
	rm scenarios/.gdignore
	add_gd mixed_test scenarios/tests/stray_test.gd
	run_cmd bash -c '. tools/verify/_gdscript.sh && gd_all_files'
	assert_eq "main.gd"$'\n'"src/serve.gd"$'\n'"tests/main_test.gd"$'\n'"tools/verify/_arch_probe.gd" "$out" "gd_all_files"
	run_step test
	assert_eq "test_main_script_loads	ERROR	tests/main_test.gd:4" "$(results)" "the test step"
	run_step prepare
	assert_status 1
	assert_eq "tools/verify/scenario-folder:1 scenario-not-ignored scenarios/ holds Scenario scripts but no .gdignore, so Godot would import and export them; the Scenario run adds it" "$out"
	: > scenarios/.gdignore
	run_step prepare
	assert_status 0
	assert_eq "" "$out" "a gdignored Scenario folder ships in no preset and needs no scope line"
}

test_prepare_finds_the_tracked_gdignore_of_a_folder_left_out() {
	steps_project
	scenario_game holds
	git add -A && git commit -q -m scenarios || fail "commit failed"
	rm -r scenarios
	run_step prepare
	assert_status 0
	assert_eq "" "$out"
	git checkout -q -- scenarios && rm scenarios/.gdignore
	run_step prepare
	assert_status 1
	assert_eq "tools/verify/scenario-folder:1 scenario-not-ignored scenarios/ holds Scenario scripts but no .gdignore, so Godot would import and export them; the Scenario run adds it" "$out" "a checked-out folder needs its .gdignore on disk"
}

# --- with Godot ---

test_results_from_gdunit4_with_godot() {
	real_godot
	steps_project
	with_gdunit
	add_gd mixed_test tests/a/mixed_test.gd
	run_step prepare
	assert_status 0
	run_step test
	assert_status 1
	assert_eq "" "$out"
	assert_eq "test_passes	PASS	tests/a/mixed_test.gd:4
test_fails	FAILURE	tests/a/mixed_test.gd:8
test_errors	ERROR	tests/a/mixed_test.gd:12
test_params	FAILURE	tests/a/mixed_test.gd:18
test_main_script_loads	PASS	tests/main_test.gd:4" "$(results)"
}

test_a_broken_suite_makes_every_test_error_with_godot() {
	real_godot
	steps_project
	with_gdunit
	add_gd broken_test tests/broken_test.gd
	run_step prepare
	run_step test
	assert_status 1
	assert_eq "tests/broken_test.gd:5 test-script-error Parse Error: Expected expression as the function argument." "$out"
	assert_eq "test_in_a_broken_suite	ERROR	tests/broken_test.gd:4
test_main_script_loads	ERROR	tests/main_test.gd:4" "$(results)"
}

test_scenarios_pass_and_fail_on_the_game_with_godot() {
	real_godot
	steps_project
	with_gdunit
	scenario_game holds breaks
	run_step prepare
	assert_status 0
	run_cmd bash tools/verify/scenarios
	assert_status 1
	assert_eq "breaks	FAILURE	scenarios/breaks.gd:11
holds	PASS	scenarios/holds.gd:6" "$out"
	run_cmd bash tools/verify/scenarios
	assert_eq "breaks	FAILURE	scenarios/breaks.gd:11
holds	PASS	scenarios/holds.gd:6" "$out" "a second run, after the first's report"
	run_step test
	assert_status 0
	assert_eq "test_main_script_loads	PASS	tests/main_test.gd:4" "$(results)" "the test step leaves the Scenarios out"
}

test_typecheck_passes_a_clean_project_with_godot() {
	real_godot
	steps_project
	with_gdunit
	run_step prepare
	run_step typecheck
	assert_status 0
	assert_eq "" "$out"
}

test_typecheck_reports_a_parse_error_with_godot() {
	real_godot
	steps_project
	with_gdunit
	add_gd parse_error src/bad.gd
	run_step prepare
	run_step typecheck
	assert_status 1
	assert_eq 'src/bad.gd:5 typecheck Parse Error: Variable "untyped" has no static type. (Warning treated as error.)' "$out"
}

test_typecheck_reports_warnings_below_error_with_godot() {
	real_godot
	steps_project
	with_gdunit
	sed -i '/^gdscript\/warnings\/unsafe_cast=2$/d; s#^gdscript/warnings/integer_division=2$#gdscript/warnings/integer_division=1#' project.godot
	sed -i '/^\[debug\]$/a gdscript/warnings/directory_rules={"res://addons": 0, "res://src": 0}' project.godot
	# The expected lines come from the file as written here, and the steps must
	# leave it as it is (a run that removed it under the test once looked like a
	# missing line).
	local level_line rule_line
	level_line="$(grep -n '^gdscript/warnings/integer_division=' project.godot | cut -d: -f1)"
	rule_line="$(grep -n '^gdscript/warnings/directory_rules=' project.godot | cut -d: -f1)"
	[ -n "$level_line" ] && [ -n "$rule_line" ] || fail "the fixture's project.godot lacks a line it sets"
	cp project.godot "$TEST_TMP/project.godot"
	run_step prepare
	run_step typecheck
	assert_status 1
	cmp -s "$TEST_TMP/project.godot" project.godot || fail "the steps rewrote project.godot:"$'\n'"$(diff "$TEST_TMP/project.godot" project.godot)"
	assert_eq "project.godot:$level_line typecheck-warning-level debug/gdscript/warnings/integer_division is Warn (1); the gate needs Error (2)
project.godot:8 typecheck-warning-level debug/gdscript/warnings/unsafe_cast is Ignore (0); the gate needs Error (2)
project.godot:$rule_line typecheck-directory-rule debug/gdscript/warnings/directory_rules excludes res://src; only res://addons may be excluded" "$(printf '%s\n' "$out" | LC_ALL=C sort)"
}

# The engine's exit-time resource report is left out (a sound still playing when
# --quit-after ends prints it); every other ERROR line is a finding.
test_smoke_leaves_out_only_the_exit_resource_report() {
	steps_project
	printf '\033[1;31mERROR: 2 resources still in use at exit\033[0m\r\n   at: clear (core/io/resource.cpp:822)\n' > "$TEST_TMP/godot.stderr"
	run_step smoke
	assert_status 0
	assert_eq "" "$out"
	printf 'ERROR: 2 resources still in use at exit\nERROR: Condition "x" is true.\n' > "$TEST_TMP/godot.stderr"
	run_step smoke
	assert_status 1
	assert_eq 'project.godot:1 smoke-error Condition "x" is true.' "$out"
}

test_smoke_reports_a_runtime_error_with_godot() {
	real_godot
	steps_project
	with_gdunit
	run_step prepare
	run_step smoke
	assert_status 0
	assert_eq "" "$out"
	add_gd smoke_error main.gd
	run_step smoke
	assert_status 1
	printf '%s\n' "$out" | grep -q '^main.gd:6 smoke-error ' || fail "no smoke-error at main.gd:6:"$'\n'"$out"
}

test_two_runs_give_identical_output_with_godot() {
	real_godot
	steps_project
	with_gdunit
	add_gd mixed_test tests/a/mixed_test.gd
	unset FACTORY_RESULTS_FILE
	run_verify --twice --keep-going prepare typecheck test smoke
	assert_status 1
	assert_last_line "verify: two runs match"
	assert_line "== test FAIL"
}

# --- mutate ---

# mutate_project: steps_project with tests/src/ and the calc fixture's base
# committed; MUTATE_BASE is that commit, and src/calc.gd is then changed (it adds
# double, which its own test checks, and triple, which no test checks).
mutate_project() {
	steps_project
	mkdir -p src tests/src
	cp "$GODOT_FIXTURES/mutate_calc_base.gd.txt" src/calc.gd || fail "no calc base"
	cp "$GODOT_FIXTURES/mutate_calc_test.gd.txt" tests/src/calc_test.gd || fail "no calc test"
	git add -A && git commit -q -m base || fail "commit failed"
	MUTATE_BASE="$(git rev-parse HEAD)"
	cp "$GODOT_FIXTURES/mutate_calc.gd.txt" src/calc.gd || fail "no calc"
}

# run_mutate: the mutate step by hand, as the runner would run it in the Green phase.
run_mutate() {
	FACTORY_SURVIVORS_FILE="$TEST_TMP/survivors.txt" FACTORY_MUTATE_BASE="$MUTATE_BASE" run_cmd bash tools/verify/mutate
}

# since_record: a script, `bash <it> <source> <ref>`, printing what gdmutant's
# --since reads of <source> as gdmutant runs git (from the source's folder, with
# no git location in the environment): the new side of each hunk of
# `git diff --unified=0 <ref>`, then whether git tracks the file.
since_record() {
	cat << 'SH'
path="$(realpath "$1")"
cd "$(dirname "$path")" || exit 1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX
diff="$(git diff --unified=0 "$2" -- "$path" 2>&1)" || diff="@@ - failed @@"
tracked=untracked
git ls-files --error-unmatch "$path" > /dev/null 2>&1 && tracked=tracked
echo "$1: $(sed -n 's/^@@ -[^ ]* \([^ ]*\) @@.*/\1/p' <<< "$diff" | tr '\n' ' ')$tracked"
SH
}

# fake_gdmutant: GDMUTANT_BIN becomes a script that prints `gdmutant 0.1.4` for
# --version. A run logs one line to $TEST_TMP/gdmutant.log: its arguments, with
# the step's temp folder (TMPDIR's parent) as <tmp>. The first run lists its
# --project's tree in $TEST_TMP/gdmutant.tree (a `<find's %y> ./<path>` line
# each), and each run appends each source's since_record (run from its folder)
# to $TEST_TMP/gdmutant.since. It then runs the --godot it was given with --path
# on the project and on two copies under TMPDIR, makes reports/report_1/ and
# .godot/ in its folder as gdUnit4 and Godot do, writes
# $TEST_TMP/gdmutant/<--tests, / as _>.json (else a report without mutants)
# where --json says, and exits with $TEST_TMP/gdmutant.exit (default 0).
fake_gdmutant() {
	export GDMUTANT_BIN="$TEST_TMP/fake_gdmutant"
	mkdir -p "$TEST_TMP/gdmutant"
	since_record > "$TEST_TMP/since_record"
	cat > "$GDMUTANT_BIN" << 'SH'
#!/usr/bin/env bash
dir="$(dirname "$0")"
[ "$1" = --version ] && echo "gdmutant 0.1.4" && exit 0
tmp="$(dirname "$TMPDIR")"
echo "${*//$tmp/<tmp>}" >> "$dir/gdmutant.log"
args=("$@") sources=()
for ((i = 1; i < ${#args[@]}; i++)); do
	case "${args[i]}" in
		--godot) godot="${args[i+1]}" ;;
		--project) project="${args[i+1]}" ;;
		--tests) tests="${args[i+1]#res://}" ;;
		--since) since="${args[i+1]}" ;;
		--json) json="${args[i+1]}" ;;
	esac
	case "${args[i]}" in
		--no-require-clean) ;;
		--*) i=$((i + 1)) ;;
		*) sources+=("${args[i]}") ;;
	esac
done
[ -e "$dir/gdmutant.tree" ] || (cd "$project" && find . -mindepth 1 -printf '%y %p\n' | LC_ALL=C sort -k 2) > "$dir/gdmutant.tree"
for src in "${sources[@]}"; do
	bash "$dir/since_record" "$src" "$since" >> "$dir/gdmutant.since"
done
for path in "$project" "$TMPDIR/w0" "$TMPDIR/w1"; do
	"$godot" --headless --path "$path" --version > /dev/null
done
mkdir -p reports/report_1 .godot && echo '<testsuites/>' > reports/report_1/results.xml
echo imported > .godot/written
report="$dir/gdmutant/${tests//\//_}.json"
if [ -f "$report" ]; then
	cp "$report" "$json"
else
	printf '{\n  "schemaVersion": "2",\n  "files": {}\n}\n' > "$json"
fi
exit "$(cat "$dir/gdmutant.exit" 2> /dev/null || echo 0)"
SH
	chmod +x "$GDMUTANT_BIN"
}

# gdmutant_report [<status> <mutator> <replacement> <line> <from> <to>]...: a report
# as gdmutant 0.1.4 writes it for src/calc.gd against tests/src/calc_test.gd, one
# mutant per argument (its columns count from 1, <to> past the change). The
# source is cut short: the step reads the file on disk.
gdmutant_report() {
	local id=0 m json="$TEST_TMP/gdmutant/tests_src_calc_test.gd.json"
	cat > "$json" << 'JSON'
{
  "schemaVersion": "2",
  "thresholds": {
    "high": 80,
    "low": 60
  },
  "files": {
    "src/calc.gd": {
      "language": "gdscript",
      "source": "extends RefCounted\n\n\nstatic func less_one(n: int) -> int:\n...",
      "mutants": [
JSON
	for m in "$@"; do
		# shellcheck disable=SC2086 # each case is its words
		set -- $m
		[ "$id" -eq 0 ] || echo "        },"
		cat << JSON
        {
          "id": "$id",
          "mutatorName": "$2",
          "replacement": "$3",
          "location": {
            "start": {
              "line": $4,
              "column": $5
            },
            "end": {
              "line": $4,
              "column": $6
            }
          },
          "status": "$1"$([ "$1" = Survived ] && printf ',\n          "description": "Your tests pass whether this number is 3 or 4."')
JSON
		id=$((id + 1))
	done >> "$json"
	printf '        }\n      ]\n    }\n  }\n}\n' >> "$json"
}

# One mutant of each status, on the calc fixture.
calc_report() {
	gdmutant_report "Killed numeric 2 9 13 14" "Survived numeric 4 13 13 14" "NoCoverage arithmetic + 13 11 12" \
		"CompileError statement-deletion pass 13 2 14" "RuntimeError statement-deletion pass 9 2 14" \
		"Timeout numeric 0 9 13 14" "Ignored arithmetic - 9 11 12"
}

test_mutate_refuses_to_run_without_the_runner() {
	steps_project
	run_cmd bash tools/verify/mutate
	assert_status 2
	assert_eq "" "$out"
}

# Only Linux Godot keeps user:// under XDG_DATA_HOME (pass 1 of #88's amend
# review: macOS Godot would share it).
test_mutate_refuses_to_run_off_linux() {
	mutate_project
	fake_gdmutant
	mkdir -p "$TEST_TMP/bin"
	printf '#!/bin/sh\necho Darwin\n' > "$TEST_TMP/bin/uname"
	chmod +x "$TEST_TMP/bin/uname"
	PATH="$TEST_TMP/bin:$PATH" run_mutate
	assert_status 1
	assert_eq "tools/verify/mutate:1 mutate-unsupported this is Darwin, not Linux: the step keeps each Godot's user:// apart through XDG_DATA_HOME, which only Linux Godot reads; where it can't run, declare it a no-op" "$out"
	[ ! -e "$TEST_TMP/gdmutant.log" ] || fail "gdmutant ran: $(cat "$TEST_TMP/gdmutant.log")"
}

test_mutate_without_gdmutant_is_a_finding() {
	mutate_project
	GDMUTANT_BIN="$TEST_TMP/no-such-gdmutant" run_mutate
	assert_status 1
	assert_eq "tools/verify/local.env:1 gdmutant-missing '$TEST_TMP/no-such-gdmutant' doesn't run; install gdmutant (pinned in tools/verify/pins), or set GDMUTANT_BIN in tools/verify/local.env" "$out"
	[ ! -e "$TEST_TMP/survivors.txt" ] || fail "a survivors file from a step that couldn't run"
}

# A source with its own test file runs against it; one without, against its test
# folder; one with neither, against all of tests/. Sources that share a target
# share a run; tests, deleted files, files out of scope and unchanged ones aren't
# mutated.
test_mutate_runs_each_changed_source_against_its_own_tests() {
	mutate_project
	fake_gdmutant
	mkdir -p other addons/kit
	echo 'extends Node' > src/gone.gd
	git add src/gone.gd && git commit -q -m gone && MUTATE_BASE="$(git rev-parse HEAD)"
	git rm -q src/gone.gd
	for f in src/util.gd src/more.gd other/thing.gd addons/kit/kit.gd tests/src/util_test_helper.gd; do
		echo 'extends Node' > "$f"
	done
	GDMUTANT_JOBS=5 run_mutate
	assert_status 0
	assert_eq "" "$out"
	local args="--runner gdunit4 --godot <tmp>/godot --project <tmp>/project"
	local rest="--since $MUTATE_BASE --jobs 5 --progress none --no-require-clean"
	assert_eq "run $args --tests res://tests $rest --json <tmp>/report-1.json other/thing.gd
run $args --tests res://tests/src $rest --json <tmp>/report-2.json src/more.gd src/util.gd
run $args --tests res://tests/src/calc_test.gd $rest --json <tmp>/report-3.json src/calc.gd" "$(cat "$TEST_TMP/gdmutant.log")"
}

test_mutate_always_runs_at_least_two_jobs() {
	mutate_project
	fake_gdmutant
	GDMUTANT_JOBS=1 run_mutate
	assert_status 0
	grep -q -- ' --jobs 2 ' "$TEST_TMP/gdmutant.log" || fail "not --jobs 2: $(cat "$TEST_TMP/gdmutant.log")"
}

# Survivors (and ignored mutants) are listed for the Verifier, sorted by place;
# killed, errored and timed-out ones are only counted.
test_mutate_writes_the_survivors_file_from_the_report() {
	mutate_project
	fake_gdmutant
	calc_report
	run_mutate
	assert_status 0
	assert_eq "src/calc.gd:9 mutant-ignored arithmetic: \`*\` -> \`-\`; tests: tests/src/calc_test.gd
src/calc.gd:13 mutant-survived arithmetic: \`*\` -> \`+\`; tests: tests/src/calc_test.gd
src/calc.gd:13 mutant-survived numeric: \`3\` -> \`4\`; tests: tests/src/calc_test.gd" "$out"
	assert_eq "# gdmutant 0.1.4 on the GDScript lines changed since $(git rev-parse --short "$MUTATE_BASE"), each source against its own tests (tools/verify/mutate)
# killed 1, survived 2, errored 2, timed out 1, ignored 1
src/calc.gd:9 ignored arithmetic: \`*\` -> \`-\`; tests: tests/src/calc_test.gd
src/calc.gd:13 survived arithmetic: \`*\` -> \`+\`; tests: tests/src/calc_test.gd
src/calc.gd:13 survived numeric: \`3\` -> \`4\`; tests: tests/src/calc_test.gd" "$(cat "$TEST_TMP/survivors.txt")"
}

# A tab in the changed code would split the line's fields (pass 1 of #88's amend
# review): it shows as \t.
test_mutate_shows_a_tab_in_the_changed_code_as_backslash_t() {
	mutate_project
	fake_gdmutant
	printf '\tprint("a\tb")\n' >> src/calc.gd
	gdmutant_report "Survived statement-deletion pass 14 2 14"
	run_mutate
	assert_status 0
	assert_eq 'src/calc.gd:14 survived statement-deletion: `print("a\tb")` -> `pass`; tests: tests/src/calc_test.gd' "$(tail -n 1 "$TEST_TMP/survivors.txt")"
}

test_mutate_with_no_changed_source_writes_a_file_without_mutants() {
	mutate_project
	fake_gdmutant
	git checkout -q -- src/calc.gd
	echo '# more' >> tests/src/calc_test.gd
	run_mutate
	assert_status 0
	assert_eq "" "$out"
	[ ! -e "$TEST_TMP/gdmutant.log" ] || fail "gdmutant ran: $(cat "$TEST_TMP/gdmutant.log")"
	assert_eq "# killed 0, survived 0, errored 0, timed out 0, ignored 0
# no changed GDScript source to mutate" "$(tail -n +2 "$TEST_TMP/survivors.txt")"
}

test_mutate_fails_when_gdmutant_fails() {
	mutate_project
	fake_gdmutant
	echo 2 > "$TEST_TMP/gdmutant.exit"
	run_mutate
	assert_status 1
	assert_eq "tools/verify/mutate:1 mutate-failed gdmutant exited 2 mutating src/calc.gd against res://tests/src/calc_test.gd (its output is on stderr)" "$out"
	[ ! -e "$TEST_TMP/survivors.txt" ] || fail "a survivors file from a failed run"
}

# Each project path Godot is started on (the project, each worker's copy) gets
# user data of its own, none of it the session's, all in the step's temp folder.
test_mutate_keeps_each_godot_s_user_data_apart() {
	mutate_project
	fake_gdmutant
	export GODOT_BIN="$TEST_TMP/env_godot"
	printf '#!/usr/bin/env bash\necho "$XDG_DATA_HOME $XDG_CONFIG_HOME $TMPDIR" >> "%s/godot.env"\n' "$TEST_TMP" > "$GODOT_BIN"
	chmod +x "$GODOT_BIN"
	XDG_DATA_HOME="$TEST_TMP/session" run_mutate
	assert_status 0
	local tmp
	tmp="$(sed -n 's/^\([^ ]*\)\/user\/.*/\1/p' "$TEST_TMP/godot.env" | sort -u)"
	[ "$(printf '%s\n' "$tmp" | wc -l)" -eq 1 ] && [ -n "$tmp" ] || fail "not one temp folder: $(cat "$TEST_TMP/godot.env")"
	[ ! -e "$tmp" ] || fail "the step left its temp folder $tmp"
	assert_eq 3 "$(cut -d ' ' -f 1 "$TEST_TMP/godot.env" | sort -u | wc -l)" "user data folders, one per project path"
	assert_eq 3 "$(cut -d ' ' -f 2 "$TEST_TMP/godot.env" | sort -u | wc -l)" "config folders, one per project path"
	assert_eq "$tmp/work" "$(cut -d ' ' -f 3 "$TEST_TMP/godot.env" | sort -u)" "TMPDIR, where gdmutant copies the project"
	! grep -q "$TEST_TMP/session" "$TEST_TMP/godot.env" || fail "a Godot got the session's user data"
}

# gdmutant runs in the step's copy, so what it, Godot and gdUnit4 write there
# (.godot/, reports/) never reaches the project.
test_mutate_leaves_the_project_as_it_was() {
	mutate_project
	fake_gdmutant
	mkdir -p .godot reports && echo cache > .godot/mine && echo report > reports/mine
	local before
	before="$(git status --porcelain --ignored && find . -path ./.git -prune -o -print | LC_ALL=C sort)"
	run_mutate
	assert_status 0
	assert_eq "$before" "$(git status --porcelain --ignored && find . -path ./.git -prune -o -print | LC_ALL=C sort)"
}

# gdmutant copies its --project once per worker, which was 1.3 GB a worker in a
# main checkout, of gitignored Android builds and exports (#191 item 6). So its
# --project is the step's copy of what Godot and the tests need: what git tracks
# or would, as it is on disk, and .godot/'s import cache. A symlink to a file in
# the copy stays one; one to a file left out becomes a copy of it. Not what git
# ignores, a deleted file, the factory's own folder (but a source there the scope
# takes back), the export and shader caches, the steps' scratch, or a secret
# (.env*, tools/verify/secret-paths' globs and folders, the export credentials).
# The secrets are unreadable, as in the Verifier's sandbox: the step reads none.
test_mutate_copies_only_what_godot_and_the_tests_need() {
	mutate_project
	fake_gdmutant
	printf '/build/\n/android/\n' >> .gitignore
	printf 'keys/*.key\nprivate\n' >> tools/verify/secret-paths
	mkdir -p factory/core factory/kit build android/build assets keys private
	echo 'echo tool' > factory/core/tool.sh
	echo 'extends Node' > factory/kit/probe.gd
	echo 'factory/kit/probe.gd' >> tools/verify/scope
	echo png > build/icon.png
	ln -s ../build/icon.png assets/icon.png
	ln -s ../main.tscn assets/alias.tscn
	echo old > old.txt
	echo key > keys/game.key
	echo notes > keys/notes.txt
	echo data > private/data.txt
	git add .gitignore factory assets keys private old.txt tools/verify && git commit -q -m more || fail "commit failed"
	MUTATE_BASE="$(git rev-parse HEAD)"
	rm old.txt
	echo 'extends Node # changed' > factory/kit/probe.gd
	head -c 1000000 /dev/zero > android/build/big.bin
	echo '[gd_scene format=3]' > fresh.tscn
	echo 'TOKEN=1' > .env
	echo 'TOKEN=' > .env.example
	mkdir -p .godot/imported .godot/exported .godot/shader_cache .godot/factory
	local f secrets=(.env keys/game.key private/data.txt .godot/export_credentials.cfg)
	for f in .gdignore uid_cache.bin imported/icon.png-1.ctex export_credentials.cfg exported/cache shader_cache/cache factory/smoke.log; do
		echo cache > ".godot/$f"
	done
	chmod 000 "${secrets[@]}"
	run_mutate
	chmod 644 "${secrets[@]}"
	assert_status 0
	local expected="f ./.env.example
f ./.git
f ./.gitignore
d ./.godot
f ./.godot/.gdignore
d ./.godot/imported
f ./.godot/imported/icon.png-1.ctex
f ./.godot/uid_cache.bin
d ./assets
l ./assets/alias.tscn
f ./assets/icon.png
f ./export_presets.cfg
d ./factory
d ./factory/kit
f ./factory/kit/probe.gd
f ./fresh.tscn
d ./keys
f ./keys/notes.txt
f ./main.gd
f ./main.tscn
f ./project.godot
d ./src
f ./src/calc.gd
d ./tests
f ./tests/main_test.gd
d ./tests/src
f ./tests/src/calc_test.gd"
	assert_eq "$expected" "$(grep -v '^. \./tools' "$TEST_TMP/gdmutant.tree")"
	grep -qxF 'f ./tools/verify/mutate' "$TEST_TMP/gdmutant.tree" || fail "the copy lacks the tracked tools/"
	! grep -q 'local\.env$' "$TEST_TMP/gdmutant.tree" || fail "the copy has the ignored local.env"
}

# cp --parents gave a folder its read-only mode before its second file was in
# (pass 1 of the review): a read-only folder is copied whole, and the step's temp
# folder still goes.
test_mutate_copies_a_read_only_folder() {
	mutate_project
	fake_gdmutant
	mkdir -p assets && echo a > assets/a.png && echo b > assets/b.png
	git add assets && git commit -q -m assets || fail "commit failed"
	MUTATE_BASE="$(git rev-parse HEAD)"
	chmod 555 assets
	mkdir -p "$TEST_TMP/step-tmp"
	TMPDIR="$TEST_TMP/step-tmp" run_mutate
	chmod 755 assets
	assert_status 0
	grep -qxF 'f ./assets/a.png' "$TEST_TMP/gdmutant.tree" && grep -qxF 'f ./assets/b.png' "$TEST_TMP/gdmutant.tree" ||
		fail "the copy lacks a file of assets/: $(cat "$TEST_TMP/gdmutant.tree")"
	assert_eq "" "$(ls -A "$TEST_TMP/step-tmp")" "what the step left in its temp folder"
}

# A .godot/ that is a symlink to a folder elsewhere is copied as that folder,
# still less its export cache and credentials, unreadable here (pass 2 of the
# review). steps_project ignores .godot/, which git doesn't match to a symlink.
test_mutate_copies_a_symlinked_godot_folder_less_its_caches() {
	mutate_project
	fake_gdmutant
	local cache="$TEST_TMP/cache"
	mkdir -p "$cache/imported" "$cache/exported"
	echo cache > "$cache/imported/icon.png-1.ctex"
	echo build > "$cache/exported/build.bin"
	echo secret > "$cache/export_credentials.cfg"
	chmod 000 "$cache/exported/build.bin" "$cache/export_credentials.cfg"
	ln -s "$cache" .godot
	run_mutate
	chmod 644 "$cache/exported/build.bin" "$cache/export_credentials.cfg"
	assert_status 0
	assert_eq "d ./.godot
d ./.godot/imported
f ./.godot/imported/icon.png-1.ctex" "$(grep ' \./\.godot' "$TEST_TMP/gdmutant.tree")"
}

# gdmutant's --since runs git from each source's folder, on the file a symlink
# names: in the copy it finds the same changed lines as in the project, for a
# changed, an added and an untracked file (untracked, gdmutant mutates every
# line), and the inputs of pass 1 of the review: a symlink pointed at another
# file, and a file git assumes unchanged (its index flag kept).
test_mutate_finds_the_same_changed_lines_in_the_copy() {
	mutate_project
	fake_gdmutant
	local f
	for f in legacy modern kept; do
		cp "$GODOT_FIXTURES/mutate_calc.gd.txt" "src/$f.gd" || fail "no calc"
	done
	ln -s legacy.gd src/active.gd
	git add src/legacy.gd src/modern.gd src/kept.gd src/active.gd && git commit -q -m more || fail "commit failed"
	MUTATE_BASE="$(git rev-parse HEAD)"
	sed -i 's/n - 1/n - 2/' src/kept.gd && git commit -q -m kept src/kept.gd || fail "commit failed"
	git update-index --assume-unchanged src/kept.gd
	sed -i 's/n \* 3/n * 4/' src/kept.gd src/modern.gd
	ln -sfn modern.gd src/active.gd
	echo 'extends Node' > src/fresh.gd
	printf 'extends Node\nvar a := 1\n' > src/added.gd
	git add src/added.gd
	run_mutate
	assert_status 0
	local expected="src/active.gd: +13 tracked
src/added.gd: +1,2 tracked
src/calc.gd: +6,8 tracked
src/fresh.gd: untracked
src/kept.gd: +5 tracked
src/modern.gd: +13 tracked"
	assert_eq "$expected" "$(for f in active added calc fresh kept modern; do bash "$TEST_TMP/since_record" "src/$f.gd" "$MUTATE_BASE"; done)" "in the project"
	assert_eq "$expected" "$(LC_ALL=C sort "$TEST_TMP/gdmutant.since")" "in the copy"
}

# The copy is made from the project root, and gdmutant runs in it: a relative
# GDMUTANT_BIN or GODOT_BIN names a program from the project root still.
test_mutate_runs_a_relative_gdmutant_and_godot_from_the_project_root() {
	mutate_project
	fake_gdmutant
	GDMUTANT_BIN=../fake_gdmutant GODOT_BIN=../fake_godot run_mutate
	assert_status 0
	assert_eq "" "$out"
	assert_eq 3 "$(grep -c -- '--headless --path .* --version' "$TEST_TMP/godot.log")" "Godot runs, on the copy and two workers'"
}

# A source the copy can't take, as root's copy can't be stopped by a mode: cp
# refuses main.gd.
test_mutate_fails_when_the_copy_cant_be_made() {
	mutate_project
	fake_gdmutant
	refusing_stand_in cp main.gd
	run_mutate
	assert_status 1
	assert_eq "tools/verify/mutate:1 mutate-failed could not copy the project for gdmutant (the output is on stderr)" "$out"
	[ ! -e "$TEST_TMP/gdmutant.log" ] || fail "gdmutant ran: $(cat "$TEST_TMP/gdmutant.log")"
	[ ! -e "$TEST_TMP/survivors.txt" ] || fail "a survivors file from a step that couldn't run"
}

test_version_probe_reports_gdmutant() {
	steps_project
	fake_gdmutant
	GODOT_BIN="" GDSCRIPT_FORMATTER=no-such-formatter run_cmd bash tools/verify/versions
	assert_status 0
	assert_eq "gdmutant 0.1.4" "$out"
}

# gdmutant_limit: after mutate_project, commit the mutate_gdmutant.toml fixture
# as .gdmutant.toml, which gives gdmutant a fixed limit of 900 s a mutant, and
# run the step with 2 workers. gdmutant reads the file from the folder it runs
# in, the step's copy, which holds every file git lists. Its own limit, about
# the baseline's time plus 8 s, counted a Godot's wait for a slot of
# isolated_godot.sh, so a busy machine timed out a surviving mutant (#2, #3).
# Only the tests that run the real gdmutant call it: the other tests' copies
# stay as they were.
gdmutant_limit() {
	cp "$GODOT_FIXTURES/mutate_gdmutant.toml.txt" .gdmutant.toml || fail "no gdmutant settings"
	git add .gdmutant.toml && git commit -q -m limit || fail "commit failed"
	export GDMUTANT_JOBS=2
}

test_mutate_lists_a_survivor_and_counts_a_kill_and_an_error_with_gdmutant() {
	real_godot
	real_gdmutant
	mutate_project
	gdmutant_limit
	with_gdunit
	run_mutate
	assert_status 0
	assert_eq "# gdmutant 0.1.4 on the GDScript lines changed since $(git rev-parse --short "$MUTATE_BASE"), each source against its own tests (tools/verify/mutate)
# killed 2, survived 2, errored 2, timed out 0, ignored 0
src/calc.gd:13 survived numeric: \`3\` -> \`2\`; tests: tests/src/calc_test.gd
src/calc.gd:13 survived numeric: \`3\` -> \`4\`; tests: tests/src/calc_test.gd" "$(cat "$TEST_TMP/survivors.txt")"
	git diff --quiet "$MUTATE_BASE" -- src/calc.gd && fail "src/calc.gd lost its change"
	cmp -s "$GODOT_FIXTURES/mutate_calc.gd.txt" src/calc.gd || fail "the run rewrote src/calc.gd"
}

# Every Godot gdmutant starts runs on a copy in the step's temp folder (the
# step's, for the baseline, and one per worker), never on the project, and no
# copy holds the large gitignored build/ (#191 item 6), or an unreadable secret.
# GODOT_BIN logs each one's --path folder and whether build/ is in it. Not the
# fixture's test: a mutant that breaks src/calc.gd's load runs none, and a
# worker can get only those mutants (#3).
test_mutate_runs_godot_only_on_copies_without_ignored_folders_with_gdmutant() {
	real_godot
	real_gdmutant
	mutate_project
	gdmutant_limit
	with_gdunit
	echo '/build/' >> .gitignore
	mkdir -p build .godot && head -c 50000000 /dev/zero > build/big.bin
	# Secrets the Verifier's sandbox denies: gdmutant copying them failed there.
	echo TOKEN=1 > .env && echo secret > .godot/export_credentials.cfg
	chmod 000 .env .godot/export_credentials.cfg
	export MUTATE_COPIES="$TEST_TMP/copies" MUTATE_REAL_GODOT="$GODOT_BIN" GODOT_BIN="$TEST_TMP/logging_godot"
	cat > "$GODOT_BIN" << 'SH'
#!/usr/bin/env bash
path="" prev=""
for arg in "$@"; do
	[ "$prev" = --path ] && path="$arg"
	prev="$arg"
done
if [ -n "$path" ]; then
	build=false
	[ -d "$path/build" ] && build=true
	dir="$(cd "$path" && pwd -P)" || dir="$path"
	echo "$dir/ build:$build" >> "$MUTATE_COPIES"
fi
exec "$MUTATE_REAL_GODOT" "$@"
SH
	chmod +x "$GODOT_BIN"
	run_mutate
	chmod 644 .env .godot/export_credentials.cfg
	assert_status 0
	local seen
	seen="$(LC_ALL=C sort -u "$MUTATE_COPIES")"
	[ "$(printf '%s\n' "$seen" | wc -l)" -ge 3 ] || fail "not the step's copy and one per worker: $seen"
	! grep -q "^$(pwd -P)/" <<< "$seen" || fail "a Godot ran on the project itself: $seen"
	! grep -q "build:true$" <<< "$seen" || fail "a copy holds the ignored build/: $seen"
	grep -q "build:false$" <<< "$seen" || fail "no record: $seen"
}

# The real Godot, not isolated_godot.sh (which sets its own user data): the
# fixture's test writes where each Godot keeps user://.
test_mutate_gives_each_worker_its_own_user_data_with_gdmutant() {
	real_godot
	real_gdmutant
	mutate_project
	gdmutant_limit
	with_gdunit
	export GODOT_BIN="$FACTORY_TEST_GODOT" MUTATE_USER_LOG="$TEST_TMP/user"
	mkdir -p "$MUTATE_USER_LOG"
	XDG_DATA_HOME="$TEST_TMP/session" run_mutate
	assert_status 0
	local dirs
	dirs="$(cat "$MUTATE_USER_LOG"/* | sort -u)"
	[ "$(printf '%s\n' "$dirs" | wc -l)" -ge 2 ] || fail "not a user data folder per project copy: $dirs"
	! grep -q "^$TEST_TMP/\(session\|appdata\)/" <<< "$dirs" || fail "a Godot used the session's user data: $dirs"
}
