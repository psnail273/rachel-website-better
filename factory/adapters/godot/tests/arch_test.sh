# The Godot arch step (tools/verify/arch), run through the Core runner on a small
# throwaway project. Each rule finds a planted violation and passes the clean
# version; the sync check runs on the adapter's default rules.
#
# The tests that run Godot (the probe, for R2, R5 and R12) end in _with_godot
# (tests/names_test.sh holds it) and skip without GODOT_BIN.

GODOT_ADAPTER="$FACTORY_CORE/../adapters/godot"
. "$GODOT_ADAPTER/tests/lib.sh"

# The grep checks: a test project cites these unless it names others.
GREP_CHECKS="no-autoloads no-reach-up no-warning-ignore naming third-party tool-allowlist no-tunable-consts no-visual-new run-mode"

# godot_project [id...]: an empty project in $TEST_TMP/project holding the arch step,
# the _gdscript.sh it sources and an ARCHITECTURE.md whose rules cite exactly these
# checks (default: the grep checks); the step keeps only those checks, so the sync
# check passes, and names GameModel its plain model, rules its plain-model folder
# and high_scores (used by main) its leaf. cd there.
godot_project() {
	local ids="${*:-$GREP_CHECKS}" id
	mkdir -p "$TEST_TMP/project/tools/verify/ratchet" "$TEST_TMP/project/.fixture"
	cd "$TEST_TMP/project" || fail "could not enter the project"
	cp "$GODOT_ADAPTER/tools/verify/arch" "$GODOT_ADAPTER/tools/verify/_gdscript.sh" "$GODOT_ADAPTER/tools/verify/_arch_probe.gd" tools/verify/
	sed -i -e "s/^PLAIN_MODELS=''$/PLAIN_MODELS='GameModel'/" -e "s/^PLAIN_MODEL_DIRS=''$/PLAIN_MODEL_DIRS='rules'/" -e "s/^LAYER_LEAVES=''$/LAYER_LEAVES='high_scores:main'/" tools/verify/arch
	# shellcheck disable=SC2013 # one check id per word
	for id in $(sed -n 's/^factory_arch_check \([a-z-]*\) .*/\1/p' tools/verify/arch); do
		case " $ids " in *" $id "*) ;; *) sed -i "/^factory_arch_check $id /d" tools/verify/arch ;; esac
	done
	{
		cat << 'DOC'
# Architecture

## Layers

`main` → `game` → `ui/screens` | `ui/hud` | `ui/overlays` → `playfield` → `levels` → `config`

## Rules
DOC
		cat << 'DOC' | awk -v RS= -v ids=" $ids " '{ id = $0; sub(/^.*`arch:/, "", id); sub(/`.*$/, "", id); if (index(ids, " " id " ")) printf "\n%s\n", $0 }'
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
Enforced by: `arch:tool-allowlist`, `review`

**R12.** No sideways references.
Enforced by: `arch:no-sideways-refs`

**R13.** No tunable consts.
Enforced by: `arch:no-tunable-consts`

**R14.** No .new() on visual nodes.
Enforced by: `arch:no-visual-new`, `review`

**R15.** Product code never checks how it is run.
Enforced by: `arch:run-mode`, `review`
DOC
	} > ARCHITECTURE.md
	printf '[application]\nconfig/name="Fixture"\n' > project.godot
}

# needs_godot: skip unless GODOT_BIN runs; import the project so the probe sees
# its class_names (prepare does this in a real run).
needs_godot() {
	[ -n "${GODOT_BIN:-}" ] && command -v "$GODOT_BIN" > /dev/null 2>&1 || skip "GODOT_BIN is not set"
	printf 'config_version=5\n\n%s\n' "$(cat project.godot)" > project.godot.new && mv project.godot.new project.godot
	"$GODOT_BIN" --headless --path . --import > "$TEST_TMP/import.log" 2>&1 || fail "the import failed: $(tail -5 "$TEST_TMP/import.log")"
}

# put <path>: write stdin to <path>, making its folder.
put() {
	mkdir -p "$(dirname "$1")"
	cat > "$1"
}

# assert_clean: the arch step passes with no findings.
# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
assert_clean() {
	run_verify arch
	assert_eq "== arch PASS
verify: PASS" "$out" "the clean version has findings"
}

# assert_findings <lines>: the arch step fails with exactly these findings.
assert_findings() {
	run_verify arch
	assert_status 1
	assert_eq "== arch FAIL
$1
verify: FAILED at step arch" "$out"
}

# --- R1 ---

test_r1_autoload_is_a_finding() {
	godot_project
	printf '[autoload]\n\nEvents="*res://events.gd"\n\n[display]\nwindow/size=1\n' >> project.godot
	assert_findings "project.godot:5 R1 autoload Events; pass it down from the scene that owns it"
}

test_r1_project_without_autoloads_passes() {
	godot_project
	printf '[display]\nwindow/size/viewport_width=720\n' >> project.godot
	assert_clean
}

# --- R6 ---

