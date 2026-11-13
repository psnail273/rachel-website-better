# The Godot adapter's part of adoption (adopt.sh, ARCHITECTURE.md), and the whole
# of `factory/core/adopt.sh godot` on made-up projects: one from before the
# factory, and a new one (--new).
#
# Those two need Godot 4.7.1 in GODOT_BIN, gdscript-formatter 0.27.0 and gdmutant
# 0.1.4 (real_formatter and real_gdmutant in tests/lib.sh) and the pinned gdUnit4
# (gdunit4_source), and skip without them; they run the full verify, so they take
# a while, and end in _with_godot.

GODOT_ADAPTER="$FACTORY_CORE/../adapters/godot"
. "$GODOT_ADAPTER/tests/lib.sh"

# presets_project: $TEST_TMP/project with an export_presets.cfg of three presets
# (filters: two patterns; empty; already tools/*), and cd there.
presets_project() {
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "could not make the project"
	cat > export_presets.cfg << 'CFG'
[preset.0]
name="Android"
exclude_filter="tests/*, addons/gdUnit4/*"

[preset.1]
name="Other"
exclude_filter=""

[preset.2]
name="Done"
exclude_filter="tests/*, tools/*"
CFG
}

test_adopt_adds_tools_to_every_preset_exclude_filter() {
	presets_project
	run_cmd bash "$GODOT_ADAPTER/adopt.sh"
	assert_status 0
	assert_eq 'exclude_filter="tests/*, addons/gdUnit4/*, tools/*"
exclude_filter="tools/*"
exclude_filter="tests/*, tools/*"' "$(grep '^exclude_filter=' export_presets.cfg)" "the exclude filters"
	assert_eq 'name="Android"' "$(sed -n 2p export_presets.cfg)" "other lines changed"
}

test_adopt_twice_changes_nothing_more() {
	presets_project
	run_cmd bash "$GODOT_ADAPTER/adopt.sh"
	cp export_presets.cfg "$TEST_TMP/first"
	run_cmd bash "$GODOT_ADAPTER/adopt.sh"
	assert_status 0
	cmp -s "$TEST_TMP/first" export_presets.cfg || fail "a second run changed export_presets.cfg"
}

test_adopt_keeps_crlf_line_endings() {
	presets_project
	sed -i 's/$/\r/' export_presets.cfg
	run_cmd bash "$GODOT_ADAPTER/adopt.sh"
	assert_status 0
	assert_eq 11 "$(tr -cd '\r' < export_presets.cfg | wc -c | tr -d ' ')" "lines lost their CR"
	grep -qU $'^exclude_filter="tools/\\*"\r$' export_presets.cfg || fail "the empty filter wasn't filled"
}

