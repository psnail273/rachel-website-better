# The Core's pre-commit hook on a Godot project: the adapter's arch template
# (tools/verify/arch) supplies the static checks, R7's @warning_ignore ban among
# them. The checks registered as `runtime` (they run Godot) are left to the full
# verify.

GODOT_ADAPTER="$FACTORY_CORE/../adapters/godot"

# godot_repo <mode>: a git repo holding the arch step, the _gdscript.sh it sources,
# its probe and an ARCHITECTURE.md that cites every check, with the hook mode
# committed and the pre-commit hook on. GODOT_BIN is unset, so a runtime check that
# ran would report that it needs Godot.
godot_repo() {
	mkdir -p "$TEST_TMP/project/tools/verify" && cd "$TEST_TMP/project" || fail "could not make the project"
	unset GODOT_BIN
	isolate_git
	cp "$GODOT_ADAPTER/tools/verify/arch" "$GODOT_ADAPTER/tools/verify/_gdscript.sh" "$GODOT_ADAPTER/tools/verify/_arch_probe.gd" tools/verify/
	cat > ARCHITECTURE.md << 'MD'
# Architecture

## Layers

`main` → `game` → `ui/screens` | `ui/hud` | `ui/overlays` → `playfield` → `levels` → `config`

## Rules

**R1.** No autoloads.
Enforced by: `arch:no-autoloads`

**R2.** GameModel is plain.
Enforced by: `arch:model-plain`

**R4.** Dependencies go down the layer line.
Enforced by: `arch:layers`

**R5.** Signals go up.
Enforced by: `arch:signals-up`

**R6.** No reaching up.
Enforced by: `arch:no-reach-up`

**R7.** No warning suppressions.
Enforced by: `arch:no-warning-ignore`

**R8.** Mirrored tests.
Enforced by: `arch:mirrored-tests`

**R9.** Naming.
Enforced by: `arch:naming`

**R10.** Third-party code under addons/.
Enforced by: `arch:third-party`

**R11.** @tool scripts are allowlisted.
Enforced by: `arch:tool-allowlist`

**R12.** No sideways references.
Enforced by: `arch:no-sideways-refs`

**R13.** No tunable consts.
Enforced by: `arch:no-tunable-consts`

**R14.** No .new() on visual nodes.
Enforced by: `arch:no-visual-new`

**R15.** Product code never checks how it is run.
Enforced by: `arch:run-mode`
MD
	printf '[application]\nconfig/name="Fixture"\n' > project.godot
	echo "$1" > tools/verify/hook-mode
	git init -q -b dev . || fail "git init failed"
	git config core.hooksPath "$FACTORY_CORE/hooks/githooks"
	git add -A && git commit -q -m "fixture" || fail "could not commit the fixture"
}

# script <body>: stage game/go.gd with the body, and its mirrored test (R8).
script() {
	mkdir -p game tests/game
	printf '%b' "$1" > game/go.gd
	printf 'extends GdUnitTestSuite\n\n\nfunc test_go() -> void:\n\tassert_bool(true).is_true()\n' > tests/game/go_test.gd
	git add game/go.gd tests/game/go_test.gd
}

suppressed_script() {
	script 'extends Node\n\n@warning_ignore("unused_variable")\nfunc go() -> void:\n\tpass\n'
}

clean_script() {
	script 'extends Node\n\n\nfunc go() -> void:\n\tpass\n'
}

test_armed_pre_commit_refuses_a_warning_ignore() {
	godot_repo enforce
	suppressed_script
	run_cmd git commit -q -m "suppress"
	assert_status 1
	grep -qF 'pre-commit: game/go.gd:3 R7 suppresses a warning with @warning_ignore; fix the code instead' "$TEST_TMP/stderr" ||
		fail "no R7 finding:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

test_adopted_pre_commit_reports_a_warning_ignore() {
	godot_repo report
	suppressed_script
	run_cmd git commit -q -m "suppress"
	assert_status 0
	grep -qF 'pre-commit: game/go.gd:3 R7 ' "$TEST_TMP/stderr" || fail "no R7 finding:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

test_armed_pre_commit_passes_clean_gdscript() {
	godot_repo enforce
	clean_script
	run_cmd git commit -q -m "clean"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")"
}

# The runtime checks (R2 model-plain, R5 signals-up, R12 no-sideways-refs) would
# each report that they need Godot; pre-commit skips them, so nothing is reported.
test_pre_commit_skips_the_runtime_checks_without_godot() {
	godot_repo report
	clean_script
	run_cmd git commit -q -m "clean"
	assert_status 0
	grep -q '_arch_probe.gd\|needs Godot\| R2 \| R5 \| R12 ' "$TEST_TMP/stderr" &&
		fail "a runtime check ran in pre-commit:"$'\n'"$(cat "$TEST_TMP/stderr")"
	return 0
}

# R4 and R8 are static, so pre-commit runs them.
test_armed_pre_commit_refuses_a_script_without_its_mirrored_test() {
	godot_repo enforce
	clean_script
	git rm -q --cached tests/game/go_test.gd
	run_cmd git commit -q -m "untested"
	assert_status 1
	grep -qF 'pre-commit: game/go.gd:1 R8 has no test at tests/game/go_test.gd' "$TEST_TMP/stderr" ||
		fail "no R8 finding:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

test_armed_pre_commit_refuses_a_dependency_up_the_layer_line() {
	godot_repo enforce
	clean_script
	mkdir -p playfield tests/playfield
	printf 'class_name Board\nextends Node\n' > playfield/board.gd
	printf 'extends Node\n\n\nfunc go() -> void:\n\tvar g := Go.new()\n' > playfield/up.gd
	printf 'class_name Go\nextends Node\n\n\nfunc go() -> void:\n\tpass\n' > game/go.gd
	for f in board up; do
		printf 'extends GdUnitTestSuite\n\n\nfunc test_it() -> void:\n\tassert_bool(true).is_true()\n' > "tests/playfield/${f}_test.gd"
	done
	git add -A
	run_cmd git commit -q -m "up"
	assert_status 1
	grep -qF 'pre-commit: playfield/up.gd:5 R4 ' "$TEST_TMP/stderr" ||
		fail "no R4 finding:"$'\n'"$(cat "$TEST_TMP/stderr")"
}