test_r6_each_reach_up_is_a_finding() {
	godot_project
	put game/reach.gd << 'EOF'
extends Node
func f() -> void:
	var a := get_parent()
	var b = owner.name
	var c := get_node("../Hud")
	var d := get_tree().root
	var e := get_node("/root/Main")
	var g := get_tree().current_scene
EOF
	assert_findings "game/reach.gd:3 R6 reaches up the tree with get_parent; have its parent pass it down instead
game/reach.gd:4 R6 reaches up the tree with owner.; have its parent pass it down instead
game/reach.gd:5 R6 reaches up the tree with ../; have its parent pass it down instead
game/reach.gd:6 R6 reaches up the tree with get_tree().root; have its parent pass it down instead
game/reach.gd:7 R6 reaches up the tree with /root/; have its parent pass it down instead
game/reach.gd:8 R6 reaches up the tree with current_scene; have its parent pass it down instead"
}

test_r6_comments_and_clean_code_pass() {
	godot_project
	put game/reach.gd << 'EOF'
extends Node
## Never call get_parent() here; the owner. passes it down.
# var a := get_node("../Hud")
	# get_tree().root and /root/ and current_scene
func f(child: Node) -> void:
	child.queue_free() # not get_parent()
EOF
	assert_clean
}

# --- R7 ---

test_r7_warning_ignore_is_a_finding_in_product_and_tests() {
	godot_project
	put game/quiet.gd << 'EOF'
extends Node
@warning_ignore("unused_variable")
func f() -> void:
	pass
EOF
	put tests/game/quiet_test.gd << 'EOF'
extends Node
@warning_ignore_start("unsafe_cast")
EOF
	assert_findings "game/quiet.gd:2 R7 suppresses a warning with @warning_ignore; fix the code instead
tests/game/quiet_test.gd:2 R7 suppresses a warning with @warning_ignore_start; fix the code instead"
}

test_no_check_reads_the_scenario_folder() {
	godot_project
	printf 'scenarios/\n' > tools/verify/scenario-folder
	put scenarios/serve.gd << 'EOF'
extends Node
@warning_ignore("redundant_await")
func f() -> void:
	var a := get_parent()
EOF
	put game/scenarios/quiet.gd << 'EOF'
extends Node
@warning_ignore("unused_variable")
EOF
	assert_findings "game/scenarios/quiet.gd:2 R7 suppresses a warning with @warning_ignore; fix the code instead"
}

test_r7_comment_mention_passes() {
	godot_project
	put game/quiet.gd << 'EOF'
extends Node
# @warning_ignore("unused_variable") is banned
EOF
	assert_clean
}

test_r7_string_mention_passes() {
	godot_project
	put game/quiet.gd << 'EOF'
extends Node
var label := "@warning_ignore in a string # is not a suppression"
var other := 'nor @warning_ignore_start here'
EOF
	assert_clean
}

# --- R9 ---

test_r9_bad_file_folder_and_node_names_are_findings() {
	godot_project
	echo 'extends Node' | put UI/hud.gd
	echo 'extends Node' | put game/BigGame.gd
	put game/game.tscn << 'EOF'
[gd_scene format=3]

[node name="Game" type="Node"]

[node name="ball_slot" type="Node2D" parent="."]
EOF
	assert_findings "UI:1 R9 folder UI is not snake_case
game/BigGame.gd:1 R9 file BigGame.gd is not snake_case
game/game.tscn:5 R9 node ball_slot is not PascalCase"
}

test_r9_good_names_pass() {
	godot_project
	echo 'extends Node' | put ui/hud/life_icon.gd
	echo 'extends Node' | put levels/level_01.gd
	put levels/level_01.tscn << 'EOF'
[gd_scene format=3]

[node name="Level01" type="Node2D"]

[node name="Brick" type="Node2D" parent="."]
EOF
	echo 'x' | put ui/fonts/Jost.ttf
	echo 'x' | put docs/adr/0001-some-decision.md
	assert_clean
}

# --- R10 ---

test_r10_plugin_and_licensed_code_outside_addons_are_findings() {
	godot_project
	echo '[plugin]' | put vendor/thing/plugin.cfg
	put lib/tween_lib.gd << 'EOF'
# SPDX-License-Identifier: MIT
extends RefCounted
EOF
	assert_findings "lib/tween_lib.gd:1 R10 carries a licence header; third-party code goes under addons/
vendor/thing/plugin.cfg:1 R10 is a Godot plugin; third-party code goes under addons/"
}

test_r10_third_party_under_addons_passes() {
	godot_project
	echo '[plugin]' | put addons/thing/plugin.cfg
	printf '# Copyright (c) Someone\nextends RefCounted\n' | put addons/thing/thing.gd
	echo 'extends Node' | put game/game.gd
	assert_clean
}

# --- R11 ---

test_r11_tool_script_off_the_allowlist_is_a_finding() {
	godot_project
	printf '@tool\nextends Node2D\n' | put levels/level_guides.gd
	printf '@tool\nextends Node2D\n' | put levels/sneaky.gd
	echo 'levels/level_guides.gd' > tools/verify/ratchet/tool_scripts.txt
	assert_findings "levels/sneaky.gd:1 R11 is a @tool script not on tools/verify/ratchet/tool_scripts.txt; adding one is a declared Deviation"
}

