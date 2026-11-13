# The Godot adapter's verify-<project> generator (verify-skill.sh), through the
# Core's factory/core/verify-skill.sh, on small made-up projects. None needs
# Godot.

generate() {
	run_cmd bash "$FACTORY_CORE/verify-skill.sh" --adapter godot "$@"
}

# small_project: $TEST_TMP/project (no git), a Godot project named "Small Game"
# whose main scene is a uid://, with input actions, a preset, a tool script, a
# mirrored and an unmirrored folder, a root script, and files the map leaves out
# (addons/, tests/, tools/, a .gdignore folder, a dot folder); cd there.
small_project() {
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "could not make the project"
	unset FACTORY_PROJECT
	mkdir -p main menu/screens addons/lib tests/main tools junk .hidden
	cat > project.godot << 'CFG'
config_version=5

[application]

config/name="Small Game"
run/main_scene="uid://bmain"

[display]

window/size/viewport_width=640
window/size/viewport_height=360

[input]

jump={
"deadzone": 0.5
}
ui_fire={
}
CFG
	printf '[preset.0]\n\nname="Web"\nplatform="Web"\n' > export_presets.cfg
	printf '[gd_scene format=3 uid="uid://bmain"]\n' > main/main.tscn
	printf '[gd_scene format=3 uid="uid://bmenu"]\n' > menu/screens/title.tscn
	echo "extends Node" | tee main/main.gd main/helper.gd menu/screens/title.gd boot.gd addons/lib/lib.gd tests/main/main_test.gd tools/probe.gd junk/old.gd .hidden/x.gd > /dev/null
	: > junk/.gdignore
	printf '#!/usr/bin/env bash\n# Runs the game on a phone. Run from the root:\n#   bash tools/run.sh\n' > tools/run.sh
	printf '#!/usr/bin/env bash\necho hi\n' > tools/bare.sh
	echo "# Terms" > CONTEXT.md
}

test_the_small_project_skill_and_feature_map() {
	small_project
	generate --out "$TEST_TMP/skill"
	assert_status 0
	local skill="$TEST_TMP/skill/SKILL.md" map="$TEST_TMP/skill/feature-map.md"
	grep -qxF "name: verify-project" "$skill" || fail "the skill isn't named after the folder"
	grep -qF 'Launch, drive and inspect a running Small Game build' "$skill" || fail "no display name in the description"
	grep -qF '**Main scene** (`res://main/main.tscn`)' "$skill" || fail "the uid:// main scene isn't resolved"
	grep -qxF -- '- **Input actions** (project.godot): `jump`, `ui_fire`.' "$skill" || fail "wrong input actions"
	grep -qxF -- '- **Viewport**: 640x360; on a device, scale tap coordinates to its screen.' "$skill" || fail "wrong viewport"
	grep -qF 'Presets: "Web" (Web).' "$skill" || fail "wrong presets"
	grep -qxF -- '  - `bash tools/run.sh`: Runs the game on a phone.' "$skill" || fail "wrong tool line"
	grep -qxF -- '  - `bash tools/bare.sh`' "$skill" || fail "a tool without a header should be bare"
	grep -qF 'Names follow `CONTEXT.md`.' "$skill" || fail "no domain-doc pointer"
	grep -qF 'read `docs/agents/devices.md`' "$skill" && fail "a devices doc it doesn't have"
	assert_eq '| `./` |  | boot.gd | none |
| `main/` | main.tscn | helper.gd, main.gd | `tests/main/` |
| `menu/screens/` | title.tscn | title.gd | none |' "$(grep '^| `' "$map")" "the feature map rows"
}

test_a_bare_project_still_gets_every_section() {
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "no project"
	FACTORY_PROJECT=bare run_cmd bash "$FACTORY_CORE/verify-skill.sh" --adapter godot --out "$TEST_TMP/skill"
	assert_status 0
	grep -qF '**No main scene**' "$TEST_TMP/skill/SKILL.md" || fail "no main-scene fallback"
	grep -qF 'project.godot defines none' "$TEST_TMP/skill/SKILL.md" || fail "no input-actions fallback"
}

test_the_small_project_twice_is_identical() {
	small_project
	generate --out "$TEST_TMP/one"
	generate --out "$TEST_TMP/two"
	diff -r "$TEST_TMP/one" "$TEST_TMP/two" > /dev/null || fail "two runs differ"
}

# A long display name doesn't push the description past its 200 characters: the
# name is left out of it.
test_a_long_project_name_is_left_out_of_the_description() {
	small_project
	sed -i 's/^config\/name="Small Game"$/config\/name="A Game Whose Display Name Runs On Well Past Any Budget"/' project.godot
	generate --out "$TEST_TMP/skill"
	assert_status 0
	grep -qF 'a running build of this Godot project,' "$TEST_TMP/skill/SKILL.md" || fail "the long name wasn't left out"
}

# Generating elsewhere (--out) writes nothing into the project, not even the same
# bytes over its own committed skill: every project file keeps its old mtime.
test_generating_elsewhere_leaves_the_project_untouched() {
	small_project
	isolate_git
	git init -q . && generate && git add -A && git commit -q -m project || fail "could not commit the project"
	find . -path ./.git -prune -o -type f -exec touch -t 200001010000 {} +
	touch -t 200001020000 "$TEST_TMP/stamp"
	generate --out "$TEST_TMP/elsewhere"
	assert_status 0
	diff -r .claude/skills/verify-project "$TEST_TMP/elsewhere" > /dev/null || fail "the two skills differ"
	assert_eq "" "$(find . -path ./.git -prune -o -type f -newer "$TEST_TMP/stamp" -print)" "it wrote into the project"
	assert_eq "" "$(git status --porcelain)" "it changed the project"
}