test_adopt_without_export_presets_does_nothing() {
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" || fail "no project"
	run_cmd bash "$GODOT_ADAPTER/adopt.sh"
	assert_status 0
	[ ! -e export_presets.cfg ] || fail "it made an export_presets.cfg"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_the_default_architecture_md_cites_every_arch_check() {
	mkdir -p "$TEST_TMP/project/tools/verify" && cd "$TEST_TMP/project" || fail "no project"
	cp "$GODOT_ADAPTER/tools/verify/arch" "$GODOT_ADAPTER/tools/verify/_gdscript.sh" "$GODOT_ADAPTER/tools/verify/_arch_probe.gd" tools/verify/
	cp "$GODOT_ADAPTER/ARCHITECTURE.md" ARCHITECTURE.md
	GODOT_BIN='' run_verify arch
	assert_eq "" "$(printf '%s\n' "$out" | grep ' arch-sync ')" "the default rules and the checks are out of sync"
	[ "$(wc -l < ARCHITECTURE.md)" -le 150 ] || fail "the default ARCHITECTURE.md is over 150 lines"
}

# existing_project: $TEST_TMP/existing, a git repo on dev holding a Godot project
# from before the factory, all committed: the adapter's skeleton as its game, the
# pinned gdUnit4, the vendored factory/, its own ARCHITECTURE.md and
# format_exclude.txt, a preset that doesn't exclude tools/, and main/legacy.gd
# with a too-long line and no test. cd there. Needs gdUnit4 (gdunit4_source).
existing_project() {
	local gdunit f
	gdunit="$(gdunit4_source)" || skip "no gdUnit4 at the pinned version (set FACTORY_GDUNIT4)"
	isolate_git
	unset FACTORY_LABEL_CMD FACTORY_BASE FACTORY_PROJECT
	mkdir -p "$TEST_TMP/existing" && cd "$TEST_TMP/existing" || fail "no project"
	while IFS= read -r f; do
		mkdir -p "$(dirname "$f")"
		sed 's/<project>/existing/g' "$GODOT_ADAPTER/new/$f" > "${f%.txt}" || fail "could not copy $f"
	done < <(cd "$GODOT_ADAPTER/new" && find . -type f | sed 's#^\./##')
	sed -i 's/^exclude_filter="tests\/\*, addons\/gdUnit4\/\*, tools\/\*"$/exclude_filter="tests\/*, addons\/gdUnit4\/*"/' export_presets.cfg
	mkdir -p addons && cp -R "$gdunit" addons/gdUnit4 || fail "could not copy gdUnit4"
	cp -R "$FACTORY_CORE/.." factory || fail "could not vendor the factory"
	{
		echo "<!-- The existing project's own rules. -->"
		cat "$GODOT_ADAPTER/ARCHITECTURE.md"
	} > ARCHITECTURE.md
	mkdir -p tools/verify/ratchet && echo main/legacy.gd > tools/verify/ratchet/format_exclude.txt
	printf 'extends Node\n\nvar a_long_name: String = "%s"\n' "$(printf 'x%.0s' $(seq 1 100))" > main/legacy.gd
	git init -q -b dev . && git add -A && git commit -q -m "the existing project" || fail "could not commit the project"
}

# The whole of `adopt.sh godot` on a project that predates the factory: it keeps
# the project's own files, records its findings as the Baseline, and stages it all.
test_adopting_an_existing_project_records_its_baseline_with_godot() {
	[ -n "${GODOT_BIN:-}" ] || skip "GODOT_BIN is not set"
	"$GODOT_BIN" --headless --version 2> /dev/null | grep -q '^4\.7\.1\.stable' || skip "GODOT_BIN is not Godot 4.7.1"
	real_formatter
	real_gdmutant
	existing_project
	local architecture f
	architecture="$(cat ARCHITECTURE.md)"

	run_cmd bash factory/core/adopt.sh godot
	assert_status 0
	assert_last_line "baseline: RECORDED $(wc -l < tools/verify/ratchet/baseline.txt | tr -d ' ') entries in tools/verify/ratchet/baseline.txt"
	grep -qxF "main/legacy.gd max-line-length Line is too long: over the maximum of 100 characters" tools/verify/ratchet/baseline.txt ||
		fail "the long line isn't in the Baseline:"$'\n'"$(cat tools/verify/ratchet/baseline.txt)"
	grep -qE '^main/legacy\.gd R[0-9]+ has no test at tests/main/legacy_test\.gd$' tools/verify/ratchet/baseline.txt ||
		fail "the missing test isn't in the Baseline:"$'\n'"$(cat tools/verify/ratchet/baseline.txt)"
	for f in prepare format typecheck lint arch deviation test mutate smoke playtest bootstrap pins versions assert-counts scope test-paths generated local.env.example _arch_probe.gd; do
		[ -f "tools/verify/$f" ] || fail "tools/verify/$f isn't seeded"
	done
	assert_eq "$architecture" "$(cat ARCHITECTURE.md)" "ARCHITECTURE.md wasn't kept"
	assert_eq main/legacy.gd "$(cat tools/verify/ratchet/format_exclude.txt)" "format_exclude.txt wasn't kept"
	assert_eq 'exclude_filter="tests/*, addons/gdUnit4/*, tools/*"' "$(grep '^exclude_filter=' export_presets.cfg)" "the preset doesn't exclude tools/"
	[ -f .claude/skills/write-tests-godot/SKILL.md ] || fail "the adapter's skill isn't installed"
	grep -qxF "  - verify-existing" .claude/agents/editor-sonnet.md || fail "the Sonnet Editor's skills aren't filled"
	grep -qxF "name: verify-existing" .claude/skills/verify-existing/SKILL.md || fail "the verify-existing skill isn't generated"
	[ -f .claude/skills/verify-existing/feature-map.md ] || fail "no feature map"
	assert_eq "" "$(git status --porcelain | grep -v '^[AM] ')" "adoption left files unstaged"

	# The Baseline is the full verify adopt.sh ran; a second one (baseline.sh gate)
	# would only repeat it. The entry point runs the steps.
	run_cmd bash tools/verify.sh prepare
	assert_status 0
}

# --- --new: the skeleton ---

# gdunit_project: $TEST_TMP/project with the seeded pins, arch and the _gdscript.sh
# it sources, and a stand-in gdUnit4 addon in $TEST_TMP/gdunit whose plugin.cfg
# declares version <v> (default: the pinned one); cd to the project.
gdunit_project() {
	mkdir -p "$TEST_TMP/project/tools/verify" "$TEST_TMP/gdunit/bin" && cd "$TEST_TMP/project" || fail "no project"
	cp "$GODOT_ADAPTER/tools/verify/pins" "$GODOT_ADAPTER/tools/verify/arch" "$GODOT_ADAPTER/tools/verify/_gdscript.sh" tools/verify/
	printf '[plugin]\nname="gdUnit4"\nversion="%s"\n' "${1:-$(sed -n 's/^gdunit4 //p' tools/verify/pins)}" > "$TEST_TMP/gdunit/plugin.cfg"
	echo "extends SceneTree" > "$TEST_TMP/gdunit/bin/GdUnitCmdTool.gd"
}

test_new_vendors_the_pinned_gdunit4() {
	gdunit_project
	FACTORY_GDUNIT4="$TEST_TMP/gdunit" run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new
	assert_status 0
	cmp -s "$TEST_TMP/gdunit/plugin.cfg" addons/gdUnit4/plugin.cfg || fail "no addons/gdUnit4/plugin.cfg"
	[ -f addons/gdUnit4/bin/GdUnitCmdTool.gd ] || fail "the addon wasn't copied whole"
}

# The arch template names no project's plain models, plain-model folders or leaf
# folders; a project sets its own in its seeded copy.
test_the_arch_template_names_no_plain_model_or_leaf() {
	assert_eq "PLAIN_MODELS=''"$'\n'"PLAIN_MODEL_DIRS=''"$'\n'"LAYER_LEAVES=''" "$(grep -E '^(PLAIN_MODELS|PLAIN_MODEL_DIRS|LAYER_LEAVES)=' "$GODOT_ADAPTER/tools/verify/arch")" "the arch template's names"
	gdunit_project
	FACTORY_GDUNIT4="$TEST_TMP/gdunit" run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new
	assert_status 0
	cmp -s "$GODOT_ADAPTER/tools/verify/arch" tools/verify/arch || fail "--new changed the arch step"
}

# fake_curl <writes>: a curl on PATH that logs its call to $TEST_TMP/curl.log and
# writes <writes> to the -o file.
fake_curl() {
	mkdir -p "$TEST_TMP/bin"
	cat > "$TEST_TMP/bin/curl" << SH
#!/usr/bin/env bash
echo called >> "$TEST_TMP/curl.log"
while [ "\$#" -gt 0 ]; do
	[ "\$1" = -o ] && { printf '%s' "$1" > "\$2"; shift; }
	shift
done
SH
	chmod +x "$TEST_TMP/bin/curl"
	unset FACTORY_GDUNIT4
}

test_the_adapters_gdunit4_pin_has_a_checksum() {
	assert_eq "$(sed -n 's/^gdunit4 //p' "$GODOT_ADAPTER/tools/verify/pins")" \
		"$(sed -n 's/^GDUNIT4_VERSION=//p' "$GODOT_ADAPTER/adopt.sh")" "adopt.sh's checksummed gdUnit4 and the pin"
}

test_new_refuses_a_download_whose_checksum_differs() {
	gdunit_project
	fake_curl "not the gdUnit4 archive"
	PATH="$TEST_TMP/bin:$PATH" run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new
	assert_status 1
	stderr_has "isn't the one pinned"
	[ -s "$TEST_TMP/curl.log" ] || fail "nothing was downloaded"
	[ ! -e addons/gdUnit4 ] || fail "an unchecked archive was vendored"
}

test_new_refuses_to_download_a_version_it_has_no_checksum_for() {
	gdunit_project 9.9.9
	sed -i 's/^gdunit4 .*/gdunit4 9.9.9/' tools/verify/pins
	fake_curl "anything"
	PATH="$TEST_TMP/bin:$PATH" run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new
	assert_status 1
	stderr_has "set FACTORY_GDUNIT4 to a copy of 9.9.9's addons/gdUnit4"
	[ ! -e "$TEST_TMP/curl.log" ] || fail "it downloaded an archive it can't check"
	[ ! -e addons/gdUnit4 ] || fail "something was vendored"
}

test_new_refuses_a_gdunit4_of_another_version() {
	gdunit_project 0.0.1
	FACTORY_GDUNIT4="$TEST_TMP/gdunit" run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new
	assert_status 1
	grep -q "is gdUnit4 0.0.1, but tools/verify/pins pins" "$TEST_TMP/stderr" || fail "stderr: $(cat "$TEST_TMP/stderr")"
	[ ! -e addons/gdUnit4 ] || fail "the wrong version was vendored"
}

test_new_keeps_a_gdunit4_already_there() {
	gdunit_project
	mkdir -p addons/gdUnit4 && echo "the project's" > addons/gdUnit4/plugin.cfg
	FACTORY_GDUNIT4="$TEST_TMP/gdunit" run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new
	assert_status 0
	assert_eq "the project's" "$(cat addons/gdUnit4/plugin.cfg)" "addons/gdUnit4 was overwritten"
}

test_new_says_how_to_supply_gdunit4_when_the_download_fails() {
	gdunit_project
	mkdir -p "$TEST_TMP/bin" && printf '#!/usr/bin/env bash\nexit 22\n' > "$TEST_TMP/bin/curl" && chmod +x "$TEST_TMP/bin/curl"
	unset FACTORY_GDUNIT4
	PATH="$TEST_TMP/bin:$PATH" run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new
	assert_status 1
	grep -q "set FACTORY_GDUNIT4" "$TEST_TMP/stderr" || fail "stderr: $(cat "$TEST_TMP/stderr")"
	[ ! -e addons/gdUnit4 ] || fail "something was vendored"
}

test_without_new_no_gdunit4_is_vendored() {
	gdunit_project
	FACTORY_GDUNIT4="$TEST_TMP/gdunit" run_cmd bash "$GODOT_ADAPTER/adopt.sh"
	assert_status 0
	[ ! -e addons ] || fail "gdUnit4 was vendored without --new"
	cmp -s "$GODOT_ADAPTER/tools/verify/arch" tools/verify/arch || fail "the arch step changed without --new"
}

test_the_adapter_adopt_sh_usage() {
	gdunit_project
	run_cmd bash "$GODOT_ADAPTER/adopt.sh" --old
	assert_status 2
	run_cmd bash "$GODOT_ADAPTER/adopt.sh" --new extra
	assert_status 2
}

# The whole of `adopt.sh godot --new` in an empty git repo (the vendored factory/
# only), with the pinned gdUnit4. It runs the full verify three times.
test_a_new_project_verifies_green_twice_and_can_be_armed_with_godot() {
	[ -n "${GODOT_BIN:-}" ] || skip "GODOT_BIN is not set"
	"$GODOT_BIN" --headless --version 2> /dev/null | grep -q '^4\.7\.1\.stable' || skip "GODOT_BIN is not Godot 4.7.1"
	real_formatter
	real_gdmutant
	FACTORY_GDUNIT4="$(gdunit4_source)" || skip "no gdUnit4 at the pinned version (set FACTORY_GDUNIT4)"
	isolate_git
	unset FACTORY_LABEL_CMD FACTORY_BASE FACTORY_PROJECT
	export FACTORY_GDUNIT4
	mkdir -p "$TEST_TMP/new_game" && cd "$TEST_TMP/new_game" || fail "no project"
	cp -R "$FACTORY_CORE/.." factory || fail "could not vendor the factory"
	git init -q -b dev . && git add -A && git commit -q -m "the factory" || fail "could not commit the factory"

	run_cmd bash factory/core/adopt.sh godot --new
	assert_status 0
	assert_last_line "baseline: RECORDED 0 entries in tools/verify/ratchet/baseline.txt"
	assert_eq 'config/name="new-game"' "$(grep '^config/name=' project.godot)" "the project's name"
	cmp -s "$GODOT_ADAPTER/ARCHITECTURE.md" ARCHITECTURE.md || fail "ARCHITECTURE.md isn't the adapter's default rules"
	local f
	for f in main/main.tscn main/main.gd tests/main/main_test.gd export_presets.cfg addons/gdUnit4/plugin.cfg .claude/skills/verify-new-game/SKILL.md; do
		[ -n "$(git ls-files -- "$f")" ] || fail "$f isn't staged"
	done
	grep -qF '**Main scene** (`res://main/main.tscn`)' .claude/skills/verify-new-game/SKILL.md || fail "the verify skill doesn't launch the skeleton's main scene"
	assert_eq "" "$(git status --porcelain | grep -v '^A ')" "adoption left files unstaged"
	assert_eq "" "$(git ls-files -- .godot)" ".godot/ was staged"
	git commit -q -m "adopt the factory" || fail "could not commit the adoption"

	# It arms straight away. arm.sh runs the full verify twice itself and arms only
	# when both runs are green with identical output and the Baseline is empty; it
	# reports the verify on stderr. Then: enforce, staged, and nothing else changed.
	run_cmd bash factory/core/arm.sh
	assert_status 0
	local line
	for line in "== test PASS" "== smoke PASS" "verify: two runs match"; do
		grep -qxF "  verify: $line" "$TEST_TMP/stderr" || fail "arm.sh's verify has no '$line':"$'\n'"$(cat "$TEST_TMP/stderr")"
	done
	assert_eq enforce "$(git show :tools/verify/hook-mode | grep -v '^#')" "arm.sh didn't stage enforce"
	assert_eq "M  tools/verify/hook-mode" "$(git status --porcelain)" "arm.sh left more than the staged hook mode"
}