test_r11_allowlisted_tool_script_passes() {
	godot_project
	printf '@tool\nextends Node2D\n# @tool in a comment is not a tool script\n' | put levels/level_guides.gd
	printf 'extends Node2D\n# @tool\n' | put levels/plain.gd
	printf '# the @tool allowlist\nlevels/level_guides.gd\n' > tools/verify/ratchet/tool_scripts.txt
	assert_clean
}

test_r11_stale_allowlist_entry_is_a_finding() {
	godot_project
	printf 'extends Node2D\n' | put levels/level_guides.gd
	printf '# the @tool allowlist\nlevels/level_guides.gd\n' > tools/verify/ratchet/tool_scripts.txt
	assert_findings "tools/verify/ratchet/tool_scripts.txt:2 R11 lists levels/level_guides.gd, which is not a @tool script; remove it"
}

# --- R13 ---

test_r13_literal_consts_are_findings() {
	godot_project
	put playfield/ball.gd << 'EOF'
extends Node2D
const SPEED: float = 700.0
const STEPS := 4
	const NEGATIVE = -1.0
const TINT: Color = Color(0.5, 0.5, 0.5)
const OFFSET := Vector2(40.0, 96.0)
const RED := Color.RED
EOF
	assert_findings "playfield/ball.gd:2 R13 const SPEED is a tunable; export it on GameConfig or a scene node, or mark it ## invariant
playfield/ball.gd:3 R13 const STEPS is a tunable; export it on GameConfig or a scene node, or mark it ## invariant
playfield/ball.gd:4 R13 const NEGATIVE is a tunable; export it on GameConfig or a scene node, or mark it ## invariant
playfield/ball.gd:5 R13 const TINT is a tunable; export it on GameConfig or a scene node, or mark it ## invariant
playfield/ball.gd:6 R13 const OFFSET is a tunable; export it on GameConfig or a scene node, or mark it ## invariant
playfield/ball.gd:7 R13 const RED is a tunable; export it on GameConfig or a scene node, or mark it ## invariant"
}

test_r13_invariants_references_comments_and_tests_pass() {
	godot_project
	put levels/level_grid.gd << 'EOF'
extends RefCounted
## invariant: the Playfield is 720 units wide on every device.
const PLAYFIELD_WIDTH: float = 720.0
## The number of columns.
## invariant
const COLUMNS: int = 10
const EPSILON: float = 0.01 ## invariant
const SCENE: PackedScene = preload("res://levels/level_01.tscn")
const PATH: String = "user://scores.json"
const WIDTH: float = LevelGrid.PLAYFIELD_WIDTH
# const SPEED: float = 700.0
	# const TINT := Color(1, 0, 0)
EOF
	printf 'extends Node\nconst SPEED: float = 700.0\n' | put tests/levels/level_grid_test.gd
	assert_clean
}

test_r13_invariant_mark_covers_only_the_next_const() {
	godot_project
	put levels/level_grid.gd << 'EOF'
extends RefCounted
## invariant
const PLAYFIELD_WIDTH: float = 720.0
const COLUMNS: int = 10
EOF
	assert_findings "levels/level_grid.gd:4 R13 const COLUMNS is a tunable; export it on GameConfig or a scene node, or mark it ## invariant"
}

# --- R14 ---

test_r14_visual_new_is_a_finding() {
	godot_project
	printf 'class_name BallSockets\nextends Node2D\n' | put playfield/ball_sockets.gd
	printf 'class_name FancySockets\nextends BallSockets\n' | put playfield/fancy_sockets.gd
	put playfield/playfield.gd << 'EOF'
extends Node2D
func _ready() -> void:
	add_child(BallSockets.new())
	add_child(FancySockets.new())
	var label := Label.new(); add_child(Sprite2D.new())
EOF
	assert_findings "playfield/playfield.gd:3 R14 BallSockets.new() builds a visual node in code; instance it from its own scene
playfield/playfield.gd:4 R14 FancySockets.new() builds a visual node in code; instance it from its own scene
playfield/playfield.gd:5 R14 Label.new() builds a visual node in code; instance it from its own scene
playfield/playfield.gd:5 R14 Sprite2D.new() builds a visual node in code; instance it from its own scene"
}

test_r14_non_visual_new_comments_and_allowlist_pass() {
	godot_project
	printf 'class_name LinePath\nextends RefCounted\n' | put playfield/line_path.gd
	put playfield/playfield.gd << 'EOF'
extends Node2D
func _ready() -> void:
	var t := Timer.new()
	var shape := RectangleShape2D.new()
	var path := LinePath.new()
	var m := ShaderMaterial.new()
	# add_child(Sprite2D.new())
EOF
	printf 'extends Control\nfunc f() -> void:\n\tadd_child(Label.new())\n' | put ui/screens/title.gd
	printf 'extends Node\nfunc f() -> void:\n\tadd_child(Label.new())\n' | put tests/ui/screens/title_test.gd
	echo 'ui/screens/title.gd' > tools/verify/ratchet/visual_new.txt
	assert_clean
}

test_r14_stale_allowlist_entry_is_a_finding() {
	godot_project
	printf 'extends Control\n' | put ui/screens/title.gd
	printf '# R14 allowlist\nui/screens/title.gd\n' > tools/verify/ratchet/visual_new.txt
	assert_findings "tools/verify/ratchet/visual_new.txt:2 R14 lists ui/screens/title.gd, which builds no visual node in code; remove it"
}

# --- R15 ---

test_r15_run_mode_checks_are_findings() {
	godot_project
	put main/main.gd << 'EOF2'
extends Node
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or OS.is_debug_build():
		return
	var home := OS.get_environment("HOME"); var dbg := EngineDebugger.is_active()
	if OS.has_feature("editor") or OS.has_feature ( 'template' ) or Engine.is_editor_hint():
		pass
EOF2
	assert_findings "main/main.gd:3 R15 OS.get_cmdline_user_args() checks how the game is run; take that choice from config or a seam
main/main.gd:4 R15 DisplayServer.get_name() checks how the game is run; take that choice from config or a seam
main/main.gd:4 R15 OS.is_debug_build() checks how the game is run; take that choice from config or a seam
main/main.gd:6 R15 EngineDebugger.is_active() checks how the game is run; take that choice from config or a seam
main/main.gd:6 R15 OS.get_environment() checks how the game is run; take that choice from config or a seam
main/main.gd:7 R15 Engine.is_editor_hint() checks how the game is run; take that choice from config or a seam
main/main.gd:7 R15 OS.has_feature() checks how the game is run; take that choice from config or a seam
main/main.gd:7 R15 OS.has_feature() checks how the game is run; take that choice from config or a seam"
}

test_r15_platforms_tool_scripts_tests_comments_and_allowlist_pass() {
	godot_project
	put ui/hud/touch.gd << 'EOF2'
extends Node
func _ready() -> void:
	var touch := OS.has_feature("mobile") or OS.has_feature("android")
	var tag := "debug"
	var any := OS.has_feature(tag)
	var name := MyOS.is_debug_build()
	# if OS.is_debug_build(): return
EOF2
	printf '@tool\nextends Node2D\nfunc _draw() -> void:\n\tif not Engine.is_editor_hint():\n\t\treturn\n' | put levels/level_guides.gd
	echo 'levels/level_guides.gd' > tools/verify/ratchet/tool_scripts.txt
	printf 'extends Control\nfunc _ready() -> void:\n\tvisible = OS.is_debug_build()\n' | put ui/overlays/perf_overlay.gd
	printf '# R15 allowlist\nui/overlays/perf_overlay.gd\n' > tools/verify/ratchet/run_mode.txt
	printf 'extends Node\nfunc f() -> void:\n\tassert(OS.is_debug_build())\n' | put tests/ui/hud/touch_test.gd
	assert_clean
}

test_r15_stale_allowlist_entry_is_a_finding() {
	godot_project
	printf 'extends Control\n' | put ui/overlays/perf_overlay.gd
	printf '# R15 allowlist\nui/overlays/perf_overlay.gd\n' > tools/verify/ratchet/run_mode.txt
	assert_findings "tools/verify/ratchet/run_mode.txt:2 R15 lists ui/overlays/perf_overlay.gd, which checks nothing about how the game is run; remove it"
}

test_r15_stale_allowlist_entry_is_a_finding_with_no_product_scripts() {
	godot_project
	printf '# R15 allowlist\nmain/removed.gd\n' > tools/verify/ratchet/run_mode.txt
	assert_findings "tools/verify/ratchet/run_mode.txt:2 R15 lists main/removed.gd, which checks nothing about how the game is run; remove it"
}

# A call reads as a call across lines, with a trailing comma or a comment in it;
# a string that names one, on one line or many, is no call.
test_r15_reads_whole_calls_and_skips_strings() {
	godot_project
	put main/main.gd << 'EOF2'
extends Node
const HELP := "Call OS.get_environment() to read the environment"
const LONG := """
OS.is_debug_build()
"""
func _ready() -> void:
	if OS.has_feature(
		"debug" # check the build
	):
		pass
	if OS.has_feature("release",):
		pass
	if OS.has_feature("mobile",):
		pass
EOF2
	assert_findings "main/main.gd:11 R15 OS.has_feature() checks how the game is run; take that choice from config or a seam
main/main.gd:7 R15 OS.has_feature() checks how the game is run; take that choice from config or a seam"
}

# A backslash at a line's end continues it: the call and its tag read whole.
test_r15_reads_calls_across_backslash_continuations() {
	godot_project
	put main/main.gd << 'EOF2'
extends Node
func _ready() -> void:
	var args := OS.get_cmdline_args\
		()
	if OS.has_feature(\
		"debug"):
		pass
	print(OS.\
		get_environment("X"))
	print(OS.\
		has_feature("debug"))
EOF2
	assert_findings "main/main.gd:10 R15 OS.has_feature() checks how the game is run; take that choice from config or a seam
main/main.gd:3 R15 OS.get_cmdline_args() checks how the game is run; take that choice from config or a seam
main/main.gd:5 R15 OS.has_feature() checks how the game is run; take that choice from config or a seam
main/main.gd:8 R15 OS.get_environment() checks how the game is run; take that choice from config or a seam"
}

# --- inputs ---

test_git_ignored_files_are_not_checked() {
	godot_project
	git init -q . || skip "git init failed"
	echo '/prototypes/' > .gitignore
	printf 'extends Node\nfunc f() -> void:\n\tget_parent()\n' | put prototypes/try/try.gd
	assert_clean
}

test_two_runs_give_identical_output() {
	godot_project
	printf 'extends Node\nconst SPEED := 3\nfunc f() -> void:\n\tget_parent()\n' | put game/game.gd
	run_verify --twice arch
	assert_status 1
	assert_last_line "verify: two runs match"
}

# Without its helper the step can't tell product scripts from tests. It must stop,
# not pass having checked nothing: the get_parent here is the finding it would lose.
test_a_missing_gdscript_helper_stops_the_step() {
	godot_project
	printf 'extends Node\nfunc f() -> void:\n\tget_parent()\n' | put game/game.gd
	rm tools/verify/_gdscript.sh
	run_cmd bash tools/verify/arch
	assert_status 2
	run_verify arch
	assert_status 1
	assert_line "== arch FAIL"
}

# --- R2 ---

test_r2_model_that_holds_nodes_is_a_finding_with_godot() {
	godot_project model-plain
	printf 'class_name Ball\nextends Node2D\n' | put playfield/ball.gd
	put game/game_model.gd << 'EOF'
class_name GameModel
extends Node
var _ball: Ball
var _balls: Array[Ball] = []
var _count: int = 0
func f() -> void:
	await get_tree().process_frame
	var s: Script = preload("res://playfield/ball.gd")
	_ball.get_tree().quit()
EOF
	needs_godot
	assert_findings "game/game_model.gd:2 R2 GameModel extends Node, not RefCounted
game/game_model.gd:3 R2 GameModel has a Node field _ball (Ball); the model holds no nodes
game/game_model.gd:4 R2 GameModel has a Node field _balls (Ball); the model holds no nodes
game/game_model.gd:7 R2 GameModel uses await; the model stays plain
game/game_model.gd:7 R2 GameModel uses get_tree; the model stays plain
game/game_model.gd:8 R2 GameModel uses preload; the model stays plain
game/game_model.gd:9 R2 GameModel uses get_tree; the model stays plain"
}

test_r2_plain_model_passes_with_godot() {
	godot_project model-plain
	put game/game_model.gd << 'EOF'
class_name GameModel
extends RefCounted
## Never get_tree(), await or preload() here.
var _config: Resource
var _scores: Array[int] = []
var _note: String = "await get_tree() # preload"
# await get_tree().process_frame
EOF
	needs_godot
	assert_clean
}

test_r2_missing_model_is_a_finding_with_godot() {
	godot_project model-plain
	printf 'class_name Other\nextends RefCounted\n' | put game/other.gd
	needs_godot
	assert_findings "tools/verify/arch:1 R2 no product script declares class_name GameModel, the plain model R2 checks"
}

# plain_game_model: a clean GameModel, so the R2 tests of the folder have no
# missing-class finding.
plain_game_model() {
	printf 'class_name GameModel\nextends RefCounted\n' | put game/game_model.gd
}

test_r2_node_script_in_the_folder_is_a_finding_with_godot() {
	godot_project model-plain
	plain_game_model
	put rules/board_rules.gd << 'EOF'
extends Node
var _anchor: Node
EOF
	printf 'class_name Merge\nextends Node2D\n' | put rules/merge/merge.gd
	needs_godot
	assert_findings "rules/board_rules.gd:1 R2 board_rules.gd extends Node, not RefCounted
rules/board_rules.gd:2 R2 board_rules.gd has a Node field _anchor (Node); the model holds no nodes
rules/merge/merge.gd:2 R2 Merge extends Node2D, not RefCounted"
}

test_r2_get_tree_in_the_folder_is_a_finding_with_godot() {
	godot_project model-plain
	plain_game_model
	printf 'extends RefCounted\n' | put rules/tile.gd
	put rules/turn.gd << 'EOF'
class_name Turn
extends RefCounted
func f(n: Node) -> void:
	await n.get_tree().process_frame
	var s: Script = preload("res://rules/tile.gd")
EOF
	needs_godot
	assert_findings "rules/turn.gd:4 R2 Turn uses await; the model stays plain
rules/turn.gd:4 R2 Turn uses get_tree; the model stays plain
rules/turn.gd:5 R2 Turn uses preload; the model stays plain"
}

test_r2_plain_script_in_the_folder_passes_with_godot() {
	godot_project model-plain
	plain_game_model
	put rules/score.gd << 'EOF'
extends RefCounted
var _points: int = 0
var _table: Resource
EOF
	needs_godot
	assert_clean
}

test_r2_missing_or_empty_folder_passes_with_godot() {
	godot_project model-plain
	sed -i "s/^PLAIN_MODEL_DIRS='rules'$/PLAIN_MODEL_DIRS='rules gone'/" tools/verify/arch
	plain_game_model
	echo 'no scripts here' | put rules/notes.txt
	needs_godot
	assert_clean
}

test_r2_test_under_tests_rules_is_not_checked_with_godot() {
	godot_project model-plain
	plain_game_model
	put tests/rules/score_test.gd << 'EOF'
extends Node
var _anchor: Node
func f() -> void:
	await get_tree().process_frame
EOF
	needs_godot
	assert_clean
}

test_r2_listed_class_in_the_folder_is_checked_once_with_godot() {
	godot_project model-plain
	printf 'class_name GameModel\nextends Node\n' | put rules/game_model.gd
	needs_godot
	assert_findings "rules/game_model.gd:2 R2 GameModel extends Node, not RefCounted"
}

# --- R4 ---

test_r4_edges_against_the_layer_line_are_findings() {
	godot_project layers
	printf 'class_name GameModel\nextends RefCounted\n' | put game/game_model.gd
	printf 'class_name PauseOverlay\nextends Control\n' | put ui/overlays/pause_overlay.gd
	printf 'class_name HighScores\nextends RefCounted\nvar c: GameConfig\n' | put high_scores/high_scores.gd
	printf 'class_name GameConfig\nextends Resource\n' | put config/game_config.gd
	printf 'extends Node2D\nvar s: GameModel.BallState\n' | put playfield/serve_area/ball_sockets.gd
	printf 'extends Control\nfunc f(p: PauseOverlay) -> void:\n\tpass\n' | put ui/hud/hud.gd
	printf 'extends RefCounted\nconst BRICK: PackedScene = preload("res://playfield/brick/brick.tscn")\n' | put levels/level_check.gd
	printf 'extends "res://main/base.gd"\n' | put game/game.gd
	printf 'extends Node\nvar h := HighScores.new()\n' | put game/playing.gd
	assert_findings "game/game.gd:1 R4 uses main/base.gd from main, which is not below game on the layer line
game/playing.gd:2 R4 uses HighScores from high_scores, a leaf only main may use
high_scores/high_scores.gd:3 R4 uses GameConfig from config; high_scores is a leaf and uses nothing outside itself
levels/level_check.gd:2 R4 uses playfield/brick/brick.tscn from playfield, which is not below levels on the layer line
playfield/serve_area/ball_sockets.gd:2 R4 uses GameModel from game, which is not below playfield on the layer line
ui/hud/hud.gd:2 R4 uses PauseOverlay from ui/overlays, which is not below ui/hud on the layer line"
}

test_r4_downward_edges_names_and_comments_pass() {
	godot_project layers
	printf 'class_name Game\nextends Node\n' | put game/game.gd
	printf 'class_name Hud\nextends Control\n' | put ui/hud/hud.gd
	printf 'class_name Playfield\nextends Node2D\n' | put playfield/playfield.gd
	printf 'class_name LevelGrid\nextends RefCounted\n' | put levels/level_grid.gd
	printf 'class_name GameConfig\nextends Resource\n' | put config/game_config.gd
	printf 'class_name HighScores\nextends RefCounted\n' | put high_scores/high_scores.gd
	printf 'extends Node\nvar g: Game\nvar h := HighScores.new()\n' | put main/main.gd
	put game/playing.gd << 'EOF'
extends Node
## Hands the Hud down; the Playfield is below.
@onready var _hud: Hud = $HudLayer/Hud
@onready var _field: Playfield = %Playfield
var _g: Game
func f(x: Object) -> void:
	print("HighScores and Game in a string", x.Game)
	# var s: HighScores
EOF
	printf 'extends Control\nvar n: Node = $Game\nconst P: PackedScene = preload("res://playfield/playfield.tscn")\n' | put ui/screens/attract.gd
	printf 'extends Node2D\nvar g: LevelGrid\nvar c: GameConfig\n' | put playfield/ball.gd
	printf 'extends RefCounted\nvar c: GameConfig\n' | put levels/level_check.gd
	printf 'extends Node\nvar g: Game\n' | put tests/game/game_test.gd
	assert_clean
}

test_r4_missing_layer_line_is_a_finding() {
	godot_project layers
	sed -i '/→/d' ARCHITECTURE.md
	assert_findings "ARCHITECTURE.md:1 R4 has no layer line under ## Layers; R4 checks against it"
}

# --- R5 ---

# signal_fixture: game/hub.tscn holding Left and Right (game/side.gd, with signal
# poked and method on_poke) under Hub (game/hub.gd, whose source is stdin).
signal_fixture() {
	printf 'extends Node\nsignal poked\nfunc on_poke() -> void:\n\tpass\n' | put game/side.gd
	put game/hub.gd
	put game/hub.tscn << 'EOF'
[gd_scene format=3]

[ext_resource type="Script" path="res://game/hub.gd" id="1_hub"]
[ext_resource type="Script" path="res://game/side.gd" id="2_side"]

[node name="Hub" type="Node"]
script = ExtResource("1_hub")

[node name="Left" type="Node" parent="."]
script = ExtResource("2_side")

[node name="Right" type="Node" parent="."]
script = ExtResource("2_side")
EOF
}

test_r5_sideways_connections_are_findings_with_godot() {
	godot_project signals-up
	signal_fixture << 'EOF'
extends Node
func _ready() -> void:
	$Left.poked.connect(_on_poked)
	$Left.poked.connect($Right.on_poke)
func _on_poked() -> void:
	pass
EOF
	printf '\n[connection signal="poked" from="Right" to="Left" method="on_poke"]\n' >> game/hub.tscn
	needs_godot
	assert_findings "game/hub.gd:4 R5 Left.poked is connected to Right.on_poke, which is not Left or an ancestor of it; relay it through their common parent
game/hub.tscn:15 R5 Right.poked is connected to Left.on_poke, which is not Right or an ancestor of it; relay it through their common parent"
}

test_r5_connections_up_and_to_self_pass_with_godot() {
	godot_project signals-up
	signal_fixture << 'EOF'
extends Node
func _ready() -> void:
	$Left.poked.connect(_on_poked)
	$Left.poked.connect($Left.on_poke)
	$Right.poked.connect(func() -> void: pass)
	$Right.tree_exiting.connect(_on_poked)
func _on_poked() -> void:
	pass
EOF
	printf '\n[connection signal="poked" from="Right" to="." method="_on_poked"]\n' >> game/hub.tscn
	needs_godot
	assert_clean
}

test_r5_walk_runs_twice_with_identical_output_with_godot() {
	godot_project signals-up
	signal_fixture << 'EOF'
extends Node
func _ready() -> void:
	$Left.poked.connect($Right.on_poke)
	$Right.poked.connect($Left.on_poke)
EOF
	needs_godot
	run_verify --twice arch
	assert_status 1
	assert_last_line "verify: two runs match"
}

test_godot_checks_without_godot_are_findings() {
	godot_project signals-up
	echo 'extends Node' | signal_fixture
	GODOT_BIN='' run_verify arch
	assert_status 1
	assert_eq "== arch FAIL
tools/verify/_arch_probe.gd:1 R5 needs Godot; set GODOT_BIN in tools/verify/local.env
verify: FAILED at step arch" "$out"
}

# --- R8 ---

test_r8_script_without_a_mirrored_test_is_a_finding() {
	godot_project mirrored-tests
	echo 'extends Node' | put game/game.gd
	echo 'extends Node' | put game/playing.gd
	echo 'extends Node' | put playfield/ball/ball.gd
	echo 'extends Node' | put tests/game/game_test.gd
	echo 'extends Node' | put tests/game/playing_flow_test.gd
	echo 'extends Node' | put tests/playfield/ball_test.gd
	assert_findings "game/playing.gd:1 R8 has no test at tests/game/playing_test.gd
playfield/ball/ball.gd:1 R8 has no test at tests/playfield/ball/ball_test.gd"
}

test_r8_mirrored_tests_and_allowlisted_tool_scripts_pass() {
	godot_project mirrored-tests
	echo 'extends Node' | put game/game.gd
	echo 'extends Node' | put playfield/ball/ball.gd
	printf '@tool\nextends Node2D\n' | put levels/level_guides.gd
	echo 'extends Node' | put tests/game/game_test.gd
	echo 'extends Node' | put tests/playfield/ball/ball_test.gd
	echo 'extends Node' | put tests/game/extra_test.gd
	printf '# R11\nlevels/level_guides.gd\n' > tools/verify/ratchet/tool_scripts.txt
	assert_clean
}

# Which files are tests comes from tools/verify/test-paths, not a fixed tests/.
test_r8_takes_the_test_files_from_test_paths() {
	godot_project mirrored-tests
	echo 'spec/**' > tools/verify/test-paths
	echo 'extends Node' | put game/game.gd
	echo 'extends Node' | put spec/game/game_spec.gd
	echo 'extends Node' | put tests/game/game_test.gd
	assert_findings "tests/game/game_test.gd:1 R8 has no test at tests/tests/game/game_test_test.gd"
}

# --- R12 ---

# holder_script: game/holder.gd, the exporting node's script.
holder_script() {
	put game/holder.gd << 'EOF'
extends Node
@export var buddy: Node
@export var buddy_path: NodePath
@export var kid: Node
@export var kids: Array[Node] = []
EOF
}

# scene_ref_fixture: game/outer.tscn defining Holder (game/holder.gd, with Kid
# under it) and its sibling Buddy; stdin is Holder's property lines.
scene_ref_fixture() {
	holder_script
	{
		cat << 'EOF'
[gd_scene format=3]

[ext_resource type="Script" path="res://game/holder.gd" id="1_holder"]

[node name="Outer" type="Node"]

[node name="Holder" type="Node" parent="." node_paths=PackedStringArray("buddy", "kid", "kids")]
script = ExtResource("1_holder")
EOF
		cat
		printf '\n[node name="Kid" type="Node" parent="Holder"]\n\n[node name="Buddy" type="Node" parent="."]\n'
	} | put game/outer.tscn
}

# instance_ref_fixture: Holder (game/holder.gd, with Kid under it) as its own scene,
# game/holder.tscn, instanced in game/outer.tscn beside Buddy; stdin is the
# property lines outer.tscn sets on the instance.
instance_ref_fixture() {
	holder_script
	put game/holder.tscn << 'EOF'
[gd_scene format=3]

[ext_resource type="Script" path="res://game/holder.gd" id="1_holder"]

[node name="Holder" type="Node"]
script = ExtResource("1_holder")

[node name="Kid" type="Node" parent="."]
EOF
	{
		cat << 'EOF'
[gd_scene format=3]

[ext_resource type="PackedScene" path="res://game/holder.tscn" id="1_holder"]

[node name="Outer" type="Node"]

[node name="Holder" parent="." node_paths=PackedStringArray("buddy", "kid", "kids") instance=ExtResource("1_holder")]
EOF
		cat
		printf '\n[node name="Buddy" type="Node" parent="."]\n'
	} | put game/outer.tscn
}

# A node that instances a scene belongs to that scene: set from the parent scene,
# its references are judged against its own subtree, as Game.hud would be.
test_r12_an_instanced_scenes_references_outside_its_own_scene_are_findings_with_godot() {
	godot_project no-sideways-refs
	instance_ref_fixture << 'EOF'
buddy = NodePath("../Buddy")
buddy_path = NodePath("../Buddy")
kid = NodePath("Kid/../../Buddy")
kids = [NodePath("Kid"), NodePath("/root/Buddy")]
EOF
	needs_godot
	assert_findings "game/holder.gd:2 R12 Holder.buddy points at ../Buddy, outside Holder's own subtree (set in game/outer.tscn); pass it down from the parent instead
game/holder.gd:3 R12 Holder.buddy_path points at ../Buddy, outside Holder's own subtree (set in game/outer.tscn); pass it down from the parent instead
game/holder.gd:4 R12 Holder.kid points at Kid/../../Buddy, outside Holder's own subtree (set in game/outer.tscn); pass it down from the parent instead
game/holder.gd:5 R12 Holder.kids points at /root/Buddy, outside Holder's own subtree (set in game/outer.tscn); pass it down from the parent instead"
}

test_r12_references_inside_an_instanced_scene_pass_with_godot() {
	godot_project no-sideways-refs
	instance_ref_fixture << 'EOF'
buddy = NodePath(".")
buddy_path = NodePath("Kid/../Kid")
kid = NodePath("Kid")
kids = [NodePath("Kid")]
EOF
	needs_godot
	assert_clean
}

# Any other node belongs to the scene that defines it: a sibling there is in reach.
test_r12_a_reference_to_a_sibling_in_the_same_scene_passes_with_godot() {
	godot_project no-sideways-refs
	scene_ref_fixture << 'EOF'
buddy = NodePath("../Buddy")
buddy_path = NodePath("../Buddy")
kid = NodePath("Kid")
kids = [NodePath("Kid"), NodePath("../Buddy")]
EOF
	needs_godot
	assert_clean
}

test_r12_a_reference_leaving_the_scene_is_a_finding_with_godot() {
	godot_project no-sideways-refs
	scene_ref_fixture << 'EOF'
buddy = NodePath("../Buddy")
kid = NodePath("../../Elsewhere")
kids = [NodePath("/root/Buddy")]
EOF
	needs_godot
	assert_findings "game/holder.gd:4 R12 Holder.kid points at ../../Elsewhere, outside game/outer.tscn, the scene Holder belongs to; pass it down from the parent instead
game/holder.gd:5 R12 Holder.kids points at /root/Buddy, outside game/outer.tscn, the scene Holder belongs to; pass it down from the parent instead"
}

test_r12_without_godot_is_a_finding() {
	godot_project no-sideways-refs
	echo '' | scene_ref_fixture
	GODOT_BIN='' run_verify arch
	assert_status 1
	assert_eq "== arch FAIL
tools/verify/_arch_probe.gd:1 R12 needs Godot; set GODOT_BIN in tools/verify/local.env
verify: FAILED at step arch" "$out"
}

# --- the sync check on the adapter's default rules ---

# default_rules: godot_project with every check, and the adapter's default
# ARCHITECTURE.md (adopt_test.sh checks it cites every check).
default_rules() {
	# shellcheck disable=SC2086
	godot_project $GREP_CHECKS model-plain layers signals-up mirrored-tests no-sideways-refs
	cp "$GODOT_ADAPTER/ARCHITECTURE.md" ARCHITECTURE.md || fail "no default ARCHITECTURE.md"
}

# sync_findings: the arch-sync lines of $out.
sync_findings() { printf '%s\n' "$out" | grep ' arch-sync '; }

test_the_default_rules_fail_when_a_check_is_removed() {
	default_rules
	local rule
	rule="$(grep -B1 'arch:no-tunable-consts' ARCHITECTURE.md | sed -n 's/^\*\*\(R[0-9]*\)\.\*\*.*/\1/p')"
	[ -n "$rule" ] || fail "the default rules don't cite no-tunable-consts"
	sed -i '/^factory_arch_check no-tunable-consts /d' tools/verify/arch
	GODOT_BIN='' run_verify arch
	assert_status 1
	sync_findings | grep -qE "^ARCHITECTURE.md:[0-9]+ arch-sync arch:no-tunable-consts \\($rule\\) has no check\$" ||
		fail "no sync finding for the removed check:"$'\n'"$out"
}
